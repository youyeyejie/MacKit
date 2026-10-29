import Foundation
import CoreGraphics

/// Coordinate-independent Dock layout and pointer routing.
enum DockEdge: String, Sendable { case bottom, left, right }

enum DockGeometry {
    static func panel(anchor: CGRect, size: CGSize, screen: CGRect, edge: DockEdge) -> CGRect {
        let padding: CGFloat = 8
        let width = min(size.width, max(1, screen.width - padding * 2))
        let height = min(size.height, max(1, screen.height - padding * 2))
        var origin: CGPoint
        switch edge {
        case .bottom: origin = CGPoint(x: anchor.midX - width / 2, y: anchor.maxY + 6)
        case .left: origin = CGPoint(x: anchor.maxX + 6, y: anchor.midY - height / 2)
        case .right: origin = CGPoint(x: anchor.minX - width - 6, y: anchor.midY - height / 2)
        }
        origin.x = min(max(screen.minX + padding, origin.x), max(screen.minX + padding, screen.maxX - width - padding))
        origin.y = min(max(screen.minY + padding, origin.y), max(screen.minY + padding, screen.maxY - height - padding))
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    /// A narrow bridge permits travel from the icon into the preview without
    /// keeping a large unrelated portion of the desktop active.
    static func openingPath(_ point: CGPoint, icon: CGRect, panel: CGRect, edge: DockEdge) -> Bool {
        let bridge: CGRect
        switch edge {
        case .bottom:
            bridge = CGRect(x: icon.minX - 12, y: min(icon.maxY, panel.minY),
                            width: icon.width + 24, height: abs(panel.minY - icon.maxY))
        case .left:
            bridge = CGRect(x: min(icon.maxX, panel.minX), y: icon.minY - 12,
                            width: abs(panel.minX - icon.maxX), height: icon.height + 24)
        case .right:
            bridge = CGRect(x: min(panel.maxX, icon.minX), y: icon.minY - 12,
                            width: abs(icon.minX - panel.maxX), height: icon.height + 24)
        }
        return icon.insetBy(dx: -6, dy: -6).contains(point) || bridge.contains(point)
    }

    static func isDrag(from origin: CGPoint, to point: CGPoint) -> Bool {
        hypot(point.x - origin.x, point.y - origin.y) > 6
    }
}
