import Foundation

/// A successful AX answer is authoritative, including an empty window array.
/// CG can retain closed backing surfaces; only live onscreen surfaces are a
/// fallback when Accessibility could not answer at all.
enum WindowPresence {
    static func orderGroup(windowless: Bool, minimized: Bool) -> Int {
        windowless ? 2 : (minimized ? 1 : 0)
    }

    static func permitsSurface(axAnswered: Bool, onScreen: Bool, hasTitle: Bool) -> Bool {
        !axAnswered && onScreen && hasTitle
    }
}
