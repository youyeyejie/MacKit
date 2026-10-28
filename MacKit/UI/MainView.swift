import SwiftUI
import ServiceManagement

enum AppPage: String, CaseIterable, Identifiable {
    case settings = "软件设置", permissions = "权限管理", about = "关于 MacKit"
    case cleaning = "清洁模式", finder = "Finder 剪切", uninstall = "应用卸载"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .settings: "gearshape.fill"
        case .permissions: "hand.raised.fill"
        case .about: "info.circle.fill"
        case .cleaning: "sparkles"
        case .finder: "scissors"
        case .uninstall: "shippingbox.fill"
        }
    }
    var color: Color {
        switch self {
        case .settings: .gray
        case .permissions: .indigo
        case .about: .blue
        case .cleaning: .teal
        case .finder: .blue
        case .uninstall: .orange
        }
    }
}

struct MainView: View {
    @Bindable var model: AppModel
    @State private var page: AppPage? = .cleaning
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MacKit").font(.title3.bold())
                        Text("让 Mac 更顺手").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.horizontal, 18).padding(.vertical, 22)
                List(selection: $page) {
                    Section {
                        ForEach([AppPage.settings, .permissions, .about]) { item in navigationRow(item) }
                    }
                    Section("工具") {
                        ForEach([AppPage.cleaning, .finder, .uninstall]) { item in navigationRow(item) }
                    }
                }.listStyle(.sidebar)
                VStack(spacing: 12) {
                    Divider()
                    HStack {
                        Text("⌃⌥⌘M 唤起").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                            .buttonStyle(.plain).help("退出 MacKit")
                    }
                }.padding(18)
            }.navigationSplitViewColumnWidth(min: 210, ideal: 225, max: 260)
        } detail: {
            Group {
                switch page ?? .cleaning {
                case .settings: settings
                case .permissions: permissions
                case .about: about
                case .cleaning: CleaningView(service: model.cleaning)
                case .finder: FinderCutView(service: model.finderCut)
                case .uninstall: UninstallerView(service: model.uninstaller)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.navigationSplitViewStyle(.balanced)
    }

    private func navigationRow(_ item: AppPage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white).frame(width: 26, height: 26)
                .background(item.color.gradient, in: RoundedRectangle(cornerRadius: 7))
            Text(item.rawValue).font(.system(size: 13, weight: .medium))
        }.padding(.vertical, 5).tag(item)
    }

    private var settings: some View {
        PageLayout {
            PageHeader(title: "软件设置", subtitle: "安静地留在后台，需要时随时唤起。", symbol: "gearshape.fill", color: .gray)
            SettingsCard(title: "启动与运行") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("登录后启动")
                        Text(model.loginStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("登录后启动", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: model.setLogin)).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                Text("MacKit 不占用 Dock 或菜单栏。关闭窗口后，已启用的功能会继续运行。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("系统登录项设置…") { SMAppService.openSystemSettingsLoginItems() }
            }
            SettingsCard(title: "快捷键") {
                HStack { Text("打开 MacKit"); Spacer(); Text("⌃ ⌥ ⌘ M").monospaced() }
                Divider()
                HStack { Text("开始清洁"); Spacer(); Text("⌃ ⌥ ⌘ K").monospaced() }
            }
            if let message = model.message { Text(message).font(.callout).foregroundStyle(.orange) }
        }
    }
    private var permissions: some View {
        PageLayout {
            PageHeader(title: "权限管理", subtitle: "只在使用对应功能时需要授权。", symbol: "hand.raised.fill", color: .indigo)
            SettingsCard(title: "辅助功能") {
                HStack {
                    Text("用于锁定输入、识别 Finder 焦点及处理剪切快捷键。")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    StatusPill(text: model.permissions.accessibility ? "已授权" : "未授权", color: model.permissions.accessibility ? .green : .orange)
                }
                HStack {
                    Button("前往授权…") { model.permissions.requestAccessibility() }
                    Button("刷新") { model.permissions.refresh(); model.finderCut.sync() }
                }
            }
            SettingsCard(title: "完整磁盘访问") {
                Text("扩大卸载扫描可读取的范围，包括受保护的应用容器和权限记录。未授权或无法访问的项目会明确显示，不会当作不存在。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("打开完整磁盘访问设置…") { model.permissions.openSettings("Privacy_AllFiles") }
            }
            SettingsCard(title: "Finder 扩展") {
                Text(model.finderCut.badgeStatus).font(.callout).foregroundStyle(.secondary)
                Button("管理 Finder 扩展…") { model.finderCut.openExtensionSettings() }
            }
        }.onAppear { model.permissions.refresh() }
    }
    private var about: some View {
        PageLayout {
            VStack(spacing: 16) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable().frame(width: 112, height: 112)
                Text("MacKit").font(.system(size: 32, weight: .bold, design: .rounded))
                Text("轻一点，顺手一点。").font(.title3).foregroundStyle(.secondary)
                StatusPill(text: "开发预览 0.2", color: .blue)
            }.frame(maxWidth: .infinity).padding(.vertical, 30)
            SettingsCard(title: "为你的 Mac 而生") {
                Text("使用 Swift 与 SwiftUI 构建。功能按需运行，数据留在本机，无需账号或云服务。")
                    .foregroundStyle(.secondary)
                Divider()
                HStack { Text("系统支持目标"); Spacer(); Text("macOS 14–27").foregroundStyle(.secondary) }
                HStack { Text("当前系统"); Spacer(); Text(ProcessInfo.processInfo.operatingSystemVersionString).foregroundStyle(.secondary) }
            }
        }
    }
}
