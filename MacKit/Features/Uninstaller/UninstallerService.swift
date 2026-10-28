import AppKit
import Observation
import UniformTypeIdentifiers
import ServiceManagement

struct SystemOperationResult: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let succeeded: Bool
    let message: String
}

@MainActor @Observable
final class UninstallerService: FeatureModule {
    let id = FeatureID.uninstaller
    private(set) var report: ScanReport?
    private(set) var busy = false
    private(set) var executing = false
    private(set) var status = "选择一个应用以查找关联项目"
    private(set) var results: [RemovalResult] = []
    private(set) var journalURL: URL?
    var selected: Set<String> = []
    var selectedSystem: Set<String> = []
    private(set) var systemResults: [SystemOperationResult] = []
    private(set) var extraRoots: [URL] = []
    var selectedSystemItems: [SystemAssociation] { report?.systemItems.filter { selectedSystem.contains($0.id) && $0.selectable } ?? [] }
    var selectionCount: Int { selected.count + selectedSystemItems.count }

    func chooseExtraRoots() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "添加应用可能存放数据的位置"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            extraRoots = panel.urls.filter { PathPolicy.path($0) != "/" && !PathPolicy.contains(URL(fileURLWithPath: "/System"), $0) }
            status = "已设置额外扫描位置，请重新选择应用扫描"
        }
    }
    func openSystemItem(_ item: SystemAssociation) {
        if item.kind == .login { SMAppService.openSystemSettingsLoginItems() }
        else if item.kind == .privacy {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") { NSWorkspace.shared.open(url) }
        } else { status = "请使用 \(report?.app.name ?? "该应用") 提供的官方卸载器；安装收据本身不能证明文件独占归属。" }
    }
    var confirmRemoval = false
    private var scanTask: Task<ScanReport, Error>?
    private var removalTask: Task<[RemovalResult], Error>?
    private var generation = UUID()
    private var cancelled = false

    var selectedItems: [ScanItem] { report?.items.filter { selected.contains($0.id) } ?? [] }
    var selectedBytes: Int64 { selectedItems.compactMap(\.bytes).reduce(0, +) }

    func choose() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "选择要卸载的应用"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { scan(url) }
    }

    func scan(_ url: URL) {
        guard !busy else { return }
        let token = UUID(); generation = token
        report = nil; selected = []; selectedSystem = []; results = []; systemResults = []; journalURL = nil
        busy = true; cancelled = false; status = "正在识别应用…"
        let ownURL = Bundle.main.bundleURL, ownID = Bundle.main.bundleIdentifier
        let roots = extraRoots
        let work = Task.detached(priority: .utility) { [weak self] in
            let owner = self
            return try AppScanner(ownURL: ownURL, ownID: ownID, extraRoots: roots).scan(url) { update in
                Task { @MainActor in
                    guard let self = owner, self.generation == token, self.busy else { return }
                    self.status = "已发现 \(update.count) 项 · \(update.path)"
                }
            }
        }
        scanTask = work
        Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.busy = false; self.scanTask = nil } }
            do {
                let report = try await work.value
                guard self.generation == token, !self.cancelled else { return }
                self.report = report
                self.selected = Set(report.items.filter(\.suggested).map(\.id))
                self.status = "发现 \(report.items.count) 个关联项目；请审阅后操作"
            } catch is CancellationError { self.status = "扫描已取消，没有删除任何文件" }
            catch { self.status = error.localizedDescription }
        }
    }

    func removeSelected() {
        guard !busy, let report else { return }
        guard selectionCount > 0 else { return }
        let systemItems = selectedSystemItems
        let plan: RemovalPlan?
        do { plan = selected.isEmpty ? nil : try RemovalPlan(report: report, selected: selected) }
        catch { status = error.localizedDescription; return }
        busy = true; executing = true; cancelled = false; results = []; systemResults = []
        let token = UUID(); generation = token
        Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.executing = false; self.removalTask = nil }
            let running = NSWorkspace.shared.runningApplications.filter { app in
                report.app.relatedIDs.contains(app.bundleIdentifier ?? "") ||
                app.bundleURL.map { PathPolicy.contains(report.app.url, $0) } == true
            }
            if !running.isEmpty {
                self.status = "正在请求目标应用正常退出…"
                running.forEach { _ = $0.terminate() }
                for _ in 0..<20 {
                    if running.allSatisfy(\.isTerminated) || self.cancelled { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard running.allSatisfy(\.isTerminated) else {
                    self.status = "应用仍在运行，尚未删除。请保存工作并退出后重试。"; return
                }
            }
            guard !self.cancelled else { self.status = "操作已取消"; return }
            let journal = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/MacKit/Operations/\(UUID().uuidString).json")
            self.journalURL = journal
            self.status = "正在移到废纸篓…"
            let work = Task.detached(priority: .utility) { [weak self] in
                let owner = self
                var completed: [SystemOperationResult] = []
                let systemJournal = journal.deletingPathExtension().appendingPathExtension("system.json")
                try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
                for item in systemItems {
                    if Task.isCancelled { break }
                    guard let bundleID = item.bundleID else { continue }
                    let result: SystemOperationResult
                    do {
                        guard try FileIdentity.read(report.app.url) == report.app.snapshot else { throw UninstallError.changed(report.app.url.path) }
                        let command = try SystemCleanup.resetPermissions(bundleID: bundleID, allowedIDs: report.app.relatedIDs)
                        result = SystemOperationResult(id: item.id, title: bundleID, succeeded: command.status == 0,
                            message: command.status == 0 ? "已重置系统支持的隐私权限；重新使用时需授权" : "未能重置：" + String(command.output.prefix(400)))
                    } catch {
                        result = SystemOperationResult(id: item.id, title: bundleID, succeeded: false, message: error.localizedDescription)
                    }
                    completed.append(result)
                    try JSONEncoder().encode(completed).write(to: systemJournal, options: .atomic)
                    Task { @MainActor in
                        guard let owner, owner.generation == token else { return }
                        if !owner.systemResults.contains(where: { $0.id == result.id }) { owner.systemResults.append(result) }
                    }
                }
                guard let plan else { return [] as [RemovalResult] }
                return try RemovalExecutor.execute(plan, journalURL: journal, progress: { result in
                    Task { @MainActor in
                        guard let owner, owner.generation == token else { return }
                        if !owner.results.contains(where: { $0.id == result.id }) { owner.results.append(result) }
                    }
                })
            }
            self.removalTask = work
            do {
                self.results = try await work.value
                let success = self.results.filter(\.succeeded).count
                self.status = "\(self.cancelled ? "已停止" : "处理结束")：\(success)/\(plan?.items.count ?? 0) 项移到废纸篓。系统操作请查看单独结果。"
                self.selected = []; self.selectedSystem = []
                self.report = nil
            } catch { self.status = "处理未完成：\(error.localizedDescription)" }

        }
    }

    func stop() {
        cancelled = true
        scanTask?.cancel(); removalTask?.cancel()
        if busy { status = "正在停止；当前文件操作结束后返回…" }
    }
}
