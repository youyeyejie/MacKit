import SwiftUI
import ServiceManagement

enum AppPage: String, CaseIterable, Identifiable {
    case settings = "软件设置", permissions = "权限管理", about = "关于 MacKit"
    case cleaning = "清洁模式", finder = "访达剪切"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .settings: "gearshape.fill"
        case .permissions: "hand.raised.fill"
        case .about: "info.circle.fill"
        case .cleaning: "sparkles"
        case .finder: "scissors"
        }
    }
    var color: Color {
        switch self {
        case .settings: .gray
        case .permissions: .indigo
        case .about: .blue
        case .cleaning: .teal
        case .finder: .blue
        }
    }
}

struct MainView: View {
    @Bindable var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            if model.sidebarVisible {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: AppBrand.icon).resizable().frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MacKit").font(.title3.bold())
                        Text("让 Mac 更顺手").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.horizontal, 18).padding(.vertical, 22)
                List(selection: $model.page) {
                    Section {
                        ForEach([AppPage.settings, .permissions, .about]) { item in navigationRow(item) }
                    }
                    Section("工具") {
                        ForEach([AppPage.cleaning, .finder]) { item in navigationRow(item) }
                    }
                }.listStyle(.sidebar)
                VStack(spacing: 12) {
                    Divider()
                    HStack {
                        if let shortcut = model.shortcuts.show { Text("\(shortcut.label) 唤起").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                            .buttonStyle(.plain).help("退出 MacKit")
                    }
                }.padding(18)
            }.frame(width: 202)
            Divider()
            }

            Group {
                switch model.page ?? .cleaning {
                case .settings: settings
                case .permissions: permissions
                case .about: about
                case .cleaning: CleaningView(service: model.cleaning, shortcut: model.shortcuts.clean?.label)
                case .finder: FinderCutView(service: model.finderCut)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
            SettingsRows(title: "启动与运行") {
                SettingsRow(title: "登录后启动") {
                    Toggle("登录后启动", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsRows(title: "显示位置") {
                SettingsRow(title: "在 Dock 中显示") {
                    Toggle("在 Dock 中显示", isOn: Binding(get: { model.showDock }, set: model.setDock))
                        .labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingsRow(title: "在菜单栏中显示") {
                    Toggle("在菜单栏中显示", isOn: Binding(get: { model.showMenuBar }, set: model.setMenuBar))
                        .labelsHidden().toggleStyle(.switch)
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
            if let message = model.message { Text(message).font(.callout).foregroundStyle(.orange) }
        }
    }
    private var permissions: some View {
        PageLayout {
            PageHeader(title: "权限管理", subtitle: "只在使用对应功能时需要授权。", symbol: "hand.raised.fill", color: .indigo)
            PermissionCard(title: "辅助功能", subtitle: "用于锁定输入、识别访达焦点及处理剪切快捷键。") {
                StatusPill(text: model.permissions.accessibility ? "已授权" : "未授权", color: model.permissions.accessibility ? .green : .orange)
                Button(model.permissions.accessibility ? "管理…" : "前往授权…") {
                    model.permissions.requestAccessibility()
                }
            }
        }.onAppear { model.permissions.refresh() }
    }
    private var about: some View {
        PageLayout {
            VStack(spacing: 16) {
                Image(nsImage: AppBrand.icon).resizable().frame(width: 112, height: 112)
                Text("MacKit").font(.system(size: 32, weight: .bold, design: .rounded))
                Text("轻一点，顺手一点。").font(.title3).foregroundStyle(.secondary)
                StatusPill(text: "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.0"), color: .blue)
            }.frame(maxWidth: .infinity).padding(.vertical, 30)
            SettingsCard(title: "为你的 Mac 而生") {
                Text("使用 Swift 与 SwiftUI 构建。功能按需运行，数据留在本机，无需账号或云服务。")
                    .foregroundStyle(.secondary)
                Divider()
                VStack(spacing: 0) {
                    SettingsRow(title: "系统支持目标") { Text("macOS 14–27").foregroundStyle(.secondary) }
                    Divider()
                    SettingsRow(title: "当前系统") { Text(ProcessInfo.processInfo.operatingSystemVersionString).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                }
            }
        }
    }
}
