// MacKit playback-driven lyric presentation, GPL-3.0-or-later. Modified 2026-11-08.
import SwiftUI

struct TimedLyricLine: View {
    @ObservedObject private var music = MusicManager.shared
    let width: CGFloat
    let color: Color
    var textScale: CGFloat = 1
    @State private var measuredWidth: CGFloat = 0
    var body: some View {
        let foreground = color.readableOnBlack()
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !music.isPlaying)) { context in
            let position = music.estimatedPlaybackPosition(at: context.date)
            let index = music.syncedLyrics.lastIndex { $0.timestamp <= position }
            let line = index.map { music.syncedLyrics[$0] }
            let text = line?.text ?? (music.syncedLyrics.isEmpty ? music.currentLyrics : "")
            let start = line?.timestamp ?? position
            let next = index.flatMap { selected in music.syncedLyrics.dropFirst(selected + 1).first { $0.timestamp > start }?.timestamp }
            let end = next ?? max(start + 1, music.songDuration)
            // Hold through the first half, then scroll at constant speed to the end.
            let fraction = min(1, max(0, ((position - start) / max(0.001, end - start) - 0.5) * 2))
            Text(text).font(.system(size: NSFont.preferredFont(forTextStyle: .body).pointSize * textScale)).foregroundStyle(foreground)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .background { GeometryReader { geo in
                    Color.clear.onAppear { measuredWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, size in measuredWidth = size }
                } }
                .offset(x: -max(0, measuredWidth - width) * fraction)
                .frame(width: max(0, width), alignment: .leading).clipped()
        }.frame(height: NSFont.preferredFont(forTextStyle: .body).pointSize * 1.4 * textScale)
    }

}
