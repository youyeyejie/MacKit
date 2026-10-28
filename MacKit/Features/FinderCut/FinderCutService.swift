import AppKit
import ApplicationServices
import Observation

@MainActor @Observable
final class FinderCutService: FeatureModule {
    let id = FeatureID.finderCut
    private(set) var enabled = UserDefaults.standard.bool(forKey: "finderCut.enabled")
    private(set) var status = "未启用"
    private(set) var pendingCount = 0
    private(set) var soundEnabled = UserDefaults.standard.object(forKey: "finderCut.soundEnabled") as? Bool ?? true
    private let cutSound = CutSoundPlayer()
    private var shuttingDown = false
    private var session: CutSession?
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
        sync()
    }

    func setEnabled(_ value: Bool) {
        enabled = value; UserDefaults.standard.set(value, forKey: "finderCut.enabled")
        if !value { cancel(); cutSound.stop() }
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
                    if soundEnabled { cutSound.play() }
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

    private func validateSession() {
        guard let session else { return }
        if !AXIsProcessTrusted() || !session.matches(urls: fileURLs(), changeCount: NSPasteboard.general.changeCount) {
            cancel(); sync()
        }
    }
    func cancel() {
        session = nil; pendingCount = 0
        timer?.invalidate(); timer = nil
        filter?.update(pending: false, busy: false)
        status = enabled ? "已取消待移动状态" : "未启用"
    }
    func setSoundEnabled(_ value: Bool) {
        guard value != soundEnabled else { return }
        soundEnabled = value
        UserDefaults.standard.set(value, forKey: "finderCut.soundEnabled")
        if value { cutSound.play() } else { cutSound.stop() }
    }
    func stop() {
        shuttingDown = true
        cutSound.stop()
        generation = UUID(); commandTask?.cancel(); commandTask = nil
        worker?.stop(); worker = nil; filter = nil; cancel()
    }
}
