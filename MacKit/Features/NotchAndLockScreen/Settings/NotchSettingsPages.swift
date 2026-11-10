// Derived from Atoll; GPL-3.0-or-later.
// Original settings by Richard Kunkli, 2024; MacKit host adaptation, 2026.
// See THIRD_PARTY_NOTICES.md.
import AppKit
import Defaults
import SwiftUI

/// Root settings pages contain general controls and complete-row child destinations.
struct ConsolidatedNotchSettings: View {
    let lockScreen: Bool
    var navigate: (AppPage) -> Void = { _ in }
    var body: some View {
        PageLayout {
            if lockScreen {
                LockScreenSettingsView(navigate: navigate)
            } else {
                NotchGeneralSettingsView()
                SettingsRows(title: "功能") {
                    SettingsDestinationRow(title: "媒体控制") { navigate(.notchMedia) }
                    Divider()
                    SettingsDestinationRow(title: "实时活动") { navigate(.notchActivities) }
                    Divider()
                    SettingsDestinationRow(title: "系统控制") { navigate(.notchSystem) }
                    Divider()
                    SettingsDestinationRow(title: "日程提醒") { navigate(.notchSchedule) }
                    Divider()
                    SettingsDestinationRow(title: "文件托盘") { navigate(.notchShelf) }
                    Divider()
                    SettingsDestinationRow(title: "终端") { navigate(.notchTerminal) }
                }
            }
        }
        .modifier(NotchSettingsStyle())
        .id(lockScreen)
    }
}

struct NotchSecondarySettings: View {
    let destination: AppPage
    var body: some View {
        PageLayout {
            switch destination {
            case .notchMedia: NotchMediaSettingsView()
            case .notchActivities:
                LiveActivitiesSettings()
                DevicesSettingsView()
                NotchBatterySettingsView()
            case .notchSystem: HUDAndOSDSettingsView()
            case .notchSchedule: NotchCalendarSettingsView()
            case .notchShelf: NotchShelfSettingsView()
            case .notchTerminal: NotchTerminalSettingsView()
            default: LockScreenSettingsView(destination: destination)
            }
        }
        .modifier(NotchSettingsStyle())
        .id(destination)
    }
}

private struct NotchSettingsStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toggleStyle(SettingsTrailingToggleStyle())
            .controlSize(.small)
            .buttonStyle(.bordered)
    }
}
