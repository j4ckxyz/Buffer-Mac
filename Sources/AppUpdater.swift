import Foundation
import AppKit

final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    
    @Published var isChecking = false
    @Published var statusMessage: String? = nil
    @Published var updateAvailable = false
    @Published var latestVersionString = ""
    
    private init() {}
    
    struct GitHubRelease: Codable {
        let tag_name: String
        let html_url: String
        let assets: [GitHubAsset]
    }
    
    struct GitHubAsset: Codable {
        let name: String
        let browser_download_url: String
    }
    
    func checkForUpdatesAndInstall(silentOnNoUpdate: Bool = false) {
        guard !isChecking else { return }
        
        isChecking = true
        statusMessage = "Checking for updates..."
        
        guard let url = URL(string: "https://api.github.com/repos/j4ckxyz/Buffer-Mac/releases/latest") else {
            isChecking = false
            statusMessage = "Invalid update URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Buffer-Mac Updater", forHTTPHeaderField: "User-Agent")
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    await updateStatus("Failed to contact update server", isErr: true)
                    return
                }
                
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let latestTag = release.tag_name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "v", with: "")
                let currentTag = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
                
                if latestTag.compare(currentTag, options: .numeric) == .orderedDescending {
                    await MainActor.run {
                        self.latestVersionString = release.tag_name
                        self.updateAvailable = true
                    }
                    
                    if let dmgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) {
                        await updateStatus("Downloading version \(release.tag_name)...")
                        try await downloadAndInstallDMG(from: dmgAsset.browser_download_url)
                    } else {
                        await updateStatus("No DMG installer found in release assets", isErr: true)
                    }
                } else {
                    await updateStatus(silentOnNoUpdate ? nil : "You are up to date! (Version \(currentTag))")
                }
            } catch {
                await updateStatus("Failed to check: \(error.localizedDescription)", isErr: true)
            }
        }
    }
    
    private func updateStatus(_ msg: String?, isErr: Bool = false) async {
        await MainActor.run {
            self.isChecking = false
            self.statusMessage = msg
        }
    }
    
    private func downloadAndInstallDMG(from urlString: String) async throws {
        guard let url = URL(string: urlString) else {
            await updateStatus("Invalid download asset URL", isErr: true)
            return
        }
        
        let tempDir = NSTemporaryDirectory()
        let localDMGURL = URL(fileURLWithPath: tempDir).appendingPathComponent("Buffer-Mac-Download.dmg")
        
        try? FileManager.default.removeItem(at: localDMGURL)
        
        let (downloadURL, _) = try await URLSession.shared.download(from: url)
        try FileManager.default.moveItem(at: downloadURL, to: localDMGURL)
        
        await updateStatus("Mounting installer...")
        
        let mountProcess = Process()
        mountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mountProcess.arguments = ["mount", "-nobrowse", "-readonly", localDMGURL.path]
        try mountProcess.run()
        mountProcess.waitUntilExit()
        
        guard mountProcess.terminationStatus == 0 else {
            await updateStatus("Failed to mount installer DMG", isErr: true)
            return
        }
        
        await updateStatus("Installing and restarting...")
        
        let currentAppPath = Bundle.main.bundlePath
        let volumePath = "/Volumes/Buffer-Mac"
        let sourceAppPath = "\(volumePath)/BufferMenubar.app"
        
        let script = """
        sleep 1.2
        rm -rf "\(currentAppPath)"
        cp -R "\(sourceAppPath)" "\(currentAppPath)"
        hdiutil detach "\(volumePath)" -force
        open "\(currentAppPath)"
        """
        
        let restartProcess = Process()
        restartProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
        restartProcess.arguments = ["-c", script]
        
        try restartProcess.run()
        
        await MainActor.run {
            NSApp.terminate(nil)
        }
    }
}
