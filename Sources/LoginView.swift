import SwiftUI
import AppKit

struct BufferLogoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateSlabs = false
    
    var body: some View {
        logoImage
            .shadow(color: Color.blue.opacity(0.25), radius: 6, x: 0, y: 3)
            .offset(y: animateSlabs && !reduceMotion ? -4 : 0)
            .padding(.vertical, 8)
            .onAppear {
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                        animateSlabs = true
                    }
                }
            }
    }
    
    @ViewBuilder
    private var logoImage: some View {
        if let appIcon = NSImage(named: "AppIcon") {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 78, height: 78)
        } else {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

struct LoginView: View {
    let onLoginSuccess: (String) -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTokenFocused: Bool
    @State private var tokenInput = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            // Accessible Top Utility Bar for Preferences and Quit
            HStack(spacing: 12) {
                Spacer()
                
                Button(action: {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.openSettingsWindow()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                Text("|")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.3))
                
                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                        Text("Quit")
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            
            Spacer()
            
            // 3-Slab Isometric Vector Buffer Logo
            BufferLogoView()
            
            // App Branding Title
            VStack(spacing: 4) {
                Text("Buffer for Mac")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Unofficial FOSS Client")
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            
            // Secure Client-Side OAuth Personal Token Guide
            VStack(alignment: .leading, spacing: 8) {
                Text("SECURE DIRECT AUTHENTICATION")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
                    .tracking(1.2)
                
                Text("This app is a client-side FOSS utility that communicates directly with Buffer. We do not use intermediate servers. Please generate a secure developer OAuth token to sign in.")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button(action: openTokenSetupPage) {
                    HStack(spacing: 5) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 10))
                        Text("Create Personal Access Token")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    }
                }
                .buttonStyle(BorderedButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 28)
            
            // Token Inputs
            VStack(alignment: .leading, spacing: 6) {
                Text("ENTER BEARER ACCESS TOKEN")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
                    .tracking(1.2)
                
                TextField("Paste your Bearer Token here...", text: $tokenInput)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isTokenFocused ? Color.blue : Color.primary.opacity(0.12), lineWidth: isTokenFocused ? 1.5 : 1)
                    )
                    .scaleEffect(isTokenFocused && !reduceMotion ? 1.002 : 1)
                    .animation(formAnimation, value: isTokenFocused)
                    .foregroundColor(.primary)
                    .font(.system(.body, design: .monospaced))
                    .disableAutocorrection(true)
                    .focused($isTokenFocused)
            }
            .padding(.horizontal, 28)
            
            if let error = errorMessage {
                Text(error)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .transition(.opacity)
            }
            
            // Connect Button
            Button(action: handleLogin) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text("Connect Account")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading ? .secondary : .white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                    ? Color.primary.opacity(0.1)
                    : Color.blue
                )
                .cornerRadius(8)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            .padding(.horizontal, 28)
            
            // Highly Readable, High-Contrast Privacy and Affiliation Warnings
            VStack(spacing: 6) {
                // Privacy and Media Uploads Warning
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    
                    Text("Privacy Warning: Buffer requires public web paths to publish media. Any local images or videos will be uploaded securely and anonymously to Catbox.moe (a third-party server) before posting.")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
                
                // Unofficial Client Disclaimer
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    
                    Text("Disclaimer: This is an unofficial FOSS app and is not affiliated, endorsed, or officially connected with Buffer Inc.")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(.horizontal, 28)
            
            Spacer()
        }
        .padding(.vertical, 16)
        .animation(formAnimation, value: errorMessage)
    }
    
    private func handleLogin() {
        let cleanToken = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }
        
        withAnimation(formAnimation) {
            isLoading = true
            errorMessage = nil
        }
        
        Task {
            do {
                let account = try await BufferAPI.shared.verifyTokenAndGetOrganizations(token: cleanToken)
                
                // Fetch and cache all channels immediately to avoid redundant API calls later
                var allChannels: [Storage.CachedChannel] = []
                for org in account.organizations {
                    let orgChannels = try await BufferAPI.shared.fetchChannels(forOrganizationId: org.id, token: cleanToken)
                    for item in orgChannels {
                        allChannels.append(Storage.CachedChannel(id: item.id, name: item.name, service: item.service))
                    }
                }
                
                await MainActor.run {
                    Storage.cachedChannels = allChannels
                    
                    // Pre-select the first channel if no channels are currently selected
                    if Storage.selectedChannelIds.isEmpty, let first = allChannels.first {
                        Storage.selectedChannelIds = [first.id]
                    }
                    
                    isLoading = false
                    Storage.userEmail = account.email
                    onLoginSuccess(cleanToken)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func openTokenSetupPage() {
        if let url = URL(string: "https://publish.buffer.com/settings/api") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private var formAnimation: Animation? {
        reduceMotion ? nil : .timingCurve(0.25, 1, 0.5, 1, duration: 0.2)
    }
}
