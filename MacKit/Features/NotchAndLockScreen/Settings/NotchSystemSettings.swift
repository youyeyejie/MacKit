// Derived from Atoll; GPL-3.0-or-later.
// Original settings by Richard Kunkli, 2024; MacKit host adaptation, 2026.
// See THIRD_PARTY_NOTICES.md.
import AppKit
import Defaults
import SwiftUI

struct HUDAndOSDSettingsView: View {
    @Default(.enableSystemHUD) private var notchEnabled
    @Default(.enableVerticalHUD) private var verticalEnabled
    @AppStorage("notch.controls.preferredStyle") private var preferredStyle = "notch"
    @Default(.inlineHUD) private var inlineLayout
    @Default(.progressBarStyle) private var progressStyle
    private var enabled: Bool { notchEnabled || verticalEnabled }
    private var style: String {
        verticalEnabled ? "vertical" : (notchEnabled ? "notch" : (preferredStyle == "vertical" ? "vertical" : "notch"))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.pageSpacing) {
            SettingsRows(title: "系统控制") {
                SettingsRow(title: "启用系统控制") {
                    Toggle("启用系统控制", isOn: Binding(get: { enabled }, set: setEnabled)).labelsHidden().toggleStyle(
                        .switch
                    ).controlSize(.small)
                }
                Divider()
                option("启用音量提示", key: .enableVolumeHUD)
                Divider()
                option("启用亮度提示", key: .enableBrightnessHUD)
                Divider()
                option("启用键盘背光提示", key: .enableKeyboardBacklightHUD)
            }
            SettingsRows(title: "外观") {
                SettingsRow(title: "样式") {
                    Picker("样式", selection: Binding(get: { style }, set: setStyle)) {
                        Text("刘海").tag("notch")
                        Text("侧边").tag("vertical")
                    }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().pickerStyle(.menu)
                }
                if style == "vertical" {
                    Divider()
                    option("启用鼠标交互", key: .verticalHUDInteractive)
                    Divider()
                    option("显示百分比", key: .verticalHUDShowValue)
                    Divider()
                    option("指示器使用强调色", key: .verticalHUDUseAccentColor)
                } else {
                    Divider()
                    SettingsRow(title: "提示布局") {
                        Picker("提示布局", selection: $inlineLayout) {
                            Text("内嵌").tag(true)
                            Text("横幅").tag(false)
                        }.frame(minWidth: AppStyle.pickerMinimumWidth)
                            .labelsHidden().pickerStyle(.menu)
                            .onChange(of: inlineLayout) { _, _ in
                                DynamicIslandViewCoordinator.shared.previewSetting(
                                    "音量", symbol: "speaker.wave.2.fill", type: .volume)
                            }
                    }
                    Divider()
                    SettingsRow(title: "进度条样式") {
                        Picker("进度条样式", selection: $progressStyle) {
                            Text("分层").tag(ProgressBarStyle.hierarchical)
                            Text("渐变").tag(ProgressBarStyle.gradient)
                            Text("分段").tag(ProgressBarStyle.segmented)
                        }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().pickerStyle(.menu)
                    }
                    Divider()
                    option("显示百分比", key: .showProgressPercentages)
                    Divider()
                    option("启用音量颜色提示", key: .useColorCodedVolumeDisplay)
                    Divider()
                    option("指示器使用强调色", key: .systemEventIndicatorUseAccent)
                }
            }
            ExternalDisplayIntegrationsSection(stepsOnly: true)
            ExternalDisplayIntegrationsSection()
        }
    }
    private func option(_ title: String, key: Defaults.Key<Bool>) -> some View {
        SettingsRow(title: title) {
            Defaults.Toggle(key: key) { Text(title) }
                .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!enabled)
                .onReceive(Defaults.publisher(key, options: [])) { change in
                    guard change.newValue else { return }
                    let type: SneakContentType =
                        key.name == Defaults.Keys.enableBrightnessHUD.name
                        ? .brightness
                        : (key.name == Defaults.Keys.enableKeyboardBacklightHUD.name ? .backlight : .volume)
                    let symbol =
                        type == .brightness
                        ? "sun.max.fill" : (type == .backlight ? "light.max" : "speaker.wave.2.fill")
                    DynamicIslandViewCoordinator.shared.previewSetting(title, symbol: symbol, type: type)
                }
        }
    }
    private func setEnabled(_ value: Bool) {
        if value {
            setStyle(style, activate: true)
        } else {
            preferredStyle = style
            notchEnabled = false
            verticalEnabled = false
        }
    }
    private func setStyle(_ value: String) { setStyle(value, activate: enabled) }
    private func setStyle(_ value: String, activate: Bool) {
        preferredStyle = value == "vertical" ? "vertical" : "notch"
        if activate {
            notchEnabled = preferredStyle == "notch"
            verticalEnabled = preferredStyle == "vertical"
        }
    }
}

// MARK: - External Display Integrations Settings Section

private struct ExternalDisplayIntegrationsSection: View {
    var stepsOnly = false
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.thirdPartyDDCProvider) var thirdPartyDDCProvider
    @Default(.enableExternalVolumeControlListener) var enableExternalVolumeControlListener
    @Default(.volumeStepPercent) var volumeStepPercent
    @Default(.volumeFineStepPercent) var volumeFineStepPercent
    @Default(.brightnessStepPercent) var brightnessStepPercent
    @Default(.brightnessFineStepPercent) var brightnessFineStepPercent
    @ObservedObject private var betterDisplayManager = BetterDisplayManager.shared
    @ObservedObject private var lunarManager = LunarManager.shared

    private var providerStatusText: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if betterDisplayManager.isRunning { return "运行中" }
            if betterDisplayManager.isDetected { return "未运行" }
            return "未检测到"
        case .lunar:
            if lunarManager.isConnected { return "已连接" }
            if lunarManager.isRunning { return "运行中" }
            if lunarManager.isDetected { return "未运行" }
            return "未检测到"
        }
    }

    private var providerStatusColor: Color {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if betterDisplayManager.isRunning { return .green }
            if betterDisplayManager.isDetected { return .orange }
            return .secondary
        case .lunar:
            if lunarManager.isConnected { return .green }
            if lunarManager.isRunning { return .orange }
            if lunarManager.isDetected { return .orange }
            return .secondary
        }
    }

    private var providerStatusDescription: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if !betterDisplayManager.isDetected {
                return "安装 [BetterDisplay](https://betterdisplay.pro) 后，可显示外接显示器的亮度和音量提示。"
            }
            if !betterDisplayManager.isRunning {
                return "已安装 BetterDisplay，但尚未运行。启动后即可启用集成。"
            }
            return "使用当前提示样式显示 BetterDisplay 的亮度变化，开启音量监听后也会显示音量变化。请在 BetterDisplay 的应用集成设置中启用提示集成。"
        case .lunar:
            if !lunarManager.isDetected {
                return "安装 [Lunar](https://lunar.fyi) 后，可通过 DDC 调节外接显示器并显示提示。"
            }
            if !lunarManager.isRunning {
                return "已安装 Lunar，但尚未运行。启动后即可启用集成。"
            }
            if lunarManager.isConnected {
                return "已连接 Lunar，亮度和对比度变化会显示提示；启用下方音量监听后，也会显示音量提示。"
            }
            return "Lunar 正在运行，正在等待自动建立连接。"
        }
    }

    private func refreshDetectionStatus() {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            betterDisplayManager.refreshDetectionStatus()
        case .lunar:
            lunarManager.refreshDetectionStatus()
        }
    }

    var body: some View {
        Group {
            if stepsOnly {
                UnifiedSettingsSection("调节步长") {
                    SettingsRow(title: "音量步长", subtitle: "每次按键的调节百分比。启用外接设备音量监听时不可用。") {
                        Text("\(volumeStepPercent)%").foregroundStyle(.secondary).monospacedDigit()
                        Stepper("音量步长", value: $volumeStepPercent, in: 1...25).labelsHidden().fixedSize()
                    }.disabled(enableExternalVolumeControlListener)
                    SettingsRow(title: "音量精细步长", subtitle: "按住 Shift 和 Option 使用精细步长。") {
                        Text("\(volumeFineStepPercent)%").foregroundStyle(.secondary).monospacedDigit()
                        Stepper("音量精细步长", value: $volumeFineStepPercent, in: 1...25).labelsHidden().fixedSize()
                    }.disabled(enableExternalVolumeControlListener)
                    SettingsRow(title: "亮度步长", subtitle: "每次按键的调节百分比。启用第三方亮度集成时不可用。") {
                        Text("\(brightnessStepPercent)%").foregroundStyle(.secondary).monospacedDigit()
                        Stepper("亮度步长", value: $brightnessStepPercent, in: 1...25).labelsHidden().fixedSize()
                    }.disabled(enableThirdPartyDDCIntegration)
                    SettingsRow(title: "亮度精细步长", subtitle: "按住 Shift 和 Option 使用精细步长。") {
                        Text("\(brightnessFineStepPercent)%").foregroundStyle(.secondary).monospacedDigit()
                        Stepper("亮度精细步长", value: $brightnessFineStepPercent, in: 1...25).labelsHidden().fixedSize()
                    }.disabled(enableThirdPartyDDCIntegration)
                }
            } else {
                UnifiedSettingsSection("外接显示器") {
                    Toggle(isOn: $enableThirdPartyDDCIntegration) {
                        SettingsDescription(title: "启用第三方显示器控制集成", subtitle: "通过刘海提示显示 BetterDisplay 或 Lunar 的显示器调节。")
                    }
                    if enableThirdPartyDDCIntegration {
                        SettingsRow(title: "服务提供方", subtitle: providerStatusDescription) {
                            Picker("服务提供方", selection: $thirdPartyDDCProvider) {
                                ForEach(ThirdPartyDDCProvider.allCases) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(
                                maxWidth: 200, alignment: .trailing)
                        }
                        Toggle(isOn: $enableExternalVolumeControlListener) {
                            SettingsDescription(title: "监听外接设备音量控制", subtitle: "开启后跟随所选服务的音量数据，关闭后使用内建音量键拦截。")
                        }
                        SettingsRow(title: "连接状态") {
                            Text(providerStatusText).foregroundStyle(providerStatusColor)
                            Button("刷新检测") { refreshDetectionStatus() }
                        }
                    }
                }
            }
        }
    }
}
