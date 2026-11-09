// MacKit host adaptation, modified 2026-11-08.
// See THIRD_PARTY_NOTICES.md for the host integration changes; GPL-3.0-or-later.
// Derived from Atoll; GPL-3.0-or-later. MacKit routes every settings entry to its host window.
import AppKit

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    func showWindow() { AtollIntegration.shared.openSettings?() }
}
