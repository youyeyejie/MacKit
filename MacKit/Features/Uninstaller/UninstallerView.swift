import SwiftUI
import UniformTypeIdentifiers

struct UninstallerView: View {
    @Bindable var service: UninstallerService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("应用卸载", systemImage: "trash").font(.title2.bold())
                Spacer()
                Button("选择应用…") { service.choose() }.disabled(service.busy)
            }
            Text("也可将 .app 拖到此处。默认只勾选应用本体及低风险关联文件；配置和用户数据需自行审阅。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if service.busy { ProgressView().controlSize(.small) }
                Text(service.status).font(.callout).lineLimit(2).textSelection(.enabled)
                Spacer()
                if service.busy { Button("停止") { service.stop() } }
            }
            if let report = service.report {
                Text("\(report.app.name) · \(report.app.bundleID)").font(.headline)
                List(report.items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("选择", isOn: Binding(get: { service.selected.contains(item.id) }, set: { value in
                            if value { service.selected.insert(item.id) } else { service.selected.remove(item.id) }
                        })).labelsHidden().disabled(!item.removable || service.busy)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.url.lastPathComponent).fontWeight(.medium)
                                Text(item.category.rawValue).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(item.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "大小未知").font(.caption)
                            }
                            Text(item.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(item.evidence).font(.caption2).foregroundStyle(.secondary)
                            if let caution = item.caution { Text(caution).font(.caption).foregroundStyle(.orange) }
                        }
                        Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "magnifyingglass") }
                            .help("在 Finder 显示")
                    }.padding(.vertical, 4)
                }.frame(minHeight: 180)
                DisclosureGroup("扫描范围与限制（\(report.warnings.count)）") {
                    ScrollView { VStack(alignment: .leading, spacing: 5) {
                        ForEach(report.warnings, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                    }}.frame(maxHeight: 100)
                }
                HStack {
                    Text("已选 \(service.selected.count) 项 · 逻辑大小约 \(ByteCountFormatter.string(fromByteCount: service.selectedBytes, countStyle: .file))").font(.caption)
                    Spacer()
                    Button("审阅并移到废纸篓…") { service.confirmRemoval = true }
                        .disabled(service.selected.isEmpty || service.busy).buttonStyle(.borderedProminent)
                }
            } else if !service.results.isEmpty {
                List(service.results) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(result.original.lastPathComponent, systemImage: result.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                        Text(result.message).font(.caption).foregroundStyle(.secondary)
                        if let destination = result.destination { Text(destination.path).font(.caption2).textSelection(.enabled) }
                    }
                }
                if let journal = service.journalURL {
                    Button("显示操作记录") { NSWorkspace.shared.activateFileViewerSelecting([journal]) }
                }
            } else {
                ContentUnavailableView("选择一个应用", systemImage: "app.dashed", description: Text("扫描只在使用时运行。所有关联结果都可以先查看，再决定是否处理。"))
            }
        }.padding(16)
        .dropDestination(for: URL.self) { urls, _ in
            guard !service.busy, urls.count == 1, let url = urls.first, url.pathExtension.lowercased() == "app" else { return false }
            service.scan(url); return true
        }
        .sheet(isPresented: $service.confirmRemoval) {
            VStack(alignment: .leading, spacing: 16) {
                Text("确认处理 \(service.selected.count) 个项目").font(.title2.bold())
                Text("目标应用将被请求正常退出。下列文件将移到废纸篓，不会永久删除；已运行的后台服务可能需要厂商卸载器处理。")
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(service.selectedItems) { item in
                            Text(item.url.path).textSelection(.enabled)
                            if let caution = item.caution { Text(caution).foregroundStyle(.orange).font(.caption) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 240)
                HStack {
                    Spacer()
                    Button("取消") { service.confirmRemoval = false }.keyboardShortcut(.cancelAction)
                    Button("移到废纸篓", role: .destructive) {
                        service.confirmRemoval = false; service.removeSelected()
                    }
                }
            }.padding(24).frame(width: 580)
        }
    }
}
