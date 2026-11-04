import SwiftUI

struct OpenSourceLicensesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("开源许可与第三方声明").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Link("获取 MacKit 源码", destination: URL(string: "https://github.com/youyeyejie/MacKit")!)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("MacKit · GPL-3.0-or-later", file: "MacKit-LICENSE", ext: "txt", subdirectory: "Licenses")
                    Divider()
                    section("第三方代码说明", file: "THIRD_PARTY_NOTICES", ext: "md", subdirectory: nil)
                    Divider()
                    section("Vorssaint · GPL-3.0-or-later", file: "Vorssaint-GPL-3.0", ext: "txt", subdirectory: "Licenses")
                    Divider()
                    section("Phosphene · MIT License", file: "Phosphene-LICENSE", ext: "txt", subdirectory: "Licenses")
                }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
        }.padding(24).frame(width: 620, height: 520)
    }
    private func section(_ title: String, file: String, ext: String, subdirectory: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(contents(file, ext: ext, subdirectory: subdirectory))
                .font(.system(size: 12, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func contents(_ file: String, ext: String, subdirectory: String?) -> String {
        guard let url = Bundle.main.url(forResource: file, withExtension: ext, subdirectory: subdirectory),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "当前构建中缺少许可文件。" }
        return text
    }
}
