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

/// Groups for organizing settings tabs in the sidebar.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, media, liveActivities, lockScreen, devices, hudAndOSD, battery, calendar, shelf, terminal, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return String(localized: "通用")
        case .media: return String(localized: "媒体")
        case .liveActivities: return String(localized: "实时活动")
        case .lockScreen: return String(localized: "锁屏")
        case .devices: return String(localized: "设备")
        case .hudAndOSD: return String(localized: "控制")
        case .battery: return String(localized: "电池")
        case .calendar: return String(localized: "日历")
        case .shelf: return "文件托盘"
        case .terminal: return String(localized: "终端")
        case .about: return String(localized: "关于")
        }
    }
    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .media: return "play.laptopcomputer"
        case .liveActivities: return "waveform.path.ecg"
        case .lockScreen: return "lock.laptopcomputer"
        case .devices: return "headphones"
        case .hudAndOSD: return "dial.medium.fill"
        case .battery: return "battery.100.bolt"
        case .calendar: return "calendar"
        case .shelf: return "books.vertical"
        case .terminal: return "apple.terminal"
        case .about: return "info.circle"
        }
    }
    var tint: Color { .accentColor }
    func highlightID(for title: String) -> String { "\(rawValue).\(title)" }
}

final class SettingsHighlightCoordinator: ObservableObject {
    struct ScrollRequest: Identifiable, Equatable {
        let id: String
        fileprivate let tab: SettingsTab
    }

    @Published fileprivate var pendingScrollRequest: ScrollRequest?
    @Published private(set) var activeHighlightID: String?

    private var clearWorkItem: DispatchWorkItem?



    func consumeScrollRequest(_ request: ScrollRequest) {
        guard pendingScrollRequest?.id == request.id else { return }
        pendingScrollRequest = nil
    }

    private func activateHighlight(id: String) {
        activeHighlightID = id
        clearWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard self?.activeHighlightID == id else { return }
            self?.activeHighlightID = nil
        }

        clearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }
}

private struct SettingsHighlightModifier: ViewModifier {
    let id: String
    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator
    @State private var animatePulse = false

    private var isActive: Bool {
        highlightCoordinator.activeHighlightID == id
    }

    func body(content: Content) -> some View {
        content
            .id(id)
            .background(highlightBackground)
            .onChange(of: isActive) { _, active in
                animatePulse = active
            }
            .onAppear {
                if isActive {
                    animatePulse = true
                }
            }
    }

    private var highlightBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                Color.accentColor.opacity(isActive ? (animatePulse ? 0.95 : 0.4) : 0),
                lineWidth: 2
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(isActive ? 0.08 : 0))
            )
            .padding(-4)
            .shadow(color: Color.accentColor.opacity(isActive ? 0.25 : 0), radius: animatePulse ? 8 : 2)
            .animation(
                isActive ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: animatePulse
            )
    }
}

extension View {
    func settingsHighlight(id: String) -> some View {
        modifier(SettingsHighlightModifier(id: id))
    }

    @ViewBuilder
    func settingsHighlightIfPresent(_ id: String?) -> some View {
        if let id {
            settingsHighlight(id: id)
        } else {
            self
        }
    }
}

private struct SettingsForm<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator

    var body: some View {
        ScrollViewReader { proxy in
            content()
                .onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { request -> SettingsHighlightCoordinator.ScrollRequest? in
                    guard let request, request.tab == tab else { return nil }
                    return request
                }) { request in
                    withAnimation(.easeInOut(duration: 0.45)) {
                        proxy.scrollTo(request.id, anchor: .center)
                    }
                    highlightCoordinator.consumeScrollRequest(request)
                }
        }
    }
}

struct SettingsView: View {
    var hostedTab: SettingsTab?
    @StateObject private var highlightCoordinator = SettingsHighlightCoordinator()
    init(hostedTab: SettingsTab? = nil) {
        self.hostedTab = hostedTab
    }
    var body: some View {
        detailView(for: hostedTab ?? .general)
            .environmentObject(highlightCoordinator)
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    @ViewBuilder
    private func detailView(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            SettingsForm(tab: .general) {
                GeneralSettings()
            }
        case .liveActivities:
            SettingsForm(tab: .liveActivities) {
                LiveActivitiesSettings()
            }
        case .lockScreen:
            SettingsForm(tab: .lockScreen) {
                LockScreenSettings()
            }
        case .media:
            SettingsForm(tab: .media) {
                Media()
            }
        case .devices:
            SettingsForm(tab: .devices) {
                DevicesSettingsView()
            }
        case .calendar:
            SettingsForm(tab: .calendar) {
                CalendarSettings()
            }
        case .hudAndOSD:
            SettingsForm(tab: .hudAndOSD) {
                HUDAndOSDSettingsView()
            }
        case .battery:
            SettingsForm(tab: .battery) {
                Charge()
            }
        case .shelf:
            SettingsForm(tab: .shelf) {
                Shelf()
            }
        case .terminal:
            SettingsForm(tab: .terminal) {
                TerminalSettings()
            }
        case .about:
            SettingsForm(tab: .about) { About() }

        }
    }
}

struct GeneralSettings: View {
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

    private func highlightID(_ title: String) -> String {
        SettingsTab.general.highlightID(for: title)
    }

    var body: some View {
        Form {
            

            Section {
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("在所有显示器上显示")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                .settingsHighlight(id: highlightID("在所有显示器上显示"))
                Picker("在指定显示器上显示", selection: $coordinator.preferredScreen) {
                    ForEach(screens, id: \.self) { screen in
                        Text(screen)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens =  NSScreen.screens.compactMap({$0.localizedName})
                }
                .disabled(showOnAllDisplays)
                .settingsHighlight(id: highlightID("在指定显示器上显示"))
                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("自动切换显示器")
                }
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
                .settingsHighlight(id: highlightID("自动切换显示器"))
                Defaults.Toggle(key: .hideDynamicIslandFromScreenCapture) {
                    Text("截图或录屏时隐藏刘海")
                }
                .settingsHighlight(id: highlightID("截图或录屏时隐藏刘海"))
            } header: {
                Text("系统功能")
            }

            Section("展开尺寸") {
                let minimum = builtinClosedMinimumWidth()
                Slider(value: Binding(get: { max(minimum, builtinWidth) }, set: { builtinWidth = $0 }), in: minimum...max(400, minimum + 200), step: 4) {
                    Text("内建显示器闭合宽度：\(Int(max(minimum, builtinWidth)))")
                }.onChange(of: builtinWidth) { _, _ in NotificationCenter.default.post(name: .notchHeightChanged, object: nil) }

                Slider(value: $externalWidth, in: 120...360, step: 4) { Text("外接显示器闭合宽度：\(Int(externalWidth))") }
                    .onChange(of: externalWidth) { _, _ in NotificationCenter.default.post(name: .notchHeightChanged, object: nil) }

                Slider(value: $width, in: Double(currentRecommendedMinimumNotchWidth())...900, step: 10) {
                    Text("展开宽度：\(Int(width))")
                } onEditingChanged: { editing in
                    if editing { AtollAppDelegate.shared?.viewModels.values.forEach { $0.open() }; AtollAppDelegate.shared?.vm.open() }
                }
                .onChange(of: width) { _, _ in
                    AtollAppDelegate.shared?.viewModels.values.forEach { $0.open() }
                    AtollAppDelegate.shared?.vm.open()
                }
            }
            NotchBehaviour()


        }
        .navigationTitle("通用")

    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .enableHaptics) {
                Text("启用触觉反馈")
            }
            .settingsHighlight(id: highlightID("启用触觉反馈"))
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("悬停时展开刘海")
            }
            .settingsHighlight(id: highlightID("悬停时展开刘海"))
            Toggle("记住上次标签页", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("悬停延迟")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
            Picker("外接显示器样式", selection: $externalDisplayStyle) {
                ForEach(ExternalDisplayStyle.allCases) { style in
                    Text(style.localizedName)
                        .tag(style)
                }
            }
            .onChange(of: externalDisplayStyle) {
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            .settingsHighlight(id: highlightID("外接显示器样式"))
            Text(externalDisplayStyle.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Defaults.Toggle(key: .hideNonNotchUntilHover) {
                Text("在非刘海显示器上悬停时显示")
            }
            .settingsHighlight(id: highlightID("Hide until hovered"))
            Text("启用后，外接显示器上的刘海会隐藏，指针悬停时显示。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("刘海行为")
        }
    }
}

struct Charge: View {
    var body: some View {
        Form {
            Section("电池提示") {
                Defaults.Toggle(key: .showPowerStatusNotifications) { Text("显示电源状态提示") }
                    .onReceive(Defaults.publisher(.showPowerStatusNotifications, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("正在充电", symbol: "battery.100percent.bolt", circular: false) } }
                Defaults.Toggle(key: .showChargingBatteryHUD) { Text("充电提示") }
                    .onReceive(Defaults.publisher(.showChargingBatteryHUD, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("正在充电", symbol: "battery.100percent.bolt", circular: false) } }
                Defaults.Toggle(key: .showLowBatteryHUD) { Text("低电量提示") }
                    .onReceive(Defaults.publisher(.showLowBatteryHUD, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("电量不足 20%", symbol: "battery.25percent", circular: false) } }
                Defaults.Toggle(key: .showFullBatteryHUD) { Text("充满电提示") }
                    .onReceive(Defaults.publisher(.showFullBatteryHUD, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("已充满", symbol: "battery.100percent", circular: false) } }
            }
        }.navigationTitle("电池")
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
        PageLayout {
            PageHeader(title: "控制", subtitle: "调节音量、屏幕亮度和键盘背光。", symbol: "slider.horizontal.3", color: .blue)
            SettingsRows(title: "系统控制") {
                SettingsRow(title: "启用系统控制") {
                    Toggle("启用系统控制", isOn: Binding(get: { enabled }, set: setEnabled))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                option("音量提示", key: .enableVolumeHUD)
                Divider()
                option("亮度提示", key: .enableBrightnessHUD)
                Divider()
                option("键盘背光提示", key: .enableKeyboardBacklightHUD)
            }
            SettingsRows(title: "提示样式") {
                SettingsRow(title: "样式") {
                    Picker("样式", selection: Binding(get: { style }, set: setStyle)) {
                        Text("刘海").tag("notch")
                        Text("垂直条").tag("vertical")
                    }.labelsHidden().pickerStyle(.menu).frame(maxWidth: 160)
                }
                if style == "vertical" {
                    Divider()
                    option("显示数值", key: .verticalHUDShowValue)
                    Divider()
                    option("鼠标交互", key: .verticalHUDInteractive)
                    Divider()
                    option("使用强调色", key: .verticalHUDUseAccentColor)
                } else {
                    Divider()
                    SettingsRow(title: "提示布局") {
                        Picker("提示布局", selection: $inlineLayout) {
                            Text("内嵌").tag(true)
                            Text("展开").tag(false)
                        }.labelsHidden().frame(maxWidth: 160)
                         .onChange(of: inlineLayout) { _, _ in DynamicIslandViewCoordinator.shared.previewSetting("音量", symbol: "speaker.wave.2.fill", type: .volume) }
                    }
                    Divider()
                    option("音量颜色提示", key: .useColorCodedVolumeDisplay)
                    Divider()
                    SettingsRow(title: "进度条样式") {
                        Picker("进度条样式", selection: $progressStyle) {
                            Text("分层").tag(ProgressBarStyle.hierarchical)
                            Text("渐变").tag(ProgressBarStyle.gradient)
                            Text("分段").tag(ProgressBarStyle.segmented)
                        }.labelsHidden().pickerStyle(.menu).frame(maxWidth: 160)
                    }
                    Divider()
                    option("显示百分比", key: .showProgressPercentages)
                    Divider()
                    option("指示器使用强调色", key: .systemEventIndicatorUseAccent)
                }
            }
            SettingsCard(title: "调节步长") { ExternalDisplayIntegrationsSection(stepsOnly: true) }
            SettingsCard(title: "外接显示器") { ExternalDisplayIntegrationsSection() }
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

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

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
        VStack(alignment: .leading, spacing: 14) {
            if stepsOnly {
            Section {
                Stepper(value: $volumeStepPercent, in: 1...25) {
                    HStack {
                        Text("音量步长")
                        Spacer()
                        Text("\(volumeStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("音量步长"))
                .disabled(enableExternalVolumeControlListener)

                Stepper(value: $volumeFineStepPercent, in: 1...25) {
                    HStack {
                        Text("音量精细步长")
                        Spacer()
                        Text("\(volumeFineStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("音量精细步长"))
                .disabled(enableExternalVolumeControlListener)

                if enableExternalVolumeControlListener {
                    Text("启用外接显示器音量集成时不可用。")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.secondary)
                }

                Stepper(value: $brightnessStepPercent, in: 1...25) {
                    HStack {
                        Text("亮度步长")
                        Spacer()
                        Text("\(brightnessStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("亮度步长"))
                .disabled(enableThirdPartyDDCIntegration)

                Stepper(value: $brightnessFineStepPercent, in: 1...25) {
                    HStack {
                        Text("亮度精细步长")
                        Spacer()
                        Text("\(brightnessFineStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("亮度精细步长"))
                .disabled(enableThirdPartyDDCIntegration)

                if enableThirdPartyDDCIntegration {
                    Text("启用外接显示器亮度集成时不可用。")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("调节步长")
            } footer: {
                Text("每次按键的调节百分比。按住 Shift 和 Option 使用精细步长。")
                    .foregroundStyle(.secondary)
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }

            }
            if !stepsOnly {
            Section {
                Toggle("启用第三方显示器控制集成", isOn: $enableThirdPartyDDCIntegration)
                    .settingsHighlight(id: highlightID("Third-party DDC app integration"))

                if enableThirdPartyDDCIntegration {
                    Picker("服务提供方", selection: $thirdPartyDDCProvider) {
                        ForEach(ThirdPartyDDCProvider.allCases) { provider in
                            HStack {
                                AppIconImage(
                                    bundleIdentifiers: provider.bundleIdentifiers,
                                    symbolFallback: "display",
                                    symbolColor: .secondary, size: 14
                                )
                                Text(provider.displayName)
                            }
                            .tag(provider)
                        }
                    }
                    .settingsHighlight(id: highlightID("Third-party DDC provider"))

                    Toggle("监听外接设备音量控制", isOn: $enableExternalVolumeControlListener)
                        .settingsHighlight(id: highlightID("监听外接设备音量控制"))

                    Text(
                        enableExternalVolumeControlListener
                        ? "Atoll's built-in volume key interception is disabled while external volume listening is on. Volume HUD/OSD will follow \(thirdPartyDDCProvider.displayName) payloads."
                        : "Atoll 保持原生音量键拦截。关闭此项时将忽略外部提供商的音量数据。"
                    )
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)

                    HStack {
                        Text("状态")
                        Spacer()
                        Text(providerStatusText)
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(providerStatusColor)
                    }

                    Text(providerStatusDescription)
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.secondary)

                    Button {
                        refreshDetectionStatus()
                    } label: {
                        Label("刷新检测", systemImage: "arrow.clockwise")
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.link)
                } else {
                    Text("通过刘海提示显示 BetterDisplay 或 Lunar 的显示器调节。")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if enableThirdPartyDDCIntegration {
                    Text("监听所选服务的亮度变化；启用外接音量监听后，同时监听音量变化。")
                        .foregroundStyle(.secondary)
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
            }
        }
    }
}



private struct DevicesSettingsView: View {
    @Default(.useCircularBluetoothBatteryIndicator) private var circular
    var body: some View {
        Form {
            Section("蓝牙音频设备") {
                Defaults.Toggle(key: .showBluetoothDeviceConnections) { Text("显示蓝牙设备连接提示") }
                    .onReceive(Defaults.publisher(.showBluetoothDeviceConnections, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("蓝牙耳机", symbol: "headphones", circular: Defaults[.useCircularBluetoothBatteryIndicator]) } }
                Picker("电量指示器", selection: $circular) {
                    Text("内嵌").tag(false)
                    Text("环形").tag(true)
                }.onChange(of: circular) { _, value in
                    DynamicIslandViewCoordinator.shared.previewSetting("蓝牙耳机 75%", symbol: "headphones", circular: value)
                }
            }
        }.navigationTitle("设备")
    }
}



struct Media: View {
    private static let hideDelays: [Double] = [0, 1, 3, 5, 10, 15, 30, 60, -1]
    @Default(.pausedMediaHideDelay) private var pausedMediaHideDelay
    var body: some View {
        Form {
            Section("媒体") {
                Defaults.Toggle(key: .showStandardMediaControls) { Text("在刘海中显示媒体控制") }
                Defaults.Toggle(key: .autoHideInactiveNotchMediaPlayer) { Text("自动隐藏未播放媒体的面板") }
                Slider(value: Binding(get: { Self.hideDelays.firstIndex(of: pausedMediaHideDelay).map(Double.init) ?? 2 }, set: { pausedMediaHideDelay = Self.hideDelays[Int($0.rounded())] }), in: 0...8, step: 1) {
                    Text(pausedMediaHideDelay < 0 ? "暂停后收回媒体：一直保留" : "暂停后收回媒体：\(Int(pausedMediaHideDelay)) 秒")
                }
                if pausedMediaHideDelay < 0 {
                    Defaults.Toggle(key: .hideLyricsWhenPaused) { Text("暂停时收回歌词") }
                }
                Defaults.Toggle(key: .showLyricsBelowBuiltinNotch) { Text("在常驻灵动岛显示歌词") }
                Text("查询歌词时，会向网易云和 LRCLIB 发送歌名、艺人或歌曲 ID。").font(.caption).foregroundStyle(.secondary)
            }
            Section("锁屏媒体") {
                Defaults.Toggle(key: .enableLockScreenMediaWidget) { Text("显示锁屏媒体") }
            }
        }.navigationTitle("媒体")
    }
}

struct CalendarSettings: View {
    @Default(.showCalendar) private var enabled
    @Default(.reminderLeadTime) private var lead
    @Default(.reminderSneakPeekDuration) private var reminderDuration
    @Default(.lockScreenReminderChipStyle) private var reminderChipStyle
    @Default(.reminderPresentationStyle) private var reminderStyle
    @ObservedObject private var calendar = CalendarManager.shared
    var body: some View {
        Form {
            Section("日历") { Toggle("启用日历", isOn: $enabled) }
            if enabled {
                Section("日历列表") {
                    ForEach(calendar.allCalendars, id: \.id) { item in
                        Toggle(item.title, isOn: Binding(get: { calendar.selectedCalendarIDs.contains(item.id) }, set: { _ in Task { await calendar.setCalendarSelected(item, isSelected: !calendar.selectedCalendarIDs.contains(item.id)) } }))
                    }
                }
                Section("提醒实时活动") {
                    Slider(value: $reminderDuration, in: 3...20, step: 1) { Text("提醒展示时长：\(Int(reminderDuration)) 秒") }
                    Defaults.Toggle(key: .enableReminderLiveActivity) { Text("启用提醒实时活动") }
                    Picker("倒计时样式", selection: $reminderStyle) {
                        ForEach(ReminderPresentationStyle.allCases) { style in Text(style.displayName).tag(style) }
                    }
                    Slider(value: Binding(get: { Double(lead) }, set: { lead = Int($0) }), in: 1...60, step: 1) { Text("提前提醒：\(lead) 分钟") }
                }
                Section("锁屏") {
                    Picker("提醒配色", selection: $reminderChipStyle) {
                        Text("事件颜色").tag(LockScreenReminderChipStyle.eventColor)
                        Text("白色").tag(LockScreenReminderChipStyle.monochrome)
                    }
                    Defaults.Toggle(key: .enableLockScreenReminderWidget) { Text("显示锁屏提醒") }
                    Defaults.Toggle(key: .lockScreenShowCalendarEvent) { Text("显示日历事件") }
                    Defaults.Toggle(key: .lockScreenShowCalendarCountdown) { Text("显示事件倒计时") }
                }
            }
        }.navigationTitle("日历")
         .onChange(of: enabled) { _, value in calendar.setEnabled(value) }
    }
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("版本名称")
                        Spacer()
                        Text(Defaults[.releaseName])
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("版本")
                        Spacer()
                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "unkown")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        withAnimation {
                            showBuildNumber.toggle()
                        }
                    }
                } header: {
                    Text("版本信息")
                }


                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.open(sponsorPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("捐赠")
                                .foregroundStyle(.white)
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.open(productPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                            Text("GitHub")
                                .foregroundStyle(.white)
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())
                Text("您的支持将资助高中生的软件开发学习。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            VStack(spacing: 0) {
                Divider()
                Text("由 Ebullioscopic 用 ❤️ 制作")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .background(.regularMaterial)
        }
        .navigationTitle("关于")
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

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }

    init() {
        QuickShareService.shared.ensureDiscovered()
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.shelf.highlightID(for: title)
    }

    var body: some View {
        Form {
            if !canEnableShelf || !fullDiskAccessPermission.isAuthorized {
                Section {
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

            Section {
                Defaults.Toggle(key: .dynamicShelf) {
                    Text("启用文件托盘")
                }
                .disabled(!canEnableShelf)
                .settingsHighlight(id: highlightID("启用文件托盘"))

                

                

                Defaults.Toggle(key: .copyOnDrag) {
                    Text("拖动时复制项目")
                }
                .settingsHighlight(id: highlightID("拖动时复制项目"))

                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("拖出后从文件托盘移除")
                }
                .settingsHighlight(id: highlightID("拖出后从文件托盘移除"))
            } header: {
                HStack {
                    Text("通用")
                }
            }

            Section {
                Picker("快速分享服务", selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            QuickShareProviderIconImage(provider: provider, size: 12)
                            Text(provider.settingsTitle)
                        }
                        .tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                .settingsHighlight(id: highlightID("快速分享服务"))

                if let selectedProvider {
                    HStack {
                        QuickShareProviderIconImage(provider: selectedProvider, size: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("当前选择：\(selectedProvider.settingsTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("托盘中的文件将通过此服务分享")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text("快速分享")
                }
            } footer: {
                Text("选择文件托盘使用的分享服务。拖入文件，或点击托盘按钮选择文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if quickShareProvider == "LocalSend" {
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("文件托盘")
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
        Form {
            Section("隐私指示器") {
                Defaults.Toggle(key: .enableCameraDetection) { Text("相机指示器") }
                    .onReceive(Defaults.publisher(.enableCameraDetection, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("相机", symbol: "camera.fill", circular: false) } }
                Defaults.Toggle(key: .enableMicrophoneDetection) { Text("麦克风指示器") }
                    .onReceive(Defaults.publisher(.enableMicrophoneDetection, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("麦克风", symbol: "mic.fill", circular: false) } }
            }
            Section("大写锁定") {
                Defaults.Toggle(key: .enableCapsLockIndicator) { Text("大写锁定指示器") }
                    .onReceive(Defaults.publisher(.enableCapsLockIndicator, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("大写锁定", symbol: "capslock.fill", circular: false) } }
            }
            Section("系统活动") {
                Defaults.Toggle(key: .showRecordingIndicator) { Text("显示录制指示器") }
                    .onReceive(Defaults.publisher(.showRecordingIndicator, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("屏幕录制", symbol: "record.circle.fill", circular: false) } }
                Defaults.Toggle(key: .showDoNotDisturbIndicator) { Text("专注模式指示器") }
                    .onReceive(Defaults.publisher(.showDoNotDisturbIndicator, options: [])) { change in if change.newValue { DynamicIslandViewCoordinator.shared.previewSetting("专注模式", symbol: "moon.fill", circular: false) } }
            }
        }.navigationTitle("实时活动")
    }
}

struct LockScreenSettings: View {
    @Default(.lockScreenWeatherWidgetStyle) private var weatherStyle
    @Default(.lockScreenWeatherTemperatureUnit) private var unit
    @Default(.lockScreenWeatherProviderSource) private var provider
    var body: some View {
        Form {
            Section("锁屏") {
                Defaults.Toggle(key: .enableLockScreenLiveActivity) { Text("显示实时活动") }
                Defaults.Toggle(key: .enableLockSounds) { Text("锁定与解锁音效") }
            }
            Section("媒体面板") {
                Defaults.Toggle(key: .enableLockScreenMediaWidget) { Text("显示媒体面板") }
                Defaults.Toggle(key: .lockScreenShowAppIcon) { Text("显示应用图标") }

                Defaults.Toggle(key: .lockScreenPanelShowsBorder) { Text("显示面板边框") }
            }
            Section("天气") {
                Defaults.Toggle(key: .enableLockScreenWeatherWidget) { Text("显示天气") }
                Picker("样式", selection: $weatherStyle) { ForEach(LockScreenWeatherWidgetStyle.allCases) { style in Text(style.localizedName).tag(style) } }
                Picker("温度", selection: $unit) { ForEach(LockScreenWeatherTemperatureUnit.allCases) { unit in Text(unit.symbol).tag(unit) } }
                Picker("服务提供方", selection: $provider) { ForEach(LockScreenWeatherProviderSource.allCases) { provider in Text(provider.displayName).tag(provider) } }
                Defaults.Toggle(key: .lockScreenWeatherShowsLocation) { Text("显示位置") }
                Defaults.Toggle(key: .lockScreenWeatherShowsSunrise) { Text("显示日出和日落") }
                Defaults.Toggle(key: .lockScreenWeatherShowsAQI) { Text("显示空气质量") }
                Defaults.Toggle(key: .lockScreenWeatherUsesGaugeTint) { Text("天气仪表使用主题色") }
            }
            Section("电池") {
                Defaults.Toggle(key: .lockScreenBatteryShowsBatteryGauge) { Text("电池仪表") }
                Defaults.Toggle(key: .lockScreenBatteryUsesLaptopSymbol) { Text("笔记本图标") }
                Defaults.Toggle(key: .lockScreenBatteryShowsCharging) { Text("充电状态") }
                Defaults.Toggle(key: .lockScreenBatteryShowsChargingPercentage) { Text("充电百分比") }
                Defaults.Toggle(key: .lockScreenBatteryShowsBluetooth) { Text("蓝牙设备电量") }
            }
            Section("日历与专注模式") {
                Defaults.Toggle(key: .enableLockScreenReminderWidget) { Text("显示日程到时提醒") }
                Defaults.Toggle(key: .lockScreenShowCalendarEvent) { Text("显示日历事件") }
                Defaults.Toggle(key: .lockScreenShowCalendarCountdown) { Text("显示事件倒计时") }
                Defaults.Toggle(key: .lockScreenShowCalendarEventEntireDuration) { Text("在事件持续期间显示") }
                Defaults.Toggle(key: .lockScreenShowCalendarEventAfterStartEnabled) { Text("事件开始后继续显示") }
                Defaults.Toggle(key: .lockScreenShowCalendarTimeRemaining) { Text("显示剩余时间") }
                Defaults.Toggle(key: .lockScreenShowCalendarStartTimeAfterBegins) { Text("开始后显示起始时间") }
                Defaults.Toggle(key: .enableLockScreenFocusWidget) { Text("显示专注模式") }
            }
            LockScreenPositioningControls()
        }.navigationTitle("锁屏")
    }
}





private struct LockScreenPositioningControls: View {
    @State private var previewWidth: CGFloat = 500
    var body: some View {
        Section("位置与预览") {
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
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}



private func copyLatestCrashReport() {
    let crashReportsPath = NSString(string: "~/Library/Logs/DiagnosticReports").expandingTildeInPath
    let fileManager = FileManager.default

    do {
        let files = try fileManager.contentsOfDirectory(atPath: crashReportsPath)
        let crashFiles = files.filter { $0.contains("DynamicIsland") && $0.hasSuffix(".crash") }

        guard let latestCrash = crashFiles.sorted(by: >).first else {
            let alert = NSAlert()
            alert.messageText = "No Crash Reports Found"
            alert.informativeText = "No crash reports found for DynamicIsland"
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        let crashPath = (crashReportsPath as NSString).appendingPathComponent(latestCrash)
        let crashContent = try String(contentsOfFile: crashPath, encoding: .utf8)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(crashContent, forType: .string)

        let alert = NSAlert()
        alert.messageText = "Crash Report Copied"
        alert.informativeText = "Crash report '\(latestCrash)' has been copied to clipboard"
        alert.alertStyle = .informational
        alert.runModal()
    } catch {
        let alert = NSAlert()
        alert.messageText = "错误"
        alert.informativeText = "Failed to read crash reports: \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}



func proFeatureBadge() -> some View {
    Text("升级至 Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("即将上线")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func alphaBadge() -> some View {
    Text("测试版")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.9))
        )
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
        Form {
            Section("终端") {
                Defaults.Toggle(key: .enableTerminalFeature) { Text("启用终端") }
                LabeledContent("命令解释器") {
                    TextField("", text: $shell, prompt: Text("/bin/zsh"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
                Defaults.Toggle(key: .terminalStickyMode) { Text("鼠标移开时保持终端打开") }
            }
            Section("字体") {
                Picker("字体", selection: $font) {
                    ForEach(Array(Set(NSFontManager.shared.availableFontFamilies.filter { family in
                        guard let candidate = NSFont(name: family, size: 13) else { return false }
                        return candidate.isFixedPitch || NSFontManager.shared.traits(of: candidate).contains(.fixedPitchFontMask)
                    } + [font])).sorted(), id: \.self) { family in
                        Text(family).font(.custom(family, size: 13)).tag(family)
                    }
                }
                Slider(value: $size, in: 9...24, step: 1) { Text("字号：\(Int(size))") }
                Slider(value: $height, in: 0.2...0.8, step: 0.05) { Text("最大屏幕高度占比：\(Int(height * 100))%") }
            }
            Section { Button("重新启动终端") { TerminalManager.shared.restartShell() } }
        }.navigationTitle("终端")
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
