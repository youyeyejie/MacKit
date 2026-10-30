import SwiftUI

struct WindowSwitcherView: View {
    @Bindable var service: WindowSwitcherService

    var body: some View {
        PageLayout {
            PageHeader(title: "窗口切换", subtitle: "更熟悉的切换预览，快速找到目标窗口。",
                       symbol: "rectangle.on.rectangle", color: .purple)
            SettingsRows(title: "窗口切换") {
                SettingsRow(title: "启用预览") {
                    Toggle("启用预览", isOn: Binding(get: { service.enabled }, set: service.setEnabled))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                SettingsRow(title: "启用按钮") {
                    Toggle("启用按钮", isOn: Binding(get: { service.buttonsEnabled }, set: service.setButtonsEnabled))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            SettingsCard(title: "快捷键") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), alignment: .leading)], alignment: .leading, spacing: 16) {
                    shortcut(["⌘", "Tab"], description: "切换窗口")
                    shortcut(["⌘", "`"], description: "切换应用内窗口")
                    shortcut(["↑", "↓", "←", "→"], separator: "/", description: "移动选择")
                    if service.buttonsEnabled {
                        shortcut(["⌘", "Q"], description: "退出应用")
                        shortcut(["⌘", "W"], description: "关闭窗口")
                        shortcut(["⌘", "M"], description: "最小化窗口")
                        shortcut(["⌘", "⇧", "Q"], description: "退出所有应用")
                    }
                }
            }
        }.onAppear { service.sync() }
    }

    private func shortcut(_ keys: [String], separator: String? = nil, description: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    if index > 0, let separator {
                        Text(separator).foregroundStyle(.secondary)
                    }
                    Text(key).font(.system(size: 13, weight: .medium))
                        .frame(minWidth: key == "Tab" ? 34 : 25, minHeight: 27)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
                }
            }
            Text(description).font(.body)
        }
    }

}

struct DockEnhancementView: View {
    @Bindable var service: DockEnhancementService

    var body: some View {
        PageLayout {
            PageHeader(title: "程序坞增强", subtitle: "悬停程序坞图标，预览打开的窗口。",
                       symbol: "dock.rectangle", color: .orange)
            SettingsRows(title: "程序坞增强") {
                SettingsRow(title: "悬停预览") {
                    Toggle("悬停预览", isOn: Binding(get: { service.previewEnabled }, set: service.setPreviewEnabled))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                SettingsRow(title: "点击图标最小化") {
                    Toggle("点击图标最小化", isOn: Binding(get: { service.clickEnabled }, set: service.setClickEnabled))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }.onAppear { service.sync() }
    }
}
