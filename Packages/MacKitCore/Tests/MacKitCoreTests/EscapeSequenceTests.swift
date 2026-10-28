import Testing
@testable import MacKitCore

@Test func fiveCompletePressesUnlock() {
    var sequence = EscapeSequence()
    for i in 0..<5 {
        sequence.keyDown(code: 53, repeating: false, modified: false, time: Double(i))
        #expect(sequence.keyUp(code: 53, time: Double(i) + 0.1) == (i == 4))
    }
}

@Test func repeatAndOrphanReleaseDoNotUnlock() {
    var sequence = EscapeSequence()
    #expect(!sequence.keyUp(code: 53, time: 0))
    sequence.keyDown(code: 53, repeating: false, modified: false, time: 1)
    for i in 0..<20 { sequence.keyDown(code: 53, repeating: true, modified: false, time: Double(i) + 1) }
    #expect(!sequence.keyUp(code: 53, time: 22))
    #expect(sequence.count == 1)
}

@Test func unrelatedKeysModifiersAndTimeoutReset() {
    var sequence = EscapeSequence()
    sequence.keyDown(code: 53, repeating: false, modified: false, time: 0)
    sequence.keyUp(code: 53, time: 0.1)
    sequence.keyDown(code: 53, repeating: false, modified: false, time: 5)
    sequence.keyUp(code: 53, time: 5.1)
    #expect(sequence.count == 1)
    sequence.keyDown(code: 0, repeating: false, modified: false, time: 6)
    #expect(sequence.count == 0)
    sequence.keyDown(code: 53, repeating: false, modified: true, time: 7)
    #expect(!sequence.keyUp(code: 53, time: 7.1))
}
