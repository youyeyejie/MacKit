import AppKit
import ApplicationServices
import FinderSync
import Observation

@MainActor @Observable
final class FinderCutService: FeatureModule {
    let id = FeatureID.finderCut
    private(set) var enabled = UserDefaults.standard.bool(forKey: "finderCut.enabled")
    private(set) var status = "未启用"
    private(set) var pendingCount = 0
    private(set) var badgeStatus = "需签名并启用 访达扩展"
    private(set) var extensionEnabled = FIFinderSyncController.isExtensionEnabled
    private(set) var reloadingExtension = false
    private(set) var extensionMessage: String?
    let extensionLifecycle = FinderExtensionLifecycle()
    private var shuttingDown = false
    private var extensionPaused = false
    private var extensionReloadTask: Task<Void, Never>?
    private var session: CutSession?
    private var lastPublished: BadgeState?
    private var filter: FinderKeyFilter?
    private var worker: EventTapWorker?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var suspended = false
    private var generation = UUID()
    private var commandTask: Task<Void, Never>?

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let terminatedFinder = name == NSWorkspace.didTerminateApplicationNotification && app?.bundleIdentifier == "com.apple.finder"
                Task { @MainActor in
                    if terminatedFinder { self?.cancel() }
                    self?.sync()
                }
            })
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSuspended(true) }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSuspended(false) }
            })
        }
        publishBadges()
        sync()
    }

    func setEnabled(_ value: Bool) {
        enabled = value; UserDefaults.standard.set(value, forKey: "finderCut.enabled")
        if !value { cancel() }
        sync()
    }
    func setSuspended(_ value: Bool) {
        suspended = value
        if value { cancel() }
        sync()
    }
    func sync() {
        guard !shuttingDown else { return }
        let finder = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        guard enabled, !suspended, AXIsProcessTrusted(), finder else {
            generation = UUID(); commandTask?.cancel(); commandTask = nil
            worker?.stop(); worker = nil; filter = nil
            if !enabled { status = "未启用" }
            else if !AXIsProcessTrusted() { status = "等待辅助功能授权" }
            else if session == nil { status = "等待 访达前台激活" }
            return
        }
        guard worker == nil else { return }
        let token = UUID(); generation = token
        let filter = FinderKeyFilter { [weak self] key, flags in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.commandTask = Task { await self.handle(key: key, flags: flags, token: token) }
            }
        }
        filter.update(pending: session != nil, busy: false)
        let worker = EventTapWorker(mask: (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue), failed: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.worker?.stop(); self.worker = nil; self.filter = nil
                self.cancel(); self.status = "输入监听中断；切换回 Finder 后重试"
            }
        }, handler: { type, event in filter.handle(type, event) })
        if worker.start() { self.filter = filter; self.worker = worker; status = "已启用 · ⌘X / ⌘V" }
        else { status = "无法监听 访达快捷键，请检查辅助功能授权" }
    }

    private func fileURLs() -> [URL] {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .filter(\.isFileURL)
    }

    private func handle(key: Int64, flags: UInt64, token: UUID) async {
        defer { if generation == token { filter?.update(pending: session != nil, busy: false) } }
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == "com.apple.finder" else { return }
        let pid = app.processIdentifier
        let fileContext = await Task.detached(priority: .userInitiated) { FinderFocus.isFileBrowser(pid: pid) }.value
        guard !Task.isCancelled, generation == token,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        guard fileContext else { post(key: key, flags: CGEventFlags(rawValue: flags), pid: pid); return }
        if key == 53 { cancel(); return }
        if key == 7 {
            cancel()
            filter?.update(pending: false, busy: true)
            let previous = NSPasteboard.general.changeCount
            post(key: 8, flags: .maskCommand, pid: pid)
            for _ in 0..<20 {
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
                guard generation == token, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                if NSPasteboard.general.changeCount != previous {
                    let urls = fileURLs()
                    guard !urls.isEmpty else { status = "未获取到文件；没有建立剪切状态"; return }
                    session = CutSession(urls: urls, changeCount: NSPasteboard.general.changeCount)
                    pendingCount = urls.count
                    status = "\(urls.count) 个项目待移动 · Esc 取消"
                    publishBadges()
                    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                        Task { @MainActor in self?.validateSession() }
                    }
                    return
                }
            }
            status = "访达未完成复制，请重试"
        } else if key == 9 {
            guard let session, session.matches(urls: fileURLs(), changeCount: NSPasteboard.general.changeCount) else {
                cancel(); post(key: 9, flags: .maskCommand, pid: pid); return
            }
            // Delegate transfer, conflicts and undo to Finder; no success claim here.
            cancel()
            post(key: 9, flags: [.maskCommand, .maskAlternate], pid: pid)
            status = "已交给访达；若取消移动，请重新 ⌘X"
        }
    }

    private func post(key: Int64, flags: CGEventFlags, pid: pid_t) {
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: FinderKeyFilter.marker)
            event.postToPid(pid)
        }
    }

    private func updateBadgeReceipt() {
        guard let lastPublished, !lastPublished.paths.isEmpty else { return }
        if let receipt = BadgeReceipt.read(), receipt.sessionID == lastPublished.sessionID, receipt.pathCount == lastPublished.paths.count {
            badgeStatus = receipt.badgeRequests > 0 ? "扩展已响应角标请求 · \(receipt.pathCount) 项" : "扩展已同步 · 等待访达请求角标"
        } else {
            badgeStatus = "等待扩展同步；若持续无响应，请重新启用访达扩展"
        }
    }
    private func validateSession() {
        updateBadgeReceipt()
        guard let session else { return }
        if !AXIsProcessTrusted() || !session.matches(urls: fileURLs(), changeCount: NSPasteboard.general.changeCount) {
            cancel(); sync()
        }
    }
    func cancel() {
        session = nil; pendingCount = 0
        timer?.invalidate(); timer = nil
        filter?.update(pending: false, busy: false)
        publishBadges()
        status = enabled ? "已取消待移动状态" : "未启用"
    }
    func diagnoseExtension() {
        refreshBadges()
        guard extensionEnabled else { extensionMessage = "MacKit 扩展未启用。请打开管理并开启后重试。"; return }
        guard let published = lastPublished, !published.paths.isEmpty else {
            extensionMessage = "扩展已启用。请在普通本地文件夹选中文件并按 ⌘X，再检查一次；应用程序和云盘目录可能不支持角标。"
            return
        }
        guard let receipt = BadgeReceipt.read(), receipt.sessionID == published.sessionID else {
            extensionMessage = "主程序已写入剪切状态，扩展尚未确认。可先重载 MacKit 扩展，再重新打开文件夹。"
            return
        }
        extensionMessage = receipt.badgeRequests > 0
            ? "扩展已收到访达角标请求。若仍不可见，请检查当前视图、目录类型，以及其他扩展是否覆盖角标。"
            : "扩展已同步剪切状态，但访达尚未请求角标。可能是目录限制、视图未刷新或其他扩展占用。可先重载；仍无效时在管理中逐项排查。"
    }
    func refreshExtensionStatus() { extensionEnabled = FIFinderSyncController.isExtensionEnabled }
    func refreshBadges() { refreshExtensionStatus(); publishBadges(); updateBadgeReceipt() }
    func restoreExtension() async {
        let success = await extensionLifecycle.resumeIfNeeded()
        if !success { extensionMessage = "未能恢复访达扩展，请在管理中重新开启。" }
        refreshBadges()
    }
    func reloadExtension() {
        guard !reloadingExtension, !shuttingDown else { return }
        refreshExtensionStatus()
        guard extensionEnabled else { extensionMessage = "请先在管理中启用 MacKit 扩展。"; return }
        reloadingExtension = true; extensionMessage = nil
        extensionReloadTask = Task { [weak self] in
            guard let self else { return }
            let success = await self.extensionLifecycle.reload(afterPause: {
                self.extensionPaused = true
                self.publishBadges(ownerRunning: false)
            }, beforeResume: {
                self.extensionPaused = false
                self.publishBadges()
            })
            self.reloadingExtension = false
            guard !self.shuttingDown else { return }
            self.refreshBadges()
            self.extensionMessage = success ? "已请求重载 MacKit 扩展。请重新打开测试文件夹再剪切。" : "重载未完成，请在管理中重新开启 MacKit 扩展。"
        }
    }
    func prepareToQuit() async {
        shuttingDown = true
        stop()
        await extensionReloadTask?.value
        _ = await extensionLifecycle.pauseForQuit()
        publishBadges(ownerRunning: false)
        try? await Task.sleep(for: .milliseconds(400))
    }
    private func publishBadges(ownerRunning: Bool = true) {
        let state = BadgeState(sessionID: session?.id ?? UUID(), paths: session?.urls.map(\.path) ?? [],
                               expiresAt: session?.createdAt.addingTimeInterval(600) ?? Date(), ownerRunning: ownerRunning && !extensionPaused)
        do {
            try BadgeStore.write(state)
            lastPublished = state
            DistributedNotificationCenter.default().postNotificationName(NSNotification.Name(BadgeStore.notification), object: nil, userInfo: nil, deliverImmediately: true)
            refreshExtensionStatus()
            badgeStatus = extensionEnabled ? "访达扩展已启用" : "请在系统设置启用 访达扩展"
        } catch { badgeStatus = "角标不可用：需配置开发团队并签名；剪切仍可使用" }
    }
    func openExtensionSettings() { FIFinderSyncController.showExtensionManagementInterface() }
    func stop() {
        generation = UUID(); commandTask?.cancel(); commandTask = nil
        worker?.stop(); worker = nil; filter = nil; cancel()
    }
}
