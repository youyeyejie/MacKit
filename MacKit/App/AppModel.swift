import AppKit
import Observation
import ServiceManagement

@MainActor @Observable
final class AppModel {
    let permissions = PermissionService()
    let cleaning = CleaningService()
    var loginStatus = "未启用"
    var message: String?

    init() { refreshLogin() }

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
