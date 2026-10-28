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
