import Foundation
import Testing
@testable import MacKitCore

@Test func clipboardOwnershipAndExpiry() {
    let urls = [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")]
    let time = Date(timeIntervalSince1970: 1000)
    let session = CutSession(urls: urls, changeCount: 12, now: time)
    #expect(session.matches(urls: urls.reversed(), changeCount: 12, now: time))
    #expect(!session.matches(urls: urls, changeCount: 13, now: time))
    #expect(!session.matches(urls: [urls[0]], changeCount: 12, now: time))
    #expect(!session.matches(urls: urls, changeCount: 12, now: time.addingTimeInterval(601)))
}

@Test func expiredBadgesDisappear() throws {
    let state = BadgeState(paths: ["/tmp/a", "relative"], expiresAt: Date(timeIntervalSince1970: 200))
    #expect(state.validPaths(now: Date(timeIntervalSince1970: 100)) == ["/tmp/a"])
    #expect(state.validPaths(now: Date(timeIntervalSince1970: 201)).isEmpty)
    let decoded = try JSONDecoder().decode(BadgeState.self, from: JSONEncoder().encode(state))
    #expect(decoded.sessionID == state.sessionID)
}
