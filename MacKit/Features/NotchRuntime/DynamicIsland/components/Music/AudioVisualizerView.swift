// Adapted from Atoll, GPL-3.0-or-later. MacKit fixed animated spectrum, 2026-11-08.
import SwiftUI
struct AudioVisualizerView: View {
    @Binding var isPlaying: Bool
    var body: some View { AudioSpectrumView(isPlaying: $isPlaying) }
}
