// MacKit activity presentation, GPL-3.0-or-later. Modified 2026-11-08.
import SwiftUI
struct PersistentActivityItem: Identifiable {
    let id: String
    let symbol: String
    let color: Color
}
struct PersistentActivityIcons: View {
    let items: [PersistentActivityItem]
    let diameter: CGFloat
    var compact = false
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Image(systemName: item.symbol)
                    .font(.system(size: compact ? max(10, diameter * 0.7) : 16, weight: .semibold))
                    .foregroundStyle(item.color)
                    .frame(width: diameter, height: diameter)
                    .background(compact ? Color.clear : .black, in: Circle())
                    .accessibilityLabel(item.id)
            }
        }.fixedSize().allowsHitTesting(false)
    }
}
