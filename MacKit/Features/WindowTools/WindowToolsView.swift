// SPDX-License-Identifier: GPL-3.0-or-later
// Based in part on implementation mechanisms from Vorssaint.
// Copyright (C) 2026 Vorssaint; modifications Copyright (C) 2026 youyeyejie.
// Adapted for MacKit; provenance and license update: 2026-11-04.
// See THIRD_PARTY_NOTICES.md and LICENSES/Vorssaint-GPL-3.0.txt.
import SwiftUI

struct WindowSwitcherView: View {
    @Bindable var service: WindowSwitcherService
    @Bindable var dock: DockEnhancementService
    @Bindable var missionControl: MissionControlService
    var body: some View {
        PageLayout {
            SettingsRows(title: "窗口切换") {
                SettingsRow(title: "启用预览", subtitle: "⌘ Tab 切换窗口，⌘ ` 切换应用内窗口，方向键移动选择。") {
                    Toggle("启用预览", isOn: Binding(get: { service.enabled }, set: service.setEnabled)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                SettingsRow(title: "启用按钮", subtitle: "⌘ Q 退出应用，⌘ W 关闭窗口，⌘ M 最小化窗口，⌘ ⇧ Q 退出所有应用。") {
                    Toggle("启用按钮", isOn: Binding(get: { service.buttonsEnabled }, set: service.setButtonsEnabled)).labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!service.enabled)
                }
            }
            SettingsRows(title: "调度中心增强") {
                SettingsRow(title: "启用调度中心增强", subtitle: "在调度中心中，⌘ W 关闭鼠标悬停窗口，⌘ Q 退出窗口所属应用。") {
                    Toggle("启用调度中心增强", isOn: Binding(get: { missionControl.enabled }, set: missionControl.setEnabled))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                if let message = missionControl.message {
                    Text(message).font(.system(size: 11)).foregroundStyle(.secondary).padding(.bottom, 8)
                }
            }
            SettingsRows(title: "程序坞增强") {
                SettingsRow(title: "启用悬停预览") {
                    Toggle("启用悬停预览", isOn: Binding(get: { dock.previewEnabled }, set: dock.setPreviewEnabled)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                SettingsRow(title: "点击图标最小化") {
                    Toggle("点击图标最小化", isOn: Binding(get: { dock.clickEnabled }, set: dock.setClickEnabled)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }.onAppear { service.sync(); dock.sync(); missionControl.sync() }
    }
}
