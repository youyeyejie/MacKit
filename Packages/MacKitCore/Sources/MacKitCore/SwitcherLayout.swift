import Foundation
import CoreGraphics

enum SwitcherLayout {
    static func columns(count: Int, available: CGSize, targetAspect: CGFloat) -> Int {
        let maximum = max(1, min(count, Int((available.width - 100) / 224)))
        let target = max(0.1, targetAspect)
        return (1...maximum).min { score($0) < score($1) } ?? 1
        func score(_ columns: Int) -> Double {
            let rows = (max(count, 1) + columns - 1) / columns
            let height = min(max(1, available.height - 80), CGFloat(rows) * 184 + 64)
            let ratio = (CGFloat(columns) * 224 + 32) / height
            let vacancies = Double(rows * columns - max(count, 1)) / Double(max(count, 1))
            return abs(log(Double(ratio / target))) + vacancies * 0.12
        }
    }
}
