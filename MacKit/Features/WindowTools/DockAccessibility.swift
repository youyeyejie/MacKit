import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func dockWindowNumber(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// AX references are confined to DockWindowAccess.queue after construction.
struct DockWindow: Identifiable, @unchecked Sendable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let bounds: CGRect
    let minimized: Bool
    let fullscreen: Bool
    let element: AXUIElement?
}

enum DockAX {
    static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }
    static func string(_ element: AXUIElement, _ name: String) -> String? { value(element, name) as? String }
    static func bool(_ element: AXUIElement, _ name: String) -> Bool { (value(element, name) as? NSNumber)?.boolValue ?? false }
    static func element(_ source: AXUIElement, _ name: String) -> AXUIElement? {
        guard let result = value(source, name), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }
    static func children(_ source: AXUIElement) -> [AXUIElement] { value(source, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = value(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }
}

/// All target-app AX enumeration and mutations run off the input tap/UI thread.
enum DockWindowAccess {
    static let queue = DispatchQueue(label: "MacKit.Dock.Accessibility", qos: .userInitiated)

    static func windows(pid: pid_t) async -> [DockWindow] {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: read(pid: pid)) }
        }
    }

    private static func read(pid: pid_t) -> [DockWindow] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
        let surfaces = raw.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
        let order = surfaces.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        let axAnswer = DockAX.value(app, kAXWindowsAttribute) as? [AXUIElement]
        var elements = axAnswer ?? []
        for name in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if let window = DockAX.element(app, name), !elements.contains(where: { CFEqual($0, window) }) { elements.append(window) }
        }
        var windows: [CGWindowID: DockWindow] = [:]
        let deadline = ProcessInfo.processInfo.systemUptime + 0.8
        for element in elements.prefix(64) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            AXUIElementSetMessagingTimeout(element, 0.1)
            guard DockAX.string(element, kAXRoleAttribute) == kAXWindowRole else { continue }
            var id: CGWindowID = 0
            guard dockWindowNumber(element, &id) == .success, id != 0 else { continue }
            let minimized = DockAX.bool(element, kAXMinimizedAttribute)
            let fullscreen = DockAX.bool(element, "AXFullScreen")
            let subrole = DockAX.string(element, kAXSubroleAttribute)
            guard minimized || fullscreen || subrole == nil || subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
            guard let frame = DockAX.frame(element), frame.width >= 80, frame.height >= 50 else { continue }
            windows[id] = DockWindow(id: id, pid: pid, title: DockAX.string(element, kAXTitleAttribute) ?? "",
                                     bounds: frame, minimized: minimized, fullscreen: fullscreen, element: element)
        }
        // AX can omit fullscreen windows on another Space. Merge those CG
        // surfaces instead of treating the AX array as the entire directory.
        for info in surfaces where axAnswer == nil {
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value, windows[id] == nil,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.width >= 80, frame.height >= 50 else { continue }
            let title = info[kCGWindowName as String] as? String ?? ""
            guard WindowPresence.permitsSurface(axAnswered: axAnswer != nil, onScreen: (info[kCGWindowIsOnscreen as String] as? Bool) == true, hasTitle: !title.isEmpty) else { continue }
            windows[id] = DockWindow(id: id, pid: pid, title: title, bounds: frame, minimized: false, fullscreen: false, element: nil)
        }
        return windows.values.sorted {
            let l = order.firstIndex(of: $0.id) ?? Int.max, r = order.firstIndex(of: $1.id) ?? Int.max
            return l == r ? $0.id < $1.id : l < r
        }
    }

    static func setMinimized(_ value: Bool, windows: [DockWindow]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                for window in windows {
                    guard let element = window.element, !window.fullscreen else { continue }
                    _ = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, value ? kCFBooleanTrue : kCFBooleanFalse)
                }
                continuation.resume()
            }
        }
    }

    static func raise(_ window: DockWindow) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                let element = window.element ?? read(pid: window.pid).first(where: { $0.id == window.id })?.element
                if let element {
                    _ = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    let app = AXUIElementCreateApplication(window.pid)
                    AXUIElementSetMessagingTimeout(app, 0.15)
                    _ = AXUIElementSetAttributeValue(app, kAXMainWindowAttribute as CFString, element)
                    _ = AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, element)
                    _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    _ = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
                    _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                }
                continuation.resume()
            }
        }
    }

    static func close(_ window: DockWindow) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                if let element = window.element, let button = DockAX.element(element, kAXCloseButtonAttribute) {
                    _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
                }
                continuation.resume()
            }
        }
    }

    static func minimizeAllMenu(pid: pid_t) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.15)
                guard let menu = DockAX.element(app, kAXMenuBarAttribute) else { continuation.resume(returning: false); return }
                var budget = 400
                let deadline = ProcessInfo.processInfo.systemUptime + 0.5
                for heading in DockAX.children(menu).reversed() {
                    for submenu in DockAX.children(heading) {
                        for item in DockAX.children(submenu) {
                            budget -= 1
                            guard budget >= 0, ProcessInfo.processInfo.systemUptime < deadline else { continuation.resume(returning: false); return }
                            if DockAX.string(item, kAXIdentifierAttribute) == "miniaturizeAll:", DockAX.bool(item, kAXEnabledAttribute) {
                                continuation.resume(returning: AXUIElementPerformAction(item, kAXPressAction as CFString) == .success)
                                return
                            }
                        }
                    }
                }
                continuation.resume(returning: false)
            }
        }
    }
}
