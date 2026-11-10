// Derived from Atoll; GPL-3.0-or-later.
// Original settings by Richard Kunkli, 2024; MacKit host adaptation, 2026.
// See THIRD_PARTY_NOTICES.md.
import AppKit
import Defaults
import SwiftUI

struct LockScreenSettingsView: View {
    var destination: AppPage = .lockScreen
    var navigate: (AppPage) -> Void = { _ in }
    @Default(.lockScreenWeatherWidgetStyle) private var weatherStyle
    @Default(.lockScreenWeatherTemperatureUnit) private var unit
    @Default(.lockScreenWeatherProviderSource) private var provider
    var body: some View {
        Group {
            switch destination {
            case .lockMedia: mediaPanel
            case .lockWeather: weather
            case .lockBattery: battery
            case .lockSchedule: schedule
            case .lockFocus: focusSettings
            default:
                general
                SettingsRows(title: "组件") {
                    SettingsDestinationRow(title: "媒体") { navigate(.lockMedia) }
                    Divider()
                    SettingsDestinationRow(title: "天气") { navigate(.lockWeather) }
                    Divider()
                    SettingsDestinationRow(title: "电池") { navigate(.lockBattery) }
                    Divider()
                    SettingsDestinationRow(title: "日程") { navigate(.lockSchedule) }
                    Divider()
                    SettingsDestinationRow(title: "专注模式") { navigate(.lockFocus) }
                }
                LockScreenPositioningControls()
            }
        }
    }
    private var general: some View {
        UnifiedSettingsSection("通用") {
            Defaults.Toggle(key: .enableLockScreenLiveActivity) { Text("启用锁屏组件") }
            Defaults.Toggle(key: .enableLockSounds) { Text("启用锁定与解锁音效") }
            Defaults.Toggle(key: .lockScreenWeatherUsesGaugeTint) { Text("使用主题色") }
            SettingsRow(title: "组件样式") {
                Picker("组件样式", selection: $weatherStyle) {
                    ForEach(LockScreenWeatherWidgetStyle.allCases) { style in Text(style.localizedName).tag(style) }
                }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(maxWidth: 200, alignment: .trailing)
            }
        }
    }
    private var mediaPanel: some View {
        UnifiedSettingsSection("媒体") {
            Defaults.Toggle(key: .enableLockScreenMediaWidget) { Text("启用媒体面板") }
            Defaults.Toggle(key: .lockScreenShowAppIcon) { Text("显示应用图标") }
            Defaults.Toggle(key: .lockScreenPanelShowsBorder) { Text("显示面板边框") }
        }
    }
    private var weather: some View {
        UnifiedSettingsSection("天气") {
            Defaults.Toggle(key: .enableLockScreenWeatherWidget) { Text("启用天气面板") }
            SettingsRow(title: "温度单位") {
                Picker("温度单位", selection: $unit) {
                    ForEach(LockScreenWeatherTemperatureUnit.allCases) { unit in Text(unit.symbol).tag(unit) }
                }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(maxWidth: 200, alignment: .trailing)
            }
            SettingsRow(title: "服务提供方") {
                Picker("服务提供方", selection: $provider) {
                    ForEach(LockScreenWeatherProviderSource.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(maxWidth: 200, alignment: .trailing)
            }
            Defaults.Toggle(key: .lockScreenWeatherShowsLocation) {
                SettingsDescription(title: "显示位置", subtitle: "显示天气对应的城市名称；仅内嵌样式且已取得城市名称时可见。")
            }
            Defaults.Toggle(key: .lockScreenWeatherShowsSunrise) { Text("显示日出和日落") }
            Defaults.Toggle(key: .lockScreenWeatherShowsAQI) { Text("显示空气质量") }
        }
    }
    private var battery: some View {
        UnifiedSettingsSection("电池") {
            Defaults.Toggle(key: .lockScreenBatteryShowsBatteryGauge) { Text("启用电池面板") }
            Defaults.Toggle(key: .lockScreenBatteryShowsCharging) { Text("显示充电状态") }
            Defaults.Toggle(key: .lockScreenBatteryShowsChargingPercentage) { Text("显示充电百分比") }
            Defaults.Toggle(key: .lockScreenBatteryShowsBluetooth) { Text("显示蓝牙设备电量") }
        }
    }
    private var schedule: some View {
        UnifiedSettingsSection("日程") {
            Defaults.Toggle(key: .lockScreenShowCalendarEvent) { Text("启用日程面板") }
            Defaults.Toggle(key: .lockScreenShowCalendarCountdown) { Text("显示事件倒计时") }
            Defaults.Toggle(key: .lockScreenShowCalendarTimeRemaining) { Text("显示事件结束倒计时") }
            Defaults.Toggle(key: .lockScreenShowCalendarEventEntireDuration) { Text("事件期间持续显示") }

        }
    }
    private var focusSettings: some View {
        UnifiedSettingsSection("专注模式") {
            Defaults.Toggle(key: .enableLockScreenFocusWidget) { Text("显示专注模式") }
        }
    }
}

private struct LockScreenPositioningControls: View {
    @State private var previewWidth: CGFloat = 500

    var body: some View {
        UnifiedSettingsSection("位置与预览") {
            VStack(spacing: 8) {
                LockScreenLayoutEditor()
                    .frame(maxWidth: .infinity)
                    .frame(height: max(120, previewWidth / LockScreenPreviewScreen.aspectRatio))
                    .background {
                        GeometryReader { geometry in
                            Color.clear.onAppear { previewWidth = geometry.size.width }
                                .onChange(of: geometry.size.width) { _, width in previewWidth = width }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        Button("复位", action: LockScreenLayoutActions.reset)
                            .buttonStyle(.bordered).controlSize(.small)
                            .padding(3)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                            )
                            .padding(10)
                    }
                instructions
            }
        }
    }

    private var instructions: some View {
        Text("上下拖动组件调整位置，所有组件始终水平居中。")
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }

}
