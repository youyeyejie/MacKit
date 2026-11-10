import SwiftUI

struct PermissionsView: View {
    @Bindable var model: AppModel
    var body: some View {
        PageLayout {
            SettingsRows(title: "权限管理") {
                SettingsRow(title: "辅助功能", subtitle: "用于锁定输入、识别访达焦点及处理剪切快捷键。") {
                    StatusPill(
                        text: model.permissions.accessibility ? "已授权" : "未授权",
                        color: model.permissions.accessibility ? .green : .orange)
                    Button("前往系统设置") { model.permissions.openSettings("Privacy_Accessibility") }
                }
                Divider()
                SettingsRow(title: "日历", subtitle: "用于刘海和锁屏组件中的日程。") {
                    CalendarPermissionStatus()
                    Button("前往系统设置") { model.permissions.openSettings("Privacy_Calendars") }
                }
                Divider()
                SettingsRow(title: "屏幕录制", subtitle: "用于生成窗口切换和程序坞预览的缩略图。") {
                    StatusPill(
                        text: model.permissions.screenRecording ? "已授权" : "未授权",
                        color: model.permissions.screenRecording ? .green : .orange)
                    Button("前往系统设置") { model.permissions.openSettings("Privacy_ScreenCapture") }
                }
            }
        }.onAppear { model.permissions.refresh() }
    }

}
