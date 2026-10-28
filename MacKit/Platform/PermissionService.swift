import AppKit
import ApplicationServices
import Observation
import Darwin

@MainActor @Observable
final class PermissionService {
    private(set) var accessibility = AXIsProcessTrusted()

    private(set) var protectedDataReadable = false
    func refresh() {
        accessibility = AXIsProcessTrusted()
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path
        let descriptor = open(path, O_RDONLY)
        protectedDataReadable = descriptor >= 0
        if descriptor >= 0 { close(descriptor) }
    }

    func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" // C global is not annotated for Swift 6 concurrency.
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        openSettings("Privacy_Accessibility")
        refresh()
    }

    func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
