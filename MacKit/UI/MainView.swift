import SwiftUI
import ServiceManagement

struct MainView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill").font(.largeTitle).foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("MacKit").font(.largeTitle.bold())
                    Text("轻量原生工具 · macOS 14–27").foregroundStyle(.secondary)
                }
                Spacer()
                Text("开发预览 0.1").font(.caption).padding(8).background(.quaternary, in: Capsule())
            }
            TabView {
                ScrollView { CleaningView(service: model.cleaning).padding(16) }
                    .tabItem { Label("清洁模式", systemImage: "sparkles") }
                ScrollView { FinderCutView(service: model.finderCut).padding(16) }
                    .tabItem { Label("Finder 剪切", systemImage: "scissors") }
                UninstallerView(service: model.uninstaller)
                    .tabItem { Label("应用卸载", systemImage: "trash") }
                settings.tabItem { Label("设置", systemImage: "gearshape") }
            }
            HStack {
                Text("关闭窗口后继续后台运行 · ⌃⌥⌘M 唤起").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("退出 MacKit") { NSApp.terminate(nil) }
            }
        }.padding(24)
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("后台运行") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("不显示 Dock 或菜单栏图标。通过 Spotlight 打开 MacKit，或使用快捷键唤起窗口。")
                        HStack {
                            Text("登录启动：\(model.loginStatus)")
                            Spacer()
                            Button("启用") { model.setLogin(true) }
                            Button("关闭") { model.setLogin(false) }
                        }
                        Button("打开系统登录项设置") { SMAppService.openSystemSettingsLoginItems() }
                    }.padding(10)
                }
                GroupBox("权限") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.permissions.accessibility ? "辅助功能已授权" : "辅助功能未授权",
                              systemImage: model.permissions.accessibility ? "checkmark.shield" : "lock.shield")
                        Text("清洁模式和 Finder 快捷键需要辅助功能权限。卸载扫描权限不足时会列出未能访问的位置。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("请求辅助功能授权") { model.permissions.requestAccessibility() }
                            Button("完整磁盘访问设置") { model.permissions.openSettings("Privacy_AllFiles") }
                            Button("刷新状态") { model.permissions.refresh(); model.refreshLogin(); model.finderCut.sync() }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                GroupBox("兼容性") {
                    Text("最低部署版本 macOS 14.0，重点验证 26 与 27。当前为开发预览；使用 27 SDK 构建不等于已在所有系统完成实机测试。")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                if let message = model.message { Text(message).foregroundStyle(.orange).textSelection(.enabled) }
            }.padding(16)
        }
    }
}
