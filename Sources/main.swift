import AppKit
import Foundation

// Disable standard output buffering to ensure prints stream in real-time to pipes/logs
setbuf(stdout, nil)
// Setting accessory policy ensures it does not appear in CMD+Tab or in the Dock.
NSApplication.shared.setActivationPolicy(.accessory)

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
