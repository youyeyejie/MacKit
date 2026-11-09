// MacKit fixed controls, derived from Atoll, GPL-3.0-or-later. Modified 2026-11-08.
import Foundation

enum MusicControlButton: String, Identifiable {
    case appVolume, trackBackward, playPause, trackForward, mediaOutput
    var id: String { rawValue }
    static let slotCount = 5
    static let defaultLayout: [MusicControlButton] = [.appVolume, .trackBackward, .playPause, .trackForward, .mediaOutput]
    var prefersLargeScale: Bool { self == .playPause }
    var iconName: String {
        switch self {
        case .appVolume: "slider.horizontal.3"
        case .trackBackward: "backward.fill"
        case .playPause: "playpause"
        case .trackForward: "forward.fill"
        case .mediaOutput: "speaker.wave.2"
        }
    }
}
