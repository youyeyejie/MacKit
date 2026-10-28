import ApplicationServices
import Foundation

/// Runs away from the input callback, with bounded AX messaging time.
enum FinderFocus {
    static func isFileBrowser(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        if let window = element(app, kAXFocusedWindowAttribute),
           string(window, kAXSubroleAttribute) == kAXDialogSubrole as String { return false }
        guard var current = element(app, kAXFocusedUIElementAttribute) else { return false }
        for _ in 0..<8 {
            guard let role = string(current, kAXRoleAttribute) else { return false }
            if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, kAXSearchFieldSubrole].contains(role) { return false }
            if ["AXOutline", "AXTable", "AXList", "AXBrowser"].contains(role) { return true }
            guard let parent = element(current, kAXParentAttribute) else { return false }
            current = parent
        }
        return false
    }
    private static func element(_ source: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(source, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func string(_ source: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(source, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
