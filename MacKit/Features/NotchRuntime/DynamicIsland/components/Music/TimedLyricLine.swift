// MacKit playback-driven lyric presentation, GPL-3.0-or-later. Modified 2026-11-08.
import SwiftUI

struct TimedLyricLine: View {
    @ObservedObject private var music = MusicManager.shared
    let width: CGFloat
    let color: Color
    var textScale: CGFloat = 1
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
            let duration = max(0.001, end - start)
            let scrollStart = start + duration * 0.5
            let earlyFinish = min(0.4, duration * 0.15)
            let scrollEnd = max(scrollStart + 0.001, end - earlyFinish)
            let fraction = min(1, max(0, (position - scrollStart) / (scrollEnd - scrollStart)))
            let font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize * textScale)
            let measuredWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
            Text(text).font(.system(size: NSFont.preferredFont(forTextStyle: .body).pointSize * textScale)).foregroundStyle(foreground)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .offset(x: -max(0, measuredWidth - width) * fraction)
                .frame(width: max(0, width), alignment: measuredWidth > width ? .leading : .center).clipped()
        }.frame(height: NSFont.preferredFont(forTextStyle: .body).pointSize * 1.4 * textScale)
    }

}
