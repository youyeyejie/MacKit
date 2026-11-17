// Derived from Atoll; GPL-3.0-or-later.
// Original settings by Richard Kunkli, 2024; MacKit host adaptation, 2026.
// See THIRD_PARTY_NOTICES.md.
import AppKit
import Defaults
import SwiftUI

struct NotchMediaSettingsView: View {
    private static let hideDelays: [Double] = [0, 1, 3, 5, 10, 15, 30, 60, -1]
    @Default(.pausedMediaHideDelay) private var pausedMediaHideDelay
    var body: some View {
        Group {
            UnifiedSettingsSection("媒体控制") {
                Defaults.Toggle(key: .showStandardMediaControls) { Text("启用媒体控制") }
                Defaults.Toggle(key: .autoHideInactiveNotchMediaPlayer) { Text("自动隐藏未播放媒体的面板") }
                Defaults.Toggle(key: .showLyricsBelowBuiltinNotch) {
                    SettingsDescription(title: "只在常驻灵动刘海显示歌词", subtitle: "开启时优先在外接屏常驻刘海显示，否则显示内建屏横幅；关闭时所有灵动刘海均显示。")
                }
                CompactSettingsSlider(
                    value: Binding(
                        get: { Self.hideDelays.firstIndex(of: pausedMediaHideDelay).map(Double.init) ?? 2 },
                        set: { pausedMediaHideDelay = Self.hideDelays[Int($0.rounded())] }), in: 0...8, step: 1,
                    valueText: pausedMediaHideDelay < 0 ? "不收回" : "\(Int(pausedMediaHideDelay)) 秒", uniform: false
                ) {
                    Text("暂停时收回媒体面板")
                }
                Defaults.Toggle(key: .hideLyricsWhenPaused) {
                    SettingsDescription(title: "暂停时收回歌词横幅", subtitle: "设置暂停时不收回媒体面板时，开启此选项可收回歌词横幅。")
                }
                .disabled(pausedMediaHideDelay >= 0)

            }
            UnifiedSettingsSection("手势控制") {
                Defaults.Toggle(key: .swipeToChangeTrack) {
                    SettingsDescription(title: "启用左右滑动切歌", subtitle: "悬停在灵动刘海或展开后的媒体控制区域时，双指向左滑动切换下一首，向右滑动切换上一首。")
                }
            }
        }
    }
}
