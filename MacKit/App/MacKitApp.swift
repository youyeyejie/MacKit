import AppKit
import SwiftUI
import Carbon

@main
struct MacKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let model = AppModel()
    private var window: NSWindow?
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
        AtollIntegration.shared.openSettings = { [weak self] in
            self?.model.page = .atoll
            self?.showWindow()
        }
        AtollIntegration.shared.start(notification)
        NSApp.applicationIconImage = AppBrand.icon
        applyAppearance()
        hotkeys = GlobalHotKeys(show: { [weak self] in self?.showWindow() }, clean: { [weak self] in
            self?.showWindow(); self?.model.cleaning.begin()
        })
        _ = hotkeys?.configure(show: model.shortcuts.show, clean: model.shortcuts.clean)
        model.message = hotkeys?.error
        let login = NSAppleEventManager.shared().currentAppleEvent?
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
        AtollIntegration.shared.delegate?.application(application, open: urls.filter(\.isFileURL))
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 650),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.styleMask.insert(.fullSizeContentView)
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
        window?.makeKeyAndOrderFront(nil)
        if let window {
            DispatchQueue.main.async { [weak self, weak window] in
                if let window { self?.positionWindowControls(window) }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }


    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow { positionWindowControls(window) }
    }

    private func positionWindowControls(_ window: NSWindow) {
        for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(type),
                  let frameView = window.contentView?.superview else { continue }
            // Keep AppKit's titlebar layout from restoring the edge-aligned positions.
            if button.superview !== frameView { frameView.addSubview(button) }
            button.setFrameOrigin(NSPoint(x: 23 + CGFloat(index) * 23,
                                           y: frameView.bounds.height - 32))
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AtollIntegration.shared.delegate?.applicationDidBecomeActive(notification)
        model.permissions.refresh(); model.refreshLogin(); model.finderCut.sync()
        model.missionControl.sync(); model.windowSwitcher.sync(); model.dockEnhancement.sync()
    }

    private func applyAppearance() {
        NSApp.setActivationPolicy(model.showDock ? .regular : .accessory)
        if model.showMenuBar, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = AppBrand.menuBarIcon
            let menu = NSMenu()
            menu.delegate = self
            for (title, selector) in [("打开主面板", #selector(openFromMenu)), ("打开清洁模式", #selector(cleanFromMenu)), ("启用访达剪切", #selector(toggleFinderFromMenu)), ("启用窗口切换预览", #selector(toggleSwitcherFromMenu)), ("启用程序坞增强", #selector(toggleDockFromMenu)), ("退出MacKit", #selector(quitFromMenu))] {
                let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
                entry.target = self; menu.addItem(entry)
            }
            item.menu = menu; statusItem = item
        } else if !model.showMenuBar, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item); statusItem = nil
        }
    }
    @objc private func openFromMenu() { showWindow() }
    @objc private func cleanFromMenu() { model.page = .cleaning; showWindow() }
    @objc private func toggleFinderFromMenu() { model.finderCut.setEnabled(!model.finderCut.enabled) }
    @objc private func toggleSwitcherFromMenu() { model.windowSwitcher.setEnabled(!model.windowSwitcher.enabled) }
    @objc private func toggleDockFromMenu() { model.dockEnhancement.toggleFromMenu() }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first(where: { $0.action == #selector(toggleFinderFromMenu) })?.title = model.finderCut.enabled ? "关闭访达剪切" : "启用访达剪切"
        menu.items.first(where: { $0.action == #selector(toggleSwitcherFromMenu) })?.title = model.windowSwitcher.enabled ? "关闭窗口切换预览" : "启用窗口切换预览"
        menu.items.first(where: { $0.action == #selector(toggleDockFromMenu) })?.title = model.dockEnhancement.enabled ? "关闭程序坞增强" : "启用程序坞增强"
    }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        AtollIntegration.shared.stop(notification)
        model.wallpaper.stop()
        model.cleaning.onActivity = nil
        model.cleaning.stop(); model.finderCut.stop()
        model.missionControl.stop(); model.windowSwitcher.stop(); model.dockEnhancement.stop(); hotkeys?.stop()
    }
}
