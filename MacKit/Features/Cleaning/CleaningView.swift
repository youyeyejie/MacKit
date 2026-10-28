import SwiftUI

struct CleaningView: View {
    @Bindable var service: CleaningService
    var shortcut: String?
    var body: some View {
        PageLayout {
            PageHeader(title: "清洁模式", subtitle: "给屏幕、键盘和触控板一个干净的片刻。", symbol: "sparkles", color: .teal)
            SettingsCard {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: AppStyle.contentSpacing) {
                        Text("一键锁定，安心擦拭").font(AppStyle.sectionTitle)
                        Text("锁定键盘和触控板，解锁需连续按下 5 次 ESC")
                            .font(AppStyle.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("开始清洁") { service.begin() }.buttonStyle(.borderedProminent).controlSize(.large).tint(.teal)
                        if let shortcut { Text("快捷键 \(shortcut)").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "laptopcomputer").font(.system(size: 54, weight: .ultraLight))
                        .foregroundStyle(.teal.opacity(0.8)).accessibilityHidden(true)
                }
            }
            if !service.hasBuiltinDisplay {
                SettingsCard {
                    SettingsRow(title: "没有内建显示器时使用当前屏幕") {
                        Toggle("使用当前屏幕", isOn: $service.useCurrentDisplay).labelsHidden().toggleStyle(.switch)
                    }
                }
            }
            if let message = service.message { Label(message, systemImage: "info.circle").foregroundStyle(.orange).font(.callout) }
        }
    }
}
