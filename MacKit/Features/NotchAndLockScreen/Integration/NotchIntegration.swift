import AppKit
import Defaults
import SwiftUI

/// Retains Atoll's original runtime without a second NSApplication or app bundle.
@MainActor
final class NotchIntegration {
    static let shared = NotchIntegration()
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
        Defaults[.lockScreenReminderChipStyle] = .eventColor
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

    func showsCleaningIndicator(on screen: NSScreen) -> Bool {
        guard Defaults[.notchEnabled], Defaults[.enableCleaningIndicator], let delegate else { return false }
        let panels = Array(delegate.windows.values) + [delegate.window].compactMap { $0 }
        return panels.contains { $0.isVisible && screen.frame.contains(NSPoint(x: $0.frame.midX, y: $0.frame.midY)) }
    }

    func setCleaning(_ active: Bool) {
        guard let delegate else { return }
        // Restore only panels which were visible before cleaning. A lock event
        // must not reveal a desktop notch above the lock-screen widgets.
        let panels = Array(delegate.windows.values) + [delegate.window].compactMap { $0 }
        DynamicIslandViewCoordinator.shared.cleaningActive = active
        if active {
            cleaningPanels = panels.filter(\.isVisible)
            let primary =
                NSScreen.screens.first { screen in
                    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                    else { return false }
                    return CGDisplayIsBuiltin(number.uint32Value) != 0
                } ?? NSScreen.main
            for panel in cleaningPanels {
                let screen = NSScreen.screens.first {
                    $0.frame.contains(NSPoint(x: panel.frame.midX, y: panel.frame.midY))
                }
                if screen != primary && Defaults[.notchEnabled] && Defaults[.enableCleaningIndicator] { continue }
                panel.orderOut(nil)
            }
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
