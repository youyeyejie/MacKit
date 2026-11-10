// Derived from Atoll; GPL-3.0-or-later.
// Original settings by Richard Kunkli, 2024; MacKit host adaptation, 2026.
// See THIRD_PARTY_NOTICES.md.
import AppKit
import Defaults
import SwiftUI

struct NotchBatterySettingsView: View {
    var body: some View {
        Group {
            UnifiedSettingsSection("电池") {
                Defaults.Toggle(key: .showPowerStatusNotifications) { Text("启用电源状态提示") }
                    .onReceive(Defaults.publisher(.showPowerStatusNotifications, options: [])) { change in
                        if change.newValue {
                            DynamicIslandViewCoordinator.shared.previewSetting(
                                "正在充电", symbol: "battery.100percent.bolt", circular: false)
                        }
                    }
                Defaults.Toggle(key: .showChargingBatteryHUD) { Text("启用充电提示") }
                    .onReceive(Defaults.publisher(.showChargingBatteryHUD, options: [])) { change in
                        if change.newValue {
                            DynamicIslandViewCoordinator.shared.previewSetting(
                                "正在充电", symbol: "battery.100percent.bolt", circular: false)
                        }
                    }
                Defaults.Toggle(key: .showLowBatteryHUD) { Text("启用低电量提示") }
                    .onReceive(Defaults.publisher(.showLowBatteryHUD, options: [])) { change in
                        if change.newValue {
                            DynamicIslandViewCoordinator.shared.previewSetting(
                                "电量不足 20%", symbol: "battery.25percent", circular: false)
                        }
                    }
                Defaults.Toggle(key: .showFullBatteryHUD) { Text("启用充满电提示") }
                    .onReceive(Defaults.publisher(.showFullBatteryHUD, options: [])) { change in
                        if change.newValue {
                            DynamicIslandViewCoordinator.shared.previewSetting(
                                "已充满", symbol: "battery.100percent", circular: false)
                        }
                    }
            }
        }
    }
}

struct DevicesSettingsView: View {
    @Default(.useCircularBluetoothBatteryIndicator) private var circular
    var body: some View {
        Group {
            UnifiedSettingsSection("蓝牙设备") {
                Defaults.Toggle(key: .showBluetoothDeviceConnections) { Text("启用蓝牙设备连接提示") }
                    .onReceive(Defaults.publisher(.showBluetoothDeviceConnections, options: [])) { change in
                        if change.newValue {
                            DynamicIslandViewCoordinator.shared.previewSetting(
                                "蓝牙耳机", symbol: "headphones", circular: Defaults[.useCircularBluetoothBatteryIndicator])
                        }
                    }
                SettingsRow(title: "电量指示器") {
                    Picker("电量指示器", selection: $circular) {
                        Text("内嵌").tag(false)
                        Text("环形").tag(true)
                    }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(
                        maxWidth: 200, alignment: .trailing)
                }.onChange(of: circular) { _, value in
                    DynamicIslandViewCoordinator.shared.previewSetting(
                        "蓝牙耳机 75%", symbol: "headphones", circular: value)
                }
            }
        }
    }
}

struct LiveActivitiesSettings: View {
    @ObservedObject private var privacy = PrivacyIndicatorManager.shared
    @ObservedObject private var caps = CapsLockManager.shared
    @ObservedObject private var recording = ScreenRecordingManager.shared
    var body: some View {
        Group {
            UnifiedSettingsSection("活动指示器") {
                Defaults.Toggle(key: .enableCameraDetection) { Text("启用相机指示器") }
                    .onReceive(Defaults.publisher(.enableCameraDetection, options: [])) { change in
                        if change.newValue {
                            DynamicIslandViewCoordinator.shared.previewSetting(
                                "相机", symbol: "camera.fill", circular: false)
                        }
                    }
                Defaults.Toggle(key: .enableMicrophoneDetection) { Text("启用麦克风指示器") }
                    .onReceive(Defaults.publisher(.enableMicrophoneDetection, options: [])) { change in
                        if change.newValue {
                            DynamicIslandViewCoordinator.shared.previewSetting(
                                "麦克风", symbol: "mic.fill", circular: false)
                        }
                    }
                Defaults.Toggle(key: .enableCapsLockIndicator) { Text("启用大写锁定指示器") }
                    .onReceive(Defaults.publisher(.enableCapsLockIndicator, options: [])) { change in
                        if change.newValue {
                            DynamicIslandViewCoordinator.shared.previewSetting(
                                "大写锁定", symbol: "capslock.fill", circular: false)
                        }
                    }
                Defaults.Toggle(key: .showRecordingIndicator) { Text("启用录制指示器") }
                    .onReceive(Defaults.publisher(.showRecordingIndicator, options: [])) { change in
                        if change.newValue {
                            DynamicIslandViewCoordinator.shared.previewSetting(
                                "屏幕录制", symbol: "record.circle.fill", circular: false)
                        }
                    }
                Defaults.Toggle(key: .showDoNotDisturbIndicator) { Text("启用专注模式指示器") }
                    .onReceive(Defaults.publisher(.showDoNotDisturbIndicator, options: [])) { change in
                        if change.newValue {
                            DynamicIslandViewCoordinator.shared.previewSetting(
                                "专注模式", symbol: "moon.fill", circular: false)
                        }
                    }
                Defaults.Toggle(key: .enableCleaningIndicator) { Text("启用清洁模式指示器") }
            }
        }
    }
}
