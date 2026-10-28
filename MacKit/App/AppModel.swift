import AppKit
import Observation
import ServiceManagement

@MainActor @Observable
final class AppModel {
    let permissions = PermissionService()
    let shortcuts = ShortcutSettings()
    var sidebarVisible = true
    var showDock = UserDefaults.standard.bool(forKey: "appearance.showDock")
    var showMenuBar = UserDefaults.standard.bool(forKey: "appearance.showMenuBar")
    var appearanceChanged: (() -> Void)?
    var registerShortcuts: ((AppShortcut, AppShortcut) -> String?)?
    var recordingChanged: ((Bool) -> Void)?

    func setDock(_ value: Bool) {
        showDock = value; UserDefaults.standard.set(value, forKey: "appearance.showDock"); appearanceChanged?()
    }
    func setMenuBar(_ value: Bool) {
        showMenuBar = value; UserDefaults.standard.set(value, forKey: "appearance.showMenuBar"); appearanceChanged?()
    }
    func setShortcut(_ value: AppShortcut, forCleaning: Bool) -> String? {
        let show = forCleaning ? shortcuts.show : value
        let clean = forCleaning ? value : shortcuts.clean
        guard !show.conflicts(with: clean) else { return "两个功能不能使用相同快捷键" }
        if let error = registerShortcuts?(show, clean) { return error }
        shortcuts.save(show: show, clean: clean)
        return nil
    }
    let cleaning = CleaningService()
    let finderCut = FinderCutService()
    let uninstaller = UninstallerService()
    var loginStatus = "未启用"
    var message: String?

    init() {
        cleaning.onActivity = { [weak finderCut] active in finderCut?.setSuspended(active) }
        refreshLogin()
    }

    func refreshLogin() {
        switch SMAppService.mainApp.status {
        case .enabled: loginStatus = "已启用"
        case .requiresApproval: loginStatus = "等待系统批准"
        case .notFound: loginStatus = "服务不可用，请从应用程序目录运行"
        case .notRegistered: loginStatus = "未启用"
        @unknown default: loginStatus = "未知状态"
        }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { message = "登录启动设置失败：\(error.localizedDescription)" }
        refreshLogin()
    }
}
