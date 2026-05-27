import SwiftUI

struct LoginView: View {
    let onLoginSuccess: (String) -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTokenFocused: Bool
    @State private var tokenInput = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var isHoveringLink = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Beautiful floating stacked squares to reflect Buffer logo layers
            VStack(spacing: -8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(45))
                    .scaleEffect(0.8)
                    .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(gradient: Gradient(colors: [Color.purple, Color.indigo]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(45))
                    .offset(y: -8)
                    .scaleEffect(0.6)
            }
            .padding(.bottom, 8)
            
            VStack(spacing: 8) {
                Text("Buffer Composer")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Quickly post text & media directly from your macOS menu bar.")
                    .font(.system(.caption, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .padding(.horizontal, 24)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("BUFFER API TOKEN")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
                    .tracking(1.5)
                
                TextField("Paste your Bearer Token here...", text: $tokenInput)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isTokenFocused ? Color.blue.opacity(0.45) : Color.white.opacity(0.1), lineWidth: isTokenFocused ? 1.4 : 1)
                    )
                    .scaleEffect(isTokenFocused && !reduceMotion ? 1.004 : 1)
                    .animation(formAnimation, value: isTokenFocused)
                    .foregroundColor(.white)
                    .font(.system(.body, design: .monospaced))
                    .disableAutocorrection(true)
                    .focused($isTokenFocused)
            }
            .padding(.horizontal, 28)
            
            if let error = errorMessage {
                Text(error)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
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
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                    ? Color.white.opacity(0.1)
                    : Color.blue
                )
                .cornerRadius(10)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            .padding(.horizontal, 28)
            
            Button(action: openTokenSetupPage) {
                Text("Where do I find my API key?")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(isHoveringLink ? .white : .blue)
                    .underline(isHoveringLink)
                    .onHover { isHovering in
                        withAnimation(formAnimation) {
                            isHoveringLink = isHovering
                        }
                    }
            }
            .buttonStyle(ScaleButtonStyle())
            
            // Privacy Transparency Notice for Third-Party Media Uploads
            VStack(spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .padding(.top, 1)
                    
                    Text("Privacy Note: Buffer requires public web links to publish media. Local attachments are uploaded securely and anonymously to Catbox.moe (third-party hosting) before posting.")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.gray.opacity(0.8))
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.03))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.04), lineWidth: 1)
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
                _ = try await BufferAPI.shared.verifyTokenAndGetOrganizations(token: cleanToken)
                await MainActor.run {
                    isLoading = false
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
