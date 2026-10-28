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
    #expect(report.items.contains { $0.url == named && $0.removable && !$0.suggested })
    let chosen = try RemovalPlan(report: report, selected: [named.path])
    #expect(chosen.items.count == 1)
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

@Test func nestedVendorDataIsFoundWithoutSelectingVendorRoot() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let vendor = fixture.root.appendingPathComponent("Library/Application Support/Vendor")
    let data = vendor.appendingPathComponent("Sample")
    let other = vendor.appendingPathComponent("OtherProduct")
    try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    let report = try fixture.scan()
    #expect(report.items.contains { $0.id == data.path && !$0.suggested })
    #expect(!report.items.contains { $0.id == vendor.path || $0.id == other.path })
}

@Test func dotDirectoryNeedsExplicitSelectionAndStillChecksIdentity() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let hidden = fixture.root.appendingPathComponent(".sample")
    try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
    let report = try fixture.scan()
    #expect(report.items.contains { $0.id == hidden.path && !$0.suggested })
    let plan = try RemovalPlan(report: report, selected: [hidden.path])
    try plan.validate(plan.items[0])
    #expect(!PathPolicy.isSafe(fixture.root, app: fixture.app, roots: report.allowedRoots, explicit: report.explicitPaths))
}

@Test func userAgentMatchedThroughExecutablePath() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let agents = fixture.root.appendingPathComponent("Library/LaunchAgents")
    try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
    let agent = agents.appendingPathComponent("vendor-startup.plist")
    let plist: [String: Any] = ["Label": "dev.mackit.test-agent", "ProgramArguments": [fixture.app.appendingPathComponent("Contents/MacOS/Sample").path]]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agent)
    let report = try fixture.scan()
    #expect(report.items.contains { $0.id == agent.path && $0.removable && $0.serviceLabel == "dev.mackit.test-agent" && !$0.suggested })
}

@Test func containerMetadataFindsOpaqueContainerName() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let container = fixture.root.appendingPathComponent("Library/Containers/opaque-uuid")
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(fromPropertyList: ["MCMMetadataIdentifier": "com.example.Sample"], format: .binary, options: 0)
    try data.write(to: container.appendingPathComponent(".com.apple.containermanagerd.metadata.plist"))
    let report = try fixture.scan()
    #expect(report.items.contains { $0.id == container.path && $0.association == .exact && !$0.suggested })
}

@Test func backgroundInventoryOnlyMatchesOwnedIdentifiersOrPaths() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let app = try fixture.scan().app
    let text = """
    #1:
    UUID: first
    Name: Sample Startup
    Identifier: com.example.Sample
    URL: file:///Applications/Sample.app/
    #2:
    UUID: second
    Name: Sample Other
    Identifier: com.example.SampleOther
    URL: file:///Applications/Other.app/
    """
    let matches = SystemInventory.backgroundRecords(text, app: app)
    #expect(matches.count == 1)
    #expect(matches[0].0 == "Sample Startup")
}

@Test func permissionResetRejectsUnrelatedAndSystemIDsWithoutExecuting() {
    #expect(throws: UninstallError.self) { try SystemCleanup.resetPermissions(bundleID: "com.apple.finder", allowedIDs: ["com.apple.finder"]) }
    #expect(throws: UninstallError.self) { try SystemCleanup.resetPermissions(bundleID: "com.other.App", allowedIDs: ["com.example.Sample"]) }
}

@Test func identifierBoundaryAndNameNormalization() {
    #expect(AssociationMatcher.match(name: "com.example.SampleOther", ids: ["com.example.Sample"], aliases: []) == nil)
    #expect(AssociationMatcher.match(name: "com.example.Sample.helper", ids: ["com.example.Sample"], aliases: []) == .related)
    #expect(AssociationMatcher.match(name: "Sample-App", ids: [], aliases: ["Sample App"]) == .name)
    #expect(AssociationMatcher.match(name: "Electron", ids: [], aliases: ["Electron"]) == nil)
}
