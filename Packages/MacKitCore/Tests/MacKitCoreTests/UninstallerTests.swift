import Foundation
import Testing
@testable import MacKitCore

private struct Fixture {
    let root: URL
    let app: URL
    let cache: URL
    init(bundleID: String = "com.example.Sample") throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MacKitTests-" + UUID().uuidString)
        app = root.appendingPathComponent("Applications/Sample.app")
        cache = root.appendingPathComponent("Library/Caches/" + bundleID)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": "Sample", "CFBundlePackageType": "APPL", "CFBundleVersion": "1"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data("test cache".utf8).write(to: cache.appendingPathComponent("data"))
    }
    func scan() throws -> ScanReport {
        try AppScanner(home: root, ownURL: nil, ownID: "com.mackit.app", includeSystemLibrary: false).scan(app)
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test func scanUsesExactIdentityAndPreservesSimilarNames() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let similar = fixture.root.appendingPathComponent("Library/Caches/com.example.SampleOther")
    try FileManager.default.createDirectory(at: similar, withIntermediateDirectories: true)
    let named = fixture.root.appendingPathComponent("Library/Application Support/Sample")
    try FileManager.default.createDirectory(at: named, withIntermediateDirectories: true)
    let report = try fixture.scan()
    #expect(report.items.contains { $0.url == fixture.cache && $0.suggested })
    #expect(!report.items.contains { $0.url == similar })
    #expect(report.items.contains { $0.url == named && !$0.removable && !$0.suggested })
    #expect(throws: UninstallError.self) { try RemovalPlan(report: report, selected: [named.path]) }
}

@Test func systemApplicationsAreProtected() throws {
    let fixture = try Fixture(bundleID: "com.apple.Sample"); defer { fixture.clean() }
    #expect(throws: UninstallError.self) { try fixture.scan() }
}

@Test func symlinkCandidateIsExcluded() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let target = fixture.root.appendingPathComponent("important")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let preferences = fixture.root.appendingPathComponent("Library/Preferences")
    try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
    let link = preferences.appendingPathComponent("com.example.Sample.plist")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let report = try fixture.scan()
    #expect(!report.items.contains { $0.url == link })
    #expect(report.warnings.contains { $0.contains("符号链接") })
}

@Test func replacementAfterScanIsRejected() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let report = try fixture.scan()
    let plan = try RemovalPlan(report: report, selected: [fixture.cache.path])
    try FileManager.default.moveItem(at: fixture.cache, to: fixture.root.appendingPathComponent("original-cache"))
    try FileManager.default.createDirectory(at: fixture.cache, withIntermediateDirectories: true)
    #expect(throws: UninstallError.self) { try plan.validate(plan.items[0]) }
}

@Test func pathBoundariesAndRootsAreProtected() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let root = fixture.root.appendingPathComponent("Library/Caches")
    #expect(!PathPolicy.isSafe(root, app: fixture.app, roots: [root]))
    #expect(!PathPolicy.isSafe(fixture.root.appendingPathComponent("Library/CachesOther/data"), app: fixture.app, roots: [root]))
    #expect(PathPolicy.isSafe(fixture.cache, app: fixture.app, roots: [root]))
}

@Test func removalReportsPartialFailureAndKeepsAppUntilLast() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let report = try fixture.scan()
    let plan = try RemovalPlan(report: report, selected: Set(report.items.filter(\.suggested).map(\.id)))
    #expect(plan.items.last?.url == fixture.app)
    let trashRoot = fixture.root.appendingPathComponent("FakeTrash")
    try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
    let cache = fixture.cache
    let result = try RemovalExecutor.execute(plan, trash: { url in
        if url == cache { throw CocoaError(.fileWriteNoPermission) }
        let target = trashRoot.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: target)
        return target
    })
    #expect(result.count == 2)
    #expect(result.filter(\.succeeded).count == 1)
    #expect(FileManager.default.fileExists(atPath: cache.path))
    #expect(FileManager.default.fileExists(atPath: trashRoot.appendingPathComponent("Sample.app").path))
}

@Test func cancelledScanDoesNotTouchFiles() async throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let task = Task.detached {
        while !Task.isCancelled { await Task.yield() }
        return try fixture.scan()
    }
    task.cancel()
    do { _ = try await task.value; Issue.record("Scan should be cancelled") }
    catch is CancellationError { }
    #expect(FileManager.default.fileExists(atPath: fixture.app.path))
    #expect(FileManager.default.fileExists(atPath: fixture.cache.path))
}
