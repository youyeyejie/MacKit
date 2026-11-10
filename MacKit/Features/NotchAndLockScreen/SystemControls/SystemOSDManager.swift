// MacKit adaptation of Atoll native OSD suppression. GPL-3.0-or-later. Modified 2026-11-08.
import AppKit
import ApplicationServices
import Darwin
import Defaults

/// Only the ordinary OSD helper is affected. Never touches Control Center,
/// Notification Center, privacy indicators or persistent launch-agent settings.
final class SystemOSDManager {
    static func disableSystemHUD() {
        Task { @MainActor in NativeOSDSuppression.shared.setWanted(true) }
    }
    static func enableSystemHUD() {
        Task { @MainActor in NativeOSDSuppression.shared.setWanted(false) }
    }
    static func suppressNativeOSDNow() {
        Task { @MainActor in NativeOSDSuppression.shared.synchronize() }
    }
    static func isOSDUIHelperRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.OSDUIHelper").isEmpty
    }
    @MainActor static func restoreImmediately() { NativeOSDSuppression.shared.setWanted(false) }
}

@MainActor private final class NativeOSDSuppression {
    static let shared = NativeOSDSuppression()
    private var wanted = false
    private var sleeping = false
    private var suspended: [pid_t: NSRunningApplication] = [:]
    private var watcher: Task<Void, Never>?
    private var tokens: [NSObjectProtocol] = []
    private init() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.sleeping = true
                    self?.resumeOwned()
                }
            })
        tokens.append(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.sleeping = false
                    self?.synchronize()
                }
            })
        tokens.append(
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor [weak self] in self?.synchronize() }
            })
    }
    func setWanted(_ enabled: Bool) {
        wanted = enabled
        if !enabled {
            watcher?.cancel()
            watcher = nil
            resumeOwned()
            return
        }
        synchronize()
        guard watcher == nil else { return }
        watcher = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                self?.synchronize()
            }
        }
    }
    func synchronize() {
        let controls = Defaults[.enableSystemHUD] || Defaults[.enableVerticalHUD]
        guard wanted, controls, !sleeping, AXIsProcessTrusted() else {
            resumeOwned()
            return
        }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.OSDUIHelper")
        for app in apps where !app.isTerminated {
            let pid = app.processIdentifier
            guard suspended[pid] == nil else { continue }
            if kill(pid, SIGSTOP) == 0 { suspended[pid] = app }
        }
        suspended = suspended.filter { !$0.value.isTerminated }
    }
    private func resumeOwned() {
        for (pid, app) in suspended
        where !app.isTerminated && app.processIdentifier == pid && app.bundleIdentifier == "com.apple.OSDUIHelper" {
            _ = kill(pid, SIGCONT)
        }
        suspended.removeAll()
    }
}
