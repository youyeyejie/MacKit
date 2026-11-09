// MacKit black-background contrast, GPL-3.0-or-later. Modified 2026-11-08.
import AppKit
import SwiftUI

extension Color {
    func readableOnBlack() -> Color {
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let rgb = (NSColor(self).usingColorSpace(.sRGB) ?? white).withAlphaComponent(1)
        func luminance(_ c: NSColor) -> Double {
            func linear(_ v: CGFloat) -> Double { v <= 0.04045 ? Double(v) / 12.92 : pow((Double(v) + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
        }
        if luminance(rgb) >= 0.175 { return Color(nsColor: rgb) }
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<10 {
            let amount = (low + high) / 2
            let candidate = rgb.blended(withFraction: amount, of: .white) ?? .white
            if luminance(candidate) >= 0.175 { high = amount } else { low = amount }
        }
        return Color(nsColor: rgb.blended(withFraction: high, of: .white) ?? .white)
    }
}
