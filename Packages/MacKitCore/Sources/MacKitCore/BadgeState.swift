import Foundation

public struct BadgeState: Codable, Sendable {
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
