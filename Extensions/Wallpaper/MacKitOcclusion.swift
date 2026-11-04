import Foundation
import AppKit
import CoreGraphics

@MainActor enum MacKitOcclusion {
    private static var timer: Timer?
    static func start() {
        reconfigure()
    }
    static func reconfigure() {
        timer?.invalidate(); timer = nil
        guard PlaybackStore.snapshot.prefs.pauseWhenOccluded else {
            PlaybackStore.post(.coverageChanged([]))
            return
        }
        let interval = MacKitRouting.load().pollingInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { sample() }
        }
        timer?.tolerance = min(1, interval * 0.2)
    }
    private static func sample() {
        let state = PlaybackStore.snapshot
        guard state.prefs.pauseWhenOccluded, !state.displaysAsleep, !state.screenLocked,
              SurfaceRegistry.shared.count > 0 else { return }
        let displays = Set(SurfaceRegistry.shared.surfaceKeys.compactMap { SurfaceRegistry.shared.surface(for: $0)?.displayID })
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
        let rectangles = info.compactMap { item -> CGRect? in
            guard (item[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 >= 0.99,
                  let bounds = item[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let covered = Set(displays.filter { id in
            let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
            let visible = screen?.visibleFrame
            let desktop = visible.map { CGRect(x: $0.minX, y: primaryTop - $0.maxY, width: $0.width, height: $0.height) } ?? CGDisplayBounds(id)
            return WallpaperOcclusion.covered(display: desktop, windows: rectangles)
        })
        if covered != state.prefs.occludedDisplays {
            extensionLog("[Coverage] interval=\(MacKitRouting.load().pollingInterval)s covered=\(covered.sorted())")
        }
        PlaybackStore.post(.coverageChanged(covered))
    }
}
