import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: EventMonitor?
    
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
            if let appIcon = NSImage(named: "AppIcon") {
                appIcon.size = NSSize(width: 18, height: 18)
                appIcon.isTemplate = false
                button.image = appIcon
            } else if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Buffer Composer")
            } else {
                button.title = "⚡️"
            }
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
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
