import SwiftUI

enum AppPage: String, CaseIterable, Identifiable {
    case settings = "软件设置"
    case permissions = "权限管理"
    case about = "关于 MacKit"
    case cleaning = "清洁模式"
    case finder = "访达剪切"
    case atoll = "灵动刘海"
    case lockScreen = "锁屏组件"
    case wallpaper = "动态壁纸"
    case windowSwitcher = "窗口预览"
    case licenses = "开源许可"
    case notchMedia = "媒体控制"
    case notchActivities = "实时活动"
    case notchSystem = "系统控制"
    case notchSchedule = "日程提醒"
    case notchShelf = "文件托盘"
    case notchTerminal = "终端"
    case lockMedia = "锁屏媒体"
    case lockWeather = "锁屏天气"
    case lockBattery = "锁屏电池"
    case lockSchedule = "日程"
    case lockFocus = "专注模式"
    var id: String { rawValue }
    var sidebarPage: AppPage {
        switch self {
        case .notchMedia, .notchActivities, .notchSystem, .notchSchedule, .notchShelf, .notchTerminal: .atoll
        case .lockMedia, .lockWeather, .lockBattery, .lockSchedule, .lockFocus: .lockScreen
        case .licenses: .about
        default: self
        }
    }
    var navigationTitle: String {
        if sidebarPage == self { return rawValue }
        let child: String
        switch self {
        case .lockMedia: child = "媒体"
        case .lockWeather: child = "天气"
        case .lockBattery: child = "电池"
        case .lockSchedule: child = "日程"
        default: child = rawValue
        }
        return sidebarPage.rawValue + " - " + child
    }
    var symbol: String {
        switch self {
        case .atoll: "capsule.tophalf.filled"
        case .notchMedia: "play.circle"
        case .notchActivities: "waveform.path.ecg"
        case .notchSystem, .notchSchedule, .notchShelf, .notchTerminal: "gearshape"
        case .lockMedia, .lockWeather, .lockBattery, .lockSchedule, .lockFocus: "lock.rectangle"
        case .lockScreen: "lock.rectangle"
        case .settings: "gearshape.fill"
        case .permissions: "hand.raised.fill"
        case .about, .licenses: "info.circle.fill"
        case .wallpaper: "play.rectangle"
        case .cleaning: "sparkles"
        case .finder: "scissors"
        case .windowSwitcher: "rectangle.on.rectangle"
        }
    }
    var color: Color {
        switch self {
        case .atoll, .notchMedia, .notchActivities, .notchSystem, .notchSchedule, .notchShelf, .notchTerminal: .cyan
        case .lockScreen, .lockMedia, .lockWeather, .lockBattery, .lockSchedule, .lockFocus: .indigo
        case .settings: .gray
        case .permissions: .indigo
        case .about, .licenses: .blue
        case .wallpaper: .mint
        case .cleaning: .teal
        case .finder: .blue
        case .windowSwitcher: .purple
        }
    }
}
