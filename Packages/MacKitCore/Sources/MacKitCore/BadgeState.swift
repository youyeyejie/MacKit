import Foundation
import Dispatch
import Darwin

public struct BadgeState: Codable, Sendable, Equatable {
    public let version: Int
    public let sessionID: UUID
    public let paths: [String]
    public let expiresAt: Date
    public init(sessionID: UUID = UUID(), paths: [String] = [], expiresAt: Date = Date()) {
        version = 1; self.sessionID = sessionID; self.paths = paths; self.expiresAt = expiresAt
    }
    public func validPaths(now: Date = Date()) -> Set<String> {
        guard version == 1, expiresAt > now else { return [] }
        return Set(paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
    }
}

public enum BadgeStore {
    public static let notification = "com.mackit.badges.changed"
    public static func fileURL() -> URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              !group.hasPrefix("."), !group.contains("$("),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return container.appendingPathComponent("cut-state.json")
    }
    public static func read() -> BadgeState? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url), data.count < 1_000_000 else { return nil }
        return try? JSONDecoder().decode(BadgeState.self, from: data)
    }
    public static func write(_ state: BadgeState) throws {
        guard let url = fileURL() else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}

/// Watches the containing directory, since atomic JSON writes replace the file inode.
/// Event-driven: no polling or filesystem tree traversal in the extension.
public final class BadgeDirectoryWatcher: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject
    public init(directory: URL, changed: @escaping @Sendable () -> Void) throws {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler(handler: changed)
        source.setCancelHandler { close(fd) }
        source.resume()
    }
    deinit { source.cancel() }
}

public struct BadgeReceipt: Codable, Sendable {
    public let sessionID: UUID
    public let pathCount: Int
    public let badgeRequests: Int
    public let updatedAt: Date
    public init(sessionID: UUID, pathCount: Int, badgeRequests: Int) {
        self.sessionID = sessionID; self.pathCount = pathCount
        self.badgeRequests = badgeRequests; updatedAt = Date()
    }
    public static func read() -> BadgeReceipt? {
        guard let root = BadgeStore.fileURL()?.deletingLastPathComponent(),
              let data = try? Data(contentsOf: root.appendingPathComponent("badge-receipt.json")), data.count < 4096 else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    public func write() {
        guard let root = BadgeStore.fileURL()?.deletingLastPathComponent(), let data = try? JSONEncoder().encode(self) else { return }
        // Open/save panels have their own extension instance. Do not let their
        // idle receipts erase a response already observed for this same session.
        if let previous = Self.read(), previous.sessionID == sessionID,
           previous.pathCount == pathCount, previous.badgeRequests > badgeRequests { return }
        try? data.write(to: root.appendingPathComponent("badge-receipt.json"), options: .atomic)
    }
}
