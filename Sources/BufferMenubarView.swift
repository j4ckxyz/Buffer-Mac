import SwiftUI

struct BufferMenubarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAuthenticated = false
    @State private var isChecking = true
    @State private var errorMessage: String? = nil
    
    var body: some View {
        ZStack {
            // Hard solid background that adapts perfectly to light and dark modes
            if #available(macOS 26, *) {
                // Let the system popover glass handle the background
            } else {
                Color(NSColor.windowBackgroundColor)
                    .edgesIgnoringSafeArea(.all)
            }
            
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
        if KeychainHelper.getToken() != nil {
            isAuthenticated = true
            isChecking = false
        } else {
            isAuthenticated = false
            isChecking = false
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
