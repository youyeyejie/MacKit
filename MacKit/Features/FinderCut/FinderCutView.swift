import SwiftUI

struct FinderCutView: View {
    @Bindable var service: FinderCutService
    var body: some View {
        PageLayout {
            SettingsRows(title: "访达剪切") {
                SettingsRow(title: "使用 ⌘ X 剪切", subtitle: "⌘ X 剪切，⌘ V 粘贴，Esc 取消剪切。") {
                    Toggle("使用 ⌘ X 剪切", isOn: Binding(get: { service.enabled }, set: service.setEnabled))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                SettingsRow(title: "启用剪切音效") {
                    Toggle("启用剪切音效", isOn: Binding(get: { service.soundEnabled }, set: service.setSoundEnabled))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .disabled(!service.enabled)
                }
            }
        }.onAppear { service.sync() }
    }
}
