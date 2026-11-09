// SPDX-License-Identifier: GPL-3.0-or-later
// Mission Control surface detection, CG-window targeting and AX fallback adapted from CloseUp (GPL-3.0).
// See LICENSES/CloseUp-GPL-3.0.txt and THIRD_PARTY_NOTICES.md.
import AppKit
import ApplicationServices
import Observation

/// Independent of the Cmd-Tab preview. Accessibility work runs on a serial queue,
/// while the input callback only pairs key events and queues copies of them.
@MainActor @Observable
final class MissionControlService {
    private(set) var enabled = UserDefaults.standard.bool(forKey: "missionControl.enabled")
    private(set) var message: String?
    private var suspended = false
    private var worker: EventTapWorker?
    private var filter: MissionControlKeyFilter?

    init() { sync() }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "missionControl.enabled")
        sync()
    }

    func setSuspended(_ value: Bool) { suspended = value; sync() }

    func sync() {
        guard enabled, !suspended else { stop(); message = nil; return }
        guard AXIsProcessTrusted() else { stop(); message = "需要辅助功能权限。"; return }
        guard worker == nil else { return }
        let filter = MissionControlKeyFilter()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let worker = EventTapWorker(mask: mask, location: .cgSessionEventTap, failed: { [weak self] in
            Task { @MainActor in
                self?.stop()
                try? await Task.sleep(for: .milliseconds(200))
                self?.sync()
            }
        }, handler: { [filter] type, event in filter.handle(type, event) })
        guard worker.start() else { filter.stop(); message = "无法建立调度中心快捷键监听，请检查辅助功能权限。"; return }
        message = nil
        self.filter = filter
        self.worker = worker
    }

    func stop() {
        filter?.stop()
        worker?.stop()
        worker = nil
        filter = nil
    }
}

private final class MissionControlKeyFilter: @unchecked Sendable {
    private static let marker: Int64 = 0x4D4B4D4351
    private let lock = NSLock()
    private var held: Set<Int64> = []
    private var active = true
    private let queue = DispatchQueue(label: "MacKit.MissionControl.Keys", qos: .userInteractive)
    // Confined to queue. A whole key stroke is either replayed or consumed.
    private var intercepted: Set<Int64> = []

    func stop() { lock.withLock { active = false } }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return Unmanaged.passUnretained(event) }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
        let capture = lock.withLock {
            if type == .keyUp { return held.remove(key) != nil }
            guard active, type == .keyDown else { return false }
            if held.contains(key) { return true }
            guard modifiers == .maskCommand, key == 12 || key == 13 else { return false }
            held.insert(key)
            return true
        }
        guard capture, let copy = event.copy() else { return Unmanaged.passUnretained(event) }
        let pointer = CGEvent(source: nil)?.location ?? copy.location
        queue.async { [self] in
            if type == .keyDown, copy.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                let enabled = lock.withLock { active }
                if enabled, let hit = MissionControlTarget.resolve(at: pointer) {
                    intercepted.insert(key)
                    if let window = hit.window {
                        Task { @MainActor in
                            guard self.lock.withLock({ self.active }) else { return }
                            await MissionControlAction.perform(key: key, window: window)
                        }
                    }
                } else { intercepted.remove(key) }
            }
            let consumed = intercepted.contains(key)
            if type == .keyUp { intercepted.remove(key) }
            if !consumed {
                copy.setIntegerValueField(.eventSourceUserData, value: Self.marker)
                copy.post(tap: .cgSessionEventTap)
            }
        }
        return nil
    }
}

/// Apply actions to the original window while keeping the native overview open.
/// Do not activate/raise the target or toggle Exposé: both disturb its live tiles.
@MainActor private enum MissionControlAction {
    private static var inFlight: Set<String> = []

    static func perform(key: Int64, window: DockWindow) async {
        let token = key == 12 ? "quit:\(window.pid)" : "close:\(window.pid):\(window.id)"
        guard !inFlight.contains(token), MissionControlTarget.isPresented(),
              let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else { return }
        if key == 12 {
            guard window.pid == getpid() || AppQuitPolicy.allows(bundleID: app.bundleIdentifier, ownBundleID: Bundle.main.bundleIdentifier) else { return }
        }
        inFlight.insert(token)
        defer { inFlight.remove(token) }
        if key == 12 {
            if window.pid == getpid() { NSApp.terminate(nil); return }
            _ = app.terminate()
        } else if window.pid == getpid() {
            // AppKit must close our own NSWindow on the main actor. Never send
            // synchronous AX IPC to this process from the main actor.
            guard let target = NSApp.windows.first(where: { $0.windowNumber == Int(window.id) }), target.isVisible else { return }
            target.performClose(nil)
        } else {
            await MissionControlTarget.closeCurrentWindow(window)
        }
        // Keep the stroke serialized through the native update, but never force
        // a window closed or repeat an action if the app presents a save sheet.
        try? await Task.sleep(for: .milliseconds(180))
    }
}

/// CloseUp strategy: confirm the exposé compositor surface, hit-test CGWindowIDs
/// directly in their displayed coordinates, then resolve only that app's AX window.
/// Titles and localized app names are never used to select an action target.
private enum MissionControlTarget {
    struct Hit { let window: DockWindow? }

    static func isPresented() -> Bool {
        let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
        return isPresented(entries)
    }

    private static func isPresented(_ entries: [[String: Any]]) -> Bool {
        let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        let manager = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.WindowManager").first?.processIdentifier
        return entries.contains { entry in
            let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let layer = entry[kCGWindowLayer as String] as? Int
            return (dock != nil && pid == dock && layer == 18) || (manager != nil && pid == manager && layer == 19)
        }
    }

    static func resolve(at point: CGPoint) -> Hit? {
        let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
        guard isPresented(entries) else { return nil }
        let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        let manager = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.WindowManager").first?.processIdentifier
        let excluded = Set([dock, manager].compactMap { $0 })
        for entry in entries {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  !excluded.contains(pid),
                  let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
                  app.activationPolicy != .prohibited || pid == getpid(),
                  let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let rawBounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rawBounds), bounds.width > 40, bounds.height > 40,
                  bounds.contains(point) else { continue }
            let title = entry[kCGWindowName as String] as? String ?? ""
            let window = resolveAXWindow(pid: pid, id: id)
            // Quit only requires the exact CG owner. Close uses the exact matched
            // AX element (own windows use AppKit) and never guesses a different one.
            return Hit(window: DockWindow(id: id, pid: pid, title: title, bounds: bounds,
                                          minimized: false, fullscreen: false, element: window))
        }
        return Hit(window: nil)
    }

    static func closeCurrentWindow(_ window: DockWindow) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DockWindowAccess.queue.async {
                defer { continuation.resume() }
                // Resolve again at action time; a thumbnail's saved AX reference
                // can be retired while Mission Control re-tiles its windows.
                guard isPresented(),
                      let target = resolveAXWindow(pid: window.pid, id: window.id),
                      let button = DockAX.element(target, kAXCloseButtonAttribute) else { return }
                AXUIElementSetMessagingTimeout(button, 0.5)
                _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
            }
        }
    }

    private static func resolveAXWindow(pid: pid_t, id: CGWindowID) -> AXUIElement? {
        if pid == getpid() { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        if let windows = value as? [AXUIElement], let match = match(id, in: windows) { return match }
        // A thin but successful AXWindows reply is common in custom UI apps.
        // A failed IPC reply is retried once rather than silently treated as empty.
        if status == .cannotComplete {
            AXUIElementSetMessagingTimeout(app, 0.5)
            if let windows = DockAX.value(app, kAXWindowsAttribute) as? [AXUIElement], let match = match(id, in: windows) { return match }
        }
        let children = DockAX.children(app).filter { DockAX.string($0, kAXRoleAttribute) == kAXWindowRole }
        if let match = match(id, in: children) { return match }
        let focused = [kAXMainWindowAttribute, kAXFocusedWindowAttribute].compactMap { DockAX.element(app, $0) }
        return match(id, in: focused)
    }

    private static func match(_ id: CGWindowID, in elements: [AXUIElement]) -> AXUIElement? {
        for element in elements.prefix(128) {
            AXUIElementSetMessagingTimeout(element, 0.15)
            var number: CGWindowID = 0
            if missionControlWindowNumber(element, &number) == .success, number == id { return element }
        }
        return nil
    }
}

@_silgen_name("_AXUIElementGetWindow")
private func missionControlWindowNumber(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError
