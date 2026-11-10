import SwiftUI

struct OpenSourceLicensesView: View {
    private struct LicenseSection: Identifiable, Sendable {
        let id: String
        let title: String
        let paragraphs: [String]
    }
    @State private var sections: [LicenseSection] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Link("获取 MacKit 源码", destination: URL(string: "https://github.com/youyeyejie/MacKit")!)
                ForEach(sections) { section in
                    Text(section.title).font(.headline).padding(.top, 16)
                    ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph).font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.padding(20)
        }.background(SettingsPalette.canvas)
            .task {
                guard sections.isEmpty else { return }
                sections = await Task.detached(priority: .userInitiated) { Self.loadSections() }.value
            }
    }

    private nonisolated static func loadSections() -> [LicenseSection] {
        guard let root = Bundle.main.resourceURL else { return [] }
        let directory = root.appendingPathComponent("Licenses")
        let files =
            ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "txt" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return ([root.appendingPathComponent("THIRD_PARTY_NOTICES.md")] + files).map { url in
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? "当前构建中缺少许可文件。"
            return LicenseSection(
                id: url.lastPathComponent, title: url.deletingPathExtension().lastPathComponent,
                paragraphs: text.components(separatedBy: "\n\n").filter { !$0.isEmpty })
        }
    }
}
