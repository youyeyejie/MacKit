import SwiftUI

struct CalendarPermissionStatus: View {
    @ObservedObject private var calendar = CalendarManager.shared
    var body: some View {
        StatusPill(text: calendar.hasCalendarAccess ? "已授权" : "未授权", color: calendar.hasCalendarAccess ? .green : .orange)
            .onAppear { calendar.refreshAuthorizationStatus() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                calendar.refreshAuthorizationStatus()
            }
    }
}
