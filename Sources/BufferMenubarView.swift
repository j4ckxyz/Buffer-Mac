import SwiftUI

struct BufferMenubarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAuthenticated = false
    @State private var isChecking = true
    @State private var errorMessage: String? = nil
    
    var body: some View {
        ZStack {
            // High-fidelity native macOS popover frosted glass vibrancy backdrop
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
            
            if isChecking {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.blue))
                        .scaleEffect(1.2)
                    
                    Text("Connecting to Buffer...")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                }
            } else if isAuthenticated {
                ComposerView(onLogout: {
                    KeychainHelper.deleteToken()
                    Storage.clearAll()
                    withAnimation(authAnimation) {
                        isAuthenticated = false
                    }
                })
                .transition(authTransition(forComposer: true))
            } else {
                LoginView(onLoginSuccess: { token in
                    KeychainHelper.saveToken(token)
                    withAnimation(authAnimation) {
                        isAuthenticated = true
                    }
                })
                .transition(authTransition(forComposer: false))
            }
        }
        .frame(width: 360, height: 480)
        .onAppear {
            checkAuthStatus()
        }
    }
    
    private func checkAuthStatus() {
        guard let token = KeychainHelper.getToken() else {
            isChecking = false
            isAuthenticated = false
            return
        }
        
        Task {
            do {
                // Verify the stored key is still valid
                _ = try await BufferAPI.shared.verifyTokenAndGetOrganizations(token: token)
                await MainActor.run {
                    withAnimation(authAnimation) {
                        isAuthenticated = true
                        isChecking = false
                    }
                }
            } catch {
                // Token is stale or invalid, clear and prompt login
                KeychainHelper.deleteToken()
                await MainActor.run {
                    withAnimation(authAnimation) {
                        isAuthenticated = false
                        isChecking = false
                    }
                }
            }
        }
    }
    
    private var authAnimation: Animation? {
        reduceMotion ? nil : .timingCurve(0.25, 1, 0.5, 1, duration: 0.32)
    }
    
    private func authTransition(forComposer: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        
        return .asymmetric(
            insertion: .move(edge: forComposer ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forComposer ? .leading : .trailing).combined(with: .opacity)
        )
    }
}

// MARK: - VisualEffectView Representable

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
