import Foundation

public struct RemovalPlan: Sendable {
    public let app: AppIdentity
    public let items: [ScanItem]
    public let allowedRoots: [URL]
    public let explicitPaths: [URL]

    public init(report: ScanReport, selected: Set<String>) throws {
        app = report.app; allowedRoots = report.allowedRoots; explicitPaths = report.explicitPaths
        let chosen = report.items.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { throw UninstallError.emptyPlan }
        for item in chosen {
            guard item.removable,
                  PathPolicy.isSafe(item.url, app: app.url, roots: allowedRoots, explicit: explicitPaths) else {
                throw UninstallError.unsafePath(item.url.path)
            }
        }
        // Parent selections subsume children; keep the app last to revalidate its identity.
        items = chosen.filter { item in
            !chosen.contains { other in other.id != item.id && PathPolicy.contains(other.url, item.url) }
        }.sorted { lhs, rhs in
            if lhs.url == report.app.url { return false }
            if rhs.url == report.app.url { return true }
            return lhs.url.path < rhs.url.path
        }
    }

    public func validate(_ item: ScanItem) throws {
        guard PathPolicy.isSafe(item.url, app: app.url, roots: allowedRoots, explicit: explicitPaths), !item.identity.isSymbolicLink else {
            throw UninstallError.unsafePath(item.url.path)
        }
        guard try FileIdentity.read(app.url) == app.snapshot,
              let plist = NSDictionary(contentsOf: app.url.appendingPathComponent("Contents/Info.plist")),
              plist["CFBundleIdentifier"] as? String == app.bundleID,
              try FileIdentity.read(item.url) == item.identity else { throw UninstallError.changed(item.url.path) }
    }
}

public struct RemovalResult: Codable, Identifiable, Sendable {
    public var id: String { original.path }
    public let original: URL
    public let destination: URL?
    public let message: String
    public var succeeded: Bool { destination != nil }
}

public enum RemovalExecutor {
    public static func execute(_ plan: RemovalPlan, journalURL: URL? = nil,
                               trash: @Sendable (URL) throws -> URL = moveToTrash,
                               progress: @Sendable (RemovalResult) -> Void = { _ in }) throws -> [RemovalResult] {
        var results: [RemovalResult] = []
        if let journalURL {
            try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(results).write(to: journalURL, options: .atomic)
        }
        for item in plan.items {
            if Task.isCancelled { break }
            let result: RemovalResult
            do {
                try plan.validate(item)
                try SystemCleanup.unloadUserAgent(item)
                try plan.validate(item)
                let target = try trash(item.url)
                result = RemovalResult(original: item.url, destination: target, message: "已移到废纸篓")
            } catch {
                result = RemovalResult(original: item.url, destination: nil, message: "未处理：\(error.localizedDescription)")
            }
            results.append(result); progress(result)
            if let journalURL {
                do { try JSONEncoder().encode(results).write(to: journalURL, options: .atomic) }
                catch {
                    let warning = RemovalResult(original: journalURL, destination: nil, message: "操作记录保存失败，已停止后续处理。请保留当前结果。")
                    results.append(warning); progress(warning); break
                }
            }
        }
        return results
    }

    public static func moveToTrash(_ url: URL) throws -> URL {
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        guard let destination else { throw CocoaError(.fileWriteUnknown) }
        return destination as URL
    }
}
