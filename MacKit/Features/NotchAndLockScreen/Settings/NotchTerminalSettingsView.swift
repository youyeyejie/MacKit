// Derived from Atoll; GPL-3.0-or-later.
// Original settings by Richard Kunkli, 2024; MacKit host adaptation, 2026.
// See THIRD_PARTY_NOTICES.md.
import AppKit
import Defaults
import SwiftUI

struct NotchTerminalSettingsView: View {
    @Default(.terminalShellPath) private var shell
    @Default(.terminalFontFamily) private var font
    @Default(.terminalFontSize) private var size
    @Default(.terminalMaxHeightFraction) private var height
    var body: some View {
        Group {
            UnifiedSettingsSection("终端") {
                Defaults.Toggle(key: .enableTerminalFeature) { Text("启用终端") }
                Defaults.Toggle(key: .terminalStickyMode) { Text("鼠标移开时保持终端打开") }
                SettingsRow(title: "命令解释器") {
                    TextField("", text: $shell, prompt: Text("/bin/zsh"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                }
                SettingsRow(title: "重启终端") { Button("重启") { TerminalManager.shared.restartShell() } }
            }
            UnifiedSettingsSection("外观") {
                SettingsRow(title: "字体") {
                    Picker("字体", selection: $font) {
                        ForEach(
                            Array(
                                Set(
                                    NSFontManager.shared.availableFontFamilies.filter { family in
                                        guard let candidate = NSFont(name: family, size: 13) else { return false }
                                        return candidate.isFixedPitch
                                            || NSFontManager.shared.traits(of: candidate).contains(.fixedPitchFontMask)
                                    } + [font])
                            ).sorted(), id: \.self
                        ) { family in
                            Text(family).font(.custom(family, size: 13)).tag(family)
                        }
                    }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(
                        maxWidth: 200, alignment: .trailing)
                }
                CompactSettingsSlider(value: $size, in: 9...24, step: 1, valueText: "\(Int(size)) pt") { Text("字号") }
                CompactSettingsSlider(value: $height, in: 0.2...0.8, step: 0.05, valueText: "\(Int(height * 100))%") {
                    Text("最大屏幕高度占比")
                }
            }
        }
        .onChange(of: size) { _, value in TerminalManager.shared.applyFontSize(value) }
        .onChange(of: font) { _, value in TerminalManager.shared.applyFontFamily(value) }
    }
}
