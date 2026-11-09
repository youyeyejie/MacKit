import SwiftUI
import EventKit

struct CalendarPermissionsCard: View {
    @ObservedObject private var calendar = CalendarManager.shared
    var body: some View {
        Group {
            PermissionCard(title: "日历", subtitle: "用于刘海和锁屏组件中的日程。") {
                StatusPill(text: calendar.hasCalendarAccess ? "已授权" : "未授权", color: calendar.hasCalendarAccess ? .green : .orange)
                Button("授权或管理…") {
                    if calendar.hasCalendarAccess { open("Privacy_Calendars") }
                    else { Task { await calendar.checkCalendarAuthorization() } }
                }
            }

        }.onAppear { calendar.refreshAuthorizationStatus() }
    }
    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}
