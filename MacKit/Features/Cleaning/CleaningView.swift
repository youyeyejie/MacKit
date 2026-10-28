import SwiftUI

struct CleaningView: View {
    @Bindable var service: CleaningService
    var shortcut: String
    var body: some View {
        PageLayout {
            PageHeader(title: "清洁模式", subtitle: "给屏幕、键盘和触控板一个干净的片刻。", symbol: "sparkles", color: .teal)
            SettingsCard {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("一键锁定，安心擦拭").font(.title3.bold())
                        Text("点击后立即锁定键盘与触控板，内建屏幕变黑。退出提示会一直保留。")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("开始清洁") { service.begin() }.buttonStyle(.borderedProminent).controlSize(.large).tint(.teal)
                        Text("快捷键 \(shortcut)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "laptopcomputer").font(.system(size: 54, weight: .ultraLight))
                        .foregroundStyle(.teal.opacity(0.8)).accessibilityHidden(true)
                }
            }
            SettingsCard(title: "如何退出") {
                HStack(spacing: 16) {
                    Text("esc").font(.system(size: 16, weight: .medium, design: .monospaced))
                        .padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 9) {
                        Text("连续按下 5 次 Esc")
                        HStack(spacing: 7) { ForEach(0..<5) { _ in Circle().fill(.teal.opacity(0.35)).frame(width: 7, height: 7) } }
                        Text("每次点亮一个圆点；按其他键会清空进度，长按不会重复计数。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !service.hasBuiltinDisplay {
                SettingsCard { Toggle("没有内建显示器时使用当前屏幕", isOn: $service.useCurrentDisplay) }
            }
            Text("外接键盘、鼠标也会暂时锁定。Touch ID 和电源键由系统管理。")
                .font(.caption).foregroundStyle(.secondary)
            if let message = service.message { Label(message, systemImage: "info.circle").foregroundStyle(.orange).font(.callout) }
        }
    }
}
