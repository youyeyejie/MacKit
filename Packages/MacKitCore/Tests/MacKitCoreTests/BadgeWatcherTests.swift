import Foundation
import Testing
@testable import MacKitCore

@Test func directoryWatcherSurvivesAtomicStateReplacement() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacKitBadgeTest-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("state.json")
    let (events, continuation) = AsyncStream<Void>.makeStream()
    let watcher = try BadgeDirectoryWatcher(directory: root) { continuation.yield(()) }
    defer { withExtendedLifetime(watcher) {}; continuation.finish() }
    let received = Task {
        var iterator = events.makeAsyncIterator()
        guard await iterator.next() != nil else { return false }
        // An atomic write replaces the inode. The second update must still arrive.
        try Data("second".utf8).write(to: file, options: .atomic)
        return await iterator.next() != nil
    }
    try Data("first".utf8).write(to: file, options: .atomic)
    let timeout = Task {
        try await Task.sleep(for: .seconds(3))
        continuation.finish()
    }
    let result = try await received.value
    timeout.cancel()
    #expect(result)
    #expect(try String(contentsOf: file, encoding: .utf8) == "second")
}

@Test func stoppedOwnerInvalidatesUnexpiredBadges() throws {
    let state = BadgeState(paths: ["/tmp/example"], expiresAt: Date().addingTimeInterval(600), ownerRunning: false)
    #expect(state.validPaths().isEmpty)
    let decoded = try JSONDecoder().decode(BadgeState.self, from: JSONEncoder().encode(state))
    #expect(decoded.ownerRunning == false)
    #expect(decoded.validPaths().isEmpty)
}

@Test func legacyBadgeStateRemainsReadable() throws {
    let state = BadgeState(paths: ["/tmp/example"], expiresAt: Date().addingTimeInterval(600))
    var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    payload.removeValue(forKey: "ownerRunning")
    let decoded = try JSONDecoder().decode(BadgeState.self, from: JSONSerialization.data(withJSONObject: payload))
    #expect(decoded.ownerRunning == nil)
    #expect(decoded.validPaths().contains("/tmp/example"))
}
