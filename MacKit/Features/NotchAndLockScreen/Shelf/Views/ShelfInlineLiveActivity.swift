/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI

/// Standalone inline HUD shown in the closed Dynamic Island when the
/// File Tray (Shelf) has items and no higher-priority live activity is active.
///
/// Layout mirrors the battery inline HUD:
///   [tray icon] ─── [ notch ] ─── [bold green count]
struct ShelfInlineLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var shelfState = ShelfStateViewModel.shared

    private let sideWidth: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {

            // LEFT of notch — tray icon (white, same style as the screenshot)
            Image(systemName: "tray.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: sideWidth, alignment: .leading)

            // Physical notch / pill space
            Rectangle()
                .fill(Color.black)
                .frame(width: vm.closedNotchSize.width)

            ShelfDocumentBadge(count: shelfState.items.count)
                .frame(width: sideWidth, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

/// A compact document outline with the file count printed inside its body.
struct ShelfDocumentBadge: View {
    let count: Int
    var height: CGFloat = 18
    static func width(for count: Int) -> CGFloat {
        max(15, CGFloat(String(count).count) * 6 + 6)
    }
    var body: some View {
        ZStack {
            ShelfCountDocumentShape()
                .stroke(.white, lineWidth: 1.2)
            Text("\(count)")
                .font(.system(size: height * (count < 100 ? 0.5 : 0.44), weight: .bold, design: .rounded))
                .monospacedDigit().foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 2).offset(y: 1)
                .contentTransition(.numericText())
        }
        .frame(width: height * 0.83, height: height)
        .animation(.smooth(duration: 0.25), value: count)
        .accessibilityLabel("文件托盘，\(count) 个文件")
    }
}

private struct ShelfCountDocumentShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: 0.8, dy: 0.8)
        let cut = min(inset.width, inset.height) * 0.24
        let vertices = [CGPoint(x: inset.minX, y: inset.minY),
                        CGPoint(x: inset.maxX - cut, y: inset.minY),
                        CGPoint(x: inset.maxX, y: inset.minY + cut),
                        CGPoint(x: inset.maxX, y: inset.maxY),
                        CGPoint(x: inset.minX, y: inset.maxY)]
        let radius = min(inset.width, inset.height) * 0.1
        var path = Path()
        for index in vertices.indices {
            let previous = vertices[(index + vertices.count - 1) % vertices.count]
            let corner = vertices[index]
            let next = vertices[(index + 1) % vertices.count]
            func insetPoint(toward point: CGPoint) -> CGPoint {
                let length = hypot(point.x - corner.x, point.y - corner.y)
                let ratio = min(radius, length / 3) / max(length, 0.01)
                return CGPoint(x: corner.x + (point.x - corner.x) * ratio,
                               y: corner.y + (point.y - corner.y) * ratio)
            }
            let start = insetPoint(toward: previous)
            let end = insetPoint(toward: next)
            if index == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: corner)
        }
        path.closeSubpath()
        return path
    }
}
