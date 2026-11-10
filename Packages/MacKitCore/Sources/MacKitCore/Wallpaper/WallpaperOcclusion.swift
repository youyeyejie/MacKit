import CoreGraphics

enum WallpaperOcclusion {
    /// Subtract opaque window rectangles without double-counting overlaps.
    static func covered(display: CGRect, windows: [CGRect]) -> Bool {
        guard display.width > 0, display.height > 0 else { return false }
        var remaining = [display]
        for window in windows {
            var next: [CGRect] = []
            for rect in remaining {
                let hit = rect.intersection(window)
                if hit.isNull || hit.isEmpty {
                    next.append(rect)
                    continue
                }
                if hit.minY > rect.minY {
                    next.append(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: hit.minY - rect.minY))
                }
                if hit.maxY < rect.maxY {
                    next.append(CGRect(x: rect.minX, y: hit.maxY, width: rect.width, height: rect.maxY - hit.maxY))
                }
                if hit.minX > rect.minX {
                    next.append(CGRect(x: rect.minX, y: hit.minY, width: hit.minX - rect.minX, height: hit.height))
                }
                if hit.maxX < rect.maxX {
                    next.append(CGRect(x: hit.maxX, y: hit.minY, width: rect.maxX - hit.maxX, height: hit.height))
                }
            }
            remaining = next
            if remaining.isEmpty { return true }
            // Avoid pathological fragmented window lists.
            if remaining.count > 512 { return false }
        }
        let uncovered = remaining.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
        return uncovered / (display.width * display.height) < 0.10
    }
}
