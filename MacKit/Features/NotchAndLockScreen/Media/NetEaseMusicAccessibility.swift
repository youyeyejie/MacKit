// Adapted from sensuschung/Atoll music-lyrics, GPL-3.0-or-later.
import AppKit
import ApplicationServices

/// Native Control menu observed in NetEase Music for macOS. Keep all AX IPC off
/// the main thread and serialize read/press/verify transactions.
enum NetEaseMusicAccessibility {
    enum Control { case favorite }

    static var isAvailable: Bool { AXIsProcessTrusted() && runningApp != nil }
    private static let queue = DispatchQueue(label: "com.atoll.netease.accessibility", qos: .userInitiated)
    private static var runningApp: NSRunningApplication? { NSRunningApplication.runningApplications(withBundleIdentifier: "com.netease.163music").first }

    static func read(_ control: Control) async -> Bool? {
        await perform { readState(control) }
    }

    /// Never treat AXPress success as playback success. Re-resolve the menu
    /// after the app has had a chance to apply its own state.
    static func set(_ control: Control, checked desired: Bool) async -> Bool {
        await perform {
            guard let element = item(control), let before = readState(control) else { return false }
            if before == desired { return true }
            guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { return false }
            for _ in 0..<25 {
                usleep(100_000)
                if readState(control) == desired { return true }
            }
            return false
        } ?? false
    }

    static func favoriteState(forTitle title: String) -> Bool? {
        switch title.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "喜欢歌曲", "Like": return false
        case "取消喜欢", "Dislike": return true
        default: return nil
        }
    }

    private static func readState(_ control: Control) -> Bool? {
        guard let element = item(control), attribute(element, kAXEnabledAttribute) as? Bool == true else { return nil }
        if control == .favorite { return title(element).flatMap(favoriteState(forTitle:)) }
        return nil
    }

    private static func item(_ control: Control) -> AXUIElement? {
        guard isAvailable, let app = runningApp else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.3)
        // CEF otherwise omits children for menus that have never been opened.
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        guard let value = attribute(root, kAXMenuBarAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let bar = value as! AXUIElement
        guard let parent = children(bar).first(where: { ["控制", "Controls", "Control"].contains(title($0) ?? "") }), let menu = children(parent).first else { return nil }
        let items = children(menu)
        if control == .favorite {
            return items.first { candidate in
                guard let label = title(candidate), favoriteState(forTitle: label) != nil else { return false }
                return (attribute(candidate, kAXMenuItemCmdCharAttribute) as? String)?.uppercased() == "L"
            }
        }
        return nil
    }

    private static func title(_ element: AXUIElement) -> String? { attribute(element, kAXTitleAttribute) as? String }
    private static func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func perform<T>(_ work: @escaping () -> T?) async -> T? {
        guard isAvailable else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
