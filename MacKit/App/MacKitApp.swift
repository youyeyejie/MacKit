import AppKit
import Carbon
import SwiftUI

@main
struct MacKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("设置…") { delegate.showWindow() }
                        .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(replacing: .appInfo) {
                    Button("关于 MacKit") {
                        delegate.model.page = .about
                        delegate.showWindow()
                    }
                }
                CommandGroup(replacing: .help) {}
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var window: NSWindow?
    private var settingsWindowOpen = false
    private var hotkeys: GlobalHotKeys?
    private var statusItem: NSStatusItem?
    private var launched = false
    private var receivedCommand = false
    private var pendingCommands: [AppCommand] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.appearanceChanged = { [weak self] in self?.applyAppearance() }
        model.registerShortcuts = { [weak self] show, clean in
            guard let self, let hotkeys = self.hotkeys else { return "快捷键服务尚未就绪" }
            return hotkeys.configure(show: show, clean: clean) ? nil : hotkeys.error
        }
        model.recordingChanged = { [weak self] recording in
            if recording { self?.hotkeys?.suspend() } else { self?.hotkeys?.resume() }
            self?.model.windowSwitcher.setSuspended(recording)
            self?.model.missionControl.setSuspended(recording)
            self?.model.dockEnhancement.setSuspended(recording)
        }
        NotchIntegration.shared.openSettings = { [weak self] in
            self?.model.page = .atoll
            self?.showWindow()
        }
        NotchIntegration.shared.start(notification)
        NSApp.applicationIconImage = AppBrand.icon
        applyAppearance()
        hotkeys = GlobalHotKeys(
            show: { [weak self] in self?.showWindow() },
            clean: { [weak self] in
                self?.showWindow()
                self?.model.cleaning.begin()
            })
        _ = hotkeys?.configure(show: model.shortcuts.show, clean: model.shortcuts.clean)
        model.message = hotkeys?.error
        let login =
            NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        launched = true
        let commands = pendingCommands
        pendingCommands.removeAll()
        for command in commands { perform(command) }
        if !login {
            // Launch Services may deliver the URL just after didFinishLaunching.
            // This is a single startup deferral, not a polling timer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, !self.receivedCommand else { return }
                self.showWindow()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NotchIntegration.shared.delegate?.application(application, open: urls.filter(\.isFileURL))
        for url in urls {
            guard let command = AppCommand(url: url) else { continue }
            receivedCommand = true
            if launched { perform(command) } else { pendingCommands.append(command) }
        }
    }

    private func perform(_ command: AppCommand) {
        switch command {
        case .wallpaper:
            model.page = .wallpaper
            showWindow()
        case .clean:
            model.permissions.refresh()
            model.cleaning.begin()
            if !model.cleaning.active {
                model.page = model.permissions.accessibility ? .cleaning : .permissions
                showWindow()
            }
        }
    }

    func showWindow() {
        if window == nil {
            let view = MainView(model: model)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.styleMask.insert(.fullSizeContentView)
            window.collectionBehavior.insert(.fullScreenNone)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.title = "MacKit"
            window.titleVisibility = .hidden
            window.delegate = self
            // Content gestures (especially the lock-screen layout editor) must not
            // fall through to AppKit's background window dragging.
            window.isMovableByWindowBackground = false
            window.contentView = NSHostingView(rootView: view)
            if let frameView = window.contentView?.superview {
                frameView.wantsLayer = true
                frameView.layer?.cornerRadius = AppStyle.windowRadius
                frameView.layer?.masksToBounds = true
            }
            window.minSize = NSSize(width: 720, height: 540)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.permissions.refresh()
        model.refreshLogin()
        settingsWindowOpen = true
        updateDockVisibility()
        window?.makeKeyAndOrderFront(nil)
        if let window {
            DispatchQueue.main.async { [weak self, weak window] in
                if let window { self?.positionWindowControls(window) }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow, closedWindow === window else { return }
        settingsWindowOpen = false
        updateDockVisibility()
    }

    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow { positionWindowControls(window) }
    }

    private func positionWindowControls(_ window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
            let container = closeButton.superview,
            let parent = container.superview,
            let frameView = window.contentView?.superview
        else { return }

        // Preserve AppKit's shared rollover tracking and native button hierarchy.
        // Move the titlebar container instead of reparenting individual buttons.
        let buttonFrame = closeButton.convert(closeButton.bounds, to: frameView)
        let targetY = frameView.isFlipped ? 32 - buttonFrame.height : frameView.bounds.height - 32
        let current = parent.convert(buttonFrame.origin, from: frameView)
        let target = parent.convert(NSPoint(x: 23, y: targetY), from: frameView)
        container.setFrameOrigin(NSPoint(
            x: container.frame.minX + target.x - current.x,
            y: container.frame.minY + target.y - current.y))
        container.updateTrackingAreas()
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.updateTrackingAreas()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.permissions.refresh()
        model.refreshLogin()
        model.finderCut.sync()
        model.missionControl.sync()
        model.windowSwitcher.sync()
        model.dockEnhancement.sync()
    }

    private func updateDockVisibility() {
        let policy: NSApplication.ActivationPolicy = model.showDock || settingsWindowOpen ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    private func applyAppearance() {
        updateDockVisibility()
        if model.showMenuBar, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = AppBrand.menuBarIcon
            let menu = NSMenu()
            for page in [AppPage.cleaning, .finder, .windowSwitcher, .wallpaper, .atoll, .lockScreen, .settings, .permissions, .about] {
                let entry = NSMenuItem(title: page.rawValue + "…", action: #selector(openPageFromMenu(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = page.rawValue
                menu.addItem(entry)
            }
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "退出 MacKit", action: #selector(quitFromMenu), keyEquivalent: "q")
            quit.target = self
            menu.addItem(quit)
            item.menu = menu
            statusItem = item
        } else if !model.showMenuBar, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
    @objc private func openPageFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let page = AppPage(rawValue: rawValue) else { return }
        model.page = page
        showWindow()
    }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        NotchIntegration.shared.stop(notification)
        model.wallpaper.stop()
        model.cleaning.onActivity = nil
        model.cleaning.stop()
        model.finderCut.stop()
        model.missionControl.stop()
        model.windowSwitcher.stop()
        model.dockEnhancement.stop()
        hotkeys?.stop()
    }
}
