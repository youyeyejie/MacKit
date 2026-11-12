import AppKit
import SwiftUI

enum NotchSwipeDirection {
    case down
    case left
    case right
}

/// Observes trackpad scrolling only while the pointer is inside this view.
struct NotchScrollGesture: NSViewRepresentable {
    var onHorizontalDrag: ((CGFloat) -> Void)? = nil
    var onSwipe: (NotchSwipeDirection) -> Bool

    func makeNSView(context: Context) -> GestureView {
        let view = GestureView()
        view.onHorizontalDrag = onHorizontalDrag
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ nsView: GestureView, context: Context) {
        nsView.onHorizontalDrag = onHorizontalDrag
        nsView.onSwipe = onSwipe
    }

    static func dismantleNSView(_ nsView: GestureView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class GestureView: NSView {
        var onHorizontalDrag: ((CGFloat) -> Void)?
        var onSwipe: ((NotchSwipeDirection) -> Bool)?
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var delta = CGPoint.zero
        private var fired = false
        private var horizontalPeak: CGFloat = 0
        private var horizontalCancelled = false
        private var lastEventTime: TimeInterval = 0

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event) == true ? nil : event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
            }
        }

        func stopMonitoring() {
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            localMonitor = nil
            globalMonitor = nil
            delta = .zero
            horizontalPeak = 0
            horizontalCancelled = false
            fired = false
        }

        @discardableResult
        private func handle(_ event: NSEvent) -> Bool {
            if event.phase.contains(.cancelled) || !event.momentumPhase.isEmpty {
                delta = .zero
                horizontalPeak = 0
                horizontalCancelled = false
                fired = false
                onHorizontalDrag?(0)
                return false
            }
            guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty,
                  let window, window.isVisible, window.alphaValue > 0,
                  window.convertToScreen(convert(bounds, to: nil)).insetBy(dx: 0, dy: -1).contains(NSEvent.mouseLocation)
            else {
                delta = .zero
                horizontalPeak = 0
                horizontalCancelled = false
                fired = false
                onHorizontalDrag?(0)
                return false
            }

            if event.phase.contains(.began) || (event.phase.isEmpty && event.timestamp - lastEventTime > 0.3) {
                delta = .zero
                horizontalPeak = 0
                horizontalCancelled = false
                fired = false
            }
            lastEventTime = event.timestamp

            // Normalize to finger motion regardless of Natural Scrolling.
            let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            delta.x += event.scrollingDeltaX * sign
            delta.y += event.scrollingDeltaY * sign
            if !horizontalCancelled {
                if horizontalPeak == 0 {
                    if abs(delta.x) >= 4 && abs(delta.x) > abs(delta.y) * 1.3 {
                        horizontalPeak = delta.x
                    }
                } else {
                    // Ignore tiny trackpad jitter, then latch cancellation for
                    // the rest of this gesture as soon as the finger reverses.
                    let reversedDistance = horizontalPeak < 0
                        ? delta.x - horizontalPeak : horizontalPeak - delta.x
                    horizontalCancelled = reversedDistance >= 3
                    if !horizontalCancelled && abs(delta.x) > abs(horizontalPeak) {
                        horizontalPeak = delta.x
                    }
                }
            }
            if event.phase.contains(.ended) {
                let shouldChangeTrack = !fired && !horizontalCancelled
                    && abs(delta.x) >= 30 && abs(delta.x) > abs(delta.y) * 1.3
                let direction: NotchSwipeDirection = delta.x < 0 ? .left : .right
                delta = .zero
                horizontalPeak = 0
                horizontalCancelled = false
                fired = false
                onHorizontalDrag?(0)
                return shouldChangeTrack ? (onSwipe?(direction) ?? false) : false
            }

            onHorizontalDrag?(abs(delta.x) > abs(delta.y) * 1.3 ? delta.x : 0)
            guard !fired, delta.y >= 30, delta.y > abs(delta.x) * 1.3 else { return false }
            fired = true
            return onSwipe?(.down) ?? false
        }
    }
}
