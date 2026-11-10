import AppKit
import ApplicationServices

/// Dock exposes overview lifecycle through AX notifications; no gesture tap or
/// additional polling loop is required. Falls back to native host state if denied.
@MainActor final class WallpaperOverviewObserver {
    private var observer: AXObserver?
    private var dock: AXUIElement?
    var changed: ((Bool) -> Void)?
    func start() {
        guard observer == nil, AXIsProcessTrusted(),
            let pid = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" })?
                .processIdentifier
        else { return }
        let element = AXUIElementCreateApplication(pid)
        var result: AXObserver?
        guard
            AXObserverCreate(
                pid,
                { _, _, notification, context in
                    guard let context else { return }
                    let target = Unmanaged<WallpaperOverviewObserver>.fromOpaque(context).takeUnretainedValue()
                    let active = (notification as String) != "AXExposeExit"
                    MainActor.assumeIsolated { target.changed?(active) }
                }, &result) == .success, let result
        else { return }
        let names = ["AXExposeShowAllWindows", "AXExposeShowFrontWindows", "AXExposeShowDesktop", "AXExposeExit"]
        for name in names {
            AXObserverAddNotification(result, element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        observer = result
        dock = element
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(result), .commonModes)
    }
    func stop() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        dock = nil
    }
}
