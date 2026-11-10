// MacKit feature reduction, modified 2026-11-08.
// See THIRD_PARTY_NOTICES.md; GPL-3.0-or-later.
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

import Defaults
import SwiftUI

struct DynamicIslandHeader: View {
    var indicators: [PersistentActivityItem] = []
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    private let showBatteryIndicator = NotchConfiguration.showBatteryIndicator
    @Default(.showBatteryPercentInside) var showBatteryPercentInside
    private let enableMinimalisticUI = NotchConfiguration.enableMinimalisticUI

    var body: some View {
        HStack(spacing: 0) {
            HStack {

                let shouldShowTabs = coordinator.alwaysShowTabs || vm.notchState == .open || !shelfState.items.isEmpty
                if shouldShowTabs {
                    TabSelectionView()
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
            .padding(8)

            if vm.notchState == .open {
                let spacerWidth = min(vm.closedNotchSize.width, 300)
                Rectangle()
                    .fill(
                        enableMinimalisticUI
                            ? .clear
                            : (NSScreen.screens
                                .first(where: { $0.localizedName == coordinator.selectedScreen })?.safeAreaInsets.top
                                ?? 0 > 0 ? .black : .clear)
                    )
                    .frame(width: spacerWidth)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open && !enableMinimalisticUI {

                    ForEach(indicators.filter { $0.id != "shelf" }) { item in
                        Image(systemName: item.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(item.color)
                            .frame(width: 26, height: 30)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                    Button { SettingsWindowController.shared.showWindow() } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).help("设置")

                }

            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)

    }
}
