import SwiftUI

struct CleaningView: View {
    @Bindable var service: CleaningService
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("清洁模式", systemImage: "sparkles").font(.title2.bold())
                Text("锁定键盘与触控板，内建屏幕显示黑色画面。连续按 5 次 Esc 解锁。")
                Text("外接键盘、鼠标也会暂时被拦截。系统多指手势仍需实机验证；电源键与 Touch ID 不属于锁定范围。")
                    .font(.caption).foregroundStyle(.secondary)
                if !service.hasBuiltinDisplay {
                    Toggle("无内建显示器时使用当前屏幕", isOn: $service.useCurrentDisplay)
                }
                if let countdown = service.countdown {
                    HStack {
                        Text("\(countdown) 秒后开始，请松开键盘与触控板")
                        Button("取消") { service.stop() }
                    }
                } else {
                    Button("开始清洁 · ⌃⌥⌘K") { service.begin() }.buttonStyle(.borderedProminent)
                }
                if let message = service.message { Text(message).foregroundStyle(.orange).textSelection(.enabled) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
    }
}
