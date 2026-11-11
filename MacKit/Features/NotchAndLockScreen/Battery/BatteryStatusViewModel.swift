/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See THIRD_PARTY_NOTICES.md for the original NOTICE and attribution.
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

import Cocoa
import Defaults
import Foundation
import IOKit.ps
import SwiftUI

enum BatteryTemporaryHUDKind: Equatable {
    case charging
    case lowBattery
    case fullBattery
    case batteryPower

    func title(batteryLevel: Int) -> String {
        switch self {
        case .charging: return "正在充电"
        case .lowBattery: return "电量不足"
        case .fullBattery: return batteryLevel >= 100 ? "已充满电" : "直驱供电"
        case .batteryPower: return "电池供电"
        }
    }

    var symbol: String? {
        switch self {
        case .charging: return "bolt.fill"
        case .fullBattery: return "powerplug.fill"
        case .lowBattery, .batteryPower: return nil
        }
    }
}

/// A view model that manages and monitors the battery status of the device
class BatteryStatusViewModel: ObservableObject {

    private var wasCharging: Bool = false
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?
    var animations: DynamicIslandAnimations = DynamicIslandAnimations()

    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared

    @Published private(set) var levelBattery: Float = 0.0
    @Published private(set) var maxCapacity: Float = 0.0
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isInLowPowerMode: Bool = false
    @Published private(set) var isInitial: Bool = false
    @Published private(set) var timeToFullCharge: Int = 0
    @Published private(set) var statusText: String = ""
    @Published private(set) var activeTemporaryHUDBatteryLevel: Int = 0
    @Published private(set) var activeTemporaryHUDKind: BatteryTemporaryHUDKind?
    @Published private(set) var activeTemporaryHUDToken: UUID = UUID()
    @Published private(set) var activeTemporaryHUDTargetScreenName: String?

    private let managerBattery = BatteryActivityManager.shared
    private var managerBatteryId: Int?

    static let shared = BatteryStatusViewModel()

    /// Initializes the view model with a given BoringViewModel instance
    /// - Parameter vm: The BoringViewModel instance
    private init() {
        setupPowerStatus()
        setupMonitor()
    }

    /// Sets up the initial power status by fetching battery information
    private func setupPowerStatus() {
        let batteryInfo = managerBattery.initializeBatteryInfo()
        updateBatteryInfo(batteryInfo)
    }

    /// Sets up the monitor to observe battery events
    private func setupMonitor() {
        managerBatteryId = managerBattery.addObserver { [weak self] event in
            guard let self = self else { return }
            self.handleBatteryEvent(event)
        }
    }

    /// Handles battery events and updates the corresponding properties
    /// - Parameter event: The battery event to handle
    private func handleBatteryEvent(_ event: BatteryActivityManager.BatteryEvent) {
        switch event {
        case .powerSourceChanged(let isPluggedIn):
            print("🔌 Power source: \(isPluggedIn ? "Connected" : "Disconnected")")
            withAnimation {
                self.isPluggedIn = isPluggedIn
                self.statusText = isPluggedIn ? String(localized: "Plugged In") : String(localized: "Unplugged")
            }

        case .batteryLevelChanged(let level):
            print("🔋 Battery level: \(Int(level))%")
            let previousLevel = self.levelBattery
            withAnimation {
                self.levelBattery = level
            }
            self.handleLowBatteryAlertIfNeeded(previousLevel: previousLevel, newLevel: level)

        case .lowPowerModeChanged(let isEnabled):
            print("⚡ Low power mode: \(isEnabled ? "Enabled" : "Disabled")")
            withAnimation {
                self.isInLowPowerMode = isEnabled
                self.statusText = String(
                    localized:
                        "Low Power: \(self.isInLowPowerMode ? String(localized: "On") : String(localized: "Off"))")
            }
        // Low Power Mode may be enabled automatically on battery power,
        // even at high charge. It is not a low-battery threshold event.

        case .isChargingChanged(let isCharging):
            print("🔌 Charging: \(isCharging ? "Yes" : "No")")
            print("maxCapacity: \(self.maxCapacity)")
            print("levelBattery: \(self.levelBattery)")
            withAnimation {
                self.isCharging = isCharging
                self.statusText =
                    isCharging
                    ? String(localized: "Charging battery")
                    : (self.isPluggedIn
                        ? BatteryTemporaryHUDKind.fullBattery.title(batteryLevel: Int(self.levelBattery))
                        : BatteryTemporaryHUDKind.batteryPower.title(batteryLevel: Int(self.levelBattery)))
            }

        case .powerStatusChanged(let info):
            updateBatteryInfo(info)
            let kind: BatteryTemporaryHUDKind = !info.isPluggedIn
                ? .batteryPower : (info.isChargeComplete ? .fullBattery : .charging)
            self.statusText = kind.title(batteryLevel: Int(info.currentCapacity))
            presentTemporaryBatteryHUDIfNeeded(kind: kind)

        case .timeToFullChargeChanged(let time):
            print("🕒 Time to full charge: \(time) minutes")
            withAnimation {
                self.timeToFullCharge = time
            }

        case .maxCapacityChanged(let capacity):
            print("🔋 Max capacity: \(capacity)")
            withAnimation {
                self.maxCapacity = capacity
            }

        case .error(let description):
            print("⚠️ Error: \(description)")
        }
    }

    /// Updates the battery information with the given BatteryInfo instance
    /// - Parameter batteryInfo: The BatteryInfo instance containing the battery data
    private func updateBatteryInfo(_ batteryInfo: BatteryInfo) {
        withAnimation {
            self.levelBattery = batteryInfo.currentCapacity
            self.isPluggedIn = batteryInfo.isPluggedIn
            self.isCharging = batteryInfo.isCharging
            self.isInLowPowerMode = batteryInfo.isInLowPowerMode
            self.timeToFullCharge = batteryInfo.timeToFullCharge
            self.maxCapacity = batteryInfo.maxCapacity
            self.statusText = batteryInfo.isPluggedIn ? String(localized: "Plugged In") : String(localized: "Unplugged")
        }
    }

    private func presentTemporaryBatteryHUDIfNeeded(kind: BatteryTemporaryHUDKind) {
        presentTemporaryBatteryHUDIfNeeded(kind: kind, force: false)
    }

    private func presentTemporaryBatteryHUDIfNeeded(
        kind: BatteryTemporaryHUDKind,
        force: Bool
    ) {
        guard force || Defaults[.showPowerStatusNotifications] else { return }
        if kind == .lowBattery && !force {
            guard levelBattery < Float(NotchConfiguration.lowBatteryHUDThreshold),
                !isPluggedIn, !isCharging
            else { return }
        }

        let duration: Int
        let isEnabled: Bool

        switch kind {
        case .charging, .batteryPower:
            duration = NotchConfiguration.chargingBatteryHUDDuration
            isEnabled = Defaults[.showChargingBatteryHUD]
        case .lowBattery:
            duration = NotchConfiguration.lowBatteryHUDDuration
            isEnabled = Defaults[.showLowBatteryHUD]
        case .fullBattery:
            duration = NotchConfiguration.fullBatteryHUDDuration
            isEnabled = Defaults[.showFullBatteryHUD]
        }

        guard force || isEnabled else { return }

        activeTemporaryHUDBatteryLevel = Int(levelBattery)
        activeTemporaryHUDKind = kind
        activeTemporaryHUDToken = UUID()
        activeTemporaryHUDTargetScreenName = resolvedTemporaryHUDTargetScreenName()
        coordinator.toggleExpandingView(
            status: true,
            type: .battery,
            autoHideDuration: TimeInterval(max(1, duration))
        )
    }

    private func resolvedTemporaryHUDTargetScreenName() -> String? {
        if Defaults[.showOnAllDisplays] {
            return nil
        }

        let preferredNames = [
            coordinator.selectedScreen,
            coordinator.preferredScreen,
            NSScreen.main?.localizedName,
        ]
        .compactMap { $0 }

        for candidate in preferredNames where NSScreen.screens.contains(where: { $0.localizedName == candidate }) {
            return candidate
        }

        return NSScreen.screens.first?.localizedName
    }

    private func preferredDynamicIslandTargetScreenName() -> String? {
        let mainScreenName = NSScreen.main?.localizedName
        let preferredNames = [coordinator.selectedScreen, coordinator.preferredScreen]

        for candidate in preferredNames where shouldUseDynamicIslandMode(for: candidate) {
            return candidate
        }

        if let externalDynamicIslandScreen = NSScreen.screens.first(where: {
            $0.localizedName != mainScreenName && shouldUseDynamicIslandMode(for: $0.localizedName)
        }) {
            return externalDynamicIslandScreen.localizedName
        }

        if let anyDynamicIslandScreen = NSScreen.screens.first(where: {
            shouldUseDynamicIslandMode(for: $0.localizedName)
        }) {
            return anyDynamicIslandScreen.localizedName
        }

        return nil
    }

    private func handleLowBatteryAlertIfNeeded(previousLevel: Float, newLevel: Float) {
        guard !isPluggedIn, !isCharging else { return }
        guard newLevel < previousLevel else { return }
        let threshold = Float(NotchConfiguration.lowBatteryHUDThreshold)
        guard previousLevel >= threshold && newLevel < threshold else { return }

        self.statusText = String(localized: "Low battery")
        presentTemporaryBatteryHUDIfNeeded(kind: .lowBattery)

    }

    deinit {
        print("🔌 Cleaning up battery monitoring...")
        if let managerBatteryId: Int = managerBatteryId {
            managerBattery.removeObserver(byId: managerBatteryId)
        }
    }

}
