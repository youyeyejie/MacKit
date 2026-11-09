import SwiftUI

struct CleaningView: View {
    @Bindable var model: AppModel
    private var service: CleaningService { model.cleaning }
    var body: some View {
        PageLayout {
            SettingsRows(title: "清洁模式") {
                SettingsRow(title: "锁定键盘和触控板", subtitle: "连续按下 5 次 ESC 解锁。也可在终端运行：open mackit://clean") {
                    Button("开始清洁") { service.begin() }.buttonStyle(.bordered)
                }
                Divider()
                SettingsRow(title: "快捷键") {
                    ShortcutRecorder(shortcut: model.shortcuts.clean,
                                     save: { model.setShortcut($0, forCleaning: true) },
                                     recordingChanged: { model.recordingChanged?($0) })
                }
            }
            if !service.hasBuiltinDisplay {
                SettingsCard {
                    SettingsRow(title: "没有内建显示器时使用当前屏幕") {
                        Toggle("使用当前屏幕", isOn: Binding(get: { service.useCurrentDisplay }, set: { service.useCurrentDisplay = $0 })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
            }
            if let message = service.message { Label(message, systemImage: "info.circle").foregroundStyle(.orange).font(.callout) }
        }
    }
}
