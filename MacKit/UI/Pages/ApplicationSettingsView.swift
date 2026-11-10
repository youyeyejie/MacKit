import SwiftUI

struct ApplicationSettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        PageLayout {
            SettingsRows(title: "启动与运行") {
                SettingsRow(title: "登录后启动") {
                    Toggle("登录后启动", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            SettingsRows(title: "显示位置") {
                SettingsRow(title: "在 Dock 中显示") {
                    Toggle("在 Dock 中显示", isOn: Binding(get: { model.showDock }, set: model.setDock))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                SettingsRow(title: "在菜单栏中显示") {
                    Toggle("在菜单栏中显示", isOn: Binding(get: { model.showMenuBar }, set: model.setMenuBar))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            SettingsRows(title: "快捷键") {
                SettingsRow(title: "打开 MacKit") {
                    ShortcutRecorder(
                        shortcut: model.shortcuts.show, save: { model.setShortcut($0, forCleaning: false) },
                        recordingChanged: { model.recordingChanged?($0) })
                }
                Divider()
                SettingsRow(title: "开始清洁") {
                    ShortcutRecorder(
                        shortcut: model.shortcuts.clean, save: { model.setShortcut($0, forCleaning: true) },
                        recordingChanged: { model.recordingChanged?($0) })
                }
            }
            SettingsRows(title: "退出应用") {
                SettingsRow(title: "退出 MacKit") {
                    Button("退出应用", role: .destructive) { NSApp.terminate(nil) }
                        .buttonStyle(.borderedProminent).tint(.red)
                }
            }
            if let message = model.message { Text(message).font(.callout).foregroundStyle(.orange) }
        }
    }

}
