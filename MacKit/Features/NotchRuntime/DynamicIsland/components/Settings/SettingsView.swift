// MacKit feature reduction, modified 2026-11-08.
// See THIRD_PARTY_NOTICES.md; GPL-3.0-or-later.
// MacKit host adaptation, modified 2026-11-08.
// See THIRD_PARTY_NOTICES.md for the host integration changes; GPL-3.0-or-later.
//
//  SettingsView.swift
//  DynamicIsland
//
//  Created by Richard Kunkli on 07/08/2024.
//
import AppKit
import AVFoundation
import Combine
import Defaults
import EventKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettings: View {
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
                Toggle("启用灵动刘海", isOn: Binding(get: { featureEnabled }, set: { value in
                    Defaults[.notchEnabled] = value
                    AtollIntegration.shared.delegate?.applyNotchEnabled(value)
                }))
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("在所有显示器上显示")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                SettingsRow(title: "在指定显示器上显示") { Picker("在指定显示器上显示", selection: $coordinator.preferredScreen) {
                    ForEach(screens, id: \.self) { screen in
                        Text(screen)
                    }
                }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(maxWidth: 200, alignment: .trailing) }
                .onChange(of: NSScreen.screens) {
                    screens =  NSScreen.screens.compactMap({$0.localizedName})
                }
                .disabled(showOnAllDisplays)
                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("自动切换显示器")
                }
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
                Defaults.Toggle(key: .hideDynamicIslandFromScreenCapture) {
                    Text("截图或录屏时隐藏刘海")
                }
            } header: {
                Text("通用")
            }

            UnifiedSettingsSection("外观") {
                let minimum = builtinClosedMinimumWidth()
                CompactSettingsSlider(value: Binding(get: { max(minimum, builtinWidth) }, set: { builtinWidth = $0 }), in: minimum...max(400, minimum + 200), step: 4, valueText: "\(Int(max(minimum, builtinWidth))) pt") {
                    Text("内建显示器闭合宽度")
                }.onChange(of: builtinWidth) { _, _ in NotificationCenter.default.post(name: .notchHeightChanged, object: nil) }

                CompactSettingsSlider(value: $externalWidth, in: 120...360, step: 4, valueText: "\(Int(externalWidth)) pt") { Text("外接显示器闭合宽度") }
                    .onChange(of: externalWidth) { _, _ in NotificationCenter.default.post(name: .notchHeightChanged, object: nil) }

                CompactSettingsSlider(value: $width, in: Double(currentRecommendedMinimumNotchWidth())...900, step: 10, valueText: "\(Int(width)) pt") {
                    Text("展开宽度")
                } onEditingChanged: { editing in
                    if editing { AtollAppDelegate.shared?.viewModels.values.forEach { $0.open() }; AtollAppDelegate.shared?.vm.open() }
                }
                .onChange(of: width) { _, _ in
                    AtollAppDelegate.shared?.viewModels.values.forEach { $0.open() }
                    AtollAppDelegate.shared?.vm.open()
                }
            SettingsRow(title: "外接显示器样式") { Picker("外接显示器样式", selection: $externalDisplayStyle) {
                ForEach(ExternalDisplayStyle.allCases) { style in
                    Text(style.localizedName)
                        .tag(style)
                }
            }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(maxWidth: 200, alignment: .trailing) }
            .onChange(of: externalDisplayStyle) {
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            }
            NotchBehaviour()

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
            Toggle("记住上次标签页", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                CompactSettingsSlider(value: $minimumHoverDuration, in: 0...1, step: 0.1,
                                      valueText: String(format: "%.1f 秒", minimumHoverDuration)) { Text("悬停延迟") }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
            Defaults.Toggle(key: .hideNonNotchUntilHover) {
                SettingsDescription(title: "在非刘海显示器上悬停时显示", subtitle: "启用后，外接显示器上的刘海会隐藏，指针悬停时显示。")
            }
        } header: {
            Text("刘海行为")
        }
    }
}

struct Charge: View {
    var body: some View {
        Group {
            UnifiedSettingsSection("电池提示") {
                Defaults.Toggle(key: .showPowerStatusNotifications) { Text("显示电源状态提示") }
                    .onReceive(Defaults.publisher(.showPowerStatusNotifications, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("正在充电", symbol: "battery.100percent.bolt", circular: false) } }
                Defaults.Toggle(key: .showChargingBatteryHUD) { Text("充电提示") }
                    .onReceive(Defaults.publisher(.showChargingBatteryHUD, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("正在充电", symbol: "battery.100percent.bolt", circular: false) } }
                Defaults.Toggle(key: .showLowBatteryHUD) { Text("低电量提示") }
                    .onReceive(Defaults.publisher(.showLowBatteryHUD, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("电量不足 20%", symbol: "battery.25percent", circular: false) } }
                Defaults.Toggle(key: .showFullBatteryHUD) { Text("充满电提示") }
                    .onReceive(Defaults.publisher(.showFullBatteryHUD, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("已充满", symbol: "battery.100percent", circular: false) } }
            }
        }
    }
}

private struct HUDAndOSDSettingsView: View {
    @Default(.enableSystemHUD) private var notchEnabled
    @Default(.enableVerticalHUD) private var verticalEnabled
    @AppStorage("notch.controls.preferredStyle") private var preferredStyle = "notch"
    @Default(.inlineHUD) private var inlineLayout
    @Default(.progressBarStyle) private var progressStyle
    private var enabled: Bool { notchEnabled || verticalEnabled }
    private var style: String { verticalEnabled ? "vertical" : (notchEnabled ? "notch" : (preferredStyle == "vertical" ? "vertical" : "notch")) }
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.pageSpacing) {
            SettingsRows(title: "系统控制") {
                SettingsRow(title: "启用系统控制") {
                    Toggle("启用系统控制", isOn: Binding(get: { enabled }, set: setEnabled)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider(); option("音量提示", key: .enableVolumeHUD)
                Divider(); option("亮度提示", key: .enableBrightnessHUD)
                Divider(); option("键盘背光提示", key: .enableKeyboardBacklightHUD)
            }
            SettingsRows(title: "提示样式") {
                SettingsRow(title: "样式") {
                    Picker("样式", selection: Binding(get: { style }, set: setStyle)) {
                        Text("刘海").tag("notch"); Text("垂直条").tag("vertical")
                    }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().pickerStyle(.menu)
                }
                if style == "vertical" {
                    Divider(); option("显示数值", key: .verticalHUDShowValue)
                    Divider(); option("鼠标交互", key: .verticalHUDInteractive)
                    Divider(); option("使用强调色", key: .verticalHUDUseAccentColor)
                } else {
                    Divider()
                    SettingsRow(title: "提示布局") {
                        Picker("提示布局", selection: $inlineLayout) { Text("内嵌").tag(true); Text("展开").tag(false) }.frame(minWidth: AppStyle.pickerMinimumWidth)
                            .labelsHidden().pickerStyle(.menu)
                            .onChange(of: inlineLayout) { _, _ in DynamicIslandViewCoordinator.shared.previewSetting("音量", symbol: "speaker.wave.2.fill", type: .volume) }
                    }
                    Divider(); option("音量颜色提示", key: .useColorCodedVolumeDisplay)
                    Divider()
                    SettingsRow(title: "进度条样式") {
                        Picker("进度条样式", selection: $progressStyle) {
                            Text("分层").tag(ProgressBarStyle.hierarchical)
                            Text("渐变").tag(ProgressBarStyle.gradient)
                            Text("分段").tag(ProgressBarStyle.segmented)
                        }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().pickerStyle(.menu)
                    }
                    Divider(); option("显示百分比", key: .showProgressPercentages)
                    Divider(); option("指示器使用强调色", key: .systemEventIndicatorUseAccent)
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
                    let type: SneakContentType = key.name == Defaults.Keys.enableBrightnessHUD.name ? .brightness : (key.name == Defaults.Keys.enableKeyboardBacklightHUD.name ? .backlight : .volume)
                    let symbol = type == .brightness ? "sun.max.fill" : (type == .backlight ? "light.max" : "speaker.wave.2.fill")
                    DynamicIslandViewCoordinator.shared.previewSetting(title, symbol: symbol, type: type)
                }
        }
    }
    private func setEnabled(_ value: Bool) {
        if value { setStyle(style, activate: true) }
        else { preferredStyle = style; notchEnabled = false; verticalEnabled = false }
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
                            }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(maxWidth: 200, alignment: .trailing)
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

private struct DevicesSettingsView: View {
    @Default(.useCircularBluetoothBatteryIndicator) private var circular
    var body: some View {
        Group {
            UnifiedSettingsSection("蓝牙音频设备") {
                Defaults.Toggle(key: .showBluetoothDeviceConnections) { Text("显示蓝牙设备连接提示") }
                    .onReceive(Defaults.publisher(.showBluetoothDeviceConnections, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("蓝牙耳机", symbol: "headphones", circular: Defaults[.useCircularBluetoothBatteryIndicator]) } }
                SettingsRow(title: "电量指示器") { Picker("电量指示器", selection: $circular) {
                    Text("内嵌").tag(false)
                    Text("环形").tag(true)
                }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(maxWidth: 200, alignment: .trailing) }.onChange(of: circular) { _, value in
                    DynamicIslandViewCoordinator.shared.previewSetting("蓝牙耳机 75%", symbol: "headphones", circular: value)
                }
            }
        }
    }
}

struct Media: View {
    private static let hideDelays: [Double] = [0, 1, 3, 5, 10, 15, 30, 60, -1]
    @Default(.pausedMediaHideDelay) private var pausedMediaHideDelay
    var body: some View {
        Group {
            UnifiedSettingsSection("媒体控制") {
                Defaults.Toggle(key: .showStandardMediaControls) { Text("启用媒体控制") }
                Defaults.Toggle(key: .autoHideInactiveNotchMediaPlayer) { Text("自动隐藏未播放媒体的面板") }
                CompactSettingsSlider(value: Binding(get: { Self.hideDelays.firstIndex(of: pausedMediaHideDelay).map(Double.init) ?? 2 }, set: { pausedMediaHideDelay = Self.hideDelays[Int($0.rounded())] }), in: 0...8, step: 1, valueText: pausedMediaHideDelay < 0 ? "一直保留" : "\(Int(pausedMediaHideDelay)) 秒", uniform: false) {
                    Text("暂停时收回")
                }
                Defaults.Toggle(key: .hideLyricsWhenPaused) { Text("暂停时收回歌词") }
                    .disabled(pausedMediaHideDelay >= 0)
                Defaults.Toggle(key: .showLyricsBelowBuiltinNotch) { Text("在常驻灵动岛显示歌词") }
            }
        }
    }
}

struct CalendarSettings: View {
    @Default(.showCalendar) private var enabled
    @Default(.reminderLeadTime) private var lead
    @Default(.reminderSneakPeekDuration) private var reminderDuration
    @Default(.reminderPresentationStyle) private var reminderStyle
    @ObservedObject private var calendar = CalendarManager.shared
    var body: some View {
        Group {
            UnifiedSettingsSection("日历") { Toggle("启用日历", isOn: $enabled) }
            if enabled {
                UnifiedSettingsSection("日历列表") {
                    ForEach(calendar.allCalendars, id: \.id) { item in
                        Toggle(isOn: Binding(get: { calendar.selectedCalendarIDs.contains(item.id) }, set: { selected in
                            guard selected != calendar.selectedCalendarIDs.contains(item.id) else { return }
                            Task { await calendar.setCalendarSelected(item, isSelected: selected) }
                        })) {
                            HStack(spacing: 8) {
                                Circle().fill(Color(nsColor: item.color)).frame(width: 9, height: 9).accessibilityHidden(true)
                                SettingsDescription(title: item.title, subtitle: item.sourceName ?? item.accountName)
                            }
                        }
                    }
                }
                UnifiedSettingsSection("提醒实时活动") {
                    CompactSettingsSlider(value: $reminderDuration, in: 3...20, step: 1, valueText: "\(Int(reminderDuration)) 秒") { Text("提醒展示时长") }
                    Defaults.Toggle(key: .enableReminderLiveActivity) { Text("启用提醒实时活动") }
                    SettingsRow(title: "倒计时样式") { Picker("倒计时样式", selection: $reminderStyle) {
                        ForEach(ReminderPresentationStyle.allCases) { style in Text(style.displayName).tag(style) }
                    }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(maxWidth: 200, alignment: .trailing) }
                    CompactSettingsSlider(value: Binding(get: { Double(lead) }, set: { lead = Int($0) }), in: 1...60, step: 1, valueText: "\(lead) 分钟") { Text("提前提醒") }
                }

            }
        }
         .onChange(of: enabled) { _, value in calendar.setEnabled(value) }
    }
}

struct Shelf: View {
    @Default(.quickShareProvider) var quickShareProvider

    @Default(.copyOnDrag) var copyOnDrag
    @Default(.autoRemoveShelfItems) var autoRemoveShelfItems
    @StateObject private var quickShareService = QuickShareService.shared
    @ObservedObject private var fullDiskAccessPermission = FullDiskAccessPermissionStore.shared
    @ObservedObject private var shelfFolderAccessPermission = ShelfFolderAccessPermissionStore.shared

    private var hasDocumentsAndDownloadsAccess: Bool {
        shelfFolderAccessPermission.hasDocumentsAndDownloadsAccess
    }

    private var canEnableShelf: Bool {
        fullDiskAccessPermission.isAuthorized || hasDocumentsAndDownloadsAccess
    }

    init() {
        QuickShareService.shared.ensureDiscovered()
    }

    var body: some View {
        Group {
            if !canEnableShelf || !fullDiskAccessPermission.isAuthorized {
                UnifiedSettingsSection {
                    if !canEnableShelf {
                        SettingsPermissionCallout(
                            title: "需要访问文件夹的权限",
                            message: "请启用完全磁盘访问权限，或允许访问文稿和下载文件夹，以使用文件托盘。",
                            icon: "folder.badge.questionmark",
                            iconColor: .orange,
                            requestButtonTitle: "请求文件夹访问权限",
                            openSettingsButtonTitle: "打开隐私与安全性",
                            requestAction: { shelfFolderAccessPermission.requestAccessPrompt() },
                            openSettingsAction: { shelfFolderAccessPermission.openSystemSettings() }
                        )
                    }

                    if !fullDiskAccessPermission.isAuthorized {
                        SettingsPermissionCallout(
                            title: "全局模式需要完全磁盘访问权限",
                            message: "未授予完全磁盘访问权限时，文件托盘只能访问文稿与下载文件夹；授权后可处理其他位置的文件。",
                            icon: "externaldrive.fill",
                            iconColor: .purple,
                            requestButtonTitle: "请求完全磁盘访问",
                            openSettingsButtonTitle: "打开隐私与安全性",
                            requestAction: { fullDiskAccessPermission.requestAccessPrompt() },
                            openSettingsAction: { fullDiskAccessPermission.openSystemSettings() }
                        )
                    }
                } header: {
                    Text("权限")
                }
            }

            UnifiedSettingsSection {
                Defaults.Toggle(key: .dynamicShelf) {
                    Text("启用文件托盘")
                }
                .disabled(!canEnableShelf)

                Defaults.Toggle(key: .copyOnDrag) {
                    Text("拖动时复制项目")
                }

                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("拖出后从文件托盘移除")
                }
            } header: {
                HStack {
                    Text("文件托盘")
                }
            }

            UnifiedSettingsSection {
                SettingsRow(title: "快速分享服务", subtitle: "选择文件托盘使用的分享服务。拖入文件，或点击托盘按钮选择文件。") { Picker("快速分享服务", selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            QuickShareProviderIconImage(provider: provider, size: 12)
                            Text(provider.settingsTitle)
                        }
                        .tag(provider.id)
                    }
                }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(maxWidth: 200, alignment: .trailing) }
                .pickerStyle(.menu)

            } header: {
                HStack {
                    Text("快速分享")
                }
            }

            if quickShareProvider == "LocalSend" {
            }
        }
        .accentColor(.effectiveAccent)

        .onAppear {
            fullDiskAccessPermission.refreshStatus()
            shelfFolderAccessPermission.refreshStatus()
        }
    }
}

// MARK: - LocalSend Settings Section

struct LiveActivitiesSettings: View {
    @ObservedObject private var privacy = PrivacyIndicatorManager.shared
    @ObservedObject private var caps = CapsLockManager.shared
    @ObservedObject private var recording = ScreenRecordingManager.shared
    var body: some View {
        Group {
            UnifiedSettingsSection("活动指示器") {
                Defaults.Toggle(key: .enableCameraDetection) { Text("启用相机指示器") }
                    .onReceive(Defaults.publisher(.enableCameraDetection, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("相机", symbol: "camera.fill", circular: false) } }
                Defaults.Toggle(key: .enableMicrophoneDetection) { Text("启用麦克风指示器") }
                    .onReceive(Defaults.publisher(.enableMicrophoneDetection, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("麦克风", symbol: "mic.fill", circular: false) } }
                Defaults.Toggle(key: .enableCapsLockIndicator) { Text("启用大写锁定指示器") }
                    .onReceive(Defaults.publisher(.enableCapsLockIndicator, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("大写锁定", symbol: "capslock.fill", circular: false) } }
                Defaults.Toggle(key: .showRecordingIndicator) { Text("启用录制指示器") }
                    .onReceive(Defaults.publisher(.showRecordingIndicator, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("屏幕录制", symbol: "record.circle.fill", circular: false) } }
                Defaults.Toggle(key: .showDoNotDisturbIndicator) { Text("启用专注模式指示器") }
                    .onReceive(Defaults.publisher(.showDoNotDisturbIndicator, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("专注模式", symbol: "moon.fill", circular: false) } }
            }
        }
    }
}

struct LockScreenSettings: View {
    var destination: AppPage = .lockScreen
    var navigate: (AppPage) -> Void = { _ in }
    @Default(.lockScreenReminderChipStyle) private var reminderChipStyle
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
                SettingsRow(title: "组件样式") {
                    Picker("组件样式", selection: $weatherStyle) {
                        ForEach(LockScreenWeatherWidgetStyle.allCases) { style in Text(style.localizedName).tag(style) }
                    }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(maxWidth: 200, alignment: .trailing)
                }
                Defaults.Toggle(key: .enableLockSounds) { Text("锁定与解锁音效") }
            }
    }
    private var mediaPanel: some View {
        UnifiedSettingsSection("媒体") {
                Defaults.Toggle(key: .enableLockScreenMediaWidget) { Text("显示媒体面板") }
                Defaults.Toggle(key: .lockScreenShowAppIcon) { Text("显示应用图标") }
                Defaults.Toggle(key: .lockScreenPanelShowsBorder) { Text("显示面板边框") }
            }
    }
    private var weather: some View {
        UnifiedSettingsSection("天气") {
                Defaults.Toggle(key: .enableLockScreenWeatherWidget) { Text("显示天气") }
                SettingsRow(title: "温度单位") { Picker("温度单位", selection: $unit) { ForEach(LockScreenWeatherTemperatureUnit.allCases) { unit in Text(unit.symbol).tag(unit) } }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(maxWidth: 200, alignment: .trailing) }
                SettingsRow(title: "服务提供方") { Picker("服务提供方", selection: $provider) { ForEach(LockScreenWeatherProviderSource.allCases) { provider in Text(provider.displayName).tag(provider) } }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(maxWidth: 200, alignment: .trailing) }
                Defaults.Toggle(key: .lockScreenWeatherShowsLocation) { Text("显示位置") }
                Defaults.Toggle(key: .lockScreenWeatherShowsSunrise) { Text("显示日出和日落") }
                Defaults.Toggle(key: .lockScreenWeatherShowsAQI) { Text("显示空气质量") }
                Defaults.Toggle(key: .lockScreenWeatherUsesGaugeTint) { Text("天气仪表使用主题色") }
            }
    }
    private var battery: some View {
        UnifiedSettingsSection("电池") {
                Defaults.Toggle(key: .lockScreenBatteryShowsBatteryGauge) { Text("显示电池状态") }
                Defaults.Toggle(key: .lockScreenBatteryShowsCharging) { Text("显示充电状态") }
                Defaults.Toggle(key: .lockScreenBatteryShowsChargingPercentage) { Text("显示充电百分比") }
                Defaults.Toggle(key: .lockScreenBatteryShowsBluetooth) { Text("显示蓝牙设备电量") }
            }
    }
    private var schedule: some View {
        UnifiedSettingsSection("日程") {
                Defaults.Toggle(key: .enableLockScreenReminderWidget) { Text("显示日程到时提醒") }
                Defaults.Toggle(key: .lockScreenShowCalendarEvent) { Text("显示日历事件") }
                Defaults.Toggle(key: .lockScreenShowCalendarCountdown) { Text("显示事件倒计时") }
                Defaults.Toggle(key: .lockScreenShowCalendarTimeRemaining) { Text("显示剩余时间") }
                Defaults.Toggle(key: .lockScreenShowCalendarStartTimeAfterBegins) { Text("开始后显示起始时间") }
                Defaults.Toggle(key: .lockScreenShowCalendarEventEntireDuration) { Text("事件持续期间一直显示") }
                SettingsRow(title: "提醒配色") { Picker("提醒配色", selection: $reminderChipStyle) {
                    Text("事件颜色").tag(LockScreenReminderChipStyle.eventColor)
                    Text("白色").tag(LockScreenReminderChipStyle.monochrome)
                }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(maxWidth: 200, alignment: .trailing) }
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
            VStack(alignment: .leading, spacing: 5) {
            LockScreenLayoutEditor()
                .frame(maxWidth: .infinity)
                .frame(height: max(120, previewWidth / LockScreenPreviewScreen.aspectRatio))
                .background {
                    GeometryReader { geometry in
                        Color.clear.onAppear { previewWidth = geometry.size.width }
                            .onChange(of: geometry.size.width) { _, width in previewWidth = width }
                    }
                }
            Text("上下拖动组件调整位置，所有组件始终水平居中。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
        }
    }
}

struct SettingsPermissionCallout: View {
    let title: String
    let message: String
    let icon: String
    let iconColor: Color
    let requestButtonTitle: String
    let openSettingsButtonTitle: String
    let requestAction: () -> Void
    let openSettingsAction: () -> Void

    init(
        title: String = "需要辅助功能权限",
        message: String,
        icon: String = "exclamationmark.triangle.fill",
        iconColor: Color = .orange,
        requestButtonTitle: String = "请求授权",
        openSettingsButtonTitle: String = "打开设置",
        requestAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconColor = iconColor
        self.requestButtonTitle = requestButtonTitle
        self.openSettingsButtonTitle = openSettingsButtonTitle
        self.requestAction = requestAction
        self.openSettingsAction = openSettingsAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(requestButtonTitle) {
                    requestAction()
                }
                .buttonStyle(.borderedProminent)

                Button(openSettingsButtonTitle) {
                    openSettingsAction()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Terminal Settings

struct TerminalSettings: View {
    @Default(.terminalShellPath) private var shell
    @Default(.terminalFontFamily) private var font
    @Default(.terminalFontSize) private var size
    @Default(.terminalMaxHeightFraction) private var height
    var body: some View {
        Group {
            UnifiedSettingsSection("终端") {
                Defaults.Toggle(key: .enableTerminalFeature) { Text("启用终端") }
                SettingsRow(title: "命令解释器") {
                    TextField("", text: $shell, prompt: Text("/bin/zsh"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                }
                Defaults.Toggle(key: .terminalStickyMode) { Text("鼠标移开时保持终端打开") }
                SettingsRow(title: "重启终端") { Button("重启") { TerminalManager.shared.restartShell() } }
            }
            UnifiedSettingsSection("终端字体") {
                SettingsRow(title: "字体") { Picker("字体", selection: $font) {
                    ForEach(Array(Set(NSFontManager.shared.availableFontFamilies.filter { family in
                        guard let candidate = NSFont(name: family, size: 13) else { return false }
                        return candidate.isFixedPitch || NSFontManager.shared.traits(of: candidate).contains(.fixedPitchFontMask)
                    } + [font])).sorted(), id: \.self) { family in
                        Text(family).font(.custom(family, size: 13)).tag(family)
                    }
                }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(maxWidth: 200, alignment: .trailing) }
                CompactSettingsSlider(value: $size, in: 9...24, step: 1, valueText: "\(Int(size)) pt") { Text("字号") }
                CompactSettingsSlider(value: $height, in: 0.2...0.8, step: 0.05, valueText: "\(Int(height * 100))%") { Text("最大屏幕高度占比") }
            }
        }
         .onChange(of: size) { _, value in TerminalManager.shared.applyFontSize(value) }
         .onChange(of: font) { _, value in TerminalManager.shared.applyFontFamily(value) }
    }
}

// MARK: - Reusable App Icon View

/// Fetches the real app icon from the system using bundle identifiers,
/// falling back to an asset catalog image or an SF Symbol.

struct AppIconImage: View {
    let bundleIdentifiers: [String]
    var assetFallback: String? = nil
    var symbolFallback: String = "app.fill"
    var symbolColor: Color = .accentColor
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let nsImage = resolvedIcon() {
                Image(nsImage: compactMenuIcon(nsImage, size: size))
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else if let assetFallback, let nsImage = NSImage(named: NSImage.Name(assetFallback)) {
                Image(nsImage: compactMenuIcon(nsImage, size: size))
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                Image(systemName: symbolFallback)
                    .foregroundColor(symbolColor)
            }
        }
        .frame(width: size, height: size)
    }

    private func resolvedIcon() -> NSImage? {
        for bundleID in bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                // NSWorkspace returns a valid icon even for generic apps;
                // resize to keep memory low.
                let thumb = NSImage(size: NSSize(width: 32, height: 32))
                thumb.lockFocus()
                icon.draw(in: NSRect(origin: .zero, size: NSSize(width: 32, height: 32)),
                          from: NSRect(origin: .zero, size: icon.size),
                          operation: .copy, fraction: 1.0)
                thumb.unlockFocus()
                return thumb
            }
        }
        return nil
    }
}

private struct QuickShareProviderIconImage: View {
    let provider: QuickShareProvider
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                Image(nsImage: compactMenuIcon(nsImg, size: size))
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                AppIconImage(
                    bundleIdentifiers: provider.bundleIdentifiersFallback,
                    assetFallback: provider.assetFallbackName,
                    symbolFallback: provider.symbolFallbackName,
                    symbolColor: .accentColor,
                    size: size
                )
            }
        }
        .frame(width: size, height: size)
    }
}

private extension QuickShareProvider {
    var bundleIdentifiersFallback: [String] {
        switch id {
        case "LocalSend":
            return ["org.localsend.localsend_app", "org.localsend.localsend"]
        case "AirDrop":
            return ["com.apple.finder"]
        case "Mail":
            return ["com.apple.mail"]
        case "Messages":
            return ["com.apple.MobileSMS", "com.apple.iChat"]
        case "Notes":
            return ["com.apple.Notes"]
        case "Reminders":
            return ["com.apple.reminders"]
        case "Add to Safari Reading List":
            return ["com.apple.Safari"]
        default:
            return []
        }
    }

    var assetFallbackName: String? {
        id == "LocalSend" ? "LocalSend" : nil
    }

    var symbolFallbackName: String {
        id == "System Share Menu" ? "square.and.arrow.up.on.square" : "square.and.arrow.up"
    }
}

private extension QuickShareProvider {
    var settingsTitle: String {
        switch id {
        case "System Share Menu": "系统分享菜单"
        case "Mail": "邮件"
        case "Messages": "信息"
        case "Notes": "备忘录"
        case "Reminders": "提醒事项"
        case "Add to Safari Reading List": "添加到 Safari 阅读列表"
        default: id
        }
    }
}

// Native menu items use the NSImage's intrinsic size, not only SwiftUI's frame.
func compactMenuIcon(_ image: NSImage, size: CGFloat) -> NSImage {
    let result = NSImage(size: NSSize(width: size, height: size))
    result.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
    result.unlockFocus()
    return result
}

/// Root settings pages contain general controls and complete-row child destinations.
struct ConsolidatedNotchSettings: View {
    let lockScreen: Bool
    var navigate: (AppPage) -> Void = { _ in }
    var body: some View {
        PageLayout {
            if lockScreen {
                LockScreenSettings(navigate: navigate)
            } else {
                GeneralSettings()
                SettingsRows(title: "功能") {
                    SettingsDestinationRow(title: "媒体控制") { navigate(.notchMedia) }
                    Divider()
                    SettingsDestinationRow(title: "实时活动") { navigate(.notchActivities) }
                    Divider()
                    SettingsDestinationRow(title: "系统控制") { navigate(.notchSystem) }
                    Divider()
                    SettingsDestinationRow(title: "日程提醒") { navigate(.notchSchedule) }
                    Divider()
                    SettingsDestinationRow(title: "文件托盘") { navigate(.notchShelf) }
                    Divider()
                    SettingsDestinationRow(title: "终端") { navigate(.notchTerminal) }
                }
            }
        }
        .toggleStyle(SettingsTrailingToggleStyle())
        .controlSize(.small)
        .buttonStyle(.bordered)
        .id(lockScreen)
    }
}

struct NotchSecondarySettings: View {
    let destination: AppPage
    var body: some View {
        PageLayout {
            switch destination {
            case .notchMedia: Media()
            case .notchActivities: LiveActivitiesSettings(); DevicesSettingsView(); Charge()
            case .notchSystem: HUDAndOSDSettingsView()
            case .notchSchedule: CalendarSettings()
            case .notchShelf: Shelf()
            case .notchTerminal: TerminalSettings()
            default: LockScreenSettings(destination: destination)
            }
        }
        .toggleStyle(SettingsTrailingToggleStyle())
        .controlSize(.small)
        .buttonStyle(.bordered)
        .id(destination)
    }
}
