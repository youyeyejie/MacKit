import Foundation
import Darwin

public struct FileIdentity: Codable, Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let birthSeconds: Int64
    public let birthNanoseconds: Int64
    public let kind: UInt16

    public static func read(_ url: URL) throws -> FileIdentity {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return FileIdentity(device: UInt64(info.st_dev), inode: info.st_ino,
                            birthSeconds: Int64(info.st_birthtimespec.tv_sec), birthNanoseconds: Int64(info.st_birthtimespec.tv_nsec),
                            kind: info.st_mode & UInt16(S_IFMT))
    }
    public var isSymbolicLink: Bool { kind == UInt16(S_IFLNK) }
}

public enum FileCategory: String, Codable, Sendable {
    case application = "应用本体", cache = "缓存", preferences = "配置", support = "应用数据"
    case logs = "日志", state = "窗口状态", container = "容器", shared = "共享数据", service = "后台服务"
}
public enum Association: String, Codable, Sendable { case exact = "精确标识", name = "名称匹配", shared = "共享关系" }

public struct ScanItem: Identifiable, Codable, Sendable {
    public var id: String { PathPolicy.path(url) }
    public let url: URL
    public let category: FileCategory
    public let association: Association
    public let evidence: String
    public let identity: FileIdentity
    public let bytes: Int64?
    public let removable: Bool
    public let caution: String?
    public var suggested: Bool {
        removable && association == .exact && [.application, .cache, .logs, .state].contains(category)
    }
}

public struct AppIdentity: Codable, Sendable {
    public let url: URL
    public let name: String
    public let bundleID: String
    public let relatedIDs: Set<String>
    public let groups: Set<String>
    public let snapshot: FileIdentity
}
public struct ScanReport: Sendable {
    public let app: AppIdentity
    public let items: [ScanItem]
    public let warnings: [String]
    public let allowedRoots: [URL]
}
public struct ScanProgress: Sendable {
    public let path: String
    public let count: Int
}

public enum UninstallError: LocalizedError {
    case invalidApplication, protectedApplication, unsafePath(String), changed(String), emptyPlan
    public var errorDescription: String? {
        switch self {
        case .invalidApplication: "请选择具有有效 Bundle ID 的 .app 应用。"
        case .protectedApplication: "系统应用和 MacKit 自身不支持此卸载流程。"
        case .unsafePath(let path): "路径超出允许范围或包含符号链接：\(path)"
        case .changed(let path): "文件在扫描后发生替换，请重新扫描：\(path)"
        case .emptyPlan: "没有选择可处理的项目。"
        }
    }
}

public enum PathPolicy {
    public static func path(_ url: URL) -> String {
        var value = url.standardizedFileURL.path
        while value.count > 1 && value.hasSuffix("/") { value.removeLast() }
        return value
    }
    public static func canonical(_ url: URL) -> URL { URL(fileURLWithPath: path(url), isDirectory: false) }
    public static func contains(_ parent: URL, _ child: URL) -> Bool {
        let a = path(parent), b = path(child)
        return b == a || b.hasPrefix(a.hasSuffix("/") ? a : a + "/")
    }
    public static func hasSymlink(_ url: URL) -> Bool {
        path(url) != path(url.resolvingSymlinksInPath())
    }
    public static func isProtectedApplication(url: URL, bundleID: String, ownURL: URL?, ownID: String?) -> Bool {
        bundleID.hasPrefix("com.apple.") || bundleID == ownID ||
        contains(URL(fileURLWithPath: "/System"), url) ||
        (ownURL.map { contains($0, url) || contains(url, $0) } ?? false)
    }
    public static func isSafe(_ url: URL, app: URL, roots: [URL]) -> Bool {
        guard url.isFileURL, !hasSymlink(url), path(url) != "/" else { return false }
        if path(url) == path(app) { return true }
        return roots.contains { path($0) != path(url) && contains($0, url) }
    }
}
