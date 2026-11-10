// Derived from Atoll; GPL-3.0-or-later.
// Original settings by Richard Kunkli, 2024; MacKit host adaptation, 2026.
// See THIRD_PARTY_NOTICES.md.
import AppKit
import Defaults
import SwiftUI

struct NotchGeneralSettingsView: View {
    @Default(.notchEnabled) private var featureEnabled
    @Default(.builtinClosedNotchWidth) private var builtinWidth
    @Default(.externalClosedNotchWidth) private var externalWidth
    @Default(.openNotchWidth) private var width
    @State private var screens: [String] = NSScreen.screens.compactMap { $0.localizedName }
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.showEmojis) var showEmojis

    @Default(.minimumHoverDuration) var minimumHoverDuration

    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay

    @Default(.openNotchOnHover) var openNotchOnHover

    @Default(.externalDisplayStyle) var externalDisplayStyle
    @Default(.hideNonNotchUntilHover) var hideNonNotchUntilHover

    var body: some View {
        Group {

            UnifiedSettingsSection {
                Toggle(
                    "启用灵动刘海",
                    isOn: Binding(
                        get: { featureEnabled },
                        set: { value in
                            Defaults[.notchEnabled] = value
                            NotchIntegration.shared.delegate?.applyNotchEnabled(value)
                        }))
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("在所有显示器上显示")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                SettingsRow(title: "在指定显示器上显示") {
                    Picker("在指定显示器上显示", selection: $coordinator.preferredScreen) {
                        ForEach(screens, id: \.self) { screen in
                            Text(screen)
                        }
                    }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(
                        maxWidth: 200, alignment: .trailing)
                }
                .onChange(of: NSScreen.screens) {
                    screens = NSScreen.screens.compactMap({ $0.localizedName })
                }
                .disabled(showOnAllDisplays)
                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("自动切换显示器")
                }
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(
                        name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
                Defaults.Toggle(key: .hideDynamicIslandFromScreenCapture) {
                    Text("截图或录屏时隐藏刘海")
                }
            } header: {
                Text("通用")
            }

            NotchBehaviour()

            UnifiedSettingsSection("外观") {
                let minimum = builtinClosedMinimumWidth()
                CompactSettingsSlider(
                    value: Binding(get: { max(minimum, builtinWidth) }, set: { builtinWidth = $0 }),
                    in: minimum...max(400, minimum + 200), step: 4, valueText: "\(Int(max(minimum, builtinWidth))) pt"
                ) {
                    Text("内建显示器闭合宽度")
                }.onChange(of: builtinWidth) { _, _ in
                    NotificationCenter.default.post(name: .notchHeightChanged, object: nil)
                }

                CompactSettingsSlider(
                    value: $externalWidth, in: 120...360, step: 4, valueText: "\(Int(externalWidth)) pt"
                ) { Text("外接显示器闭合宽度") }
                .onChange(of: externalWidth) { _, _ in
                    NotificationCenter.default.post(name: .notchHeightChanged, object: nil)
                }

                CompactSettingsSlider(
                    value: $width, in: Double(currentRecommendedMinimumNotchWidth())...900, step: 10,
                    valueText: "\(Int(width)) pt"
                ) {
                    Text("展开宽度")
                } onEditingChanged: { editing in
                    if editing {
                        AtollAppDelegate.shared?.viewModels.values.forEach { $0.open() }
                        AtollAppDelegate.shared?.vm.open()
                    }
                }
                .onChange(of: width) { _, _ in
                    AtollAppDelegate.shared?.viewModels.values.forEach { $0.open() }
                    AtollAppDelegate.shared?.vm.open()
                }
                SettingsRow(title: "外接显示器样式") {
                    Picker("外接显示器样式", selection: $externalDisplayStyle) {
                        ForEach(ExternalDisplayStyle.allCases) { style in
                            Text(style.localizedName)
                                .tag(style)
                        }
                    }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(
                        maxWidth: 200, alignment: .trailing)
                }
                .onChange(of: externalDisplayStyle) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        }

    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        UnifiedSettingsSection {
            Defaults.Toggle(key: .enableHaptics) {
                Text("启用触觉反馈")
            }
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("悬停时展开刘海")
            }
            if openNotchOnHover {
                CompactSettingsSlider(
                    value: $minimumHoverDuration, in: 0...1, step: 0.1,
                    valueText: String(format: "%.1f 秒", minimumHoverDuration)
                ) { Text("悬停延迟") }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
            Toggle("记住上次标签页", isOn: $coordinator.openLastTabByDefault)
            Defaults.Toggle(key: .hideNonNotchUntilHover) {
                SettingsDescription(title: "在非刘海显示器上悬停时显示", subtitle: "启用后，外接显示器上的刘海会隐藏，指针悬停时显示。")
            }
        } header: {
            Text("刘海行为")
        }
    }
}
