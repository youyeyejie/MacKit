import AppKit
import SwiftUI
import Carbon

@main
struct MacKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate, NSMenuDelegate {
    let model = AppModel()
    private var window: NSWindow?
    private var hotkeys: GlobalHotKeys?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.appearanceChanged = { [weak self] in self?.applyAppearance() }
        model.registerShortcuts = { [weak self] show, clean in
            guard let self, let hotkeys = self.hotkeys else { return "快捷键服务尚未就绪" }
            return hotkeys.configure(show: show, clean: clean) ? nil : hotkeys.error
        }
        model.recordingChanged = { [weak self] recording in
            if recording { self?.hotkeys?.suspend() } else { self?.hotkeys?.resume() }
        }
        NSApp.applicationIconImage = AppBrand.icon
        applyAppearance()
        hotkeys = GlobalHotKeys(show: { [weak self] in self?.showWindow() }, clean: { [weak self] in
            self?.showWindow(); self?.model.cleaning.begin()
        })
        _ = hotkeys?.configure(show: model.shortcuts.show, clean: model.shortcuts.clean)
        model.message = hotkeys?.error
        let login = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !login { showWindow() }
    }

    func showWindow() {
        if window == nil {
            let view = MainView(model: model)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 650),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "MacKit"
            window.titleVisibility = .hidden
            let toolbar = NSToolbar(identifier: "MacKit.Toolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
            window.toolbarStyle = .unifiedCompact
            window.contentView = NSHostingView(rootView: view)
            window.minSize = NSSize(width: 720, height: 540)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.permissions.refresh()
        model.refreshLogin()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }


    func applicationDidBecomeActive(_ notification: Notification) {
        model.permissions.refresh(); model.refreshLogin(); model.finderCut.sync()
    }

    private func applyAppearance() {
        NSApp.setActivationPolicy(model.showDock ? .regular : .accessory)
        if model.showMenuBar, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "MacKit")
            item.button?.image?.isTemplate = true
            let menu = NSMenu()
            menu.delegate = self
            for (title, selector) in [("打开主面板", #selector(openFromMenu)), ("打开清洁模式", #selector(cleanFromMenu)), ("启用访达剪切", #selector(toggleFinderFromMenu)), ("退出MacKit", #selector(quitFromMenu))] {
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
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first(where: { $0.action == #selector(toggleFinderFromMenu) })?.title = model.finderCut.enabled ? "关闭访达剪切" : "启用访达剪切"
    }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }
    @objc private func toggleSidebar() { model.sidebarVisible.toggle() }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("MacKit.Sidebar")] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("MacKit.Sidebar")] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "显示或隐藏侧栏"; item.toolTip = item.label
        item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: item.label)
        item.target = self; item.action = #selector(toggleSidebar)
        return item
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.cleaning.onActivity = nil; model.cleaning.stop(); model.finderCut.stop(); hotkeys?.stop() }
}
