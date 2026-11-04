import Foundation

/// Provider selection remains the desktop default; optional overrides are
/// applied inside the native rendering surface, never by replacing Apple assets.
struct WallpaperRouting: Codable, Equatable, Sendable {
    var lockedVideoID: String?
    var transitionSeconds: Double = 0.6
    var detectionSeconds: Double?
    static let detectionIntervals: [Double] = [0.1, 0.2, 0.3, 0.5, 0.7, 1, 1.5, 2, 3, 5, 7, 10]
    var pollingStep: Int { Self.detectionIntervals.firstIndex(of: pollingInterval) ?? 7 }
    var pollingInterval: Double {
        guard let value = detectionSeconds, value.isFinite else { return 2 }
        return Self.detectionIntervals.min { abs($0 - value) < abs($1 - value) } ?? 2
    }
    func choice(mode: String, systemChoice: String?, isLocked: Bool = false) -> String? {
        if isLocked { return lockedVideoID ?? systemChoice }
        return switch mode {
        case "locked": lockedVideoID ?? systemChoice
        case "idle": systemChoice
        default: systemChoice
        }
    }
    var duration: Double { transitionSeconds.isFinite ? min(2, max(0, transitionSeconds)) : 0.6 }
}
