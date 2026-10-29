import AppKit
import ApplicationServices
import CoreGraphics
import Observation

@MainActor @Observable
final class PermissionService {
    private(set) var accessibility = AXIsProcessTrusted()
    private(set) var screenRecording = CGPreflightScreenCaptureAccess()

    func refresh() {
        accessibility = AXIsProcessTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
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

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        openSettings("Privacy_ScreenCapture")
        refresh()
    }
}
