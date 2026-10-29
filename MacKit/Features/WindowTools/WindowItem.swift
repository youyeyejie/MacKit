import AppKit
import CoreGraphics
import Observation

/// A lightweight snapshot of a user window. Images are deliberately kept out
/// of this model so the catalog never retains full-size window content.
@MainActor @Observable
final class WindowItem: Identifiable {
    var stableID: String { "\(ownerPID):\(id)" }
    var isWindowless: Bool { id == 0 }
    var window: DockWindow?
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect
    let isOnscreen: Bool
    var isMinimized: Bool
    let isFullscreen: Bool
    let appIcon: NSImage?

    init(id: CGWindowID, ownerPID: pid_t, ownerName: String, title: String,
         bounds: CGRect, isOnscreen: Bool, isMinimized: Bool,
         isFullscreen: Bool, appIcon: NSImage?) {
        self.id = id
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
        self.bounds = bounds
        self.isOnscreen = isOnscreen
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.appIcon = appIcon
    }

}
