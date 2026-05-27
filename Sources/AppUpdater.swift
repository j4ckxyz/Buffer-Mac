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
        let name: String?
        let body: String?
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
                guard let latestVersion = Self.versionString(from: release) else {
                    await updateStatus("No updates available")
                    return
                }
                
                let currentTag = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
                
                if latestVersion.compare(currentTag, options: .numeric) == .orderedDescending {
                    await MainActor.run {
                        self.latestVersionString = latestVersion
                        self.updateAvailable = true
                    }
                    
                    if let dmgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) {
                        await updateStatus("Downloading version \(latestVersion)...", isComplete: false)
                        try await downloadAndInstallDMG(from: dmgAsset.browser_download_url)
                    } else {
                        await updateStatus("No DMG installer found in release assets", isErr: true)
                    }
                } else {
                    await updateStatus(silentOnNoUpdate ? nil : "No updates available")
                }
            } catch {
                await updateStatus("Failed to check: \(error.localizedDescription)", isErr: true)
            }
        }
    }
    
    private func updateStatus(_ msg: String?, isErr: Bool = false, isComplete: Bool = true) async {
        await MainActor.run {
            self.isChecking = !isComplete
            self.statusMessage = msg
        }
    }
    
    private static func versionString(from release: GitHubRelease) -> String? {
        if let tagVersion = normalizedVersionString(release.tag_name) {
            return tagVersion
        }
        
        if let bodyVersion = firstVersionString(in: release.body) {
            return bodyVersion
        }
        
        return firstVersionString(in: release.name)
    }
    
    private static func normalizedVersionString(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        let parts = withoutPrefix.split(separator: ".")
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        return withoutPrefix
    }
    
    private static func firstVersionString(in text: String?) -> String? {
        guard let text else { return nil }
        let pattern = #"\b(?:Version\s+)?([0-9]+(?:\.[0-9]+){1,2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let versionRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[versionRange])
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
        
        await updateStatus("Mounting installer...", isComplete: false)
        
        let mountURL = try await mountDMG(at: localDMGURL)
        var didDetach = false
        defer {
            if !didDetach {
                _ = try? runProcess(executable: "/usr/bin/hdiutil", arguments: ["detach", mountURL.path, "-force"])
            }
        }
        
        let sourceAppURL = mountURL.appendingPathComponent("BufferMenubar.app")
        guard FileManager.default.fileExists(atPath: sourceAppURL.path) else {
            await updateStatus("Installer did not contain BufferMenubar.app", isErr: true)
            return
        }
        
        let stagedAppURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BufferMenubar-\(UUID().uuidString)")
            .appendingPathExtension("app")
        try? FileManager.default.removeItem(at: stagedAppURL)
        try FileManager.default.copyItem(at: sourceAppURL, to: stagedAppURL)
        _ = try runProcess(executable: "/usr/bin/hdiutil", arguments: ["detach", mountURL.path, "-force"])
        didDetach = true
        
        await updateStatus("Installing and restarting...", isComplete: false)
        try launchReplacementScript(stagedAppURL: stagedAppURL, targetAppURL: URL(fileURLWithPath: Bundle.main.bundlePath))
        
        await MainActor.run {
            NSApp.terminate(nil)
        }
    }
    
    private func mountDMG(at dmgURL: URL) async throws -> URL {
        let output = try runProcess(
            executable: "/usr/bin/hdiutil",
            arguments: ["attach", "-plist", "-nobrowse", "-readonly", dmgURL.path]
        )
        
        guard let plist = try PropertyListSerialization.propertyList(from: output, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw UpdateError.mountPointNotFound
        }
        
        return URL(fileURLWithPath: mountPoint)
    }
    
    private func launchReplacementScript(stagedAppURL: URL, targetAppURL: URL) throws {
        let script = """
        set -e
        staged_app="$1"
        target_app="$2"
        target_parent="$(dirname "$target_app")"
        target_name="$(basename "$target_app")"
        replacement_app="${target_parent}/.${target_name}.updating"
        
        sleep 1.2
        rm -rf "$replacement_app"
        mv "$staged_app" "$replacement_app"
        rm -rf "$target_app"
        mv "$replacement_app" "$target_app"
        open "$target_app"
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script, "buffer-menubar-updater", stagedAppURL.path, targetAppURL.path]
        try process.run()
    }
    
    private func runProcess(executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus == 0 {
            return output
        }
        
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Process failed"
        throw UpdateError.processFailed(errorMessage.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    enum UpdateError: LocalizedError {
        case mountPointNotFound
        case processFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .mountPointNotFound:
                return "Could not find the mounted installer volume."
            case .processFailed(let message):
                return message.isEmpty ? "Installer command failed." : message
            }
        }
    }
}
