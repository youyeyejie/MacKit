import SwiftUI
import ServiceManagement

struct MainView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill").font(.largeTitle).foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("MacKit").font(.largeTitle.bold())
                    Text("轻量原生工具 · macOS 14–27").foregroundStyle(.secondary)
                }
                Spacer()
                Text("开发预览 0.1").font(.caption).padding(8).background(.quaternary, in: Capsule())
            }
            GroupBox("后台运行") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("不显示 Dock 或菜单栏图标。再次打开 MacKit 或按 ⌃⌥⌘M 唤起此窗口。")
                    HStack {
                        Text("登录启动：\(model.loginStatus)")
                        Spacer()
                        Button("启用") { model.setLogin(true) }
                        Button("关闭") { model.setLogin(false) }
                    }
                }.padding(10)
            }
            GroupBox("权限") {
                HStack {
                    Label(model.permissions.accessibility ? "辅助功能已授权" : "辅助功能未授权",
                          systemImage: model.permissions.accessibility ? "checkmark.shield" : "lock.shield")
                    Spacer()
                    Button("请求授权") { model.permissions.requestAccessibility() }
                    Button("刷新") { model.permissions.refresh(); model.refreshLogin() }
                }.padding(10)
            }
            if let message = model.message { Text(message).foregroundStyle(.orange).textSelection(.enabled) }
            Spacer()
            HStack {
                Text("关闭窗口后继续后台运行").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("退出 MacKit") { NSApp.terminate(nil) }
            }
        }.padding(28)
    }
}
