import SwiftUI

struct FinderCutView: View {
    @Bindable var service: FinderCutService
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("Finder 剪切", systemImage: "scissors").font(.title2.bold())
                Toggle("启用 ⌘X 剪切、⌘V 移动", isOn: Binding(get: { service.enabled }, set: { service.setEnabled($0) }))
                Text("在 Finder 选中文件后按 ⌘X，再到目标文件夹按 ⌘V。重命名和文本输入保留原有行为。")
                Label(service.status, systemImage: service.pendingCount > 0 ? "arrow.right.doc.on.clipboard" : "info.circle")
                Text(service.badgeStatus).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Finder 扩展设置") { service.openExtensionSettings() }
                    Button("取消待移动") { service.cancel() }.disabled(service.pendingCount == 0)
                    Button("重新检查权限") { service.sync() }
                }
                Text("移动和冲突由 Finder 处理。角标依赖签名与系统扩展授权，云盘目录可能不显示。")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
    }
}
