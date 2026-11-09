import SwiftUI
import ServiceManagement

enum AppPage: String, CaseIterable, Identifiable {
    case settings = "软件设置", permissions = "权限管理", about = "关于 MacKit"
    case cleaning = "清洁模式", finder = "访达剪切"
    case atoll = "灵动刘海", lockScreen = "锁屏组件"
    case wallpaper = "动态壁纸"
    case windowSwitcher = "窗口预览"
    case licenses = "开源许可"
    case notchMedia = "媒体控制", notchActivities = "实时活动"
    case notchSystem = "系统控制", notchSchedule = "日程提醒", notchShelf = "文件托盘", notchTerminal = "终端"
    case lockMedia = "锁屏媒体", lockWeather = "锁屏天气", lockBattery = "锁屏电池"
    case lockSchedule = "日程", lockFocus = "专注模式"
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

struct MainView: View {
    @Bindable var model: AppModel
    @State private var visitedPages: [AppPage] = [.cleaning]
    private let tools: [AppPage] = [.cleaning, .finder, .windowSwitcher, .wallpaper]
    private let applicationPages: [AppPage] = [.settings, .permissions]

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 252)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Button(action: model.goBack) { Image(systemName: "chevron.left").frame(width: 36, height: 34).contentShape(Rectangle()) }
                            .disabled(!model.canGoBack).help("后退").accessibilityLabel("后退")
                        Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 22)
                        Button(action: model.goForward) { Image(systemName: "chevron.right").frame(width: 36, height: 34).contentShape(Rectangle()) }
                            .disabled(!model.canGoForward).help("前进").accessibilityLabel("前进")
                    }.background(.primary.opacity(0.045), in: Capsule())
                    Text(model.page?.navigationTitle ?? "清洁模式")
                        .font(.system(size: 15, weight: .semibold)).padding(.leading, 4)
                    Spacer()
                }
                .buttonStyle(.plain).font(.system(size: 15, weight: .medium))
                .padding(.leading, 8).padding(.trailing, 20).frame(height: 52)
                ZStack {
                    ForEach(retainedPages) { page in
                        detail(for: page)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(model.page == page ? 1 : 0)
                            .allowsHitTesting(model.page == page)
                            .accessibilityHidden(model.page != page)
                            .zIndex(model.page == page ? 1 : 0)
                    }
                }
                .transaction { $0.animation = nil }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(SettingsPalette.canvas)
        }
        .background(SettingsPalette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.windowRadius))
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { if let page = model.page, !visitedPages.contains(page) { visitedPages.append(page) } }
        .onChange(of: model.page) { _, page in
            if let page, !visitedPages.contains(page) { visitedPages.append(page) }
            if page == .permissions { model.permissions.refresh(); CalendarManager.shared.refreshAuthorizationStatus() }
        }
    }

    // Keep the native scroll views alive while showing child destinations. Back
    // switches visibility instead of reconstructing a page and scrolling later.
    private var retainedPages: [AppPage] {
        let current = model.page ?? .cleaning
        return visitedPages.contains(current) ? visitedPages : visitedPages + [current]
    }

    @ViewBuilder private func detail(for page: AppPage) -> some View {
                    switch page {
                    case .atoll: ConsolidatedNotchSettings(lockScreen: false, navigate: { model.page = $0 })
                    case .lockScreen: ConsolidatedNotchSettings(lockScreen: true, navigate: { model.page = $0 })
                    case .notchMedia, .notchActivities, .notchSystem, .notchSchedule, .notchShelf, .notchTerminal,
                         .lockMedia, .lockWeather, .lockBattery, .lockSchedule, .lockFocus:
                        NotchSecondarySettings(destination: page)
                    case .wallpaper: WallpaperView(service: model.wallpaper)
                    case .settings: settings
                    case .permissions: permissions
                    case .about: about
                    case .licenses: OpenSourceLicensesView()
                    case .cleaning: CleaningView(model: model)
                    case .finder: FinderCutView(service: model.finderCut)
                    case .windowSwitcher: WindowSwitcherView(service: model.windowSwitcher, dock: model.dockEnhancement, missionControl: model.missionControl)
                    }
    }

    private var sidebar: some View {
        VStack(spacing: 4) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        Button { model.page = .about } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: AppBrand.icon).resizable().frame(width: 38, height: 38)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("MacKit").font(.system(size: 15, weight: .semibold))
                                    Text("让 Mac 更顺手").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }.padding(.horizontal, 6).padding(.top, 9).padding(.bottom, 20).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    ForEach(tools) { navigationRow($0) }
                    navigationRow(.atoll)
                    navigationRow(.lockScreen)
                    Color.clear.frame(height: 18)
                    ForEach(applicationPages) { navigationRow($0) }
                }.padding(.horizontal, 10)
            }
        }.padding(.top, 40)
            .modifier(SidebarGlassSurface())
            .padding(8)
    }

    private func navigationRow(_ item: AppPage) -> some View {
        Button { model.page = item } label: {
            HStack(spacing: 7) {
                Image(systemName: item.symbol).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white).frame(width: 26, height: 26)
                    .background(item.color.gradient, in: RoundedRectangle(cornerRadius: 6))
                Text(item.rawValue).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }.padding(.horizontal, 6).frame(height: 40)
                .background(model.page?.sidebarPage == item ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(model.page?.sidebarPage == item ? .white : .primary)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var settings: some View {
        PageLayout {
            SettingsRows(title: "启动与运行") {
                SettingsRow(title: "登录后启动") {
                    Toggle("登录后启动", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            SettingsRows(title: "显示位置") {
                SettingsRow(title: "在 Dock 中显示") {
                    Toggle("在 Dock 中显示", isOn: Binding(get: { model.showDock }, set: model.setDock))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                SettingsRow(title: "在菜单栏中显示") {
                    Toggle("在菜单栏中显示", isOn: Binding(get: { model.showMenuBar }, set: model.setMenuBar))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            SettingsRows(title: "快捷键") {
                SettingsRow(title: "打开 MacKit") {
                    ShortcutRecorder(shortcut: model.shortcuts.show, save: { model.setShortcut($0, forCleaning: false) },
                                     recordingChanged: { model.recordingChanged?($0) })
                }
                Divider()
                SettingsRow(title: "开始清洁") {
                    ShortcutRecorder(shortcut: model.shortcuts.clean, save: { model.setShortcut($0, forCleaning: true) },
                                     recordingChanged: { model.recordingChanged?($0) })
                }
            }
            SettingsRows(title: "退出应用") {
                SettingsRow(title: "退出 MacKit") {
                    Button("退出应用", role: .destructive) { NSApp.terminate(nil) }
                        .buttonStyle(.borderedProminent).tint(.red)
                }
            }
            if let message = model.message { Text(message).font(.callout).foregroundStyle(.orange) }
        }
    }
    private var permissions: some View {
        PageLayout {
            SettingsRows(title: "权限管理") {
                SettingsRow(title: "辅助功能", subtitle: "用于锁定输入、识别访达焦点及处理剪切快捷键。") {
                    StatusPill(text: model.permissions.accessibility ? "已授权" : "未授权", color: model.permissions.accessibility ? .green : .orange)
                    Button("前往系统设置") { model.permissions.openSettings("Privacy_Accessibility") }
                }
                Divider()
                SettingsRow(title: "日历", subtitle: "用于刘海和锁屏组件中的日程。") {
                    CalendarPermissionStatus()
                    Button("前往系统设置") { model.permissions.openSettings("Privacy_Calendars") }
                }
                Divider()
                SettingsRow(title: "屏幕录制", subtitle: "用于生成窗口切换和程序坞预览的缩略图。") {
                    StatusPill(text: model.permissions.screenRecording ? "已授权" : "未授权", color: model.permissions.screenRecording ? .green : .orange)
                    Button("前往系统设置") { model.permissions.openSettings("Privacy_ScreenCapture") }
                }
            }
        }.onAppear { model.permissions.refresh() }
    }
    private var about: some View {
        PageLayout {
            VStack(spacing: 10) {
                Image(nsImage: AppBrand.icon).resizable().frame(width: 80, height: 80)
                Text("MacKit").font(.system(size: 22, weight: .bold))
                Text("轻一点，顺手一点。").font(AppStyle.body).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 24)
                .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 12))
            SettingsRows(title: "软件信息") {
                    SettingsRow(title: "软件版本") {
                        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.11.0"
                        Link("v" + version, destination: URL(string: "https://github.com/youyeyejie/MacKit/releases/tag/v" + version)!)
                    }
                    Divider()
                    SettingsRow(title: "项目地址") {
                        Link("GitHub", destination: URL(string: "https://github.com/youyeyejie/MacKit")!)
                    }
                    Divider()
                    SettingsRow(title: "开源许可") {
                        Button("GPL-3.0") { model.page = .licenses }
                            .buttonStyle(.link)
                    }
            }
        }
    }
}
