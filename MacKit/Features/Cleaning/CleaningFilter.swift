import AppKit

final class CleaningFilter: @unchecked Sendable {
    private let lock = NSLock()
    private var sequence = EscapeSequence()
    private var heartbeat = ProcessInfo.processInfo.systemUptime
    private var active = true
    private let progress: @Sendable (Int, Bool) -> Void

    init(progress: @escaping @Sendable (Int, Bool) -> Void) { self.progress = progress }
    func beat() { lock.withLock { heartbeat = ProcessInfo.processInfo.systemUptime } }
    func deactivate() { lock.withLock { active = false } }
    func isHealthy() -> Bool {
        lock.withLock { active && ProcessInfo.processInfo.systemUptime - heartbeat < 3 }
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let result: (Bool, Int?, Bool) = lock.withLock {
            guard active, ProcessInfo.processInfo.systemUptime - heartbeat < 3 else {
                active = false
                return (false, nil, false)
            }
            let before = sequence.count
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let now = ProcessInfo.processInfo.systemUptime
            var done = false
            if type == .keyDown {
                let modified = !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty
                sequence.keyDown(code: code, repeating: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                                 modified: modified, time: now)
            } else if type == .keyUp {
                done = sequence.keyUp(code: code, time: now)
            } else if type == .flagsChanged || type.rawValue == NSEvent.EventType.systemDefined.rawValue {
                sequence.reset()
            }
            return (true, sequence.count != before ? sequence.count : nil, done)
        }
        if let count = result.1 { progress(count, result.2) }
        return result.0 ? nil : Unmanaged.passUnretained(event)
    }

    static var eventMask: CGEventMask {
        let types: [UInt32] = [
            CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue, CGEventType.flagsChanged.rawValue,
            CGEventType.mouseMoved.rawValue, CGEventType.leftMouseDown.rawValue, CGEventType.leftMouseUp.rawValue,
            CGEventType.rightMouseDown.rawValue, CGEventType.rightMouseUp.rawValue,
            CGEventType.otherMouseDown.rawValue, CGEventType.otherMouseUp.rawValue,
            CGEventType.leftMouseDragged.rawValue, CGEventType.rightMouseDragged.rawValue,
            CGEventType.otherMouseDragged.rawValue, CGEventType.scrollWheel.rawValue,
            UInt32(NSEvent.EventType.systemDefined.rawValue), UInt32(NSEvent.EventType.gesture.rawValue),
            UInt32(NSEvent.EventType.magnify.rawValue), UInt32(NSEvent.EventType.swipe.rawValue),
            UInt32(NSEvent.EventType.rotate.rawValue), UInt32(NSEvent.EventType.beginGesture.rawValue),
            UInt32(NSEvent.EventType.endGesture.rawValue), UInt32(NSEvent.EventType.smartMagnify.rawValue),
            UInt32(NSEvent.EventType.pressure.rawValue)
        ]
        return types.filter { $0 < 64 }.reduce(0) { $0 | (UInt64(1) << $1) }
    }
}
