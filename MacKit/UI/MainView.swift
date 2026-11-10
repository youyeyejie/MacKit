import SwiftUI

struct MainView: View {
    @Bindable var model: AppModel
    @State private var visitedPages: [AppPage] = [.about]
    private let tools: [AppPage] = [.cleaning, .finder, .windowSwitcher, .wallpaper]
    private let applicationPages: [AppPage] = [.settings, .permissions]

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 252)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Button(action: model.goBack) {
                            Image(systemName: "chevron.left").frame(width: 36, height: 34).contentShape(Rectangle())
                        }
                        .disabled(!model.canGoBack).help("后退").accessibilityLabel("后退")
                        Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 22)
                        Button(action: model.goForward) {
                            Image(systemName: "chevron.right").frame(width: 36, height: 34).contentShape(Rectangle())
                        }
                        .disabled(!model.canGoForward).help("前进").accessibilityLabel("前进")
                    }.background(.primary.opacity(0.045), in: Capsule())
                    Text(model.page?.navigationTitle ?? "关于 MacKit")
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
            if page == .permissions {
                model.permissions.refresh()
                CalendarManager.shared.refreshAuthorizationStatus()
            }
        }
    }

    // Keep the native scroll views alive while showing child destinations. Back
    // switches visibility instead of reconstructing a page and scrolling later.
    private var retainedPages: [AppPage] {
        let current = model.page ?? .about
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
        case .settings: ApplicationSettingsView(model: model)
        case .permissions: PermissionsView(model: model)
        case .about: AboutView(model: model)
        case .licenses: OpenSourceLicensesView()
        case .cleaning: CleaningView(model: model)
        case .finder: FinderCutView(service: model.finderCut)
        case .windowSwitcher:
            WindowSwitcherView(
                service: model.windowSwitcher, dock: model.dockEnhancement, missionControl: model.missionControl)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 4) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        Button {
                            model.page = .about
                        } label: {
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
            .padding(AppStyle.sidebarInset)
    }

    private func navigationRow(_ item: AppPage) -> some View {
        Button {
            model.page = item
        } label: {
            HStack(spacing: 7) {
                Image(systemName: item.symbol).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white).frame(width: 26, height: 26)
                    .background(item.color.gradient, in: RoundedRectangle(cornerRadius: 6))
                Text(item.rawValue).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }.padding(.horizontal, 6).frame(height: 40)
                .background(
                    model.page?.sidebarPage == item ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7)
                )
                .foregroundStyle(model.page?.sidebarPage == item ? .white : .primary)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

}
