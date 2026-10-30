import AppKit
import Observation
import ServiceManagement

@MainActor @Observable
final class AppModel {
    let permissions = PermissionService()
    let shortcuts = ShortcutSettings()
    var sidebarVisible = true
    var page: AppPage? = .cleaning {
        didSet { if let page { history.visit(page) } }
    }
    private var history = NavigationHistory<AppPage>(current: .cleaning)
    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }
    func goBack() { if let destination = history.back() { page = destination } }
    func goForward() { if let destination = history.forward() { page = destination } }
    var showDock = UserDefaults.standard.bool(forKey: "appearance.showDock")
    var showMenuBar = UserDefaults.standard.bool(forKey: "appearance.showMenuBar")
    var appearanceChanged: (() -> Void)?
    var registerShortcuts: ((AppShortcut?, AppShortcut?) -> String?)?
    var recordingChanged: ((Bool) -> Void)?

    func setDock(_ value: Bool) {
        showDock = value; UserDefaults.standard.set(value, forKey: "appearance.showDock"); appearanceChanged?()
    }
    func setMenuBar(_ value: Bool) {
        showMenuBar = value; UserDefaults.standard.set(value, forKey: "appearance.showMenuBar"); appearanceChanged?()
    }
    func setShortcut(_ value: AppShortcut?, forCleaning: Bool) -> String? {
        let show = forCleaning ? shortcuts.show : value
        let clean = forCleaning ? value : shortcuts.clean
        if let show, let clean, show.conflicts(with: clean) { return "两个功能不能使用相同快捷键" }
        if let error = registerShortcuts?(show, clean) { return error }
        shortcuts.save(show: show, clean: clean)
        return nil
    }
    let cleaning = CleaningService()
    let finderCut = FinderCutService()
    let windowSwitcher = WindowSwitcherService()
    let dockEnhancement = DockEnhancementService()
    private(set) var loginEnabled = false
    var message: String?

    init() {
        cleaning.onActivity = { [weak finderCut, weak windowSwitcher, weak dockEnhancement] active in
            finderCut?.setSuspended(active)
            windowSwitcher?.setSuspended(active)
            dockEnhancement?.setSuspended(active)
        }
        refreshLogin()
    }

    func refreshLogin() {
        loginEnabled = SMAppService.mainApp.status == .enabled
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { message = "登录启动设置失败：\(error.localizedDescription)" }
        refreshLogin()
    }
}
