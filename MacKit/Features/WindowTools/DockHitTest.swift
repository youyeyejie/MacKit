import AppKit
import ApplicationServices

struct DockHit {
    let app: NSRunningApplication
    let frame: CGRect // AppKit global coordinates
    let edge: DockEdge
}

@MainActor
final class DockHitTest {
    private var dockPID: pid_t?
    private var settingsReadAt: TimeInterval = 0
    private var tileSize: CGFloat = 64
    private(set) var edge: DockEdge = .bottom
    private var ownershipReadAt: TimeInterval = 0
    private var visibleWindows: [[String: Any]] = []
    private var pairings: [(tile: AXUIElement, pid: pid_t, launch: Date?)] = []

    static func point(_ ax: CGPoint) -> CGPoint { CGPoint(x: ax.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - ax.y) }
    static func rect(_ ax: CGRect) -> CGRect { CGRect(x: ax.minX, y: point(CGPoint(x: 0, y: ax.maxY)).y, width: ax.width, height: ax.height) }
    static func axPoint(_ point: CGPoint) -> CGPoint { self.point(point) }

    func reset() {
        dockPID = nil; pairings = []; visibleWindows = []; settingsReadAt = 0; ownershipReadAt = 0
    }

    func nearDock(_ point: CGPoint) -> Bool {
        refreshSettings()
        guard let frame = NSScreen.screens.first(where: { $0.frame.contains(point) })?.frame else { return false }
        let band = max(160, tileSize * 1.5 + 60)
        switch edge {
        case .bottom: return point.y < frame.minY + band
        case .left: return point.x < frame.minX + band
        case .right: return point.x > frame.maxX - band
        }
    }

    func hit(_ axPoint: CGPoint, fresh: Bool = false) -> DockHit? {
        let point = Self.point(axPoint)
        guard nearDock(point), AXIsProcessTrusted() else { return nil }
        if dockPID.flatMap({ NSRunningApplication(processIdentifier: $0) })?.isTerminated != false {
            dockPID = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.dock" }?.processIdentifier
            pairings = []
        }
        guard let dockPID, owns(axPoint, pid: dockPID, fresh: fresh) else { return nil }
        let dock = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dock, 0.1)
        var current: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dock, Float(axPoint.x), Float(axPoint.y), &current) == .success else { return nil }
        var chain: [AXUIElement] = []
        for _ in 0..<8 {
            guard let element = current else { break }
            var owner: pid_t = 0
            guard AXUIElementGetPid(element, &owner) == .success, owner == dockPID else { break }
            chain.append(element)
            current = DockAX.element(element, kAXParentAttribute)
        }
        for element in chain {
            guard let rawURL = DockAX.value(element, kAXURLAttribute), CFGetTypeID(rawURL) == CFURLGetTypeID() else { continue }
            let url = (rawURL as! CFURL) as URL
            let instances = NSWorkspace.shared.runningApplications.filter {
                !$0.isTerminated && $0.activationPolicy == .regular && $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
            }.sorted { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
            guard !instances.isEmpty else { continue }
            if let running = DockAX.value(element, "AXIsApplicationRunning") as? Bool, !running { return nil }
            guard let bounds = DockAX.frame(element), let app = resolve(element, instances: instances, url: url),
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
            return DockHit(app: app, frame: Self.rect(bounds), edge: edge)
        }
        // Labels are only a fallback when no URL identifies the tile. Require
        // exactly one match; a shared label must never pick an arbitrary process.
        for element in chain where DockAX.string(element, kAXRoleAttribute) == "AXDockItem" {
            let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].compactMap { DockAX.string(element, $0)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let matches = NSWorkspace.shared.runningApplications.filter { app in
                app.activationPolicy == .regular && !app.isTerminated && labels.contains { label in
                    label == app.localizedName?.lowercased() || label == app.bundleURL?.deletingPathExtension().lastPathComponent.lowercased()
                }
            }
            if matches.count == 1, let app = matches.first, let bounds = DockAX.frame(element), app.processIdentifier != getpid() {
                return DockHit(app: app, frame: Self.rect(bounds), edge: edge)
            }
        }
        return nil
    }

    private func resolve(_ tile: AXUIElement, instances: [NSRunningApplication], url: URL) -> NSRunningApplication? {
        guard instances.count > 1 else { return instances.first }
        pairings.removeAll { pair in
            guard let app = NSRunningApplication(processIdentifier: pair.pid) else { return true }
            return app.isTerminated || app.launchDate != pair.launch
        }
        if let previous = pairings.first(where: { CFEqual($0.tile, tile) }), let app = instances.first(where: { $0.processIdentifier == previous.pid }) { return app }
        guard let parent = DockAX.element(tile, kAXParentAttribute) else { return nil }
        let tiles = DockAX.children(parent).filter {
            guard let raw = DockAX.value($0, kAXURLAttribute), CFGetTypeID(raw) == CFURLGetTypeID() else { return false }
            let same = ((raw as! CFURL) as URL).standardizedFileURL == url.standardizedFileURL
            return same && (DockAX.value($0, "AXIsApplicationRunning") as? Bool != false)
        }
        guard tiles.count == instances.count else { return nil }
        // Preserve surviving pairs when icons are reordered; pair only the
        // unmatched tiles with the remaining processes in launch order.
        let live = pairings.filter { pair in tiles.contains { CFEqual($0, pair.tile) } }
        var remaining = instances.filter { app in !live.contains { $0.pid == app.processIdentifier } }
        pairings.removeAll { pair in instances.contains { $0.processIdentifier == pair.pid } }
        pairings.append(contentsOf: live)
        for candidate in tiles where !live.contains(where: { CFEqual($0.tile, candidate) }) {
            guard !remaining.isEmpty else { break }
            let app = remaining.removeFirst()
            pairings.append((candidate, app.processIdentifier, app.launchDate))
        }
        if pairings.count > 64 { pairings = Array(pairings.suffix(64)) }
        return pairings.first { CFEqual($0.tile, tile) }.flatMap { pair in instances.first { $0.processIdentifier == pair.pid } }
    }

    private func owns(_ point: CGPoint, pid: pid_t, fresh: Bool) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if fresh || now - ownershipReadAt > 0.08 {
            ownershipReadAt = now
            visibleWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
        }
        var covered = false
        for window in visibleWindows {
            guard let dict = window[kCGWindowBounds as String] as? NSDictionary, let frame = CGRect(dictionaryRepresentation: dict),
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let isDock = owner == pid && (window[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.dockWindow))
            guard (isDock ? frame.insetBy(dx: -8, dy: -8) : frame).contains(point) else { continue }
            if isDock {
                if !covered { return true }
                let system = AXUIElementCreateSystemWide()
                AXUIElementSetMessagingTimeout(system, 0.1)
                var hit: AXUIElement?
                var hitPID: pid_t = 0
                return AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success && hit.map { AXUIElementGetPid($0, &hitPID) == .success && hitPID == pid } == true
            }
            covered = true
        }
        return false
    }

    private func refreshSettings() {
        let now = ProcessInfo.processInfo.systemUptime
        guard settingsReadAt == 0 || now - settingsReadAt > 10 else { return }
        settingsReadAt = now
        let values = UserDefaults.standard.persistentDomain(forName: "com.apple.dock") ?? [:]
        edge = DockEdge(rawValue: values["orientation"] as? String ?? "bottom") ?? .bottom
        tileSize = (values["tilesize"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 64
        if values["magnification"] as? Bool == true { tileSize = max(tileSize, (values["largesize"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 128) }
    }
}
