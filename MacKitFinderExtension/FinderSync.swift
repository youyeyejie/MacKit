import Cocoa
import FinderSync

@MainActor
// Finder callbacks hop to MainActor; mutable badge state is confined there.
final class FinderSync: FIFinderSync, @unchecked Sendable {
    private var paths: Set<String> = []
    private var expiry: Timer?

    override init() {
        super.init()
        Task { @MainActor [weak self] in self?.configure() }
    }
    private func configure() {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            let arrow = "➜" as NSString
            arrow.draw(at: NSPoint(x: 3, y: 2), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.white])
            return true
        }
        FIFinderSyncController.default().setBadgeImage(image, label: "待移动", forBadgeIdentifier: "pending-cut")
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(changed), name: NSNotification.Name(BadgeStore.notification), object: nil)
        reload()
    }
    @objc private func changed() { reload() }
    private func reload() {
        expiry?.invalidate(); expiry = nil
        let controller = FIFinderSyncController.default()
        let state = BadgeStore.read()
        let next = state?.validPaths() ?? []
        for path in paths.subtracting(next) { controller.setBadgeIdentifier("", for: URL(fileURLWithPath: path)) }
        paths = next
        controller.directoryURLs = Set(paths.map { URL(fileURLWithPath: $0).deletingLastPathComponent() })
        for path in paths { controller.setBadgeIdentifier("pending-cut", for: URL(fileURLWithPath: path)) }
        if let state, !paths.isEmpty {
            expiry = Timer.scheduledTimer(withTimeInterval: max(0.1, state.expiresAt.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                Task { @MainActor in self?.reload() }
            }
        }
    }
    nonisolated override func requestBadgeIdentifier(for url: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Re-read for expiry / missed notifications; requests do not require polling.
            let valid = BadgeStore.read()?.validPaths() ?? []
            FIFinderSyncController.default().setBadgeIdentifier(valid.contains(url.standardizedFileURL.path) ? "pending-cut" : "", for: url)
            if valid != self.paths { self.reload() }
        }
    }
}
