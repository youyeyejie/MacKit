import AppKit

/// The system hosts the extension. A dead extension cannot restart itself.
@MainActor
final class WallpaperRecovery {
    private static let provider = "com.mackit.app.wallpaper.extension"
    private var monitor: Task<Void, Never>?
    private var verification: Task<Void, Never>?
    private var missingChecks = 0
    private var lastAttempt = Date.distantPast
    private var attempts = 0
    var statusChanged: ((Bool, String?) -> Void)?

    func start() {
        guard monitor == nil, ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard let self else { return }
                self.check()
            }
        }
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        verification?.cancel()
        verification = nil
        missingChecks = 0
    }

    private var extensionRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.provider).isEmpty
    }

    private func check() {
        guard selectedOnDesktop() else {
            missingChecks = 0
            attempts = 0
            return
        }
        if extensionRunning {
            missingChecks = 0
            return
        }
        missingChecks += 1
        // Two observations avoid restarting during ordinary provider transitions.
        guard missingChecks >= 2, attempts < 3 else { return }
        recover()
    }

    func recover() {
        guard verification == nil else { return }
        guard selectedOnDesktop() else {
            statusChanged?(false, "请先在系统墙纸设置中选择 MacKit 动态壁纸。")
            return
        }
        guard !extensionRunning else {
            statusChanged?(false, "动态壁纸进程正在运行。")
            return
        }
        guard Date().timeIntervalSince(lastAttempt) >= 60 else {
            statusChanged?(false, "正在等待系统恢复，请稍后再试。")
            return
        }
        guard
            let host = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.wallpaper.agent")
                .first,
            host.executableURL?.path == "/System/Library/CoreServices/WallpaperAgent.app/Contents/MacOS/WallpaperAgent"
        else {
            statusChanged?(false, "未找到系统壁纸服务，请打开系统墙纸设置后重试。")
            return
        }
        lastAttempt = Date()
        attempts += 1
        missingChecks = 0
        // Normal termination lets launchd restore the host and reacquire its selected provider.
        guard host.terminate() else {
            statusChanged?(false, "系统壁纸服务未接受恢复请求，请在系统设置中重新选择壁纸。")
            return
        }
        statusChanged?(true, "正在恢复动态壁纸…")
        verification = Task { [weak self] in
            for _ in 0..<15 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                if self.extensionRunning {
                    self.verification = nil
                    self.statusChanged?(false, "动态壁纸已恢复。")
                    return
                }
            }
            guard let self else { return }
            self.verification = nil
            self.statusChanged?(false, "恢复超时，请在系统墙纸设置中重新选择 MacKit 壁纸。")
        }
    }

    private func selectedOnDesktop() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return false }
        // Ignore SystemDefault and Idle: they may retain MacKit after the desktop changes provider.
        return ["AllSpacesAndDisplays", "Displays", "Spaces"].contains { key in
            Self.containsDesktopProvider(plist[key])
        }
    }

    private static func containsDesktopProvider(_ value: Any?) -> Bool {
        guard let dictionary = value as? [String: Any] else { return false }
        if let desktop = dictionary["Desktop"] as? [String: Any],
            let content = desktop["Content"] as? [String: Any],
            let choices = content["Choices"] as? [[String: Any]],
            choices.contains(where: { $0["Provider"] as? String == provider })
        {
            return true
        }
        return dictionary.filter { $0.key != "Idle" && $0.key != "SystemDefault" }
            .values.contains { containsDesktopProvider($0) }
    }
}
