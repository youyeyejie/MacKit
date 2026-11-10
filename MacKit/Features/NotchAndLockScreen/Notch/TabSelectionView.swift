import Defaults
// MacKit feature reduction, modified 2026-11-08.
// See THIRD_PARTY_NOTICES.md; GPL-3.0-or-later.
// MacKit adaptation, 2026-11-08; derived from Atoll, GPL-3.0-or-later.
import SwiftUI

struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    private let minimalistic = NotchConfiguration.enableMinimalisticUI
    @Default(.dynamicShelf) private var shelf
    @Default(.enableTerminalFeature) private var terminal
    @Namespace private var animation
    private var tabs: [(NotchViews, String, String)] {
        var result: [(NotchViews, String, String)] = [(.home, "主页", "house.fill")]
        if !minimalistic && shelf { result.append((.shelf, "文件托盘", "tray.fill")) }
        if !minimalistic && terminal { result.append((.terminal, "终端", "apple.terminal")) }
        return result
    }
    var body: some View {
        HStack(spacing: 24) {
            ForEach(tabs, id: \.0) { tab in
                TabButton(label: tab.1, icon: tab.2, selected: coordinator.currentView == tab.0) {
                    coordinator.currentView = tab.0
                }
                .frame(height: 26)
                .foregroundStyle(coordinator.currentView == tab.0 ? .white : .gray)
                .background {
                    if coordinator.currentView == tab.0 {
                        Capsule().fill(Color(nsColor: .secondarySystemFill).opacity(0.25))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: coordinator.currentView)
        .clipShape(Capsule())
        .onChange(of: shelf) { _, _ in validateSelection() }
        .onChange(of: terminal) { _, _ in validateSelection() }
        .onChange(of: minimalistic) { _, _ in validateSelection() }
        .onAppear { validateSelection() }
    }
    private func validateSelection() {
        if !tabs.contains(where: { $0.0 == coordinator.currentView }) { coordinator.currentView = .home }
    }
}
