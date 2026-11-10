import AppKit

// Native menu items use the NSImage's intrinsic size, not only SwiftUI's frame.
func compactMenuIcon(_ image: NSImage, size: CGFloat) -> NSImage {
    let result = NSImage(size: NSSize(width: size, height: size))
    result.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
    result.unlockFocus()
    return result
}
