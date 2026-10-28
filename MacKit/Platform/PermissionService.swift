import AppKit
import ApplicationServices
import Observation

@MainActor @Observable
final class PermissionService {
    private(set) var accessibility = AXIsProcessTrusted()

    func refresh() { accessibility = AXIsProcessTrusted() }

    func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" // C global is not annotated for Swift 6 concurrency.
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        refresh()
    }

    func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
