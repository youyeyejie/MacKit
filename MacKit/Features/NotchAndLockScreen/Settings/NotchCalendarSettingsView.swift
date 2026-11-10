// Derived from Atoll; GPL-3.0-or-later.
// Original settings by Richard Kunkli, 2024; MacKit host adaptation, 2026.
// See THIRD_PARTY_NOTICES.md.
import AppKit
import Defaults
import SwiftUI

struct NotchCalendarSettingsView: View {
    @Default(.showCalendar) private var enabled
    @Default(.reminderLeadTime) private var lead
    @Default(.reminderSneakPeekDuration) private var reminderDuration
    @Default(.reminderPresentationStyle) private var reminderStyle
    @ObservedObject private var calendar = CalendarManager.shared
    var body: some View {
        Group {
            UnifiedSettingsSection("日历与提醒") {
                Toggle("启用日历", isOn: $enabled)
                Defaults.Toggle(key: .enableReminderLiveActivity) { Text("启用日程提醒") }
            }
            if enabled {
                UnifiedSettingsSection("日历列表") {
                    ForEach(calendar.allCalendars, id: \.id) { item in
                        Toggle(
                            isOn: Binding(
                                get: { calendar.selectedCalendarIDs.contains(item.id) },
                                set: { selected in
                                    guard selected != calendar.selectedCalendarIDs.contains(item.id) else { return }
                                    Task { await calendar.setCalendarSelected(item, isSelected: selected) }
                                })
                        ) {
                            HStack(spacing: 8) {
                                Circle().fill(Color(nsColor: item.color)).frame(width: 9, height: 9)
                                    .accessibilityHidden(true)
                                SettingsDescription(title: item.title, subtitle: item.sourceName ?? item.accountName)
                            }
                        }
                    }
                }
                UnifiedSettingsSection("提醒") {
                    SettingsRow(title: "倒计时样式") {
                        Picker("倒计时样式", selection: $reminderStyle) {
                            ForEach(ReminderPresentationStyle.allCases) { style in Text(style.displayName).tag(style) }
                        }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(
                            maxWidth: 200, alignment: .trailing)
                    }
                    CompactSettingsSlider(
                        value: $reminderDuration, in: 3...20, step: 1, valueText: "\(Int(reminderDuration)) 秒"
                    ) { Text("提醒持续时长") }
                    CompactSettingsSlider(
                        value: Binding(get: { Double(lead) }, set: { lead = Int($0) }), in: 1...60, step: 1,
                        valueText: "\(lead) 分钟"
                    ) { Text("提醒提前时长") }
                }

            }
        }
        .onChange(of: enabled) { _, value in calendar.setEnabled(value) }
    }
}
