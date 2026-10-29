import AppKit
import ApplicationServices

@MainActor
final class DockClickController {
    private struct Pending {
        let hit: DockHit
        let down: CGEvent
        let origin: CGPoint
        let action: DockClickIntent
    }
    private struct Record {
        let targets: [DockWindow]
        let minimized: Bool
        let time: TimeInterval
    }
    private var pending: Pending?
    private var records: [pid_t: Record] = [:]
    private var actionTasks: [pid_t: Task<Void, Never>] = [:]
    private var actionTokens: [pid_t: UUID] = [:]
    private static let marker: Int64 = 0x4D41434B444F434B
    var onHandled: (() -> Void)?

    func reset() {
        if let pending { replay(pending.down) }
        pending = nil
        actionTasks.values.forEach { $0.cancel() }
        actionTasks = [:]; records = [:]; actionTokens = [:]
    }

    /// Only decisions about Dock ownership run in the event callback. Reading
    /// the target application's windows and all AX mutations are deferred.
    func handle(_ type: CGEventType, event: CGEvent, hitTest: DockHitTest, panelContains: Bool) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return false }
        switch type {
        case .leftMouseDown:
            pending = nil
            guard !panelContains,
                  event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
                  let hit = hitTest.hit(event.location, fresh: true), let down = event.copy() else { return false }
            let pid = hit.app.processIdentifier
            records = records.filter { NSRunningApplication(processIdentifier: $0.key)?.isTerminated == false }
            let record = records[pid]
            let elapsed = record.map { ProcessInfo.processInfo.systemUptime - $0.time } ?? .infinity
            let active = !hit.app.isHidden && (hit.app.isActive || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid)
            let action = DockClickPolicy.intent(active: active, lastMinimized: record?.minimized, elapsed: elapsed)
            guard action != .native else { return false }
            pending = Pending(hit: hit, down: down, origin: event.location, action: action)
            return true
        case .leftMouseDragged:
            guard let pending else { return false }
            if DockGeometry.isDrag(from: pending.origin, to: event.location) {
                self.pending = nil
                replay(pending.down)
                if let drag = event.copy() { replay(drag) }
            }
            return true
        case .leftMouseUp:
            guard let pending else { return false }
            self.pending = nil
            if DockGeometry.isDrag(from: pending.origin, to: event.location) {
                replay(pending.down)
                if let up = event.copy() { replay(up) }
            } else if pending.action != .ignore {
                onHandled?()
                commit(pending)
            }
            return true
        default: return false
        }
    }

    private func replay(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cghidEventTap)
    }

    private func commit(_ click: Pending) {
        let pid = click.hit.app.processIdentifier
        let previous = records[pid]
        let token = UUID()
        actionTokens[pid] = token
        actionTasks[pid]?.cancel()
        // Publish intent immediately: a second click during an AX request or
        // genie animation must toggle rather than repeat the same action.
        records[pid] = Record(targets: previous?.targets ?? [], minimized: click.action == .minimize,
                              time: ProcessInfo.processInfo.systemUptime)
        actionTasks[pid] = Task { @MainActor [weak self] in
            let windows = await DockWindowAccess.windows(pid: pid)
            guard !Task.isCancelled, let self, self.actionTokens[pid] == token else { return }
            defer { if self.actionTokens[pid] == token { self.actionTasks[pid] = nil } }
            let app = click.hit.app
            switch click.action {
            case .minimize:
                if windows.contains(where: { $0.fullscreen }) {
                    app.hide()
                    self.records[pid] = nil
                    return
                }
                let targets = windows.filter { !$0.minimized && !$0.fullscreen }
                guard !targets.isEmpty else {
                    // A windowless application should still open its native
                    // Dock window, and a manually minimized app keeps native restore.
                    self.records[pid] = nil
                    self.replay(click.down)
                    if let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: click.origin, mouseButton: .left) { self.replay(up) }
                    return
                }
                self.records[pid] = Record(targets: targets, minimized: true, time: ProcessInfo.processInfo.systemUptime)
                let batched = await DockWindowAccess.minimizeAllMenu(pid: pid)
                guard !Task.isCancelled, self.actionTokens[pid] == token else { return }
                if batched { try? await Task.sleep(for: .milliseconds(350)) }
                guard !Task.isCancelled, self.actionTokens[pid] == token else { return }
                await DockWindowAccess.setMinimized(true, windows: targets)
            case .restore:
                let captured = previous?.targets ?? []
                let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
                let ordered = captured.reversed().compactMap { byID[$0.id] }
                let targets = Array(ordered)
                guard !targets.isEmpty else {
                    app.activate(options: [.activateIgnoringOtherApps])
                    self.records[pid] = nil
                    return
                }
                app.activate(options: [.activateIgnoringOtherApps])
                await DockWindowAccess.setMinimized(false, windows: targets)
                guard !Task.isCancelled, self.actionTokens[pid] == token else { return }
                if let front = targets.last { await DockWindowAccess.raise(front) }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, self.actionTokens[pid] == token else { return }
                await DockWindowAccess.setMinimized(false, windows: targets)
                self.records[pid] = nil
            case .ignore, .native: break
            }
        }
    }
}
