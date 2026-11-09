// MacKit fixed controls, derived from Atoll, GPL-3.0-or-later. Modified 2026-11-08.
import Foundation

enum MusicControlButton: String, Identifiable {
    case reloadLyrics, trackBackward, playPause, trackForward, mediaOutput
    var id: String { rawValue }
    static let slotCount = 5
    static let defaultLayout: [MusicControlButton] = [.reloadLyrics, .trackBackward, .playPause, .trackForward, .mediaOutput]
    var prefersLargeScale: Bool { self == .playPause }
    var iconName: String {
        switch self {
        case .reloadLyrics:
            if #available(macOS 15, *) { return "arrow.trianglehead.clockwise" }
            return "arrow.clockwise"
        case .trackBackward: return "backward.fill"
        case .playPause: return "playpause"
        case .trackForward: return "forward.fill"
        case .mediaOutput: return "speaker.wave.2"
        }
    }
}
