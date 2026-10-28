import CoreGraphics
import Foundation

final class FinderKeyFilter: @unchecked Sendable {
    static let marker: Int64 = 0x4D4B435554
    private let lock = NSLock()
    private var swallowed: Set<Int64> = []
    private var pendingCut = false
    private var busy = false
    private let action: @Sendable (Int64, UInt64) -> Void
    init(action: @escaping @Sendable (Int64, UInt64) -> Void) { self.action = action }
    func update(pending: Bool, busy: Bool) { lock.withLock { pendingCut = pending; self.busy = busy } }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return Unmanaged.passUnretained(event) }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        var notify = false
        let consume = lock.withLock {
            if type == .keyUp { return swallowed.remove(key) != nil }
            guard type == .keyDown else { return false }
            let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            let candidate = (flags == .maskCommand && (key == 7 || (key == 9 && pendingCut))) ||
                (flags.isEmpty && key == 53 && pendingCut)
            guard candidate else { return swallowed.contains(key) }
            swallowed.insert(key)
            if !busy, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { busy = true; notify = true }
            return true
        }
        if notify { action(key, event.flags.rawValue) }
        return consume ? nil : Unmanaged.passUnretained(event)
    }
}
