import AppKit
import SwiftUI
import Carbon

@main
struct MacKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var window: NSWindow?
    private var hotkeys: GlobalHotKeys?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        hotkeys = GlobalHotKeys(show: { [weak self] in self?.showWindow() }, clean: { [weak self] in
            self?.showWindow(); self?.model.cleaning.begin()
        })
        model.message = hotkeys?.error
        let login = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !login { showWindow() }
    }

    func showWindow() {
        if window == nil {
            let view = MainView(model: model)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "MacKit"
            window.contentView = NSHostingView(rootView: view)
            window.minSize = NSSize(width: 740, height: 560)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.permissions.refresh()
        model.refreshLogin()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.finderCut.stop(); model.cleaning.stop(); hotkeys?.stop() }
}
