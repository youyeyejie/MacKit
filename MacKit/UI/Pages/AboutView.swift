import SwiftUI

struct AboutView: View {
    @Bindable var model: AppModel
    var body: some View {
        PageLayout {
            VStack(spacing: 10) {
                Image(nsImage: AppBrand.icon).resizable().frame(width: 80, height: 80)
                Text("MacKit").font(.system(size: 22, weight: .bold))
                Text("轻一点，顺手一点。").font(AppStyle.body).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 24)
                .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 12))
            SettingsRows(title: "软件信息") {
                SettingsRow(title: "软件版本") {
                    let version =
                        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.11.3"
                    Link(
                        "v" + version,
                        destination: URL(string: "https://github.com/youyeyejie/MacKit/releases/tag/v" + version)!)
                }
                Divider()
                SettingsRow(title: "项目地址") {
                    Link("GitHub", destination: URL(string: "https://github.com/youyeyejie/MacKit")!)
                }
                Divider()
                SettingsRow(title: "开源许可") {
                    Button("GPL-3.0") { model.page = .licenses }
                        .buttonStyle(.link)
                }
            }
        }
    }
}
