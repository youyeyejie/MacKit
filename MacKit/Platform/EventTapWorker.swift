import Foundation
import CoreGraphics

/// One dedicated run loop per active filter. Never dispatch synchronously to UI.
final class EventTapWorker: @unchecked Sendable {
    typealias Handler = @Sendable (CGEventType, CGEvent) -> Unmanaged<CGEvent>?
    private let lock = NSLock()
    private var runLoop: CFRunLoop?
    private var stopped = false
    private var ready = false
    private let mask: CGEventMask
    private let handler: Handler
    private let healthy: (@Sendable () -> Bool)?
    private let failed: @Sendable () -> Void

    init(mask: CGEventMask, healthy: (@Sendable () -> Bool)? = nil,
         failed: @escaping @Sendable () -> Void, handler: @escaping Handler) {
        self.mask = mask; self.handler = handler; self.healthy = healthy; self.failed = failed
    }

    func start() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                              options: .defaultTap, eventsOfInterest: mask,
                                              callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let worker = Unmanaged<EventTapWorker>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    worker.failed(); worker.stop()
                    return Unmanaged.passUnretained(event)
                }
                return worker.handler(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                semaphore.signal(); return
            }
            let loop = CFRunLoopGetCurrent()!
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)!
            CFRunLoopAddSource(loop, source, .commonModes)
            // This watchdog runs independently of the main thread.
            var timer: CFRunLoopTimer?
            if let healthy {
                timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 0.5, 0.5, 0, 0) { [self] _ in
                    if !healthy() { failed(); stop() }
                }
                CFRunLoopAddTimer(loop, timer, .commonModes)
            }
            let shouldRun = lock.withLock {
                runLoop = loop; ready = !stopped; return !stopped
            }
            CGEvent.tapEnable(tap: tap, enable: shouldRun)
            semaphore.signal()
            if shouldRun { CFRunLoopRun() }
            CGEvent.tapEnable(tap: tap, enable: false)
            if let timer { CFRunLoopTimerInvalidate(timer) }
            CFRunLoopSourceInvalidate(source)
            CFMachPortInvalidate(tap)
            lock.withLock { runLoop = nil; ready = false }
        }
        thread.name = "MacKit.InputFilter"
        thread.qualityOfService = .userInteractive
        thread.start()
        guard semaphore.wait(timeout: .now() + 2) == .success else { stop(); return false }
        return lock.withLock { ready }
    }

    func stop() {
        let loop = lock.withLock { stopped = true; return runLoop }
        if let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(loop) }
            CFRunLoopWakeUp(loop)
        }
    }
}
