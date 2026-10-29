import SwiftUI

struct WindowSwitcherView: View {
    @Bindable var service: WindowSwitcherService

    var body: some View {
        PageLayout {
            PageHeader(title: "窗口切换", subtitle: "使用 ⌘Tab 预览并切换应用窗口，⌘` 切换当前应用内窗口。",
                       symbol: "rectangle.on.rectangle", color: .purple)
            SettingsRows(title: "窗口切换器") {
                SettingsRow(title: "启用窗口切换") {
                    Toggle("启用窗口切换", isOn: Binding(get: { service.enabled }, set: service.setEnabled))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsCard {
                Label("支持最小化和全屏窗口；按住 ⌘ 时连续按 Tab 或 ` 选择，松开 ⌘ 确认。",
                      systemImage: "info.circle").foregroundStyle(.secondary)
                if !service.isAvailable {
                    Text("需要在权限管理中开启辅助功能。首次预览其他应用窗口时还需要屏幕录制权限。")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
            if let message = service.message {
                Text(message).font(.callout).foregroundStyle(.orange)
            }
        }.onAppear { service.sync() }
    }
}

struct DockEnhancementView: View {
    @Bindable var service: DockEnhancementService

    var body: some View {
        PageLayout {
            PageHeader(title: "程序坞增强", subtitle: "悬停程序坞图标预览窗口，点按当前应用图标最小化，再次点按还原。",
                       symbol: "dock.rectangle", color: .orange)
            SettingsRows(title: "程序坞预览") {
                SettingsRow(title: "启用程序坞增强") {
                    Toggle("启用程序坞增强", isOn: Binding(get: { service.enabled }, set: service.setEnabled))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsCard {
                Label("预览只在指针靠近程序坞并停留片刻后生成，关闭面板后保留有上限的小图缓存，停用功能时清空。",
                      systemImage: "bolt.circle").foregroundStyle(.secondary)
                Text("只处理能可靠识别为应用图标的点按，拖拽、右键和其他程序坞项目保留系统行为。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if service.needsScreenRecording {
                Text("窗口图像需要屏幕录制权限；未授权时显示窗口标题和占位图。")
                    .font(.callout).foregroundStyle(.orange)
            }
            if let message = service.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }.onAppear { service.sync() }
    }
}
