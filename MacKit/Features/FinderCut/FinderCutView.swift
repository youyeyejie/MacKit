import SwiftUI

struct FinderCutView: View {
    @Bindable var service: FinderCutService
    var body: some View {
        PageLayout {
            PageHeader(title: "Finder 剪切", subtitle: "熟悉的快捷键，更自然的文件移动。", symbol: "scissors")
            SettingsCard {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("剪切与粘贴").font(.headline)
                        Text("仅在 Finder 的文件浏览区域生效。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("启用 Finder 剪切", isOn: Binding(get: { service.enabled }, set: service.setEnabled))
                        .labelsHidden().toggleStyle(.switch)
                }
                Divider()
                HStack(spacing: 24) {
                    shortcut("⌘ X", description: "标记待移动")
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    shortcut("⌘ V", description: "移动到当前位置")
                    Spacer()
                }
            }
            SettingsCard(title: "当前状态") {
                Label(service.status, systemImage: service.pendingCount > 0 ? "arrow.right.doc.on.clipboard" : "info.circle")
                HStack {
                    Button("取消待移动") { service.cancel() }.disabled(service.pendingCount == 0)
                    Button("刷新状态") { service.sync(); service.refreshBadges() }
                }
            }
            SettingsCard(title: "待移动角标") {
                Text(service.badgeStatus).font(.callout).foregroundStyle(.secondary)
                Button("管理 Finder 扩展…") { service.openExtensionSettings() }
            }
            Text("⌘C 保留复制行为。文本框中的剪切、粘贴不受影响；按 Esc 可取消文件的待移动状态。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func shortcut(_ key: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(key).font(.system(size: 22, weight: .medium, design: .monospaced))
            Text(description).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 6)
    }
}
