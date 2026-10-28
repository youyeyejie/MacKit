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
