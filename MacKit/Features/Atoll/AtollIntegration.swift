import AppKit
import SwiftUI
import Defaults

/// Retains Atoll's original runtime without a second NSApplication or app bundle.
@MainActor
final class AtollIntegration {
    static let shared = AtollIntegration()
    private(set) var delegate: AtollAppDelegate?
    var openSettings: (() -> Void)?
    private var cleaningPanels: [NSWindow] = []

    func start(_ notification: Notification) {
        guard delegate == nil else { return }
        if UserDefaults.standard.bool(forKey: "enableCustomOSD") {
            Defaults[.enableSystemHUD] = true
            Defaults[.enableVerticalHUD] = false
        }
        UserDefaults.standard.removeObject(forKey: "enableCustomOSD")
        if !UserDefaults.standard.bool(forKey: "mackit.migratedCalendarRetention") {
            if Defaults[.lockScreenShowCalendarEventAfterStartEnabled] {
                Defaults[.lockScreenShowCalendarEventEntireDuration] = true
            }
            Defaults[.lockScreenShowCalendarEventAfterStartEnabled] = false
            UserDefaults.standard.set(true, forKey: "mackit.migratedCalendarRetention")
        }
        Defaults[.lockScreenBatteryUsesLaptopSymbol] = true
        let runtime = AtollAppDelegate()
        delegate = runtime
        runtime.applicationDidFinishLaunching(notification)
    }

    func stop(_ notification: Notification) {
        delegate?.applicationWillTerminate(notification)
        delegate = nil
        cleaningPanels.removeAll()
        openSettings = nil
    }

    func restoreActivationPolicy() {
        NSApp.setActivationPolicy(UserDefaults.standard.bool(forKey: "appearance.showDock") ? .regular : .accessory)
    }

    func setCleaning(_ active: Bool) {
        guard let delegate else { return }
        // Restore only panels which were visible before cleaning. A lock event
        // must not reveal a desktop notch above the lock-screen widgets.
        let panels = Array(delegate.windows.values) + [delegate.window].compactMap { $0 }
        if active {
            cleaningPanels = panels.filter(\.isVisible)
            for panel in cleaningPanels { panel.orderOut(nil) }
        } else {
            if !LockScreenManager.shared.isLocked {
                for panel in cleaningPanels where panels.contains(where: { $0 === panel }) {
                    panel.orderFrontRegardless()
                }
            }
            cleaningPanels.removeAll()
        }
    }
}
