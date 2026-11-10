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
                Defaults.Toggle(key: .showLyricsBelowBuiltinNotch) {
                    SettingsDescription(title: "在常驻灵动岛显示歌词", subtitle: "开启后若在外接显示器上使用灵动岛，则在外接显示器上显示歌词；否则在内建显示器上显示歌词横幅。")
                }
            }
        }
    }
}
