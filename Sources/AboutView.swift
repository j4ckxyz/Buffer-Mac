import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (Build \(build))"
    }
    
    // Replace with your final release URLs before publishing.
    private let githubURL = URL(string: "https://github.com/jack/buffer-menubar")!
    private let tangledURL = URL(string: "https://tangled.org/@jack/buffer-menubar")!
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(Color.accentColor)
                .padding(.top, 16)
            
            VStack(spacing: 3) {
                Text("Buffer Composer")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                
                Text(appVersion)
                    .font(.system(size: 10))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            
            Text("Unofficial open-source menu bar composer for Buffer.")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
            
            Text("Not affiliated with, endorsed by, or sponsored by Buffer.")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(Color.orange)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
            
            HStack(spacing: 14) {
                Link("GitHub", destination: githubURL)
                Link("Tangled", destination: tangledURL)
            }
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .padding(.top, 2)
            
            Text("© 2026 Jack • Released as open source")
                .font(.system(size: 9))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .padding(.top, 2)
            
            Spacer()
        }
        .frame(width: 320, height: 250)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }
}
