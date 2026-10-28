import SwiftUI

struct FinderCutView: View {
    @Bindable var service: FinderCutService
    var body: some View {
        PageLayout {
            PageHeader(title: "访达剪切", subtitle: "熟悉的快捷键，更自然的文件移动。", symbol: "scissors")
            SettingsCard {
                HStack {
                    Text("使用 ⌘ X 剪切").font(.headline)
                    Spacer()
                    Toggle("使用 ⌘ X 剪切", isOn: Binding(get: { service.enabled }, set: service.setEnabled))
                        .labelsHidden().toggleStyle(.switch)
                }
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { shortcuts }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 16) { shortcuts }
                }
            }
            PermissionCard(title: "剪切角标", subtitle: service.badgeStatus) {
                Button("管理扩展…") { service.openExtensionSettings() }
            }
        }.onAppear { service.sync(); service.refreshBadges() }
    }
    @ViewBuilder private var shortcuts: some View {
        shortcut(["⌘", "X"], description: "剪切")
        shortcut(["⌘", "V"], description: "粘贴")
        shortcut(["esc"], description: "取消剪切")
    }
    private func shortcut(_ keys: [String], description: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key).font(.system(size: 13, weight: .medium))
                        .frame(minWidth: key == "esc" ? 34 : 25, minHeight: 27)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
                }
            }
            Text(description).font(.body)
        }
    }
}
