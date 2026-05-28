import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: EventMonitor?
    public var isShowingOpenPanel = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[BufferMenubar] App launched, initializing components...")
        setupStatusItem()
        setupPopover()
        setupEventMonitor()
        setupMainMenu()
        
        // Setup Global Hotkey trigger to toggle popover
        GlobalHotkeyManager.shared.onTrigger = { [weak self] in
            guard let self = self else { return }
            self.togglePopover(nil)
        }
        GlobalHotkeyManager.shared.registerCurrentShortcut()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkeyManager.shared.unregister()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            button.image = createBufferMenuIcon()
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }
    
    private func createBufferMenuIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let svgPathString = "M427.84 380.67l-196.5 97.82a18.6 18.6 0 0 1-14.67 0L20.16 380.67c-4-2-4-5.28 0-7.29L67.22 350a18.65 18.65 0 0 1 14.69 0l134.76 67a18.51 18.51 0 0 0 14.67 0l134.76-67a18.62 18.62 0 0 1 14.68 0l47.06 23.43c4.05 1.96 4.05 5.24 0 7.24zm0-136.53l-47.06-23.43a18.62 18.62 0 0 0-14.68 0l-134.76 67a18.51 18.51 0 0 1-14.67 0l-134.76-67a18.65 18.65 0 0 0-14.69 0L20.16 244.12c-4 2-4 5.28 0 7.29l196.5 97.82a18.6 18.6 0 0 0 14.67 0l196.5-97.82c4-2 4-5.28 0-7.29zM427.84 107.57l-196.5 97.82a18.6 18.6 0 0 1-14.67 0L20.16 107.57c-4-2-4-5.28 0-7.29L67.22 76.85a18.65 18.65 0 0 1 14.69 0l134.76 67a18.51 18.51 0 0 0 14.67 0l134.76-67a18.62 18.62 0 0 1 14.68 0l47.06 23.43c4.05 1.96 4.05 5.24 0 7.24z"
            
            NSColor.labelColor.set()
            
            // Render inside a 14x14 box inside the 18x18 bounds (centered with 2px margins)
            let iconRect = NSRect(x: 2, y: 2, width: 14, height: 14)
            let path = SVGPath(svgPathString: svgPathString, viewBox: CGRect(x: 0, y: 0, width: 448, height: 512), targetRect: iconRect).bezierPath
            path.fill()
            
            return true
        }
        image.isTemplate = true
        return image
    }

    
    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient
        
        let contentView = BufferMenubarView()
        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover
    }
    
    private func setupEventMonitor() {
        // Register event monitor to catch mouse down events outside our popover
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return }
            if self.popover.isShown {
                if self.isShowingOpenPanel {
                    print("[BufferMenubar] Event monitor: NSOpenPanel active, ignoring click-off.")
                    return
                }
                
                // If composer holds an active draft, keep the popover open so the user can drag-and-drop
                // media or links from other windows (Finder, Safari) without it disappearing!
                let draftText = Storage.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
                if draftText.isEmpty {
                    print("[BufferMenubar] Event monitor: empty composer, auto-hiding popover...")
                    self.closePopover(event)
                } else {
                    print("[BufferMenubar] Event monitor: composer has text draft, ignoring click-off to support drag-and-drop workflow.")
                }
            }
        }
    }
    
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    
    @objc func openSettingsMenuAction(_ sender: Any?) {
        openSettingsWindow()
    }
    
    @objc func openAboutMenuAction(_ sender: Any?) {
        openAboutWindow()
    }
    
    func openSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        self.settingsWindow = window
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func openAboutWindow() {
        if let window = aboutWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Buffer Composer"
        window.center()
        window.contentViewController = NSHostingController(rootView: AboutView())
        window.isReleasedWhenClosed = false
        self.aboutWindow = window
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        appMenu.addItem(withTitle: "About Buffer Composer", action: #selector(openAboutMenuAction(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Preferences...", action: #selector(openSettingsMenuAction(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        // Edit Menu (Required for system copy/paste shortcuts to work in key popovers)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        editMenuItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
        print("[BufferMenubar] Built and assigned native system Edit menu shortcuts.")
    }
    
    func showPopover() {
        guard let button = statusItem.button else { return }
        print("[BufferMenubar] Showing popover...")
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        eventMonitor?.start()
    }
    
    func closePopover(_ sender: Any?) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            print("[BufferMenubar] Toggling popover: Closing...")
            closePopover(sender)
        } else {
            print("[BufferMenubar] Toggling popover: Opening...")
            showPopover()
        }
    }
}

// MARK: - EventMonitor Utility

final class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void
    
    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    func start() {
        // Only register if not already running
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    
    func stop() {
        guard let currentMonitor = monitor else { return }
        NSEvent.removeMonitor(currentMonitor)
        monitor = nil
    }
}
