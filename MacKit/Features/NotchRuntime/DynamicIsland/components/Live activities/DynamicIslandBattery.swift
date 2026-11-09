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
import Defaults

/// A view that displays the battery status with an icon and charging indicator.
struct BatteryView: View {
    private let showPowerStatusIcons = NotchConfiguration.showPowerStatusIcons
    var levelBattery: Float
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var batteryWidth: CGFloat = 26
    var isForNotification: Bool
    var showPercentInside: Bool = false

    var animationStyle: DynamicIslandAnimations = DynamicIslandAnimations()

    var icon: String = "battery.0"

    /// Determines the icon to display when charging.
    var iconStatus: String {
        if isCharging {
            return "bolt"
        }
        else if isPluggedIn {
            return "plug"
        }
        else {
            return ""
        }
    }

    /// Determines the color of the battery based on its status.
    var batteryColor: Color {
        if isInLowPowerMode {
            return .yellow
        } else if levelBattery <= 20 && !isCharging && !isPluggedIn {
            return .red
        } else if isCharging || isPluggedIn || levelBattery == 100 {
            return .green
        } else {
            return .white
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {

            Image(systemName: icon)
                .resizable()
                .fontWeight(.thin)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white.opacity(0.5))
                .frame(
                    width: batteryWidth + 1
                )

            RoundedRectangle(cornerRadius: 2.5)
                .fill(batteryColor)
                .frame(
                    width: CGFloat(((CGFloat(CFloat(levelBattery)) / 100) * (batteryWidth - 6))),
                    height: (batteryWidth - 2.75) - 18
                )
                .padding(.leading, 2)

            if showPercentInside {
                let showsStatusGlyph = iconStatus != "" && (isForNotification || showPowerStatusIcons)
                let bodyHeight = (batteryWidth - 2.75) - 18
                let glyphColor: Color = isCharging ? .white : .black
                let statusSymbol: String? = {
                    guard showsStatusGlyph else { return nil }
                    if isCharging { return "bolt.fill" }
                    if isPluggedIn { return "powerplug.fill" }
                    return nil
                }()
                HStack(spacing: 0.5) {
                    Text("\(Int(levelBattery))")
                        .font(.system(size: batteryWidth * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(glyphColor)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if let statusSymbol {
                        Image(systemName: statusSymbol)
                            .font(.system(size: batteryWidth * 0.22, weight: .black))
                            .foregroundStyle(glyphColor)
                    }
                }
                .frame(width: batteryWidth - 7, height: bodyHeight, alignment: .center)
                .padding(.leading, 2)
            } else if iconStatus != "" && (isForNotification || showPowerStatusIcons) {
                ZStack {
                    Image(iconStatus)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                        .frame(
                            width: 17,
                            height: 17
                        )
                }
                .frame(width: batteryWidth, height: batteryWidth)
            }
        }
    }
}

/// Pill battery for the minimalist notch, matching the charging HUD style.


/// A view that displays detailed battery information and settings.
struct BatteryMenuView: View {
    
    var isPluggedIn: Bool
    var isCharging: Bool
    var levelBattery: Float
    var maxCapacity: Float
    var timeToFullCharge: Int
    var isInLowPowerMode: Bool
    var onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack {
                Text("Battery Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(Int(levelBattery))%")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Max Capacity: \(Int(maxCapacity))%")
                    .font(.subheadline)
                    .fontWeight(.regular)
                if isInLowPowerMode {
                    Label("Low Power Mode", systemImage: "bolt.circle")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if isCharging {
                    Label("Charging", systemImage: "bolt.fill")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if isPluggedIn {
                    Label("Plugged In", systemImage: "powerplug.fill")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if timeToFullCharge > 0 {
                    Label("Time to Full Charge: \(timeToFullCharge) min", systemImage: "clock")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if !isCharging && isPluggedIn && levelBattery >= 80 {
                    Label("Charging on Hold: Desktop Mode", systemImage: "desktopcomputer")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                    
            }
            .padding(.vertical, 8)

            Divider().background(Color.white)

            Button(action: openBatteryPreferences) {
                Label("Battery Settings", systemImage: "gearshape")
                    .fontWeight(.regular)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
        .padding()
        .frame(width: 280)
        .foregroundColor(.white)
    }

    private func openBatteryPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            openURL(url)
            onDismiss()
        }
    }
}


/// A view that displays the battery status and allows interaction to show detailed information.
struct DynamicIslandBatteryView: View {
    
    private let showBatteryPercentage = NotchConfiguration.showBatteryPercentage
    @State var batteryWidth: CGFloat = 26
    var isCharging: Bool = false
    var isInLowPowerMode: Bool = false
    var isPluggedIn: Bool = false
    var levelBattery: Float = 0
    var maxCapacity: Float = 0
    var timeToFullCharge: Int = 0
    @State var isForNotification: Bool = false
    
    @State private var showPopupMenu: Bool = false
    @State private var isPressed: Bool = false
    @State private var isHoveringPopover: Bool = false

    @EnvironmentObject var vm: DynamicIslandViewModel

    var body: some View {
        HStack {
            
                ZStack(alignment: .trailing) {
                    Text("100%")
                        .font(.callout)
                        .hidden()
                    
                    Text("\(Int32(levelBattery))%")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            
            BatteryView(
                levelBattery: levelBattery,
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                isInLowPowerMode: isInLowPowerMode,
                batteryWidth: batteryWidth,
                isForNotification: isForNotification
            )
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation {
                        isPressed = false
                        showPopupMenu.toggle()
                    }
                }
        )
        .popover(
            isPresented: $showPopupMenu,
            arrowEdge: .bottom) {
            BatteryMenuView(
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                levelBattery: levelBattery,
                maxCapacity: maxCapacity,
                timeToFullCharge: timeToFullCharge,
                isInLowPowerMode: isInLowPowerMode,
                onDismiss: { 
                    showPopupMenu = false
                }
            )
            .onHover { hovering in
                isHoveringPopover = hovering
            }
        }
        .onChange(of: showPopupMenu) { _, _ in
            updateBatteryPopoverActiveState()
        }
        .onChange(of: isHoveringPopover) { _, _ in
            updateBatteryPopoverActiveState()
        }
    }

    private func updateBatteryPopoverActiveState() {
        vm.isBatteryPopoverActive = showPopupMenu && isHoveringPopover
    }
}

private struct BatteryCompactStatusRow: View {
    let title: String
    let batteryLevel: Int
    let tint: Color
    let centerWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: title)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(width: 80, alignment: .leading)

            Color.clear.frame(width: centerWidth)

            HStack(spacing: 6) {
                Text("\(batteryLevel)%")
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .monospacedDigit()
                    .font(.system(size: 14))
                    .foregroundColor(tint)

                HStack(spacing: 1.5) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tint.opacity(0.3))

                        GeometryReader { geo in
                            let clamped = max(0, min(batteryLevel, 100))
                            let width = CGFloat(clamped) / 100 * geo.size.width
                            Rectangle()
                                .fill(tint.gradient)
                                .frame(width: max(0, width))
                        }
                    }
                    .frame(width: 28, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(batteryLevel == 100 ? tint.gradient : tint.opacity(0.3).gradient)
                        .frame(width: 2, height: 6)
                }
            }.frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 8)
    }
}

struct BatteryTemporaryActivityView: View {
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    let kind: BatteryTemporaryHUDKind
    let baseWidth: CGFloat
    let baseHeight: CGFloat
    let isDynamicIslandMode: Bool
    let topCornerRadius: CGFloat
    var previewLevel: Int? = nil
    private var title: String {
        switch kind {
        case .charging: return "正在充电"
        case .lowBattery: return "电量不足"
        case .fullBattery: return "已充满电"
        }
    }
    var body: some View {
        BatteryCompactStatusRow(title: title, batteryLevel: previewLevel ?? Int(batteryModel.levelBattery), tint: kind == .lowBattery ? .red : .green, centerWidth: baseWidth)
            .frame(width: baseWidth + 176, height: baseHeight)
            .background(.black)
            .clipShape(AnyShape(isDynamicIslandMode ? AnyShape(Capsule()) : AnyShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: 14))))
    }
}


