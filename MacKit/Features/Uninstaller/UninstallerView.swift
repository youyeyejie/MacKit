import SwiftUI
import UniformTypeIdentifiers

struct UninstallerView: View {
    @Bindable var service: UninstallerService
    @State private var systemTab = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "应用卸载", subtitle: "查找关联内容，审阅后再清理。", symbol: "shippingbox.fill", color: .orange)
            HStack {
                Button("选择应用…") { service.choose() }.buttonStyle(.borderedProminent).disabled(service.busy)
                Button { service.chooseExtraRoots() } label: { Label("添加扫描位置", systemImage: "folder.badge.plus") }.disabled(service.busy)
                if !service.extraRoots.isEmpty { Text("另有 \(service.extraRoots.count) 个位置").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if service.busy { ProgressView().controlSize(.small); Button("停止") { service.stop() } }
            }
            Text(service.status).font(.callout).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            if let report = service.report {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: report.app.url.path)).resizable().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(report.app.name).font(.headline)
                        Text(report.app.bundleID).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: "\(report.items.count) 个文件项目", color: .orange)
                }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                Picker("结果类型", selection: $systemTab) {
                    Text("关联文件").tag(false)
                    Text("系统关联 · \(report.systemItems.count)").tag(true)
                }.pickerStyle(.segmented).frame(maxWidth: 360)
                if systemTab { systemList(report) } else { fileList(report) }
                DisclosureGroup("扫描范围与限制（\(report.warnings.count)）") {
                    ScrollView { VStack(alignment: .leading, spacing: 5) {
                        ForEach(report.warnings, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                    }}.frame(maxHeight: 100)
                }.font(.caption).foregroundStyle(.secondary)
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("已选择 \(service.selectionCount) 项").font(.headline)
                        Text("文件逻辑大小约 \(ByteCountFormatter.string(fromByteCount: service.selectedBytes, countStyle: .file))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("审阅并卸载…") { service.confirmRemoval = true }
                        .disabled(service.selectionCount == 0 || service.busy).buttonStyle(.borderedProminent)
                }
            } else if !service.results.isEmpty || !service.systemResults.isEmpty {
                List {
                    Section("文件处理") {
                        ForEach(service.results) { result in
                            resultRow(title: result.original.lastPathComponent, detail: result.message, success: result.succeeded)
                        }
                    }
                    if !service.systemResults.isEmpty {
                        Section("系统权限") {
                            ForEach(service.systemResults) { result in resultRow(title: result.title, detail: result.message, success: result.succeeded) }
                        }
                    }
                }.listStyle(.inset).scrollContentBackground(.hidden)
                if let journal = service.journalURL {
                    Button("显示操作记录") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: journal.deletingLastPathComponent().path) }
                }
            } else {
                ContentUnavailableView {
                    Label("把应用拖到这里", systemImage: "square.and.arrow.down.on.square")
                } description: {
                    Text("查找应用本体、数据、缓存、配置与系统关联项。\n先看清楚，再决定保留哪些。")
                }
            }
        }.padding(30).background(Color(nsColor: .windowBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            guard !service.busy, urls.count == 1, let url = urls.first, url.pathExtension.lowercased() == "app" else { return false }
            service.scan(url); return true
        }
        .sheet(isPresented: $service.confirmRemoval) { confirmation }
    }

    private func fileList(_ report: ScanReport) -> some View {
        List {
            ForEach(FileCategory.allCases, id: \.self) { category in
                let items = report.items.filter { $0.category == category }
                if !items.isEmpty {
                    Section(category.rawValue) {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Toggle("选择", isOn: Binding(get: { service.selected.contains(item.id) }, set: { value in
                                    if value { service.selected.insert(item.id) } else { service.selected.remove(item.id) }
                                })).labelsHidden().disabled(!item.removable || service.busy)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.url.lastPathComponent).fontWeight(.medium).lineLimit(1)
                                        Spacer()
                                        Text(item.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "大小未知").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(item.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                                    Text(item.evidence).font(.caption2).foregroundStyle(.secondary)
                                    if let caution = item.caution { Text(caution).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                                }
                                Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "magnifyingglass") }
                                    .buttonStyle(.borderless).help("在 Finder 显示")
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }
        }.listStyle(.inset).scrollContentBackground(.hidden).frame(minHeight: 180)
    }
    private func systemList(_ report: ScanReport) -> some View {
        List(report.systemItems) { item in
            HStack(alignment: .top, spacing: 10) {
                if item.selectable {
                    Toggle("选择权限重置", isOn: Binding(get: { service.selectedSystem.contains(item.id) }, set: { value in
                        if value { service.selectedSystem.insert(item.id) } else { service.selectedSystem.remove(item.id) }
                    })).labelsHidden().disabled(service.busy)
                } else { Image(systemName: "gearshape").foregroundStyle(.secondary).frame(width: 18) }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.title).font(.headline).lineLimit(2)
                        Spacer()
                        Text(item.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(item.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if item.action == .resetPermissions {
                        Text("选中后仅重置这个应用标识的权限，不修改其他应用。此操作不可从废纸篓恢复。")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Button(item.action == .loginSettings ? "打开登录项设置…" : "查看处理方式") { service.openSystemItem(item) }
                            .buttonStyle(.borderless)
                    }
                }
            }.padding(.vertical, 8)
        }.listStyle(.inset).scrollContentBackground(.hidden).frame(minHeight: 180)
    }
    private func resultRow(title: String, detail: String, success: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: success ? "checkmark.circle.fill" : "exclamationmark.triangle")
                .foregroundStyle(success ? .green : .orange)
            Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }.padding(.vertical, 6)
    }
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("审阅 \(service.selectionCount) 项操作").font(.title2.bold())
            Text("应用会被请求正常退出。文件移到废纸篓；所选用户启动服务会先停止。共享及名称匹配项目请逐一确认。")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(service.selectedItems) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.url.path).font(.callout).textSelection(.enabled)
                            if let caution = item.caution { Text(caution).foregroundStyle(.orange).font(.caption) }
                        }
                    }
                    ForEach(service.selectedSystemItems) { item in
                        Label("重置权限：" + item.title, systemImage: "hand.raised.slash")
                        Text("仅重置系统支持的该应用权限记录。无法撤销，重新使用时需再次授权。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 300)
            HStack {
                Spacer()
                Button("取消") { service.confirmRemoval = false }.keyboardShortcut(.cancelAction)
                Button("确认执行", role: .destructive) { service.confirmRemoval = false; service.removeSelected() }
            }
        }.padding(24).frame(width: 620)
    }
}
