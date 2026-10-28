import Foundation

public struct CutSession: Sendable {
    public let id: UUID
    public let urls: [URL]
    public let changeCount: Int
    public let createdAt: Date

    public init(urls: [URL], changeCount: Int, now: Date = Date()) {
        id = UUID(); self.urls = urls; self.changeCount = changeCount; createdAt = now
    }

    public func matches(urls: [URL], changeCount: Int, now: Date = Date()) -> Bool {
        !self.urls.isEmpty && self.changeCount == changeCount && now.timeIntervalSince(createdAt) < 600 &&
            Set(self.urls.map(\.standardizedFileURL)) == Set(urls.map(\.standardizedFileURL))
    }
}
