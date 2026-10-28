import Cocoa
import FinderSync
import OSLog

@MainActor
final class FinderSync: FIFinderSync, @unchecked Sendable {
    private var paths: Set<String> = []
    private var requested: Set<String> = []
    private var state: BadgeState?
    private var roots: Set<URL> = []
    private var expiry: Timer?
    private var watcher: BadgeDirectoryWatcher?
    private var requests = 0
    private var lastReceipt = Date.distantPast
    private let log = Logger(subsystem: "com.mackit.app.finder", category: "badges")

    override init() {
        super.init()
        if Thread.isMainThread { MainActor.assumeIsolated { configure() } }
        else { Task { @MainActor [weak self] in self?.configure() } }
    }
    private func configure() {
        let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: 40, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            let scissors = NSImage(systemSymbolName: "scissors", accessibilityDescription: "待移动")?
                .withSymbolConfiguration(configuration)
            scissors?.draw(in: rect.insetBy(dx: 10, dy: 10))
            return true
        }
        // Finder requires an explicit initial registration, including an empty set.
        FIFinderSyncController.default().directoryURLs = []
        FIFinderSyncController.default().setBadgeImage(image, label: "待移动", forBadgeIdentifier: "pending-cut")
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(changed), name: NSNotification.Name(BadgeStore.notification), object: nil, suspensionBehavior: .deliverImmediately)
        if let directory = BadgeStore.fileURL()?.deletingLastPathComponent() {
            do {
                watcher = try BadgeDirectoryWatcher(directory: directory) { [weak self] in
                    Task { @MainActor in self?.reload() }
                }
            } catch { log.error("Shared directory watcher could not start: \(error.localizedDescription, privacy: .public)") }
        }
        reload()
    }
    @objc private func changed() { reload() }
    private func reload() {
        let nextState = BadgeStore.read()
        let next = nextState?.validPaths() ?? []
        guard state != nextState || next != paths else { return }
        expiry?.invalidate(); expiry = nil
        let controller = FIFinderSyncController.default()
        let removed = paths.subtracting(next)
        // Retain previous source roots while clearing badges. Never register the whole disk.
        let nextRoots = Set(next.map { URL(fileURLWithPath: $0).deletingLastPathComponent() })
        for path in removed { controller.setBadgeIdentifier("", for: URL(fileURLWithPath: path)) }
        if !nextRoots.isEmpty, nextRoots != roots {
            roots = nextRoots
            controller.directoryURLs = roots
        }
        state = nextState; paths = next; requests = 0
        paint()
        receipt(force: true)
        log.info("Loaded badge session, paths: \(next.count), roots: \(self.roots.count)")
        // Monitoring registration is asynchronous; repaint after Finder subscribes.
        for delay in [0.15, 0.6] {
            let session = nextState?.sessionID
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.state?.sessionID == session else { return }
                self.paint()
            }
        }
        if let nextState, !paths.isEmpty {
            expiry = Timer.scheduledTimer(withTimeInterval: max(0.1, nextState.expiresAt.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                Task { @MainActor in self?.reload() }
            }
        }
    }
    private func paint() {
        for path in paths.intersection(requested) { FIFinderSyncController.default().setBadgeIdentifier("pending-cut", for: URL(fileURLWithPath: path)) }
    }
    private func receipt(force: Bool = false) {
        guard let state, force || Date().timeIntervalSince(lastReceipt) > 1 else { return }
        lastReceipt = Date()
        BadgeReceipt(sessionID: state.sessionID, pathCount: paths.count, badgeRequests: requests).write()
    }
    nonisolated override func beginObservingDirectory(at url: URL) {
        Task { @MainActor [weak self] in
            self?.log.info("Finder began observing a registered directory")
            self?.reload(); self?.paint()
        }
    }
    nonisolated override func requestBadgeIdentifier(for url: URL) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { respond(to: url) }
        } else {
            Task { @MainActor [weak self] in self?.respond(to: url) }
        }
    }
    private func respond(to url: URL) {
        reload()
        let path = url.standardizedFileURL.path
        requested.insert(path)
        FIFinderSyncController.default().setBadgeIdentifier(paths.contains(path) ? "pending-cut" : "", for: url)
        if paths.contains(path) { requests += 1; receipt(force: requests == 1) }
    }
    nonisolated override func endObservingDirectory(at url: URL) {
        Task { @MainActor [weak self] in
            let prefix = url.standardizedFileURL.path + "/"
            self?.requested = self?.requested.filter { !$0.hasPrefix(prefix) } ?? []
        }
    }
}
