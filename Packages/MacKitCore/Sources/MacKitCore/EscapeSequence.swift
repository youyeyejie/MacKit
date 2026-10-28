import Foundation

/// Counts complete, unmodified key strokes; auto-repeat cannot unlock cleaning.
public struct EscapeSequence: Sendable {
    public private(set) var count = 0
    private var pressed = false
    private var lastRelease: TimeInterval?
    public let required: Int
    public let interval: TimeInterval

    public init(required: Int = 5, interval: TimeInterval = 3) {
        self.required = required
        self.interval = interval
    }

    public mutating func reset() { count = 0; pressed = false; lastRelease = nil }

    public mutating func keyDown(code: Int64, repeating: Bool, modified: Bool, time: TimeInterval) {
        guard code == 53, !modified else { reset(); return }
        guard !repeating, !pressed else { return }
        if let lastRelease, time - lastRelease > interval { count = 0 }
        pressed = true
    }

    @discardableResult
    public mutating func keyUp(code: Int64, time: TimeInterval) -> Bool {
        guard code == 53, pressed else { return false }
        pressed = false
        count += 1
        lastRelease = time
        return count >= required
    }
}
