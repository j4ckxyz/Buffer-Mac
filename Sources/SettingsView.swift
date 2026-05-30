import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var apiToken = KeychainHelper.getToken() ?? ""
    @State private var defaultMode = UserDefaults.standard.string(forKey: "default_post_mode") ?? "shareNow"
    @State private var hotkeyModifier = UserDefaults.standard.string(forKey: "hotkey_modifier") ?? "Option"
    @State private var hotkeyKey = UserDefaults.standard.string(forKey: "hotkey_key") ?? "Space"
    @State private var activeTab: String = "general"
    @State private var isSaved = false
    @State private var isTesting = false
    @State private var testResult: String? = nil
    
    // Updates State
    @State private var updateCheckResult: String? = nil
    @State private var updateDownloadUrl: String? = nil
    @State private var isCheckingUpdates = false
    
    private struct GitHubRelease: Codable {
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: String
    }
    
    var body: some View {
        if #available(macOS 16.0, *) {
            tahoeBody
        } else {
            legacyBody
        }
    }
    
    // MARK: - macOS 16+ Tahoe Native View (Borderless & Capsule-style tabs)
    @ViewBuilder
    private var tahoeBody: some View {
        VStack(spacing: 0) {
            // MARK: - Tahoe Centered Capsule Header
            HStack(spacing: 16) {
                Spacer()
                
                TahoeTabButton(title: "General", systemImage: "gearshape", isActive: activeTab == "general") {
                    withAnimation { activeTab = "general" }
                }
                
                TahoeTabButton(title: "Accounts", systemImage: "person.crop.circle", isActive: activeTab == "accounts") {
                    withAnimation { activeTab = "accounts" }
                }
                
                Spacer()
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // MARK: - Tab Panels Content (Borderless with auto-save)
            VStack {
                if activeTab == "general" {
                    ScrollView {
                        generalGridContent
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    ScrollView {
                        accountsGridContent
                            .padding(.horizontal, 28)
                            .padding(.vertical, 20)
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 480, height: 280)
        .modifier(SettingsBackgroundModifier())
        // Observe and Auto-save General settings changes in real-time
        .onChange(of: defaultMode) { _ in saveGeneralSettings() }
        .onChange(of: hotkeyModifier) { _ in saveGeneralSettings() }
        .onChange(of: hotkeyKey) { _ in saveGeneralSettings() }
        // Auto-save Token clearing
        .onChange(of: apiToken) { newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                KeychainHelper.deleteToken()
                Storage.userEmail = ""
                Storage.cachedChannels = []
                Storage.selectedChannelIds = []
                testResult = nil
            }
        }
    }
    
    // MARK: - Legacy macOS View (Classic Segmented Tabs and Save Button)
    @ViewBuilder
    private var legacyBody: some View {
        VStack(spacing: 0) {
            // MARK: - Premium Tabbed Toolbar (Accessible, FOSS Two-Tab Layout)
            HStack(spacing: 16) {
                Spacer()
                
                TabButton(title: "General", systemImage: "gearshape", isActive: activeTab == "general") {
                    withAnimation { activeTab = "general" }
                }
                
                TabButton(title: "Accounts", systemImage: "person.crop.circle", isActive: activeTab == "accounts") {
                    withAnimation { activeTab = "accounts" }
                }
                
                Spacer()
            }
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            
            Divider()
            
            // MARK: - Tab Panels Content
            VStack {
                if activeTab == "general" {
                    ScrollView {
                        generalGridContent
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    accountsGridContent
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // MARK: - Save and Pinned Actions footer
            HStack {
                Spacer()
                
                if isSaved {
                    Text("Saved!")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                
                Button("Save Settings") {
                    saveChanges()
                }
                .buttonStyle(DefaultButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        }
        .frame(width: 480, height: 330)
        .modifier(SettingsBackgroundModifier())
    }
    
    // MARK: - Shared Grid Subviews (Consistent layout across designs)
    
    @ViewBuilder
    private var generalGridContent: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                Text("Global Shortcut:")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .gridCellAnchor(.trailing)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Picker("Modifier", selection: $hotkeyModifier) {
                            Text("Option ⌥").tag("Option")
                            Text("Command ⌘").tag("Command")
                            Text("Control ⌃").tag("Control")
                            Text("Shift ⇧").tag("Shift")
                            Divider()
                            Text("Cmd + Opt ⌘⌥").tag("Cmd + Opt")
                            Text("Cmd + Shift ⌘⇧").tag("Cmd + Shift")
                            Text("Opt + Shift ⌥⇧").tag("Opt + Shift")
                            Text("Ctrl + Opt ⌃⌥").tag("Ctrl + Opt")
                            Text("Ctrl + Cmd ⌃⌘").tag("Ctrl + Cmd")
                            Divider()
                            Text("Hyperkey ⌘⌥⌃⇧").tag("Hyperkey")
                        }
                        .frame(width: 140)
                        .labelsHidden()
                        
                        Picker("Key", selection: $hotkeyKey) {
                            Text("Spacebar").tag("Space")
                            Text("Enter").tag("Enter")
                            Divider()
                            ForEach(["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"], id: \.self) { letter in
                                Text(letter).tag(letter)
                            }
                            Divider()
                            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], id: \.self) { num in
                                Text(num).tag(num)
                            }
                        }
                        .frame(width: 100)
                        .labelsHidden()
                    }
                    
                    Text("Hyperkey maps to ⌘⌥⌃⇧ (Cmd + Opt + Ctrl + Shift). Perfect for Karabiner / Caps Lock remappers.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            GridRow {
                Text("Posting Mode:")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .gridCellAnchor(.trailing)
                
                Picker("", selection: $defaultMode) {
                    Text("Post Now").tag("shareNow")
                    Text("Add to Queue").tag("addToQueue")
                }
                .pickerStyle(RadioGroupPickerStyle())
                .horizontalRadioGroupLayout()
                .labelsHidden()
            }

            
            Divider()
                .gridCellColumns(2)
                .padding(.vertical, 6)
            
            // Check for Updates Section
            GridRow {
                Text("Updates:")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .gridCellAnchor(.trailing)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button(action: checkForUpdates) {
                            if isCheckingUpdates {
                                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                            } else {
                                Text("Check for Updates")
                            }
                        }
                        .modifier(GlassButtonModifier())
                        .buttonStyle(BorderedButtonStyle())
                        .disabled(isCheckingUpdates)
                        
                        if let downloadUrl = updateDownloadUrl {
                            Button("Download DMG") {
                                if let url = URL(string: downloadUrl) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(BorderedButtonStyle())
                        }
                    }
                    
                    if let result = updateCheckResult {
                        Text(result)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(result.contains("New Version") ? .green : (result.contains("Failed") ? .red : .primary))
                    } else {
                        Text("Current Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            GridRow {
                Text("System Cache:")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .gridCellAnchor(.trailing)
                
                VStack(alignment: .leading, spacing: 6) {
                    Button("Reset Cache & Shortcuts") {
                        Storage.clearAll()
                        apiToken = ""
                        defaultMode = "shareNow"
                        hotkeyModifier = "Option"
                        hotkeyKey = "Space"
                        
                        UserDefaults.standard.removeObject(forKey: "hotkey_keycode")
                        UserDefaults.standard.removeObject(forKey: "hotkey_carbon_modifiers")
                        UserDefaults.standard.set("Option", forKey: "hotkey_modifier")
                        UserDefaults.standard.set("Space", forKey: "hotkey_key")
                        
                        GlobalHotkeyManager.shared.registerCurrentShortcut()
                        testResult = "Caches and Token reset successfully."
                    }
                    .modifier(GlassButtonModifier())
                    .buttonStyle(BorderedButtonStyle())
                    
                    Text("Clears all cached Buffer profiles, saved text drafts, and resets global open shortcuts to ⌥ Option + Spacebar.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            GridRow {
                Text("Account:")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .gridCellAnchor(.trailing)
                
                VStack(alignment: .leading, spacing: 6) {
                    if KeychainHelper.getToken() == nil {
                        Button(action: {
                            if let delegate = NSApp.delegate as? AppDelegate {
                                delegate.showPopover()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                Text("Login to Buffer")
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                        }
                        .buttonStyle(BorderedButtonStyle())
                    } else {
                        let email = Storage.userEmail
                        Text(email.isEmpty ? "Authenticated (Active Account)" : "Authenticated as \(email)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.green)
                    }
                }
            }
            
            GridRow {
                Text("App Info:")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .gridCellAnchor(.trailing)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Buffer Menubar Composer")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0") (Free & Open Source)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var accountsGridContent: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                Text("API Token:")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .gridCellAnchor(.trailing)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        SecureField("Paste your Bearer Token here...", text: $apiToken)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disableAutocorrection(true)
                        
                        Button(action: testConnection) {
                            if isTesting {
                                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                            } else {
                                Text("Verify")
                            }
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .disabled(apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
                    }
                    
                    Text("Paste your personal Buffer access token to authorise the menubar app.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            GridRow {
                Text("Status:")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .gridCellAnchor(.trailing)
                
                VStack(alignment: .leading, spacing: 6) {
                    if let result = testResult {
                        Text(result)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(result.contains("Success") ? .green : .red)
                    } else {
                        if KeychainHelper.getToken() == nil {
                            HStack(spacing: 8) {
                                Text("Not authenticated")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                                
                                Button(action: {
                                    if let delegate = NSApp.delegate as? AppDelegate {
                                        delegate.showPopover()
                                    }
                                }) {
                                    Text("Login")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .buttonStyle(BorderedButtonStyle())
                            }
                        } else {
                            let email = Storage.userEmail
                            Text(email.isEmpty ? "Authenticated (Active Account)" : "Authenticated as \(email)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.green)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Save Operations
    
    private func saveGeneralSettings() {
        UserDefaults.standard.set(defaultMode, forKey: "default_post_mode")
        UserDefaults.standard.set(hotkeyModifier, forKey: "hotkey_modifier")
        UserDefaults.standard.set(hotkeyKey, forKey: "hotkey_key")
        
        UserDefaults.standard.removeObject(forKey: "hotkey_keycode")
        UserDefaults.standard.removeObject(forKey: "hotkey_carbon_modifiers")
        
        GlobalHotkeyManager.shared.registerCurrentShortcut()
    }
    
    private func saveChanges() {
        let cleanToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanToken.isEmpty {
            KeychainHelper.deleteToken()
            Storage.userEmail = ""
        } else {
            KeychainHelper.saveToken(cleanToken)
        }
        
        saveGeneralSettings()
        
        withAnimation {
            isSaved = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                isSaved = false
            }
        }
    }
    
    private func testConnection() {
        let cleanToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }
        
        isTesting = true
        testResult = nil
        
        Task {
            do {
                let account = try await BufferAPI.shared.verifyTokenAndGetOrganizations(token: cleanToken)
                
                // Fetch and cache the channels right now to prevent redundant future calls!
                var allChannels: [Storage.CachedChannel] = []
                for org in account.organizations {
                    let orgChannels = try await BufferAPI.shared.fetchChannels(forOrganizationId: org.id, token: cleanToken)
                    for item in orgChannels {
                        allChannels.append(Storage.CachedChannel(id: item.id, name: item.name, service: item.service))
                    }
                }
                
                await MainActor.run {
                    isTesting = false
                    Storage.userEmail = account.email
                    Storage.cachedChannels = allChannels
                    
                    // If selection is empty, auto-check the first available profile
                    if Storage.selectedChannelIds.isEmpty, let first = allChannels.first {
                        Storage.selectedChannelIds = [first.id]
                    }
                    
                    KeychainHelper.saveToken(cleanToken) // Auto-save verified token!
                    testResult = "Success: Connected as \(account.email)"
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testResult = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func checkForUpdates() {
        isCheckingUpdates = true
        updateCheckResult = nil
        updateDownloadUrl = nil
        
        guard let url = URL(string: "https://api.github.com/repos/j4ckxyz/Buffer-Mac/releases/latest") else {
            isCheckingUpdates = false
            updateCheckResult = "Failed: Invalid update URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Buffer-Mac Updater", forHTTPHeaderField: "User-Agent")
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    await MainActor.run {
                        isCheckingUpdates = false
                        updateCheckResult = "Failed: Network error"
                    }
                    return
                }
                
                if httpResponse.statusCode == 404 {
                    await MainActor.run {
                        isCheckingUpdates = false
                        updateCheckResult = "No releases published yet on GitHub."
                    }
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    await MainActor.run {
                        isCheckingUpdates = false
                        updateCheckResult = "Failed: HTTP \(httpResponse.statusCode)"
                    }
                    return
                }
                
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                
                await MainActor.run {
                    isCheckingUpdates = false
                    guard let latestTag = versionString(from: release) else {
                        updateCheckResult = "No updates available"
                        return
                    }
                    
                    let currentTag = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                    
                    if latestTag.compare(currentTag, options: .numeric) == .orderedDescending {
                        updateCheckResult = "New Version \(latestTag) Available!"
                        updateDownloadUrl = release.html_url
                    } else {
                        updateCheckResult = "No updates available"
                    }
                }
            } catch {
                await MainActor.run {
                    isCheckingUpdates = false
                    updateCheckResult = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func versionString(from release: GitHubRelease) -> String? {
        if let tagVersion = normalizedVersionString(release.tag_name) {
            return tagVersion
        }
        
        if let bodyVersion = firstVersionString(in: release.body) {
            return bodyVersion
        }
        
        return firstVersionString(in: release.name)
    }
    
    private func normalizedVersionString(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        let parts = withoutPrefix.split(separator: ".")
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        return withoutPrefix
    }
    
    private func firstVersionString(in text: String?) -> String? {
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
}

// MARK: - Legacy Visual Toolbar TabButton Subview

struct TabButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundColor(isActive ? .primary : .secondary)
                Text(title)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? .primary : .secondary)
            }
            .frame(width: 80, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.primary.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isActive ? Color.primary.opacity(0.16) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - macOS 16+ Tahoe Visual Toolbar TabButton Subview

struct TahoeTabButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundColor(isActive ? .primary : .secondary)
                Text(title)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? .primary : .secondary)
            }
            .frame(width: 76, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
        } else {
            content
                .background(Color(NSColor.windowBackgroundColor))
        }
    }
}
