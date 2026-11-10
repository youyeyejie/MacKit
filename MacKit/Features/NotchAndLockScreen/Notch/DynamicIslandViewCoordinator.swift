// MacKit feature reduction, modified 2026-11-08.
// See THIRD_PARTY_NOTICES.md; GPL-3.0-or-later.
/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Combine
import Defaults
import SwiftUI

enum SneakContentType: Equatable {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case reminder
    case recording
    case doNotDisturb
    case bluetoothAudio
    case privacy
    case lockScreen
    case capsLock
}

struct sneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
    var title: String = ""
    var subtitle: String = ""
    var accentColor: Color?
    var styleOverride: SneakPeekStyle? = nil
    var targetScreenName: String? = nil
}

enum BrowserType {
    case chromium
    case safari
}

struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
    var autoHideDuration: TimeInterval? = nil
}

struct SettingsActivityPreview {
    let title: String
    let symbol: String
    var type: SneakContentType? = nil
    var circular: Bool = false
}

class DynamicIslandViewCoordinator: ObservableObject {
    @Published var cleaningActive = false
    @Published var settingsPreview: SettingsActivityPreview?
    private var settingsPreviewTask: Task<Void, Never>?

    @MainActor func previewSetting(
        _ title: String, symbol: String, type: SneakContentType? = nil, circular: Bool = false
    ) {
        settingsPreviewTask?.cancel()
        settingsPreview = nil
        if let type, [.volume, .brightness, .backlight].contains(type), Defaults[.enableVerticalHUD] {
            VerticalHUDWindowManager.shared.show(type: type, value: 0.65, icon: symbol)
            return
        }
        let resolvedType: SneakContentType =
            type
            ?? (symbol.contains("battery")
                ? .battery
                : (symbol == "headphones"
                    ? .bluetoothAudio
                    : (symbol == "capslock.fill"
                        ? .capsLock
                        : (symbol == "record.circle.fill"
                            ? .recording : (symbol == "moon.fill" ? .doNotDisturb : .privacy)))))
        if [.volume, .brightness, .backlight, .bluetoothAudio].contains(resolvedType) {
            toggleSneakPeek(status: true, type: resolvedType, duration: 3, value: 0.75, icon: symbol, title: title)
            return
        }
        let selectedTab = currentView
        AtollAppDelegate.shared?.vm.close()
        AtollAppDelegate.shared?.viewModels.values.forEach { $0.close() }
        currentView = selectedTab
        withAnimation(.smooth) {
            settingsPreview = SettingsActivityPreview(
                title: title, symbol: symbol, type: resolvedType, circular: circular)
        }
        settingsPreviewTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            withAnimation(.smooth) { self?.settingsPreview = nil }
        }
    }

    static let shared = DynamicIslandViewCoordinator()
    private var cancellables = Set<AnyCancellable>()
    private var hoverOpenSuppressedUntil: Date = .distantPast

    private static let tabOrder: [NotchViews] = [.home, .shelf, .terminal]

    /// Direction of the most recent tab switch (true = forward/right, false = backward/left)
    @Published var tabSwitchForward: Bool = true

    @Published var currentView: NotchViews = .home {
        didSet {

            // Track direction before SwiftUI re-renders
            let oldIdx = Self.tabOrder.firstIndex(of: oldValue) ?? 0
            let newIdx = Self.tabOrder.firstIndex(of: currentView) ?? 0
            tabSwitchForward = newIdx >= oldIdx
        }
    }

    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true

    let alwaysShowTabs = true

    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {

            }
        }
    }

    @AppStorage("hudReplacement") var hudReplacement: Bool = true

    @AppStorage("preferred_screen_name") var preferredScreen = NSScreen.main?.localizedName ?? "Unknown" {
        didSet {
            selectedScreen = preferredScreen
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @Published var selectedScreen: String = NSScreen.main?.localizedName ?? "Unknown"

    @Published var optionKeyPressed: Bool = true

    private init() {
        selectedScreen = preferredScreen

        Publishers.MergeMany(
            Defaults.publisher(.showStandardMediaControls).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.showCalendar).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.dynamicShelf).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableTerminalFeature).map { _ in () }.eraseToAnyPublisher()
        ).debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { _ in enforceMinimumNotchWidth() }.store(in: &cancellables)
        enforceMinimumNotchWidth()
    }

    var isHoverOpenSuppressed: Bool {
        Date() < hoverOpenSuppressedUntil
    }

    func suppressHoverOpen(for duration: TimeInterval = 0.35) {
        hoverOpenSuppressedUntil = Date().addingTimeInterval(max(0, duration))
    }

    private func handleMinimalisticModeChange(_ isEnabled: Bool) {
        guard isEnabled else { return }
        if currentView != .home {
            withAnimation(.smooth) {
                currentView = .home
            }
        }
    }

    func toggleSneakPeek(
        status: Bool,
        type: SneakContentType,
        duration: TimeInterval = 1.5,
        value: CGFloat = 0,
        icon: String = "",
        title: String = "",
        subtitle: String = "",
        accentColor: Color? = nil,
        styleOverride: SneakPeekStyle? = nil,
        onScreen targetScreen: NSScreen? = nil
    ) {
        let resolvedDuration: TimeInterval
        switch type {
        case .reminder:
            resolvedDuration = Defaults[.reminderSneakPeekDuration]
        default:
            resolvedDuration = duration
        }
        sneakPeekDuration = resolvedDuration
        let bypassedTypes: [SneakContentType] = [.music, .reminder, .bluetoothAudio]

        if !bypassedTypes.contains(type) && !Defaults[.enableSystemHUD] {
            return
        }
        DispatchQueue.main.async {
            // Single write so `sneakPeek.didSet` (which schedules the auto-hide)
            // fires once, not once per field — the per-field writes raced the hide
            // Task and could wedge `show == true` with no pending hide.
            var updated = self.sneakPeek
            updated.show = status
            updated.type = type
            updated.value = value
            updated.icon = icon
            updated.title = title
            updated.subtitle = subtitle
            updated.accentColor = accentColor
            updated.styleOverride = styleOverride
            updated.targetScreenName = targetScreen?.localizedName
            withAnimation(.smooth(duration: 0.3)) {
                self.sneakPeek = updated
            }
        }
    }

    private var sneakPeekDuration: TimeInterval = 1.5
    private var sneakPeekTask: Task<Void, Never>?

    // Helper function to manage sneakPeek timer using Swift Concurrency
    private func scheduleSneakPeekHide(after duration: TimeInterval) {
        sneakPeekTask?.cancel()

        // Don't schedule auto-hide if duration is infinite (for persistent indicators like Caps Lock)
        guard duration.isFinite else { return }

        sneakPeekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    // Hide the sneak peek with the correct type that was showing
                    self.toggleSneakPeek(status: false, type: self.sneakPeek.type)
                    self.sneakPeekDuration = 1.5
                }
            }
        }
    }

    @Published var sneakPeek: sneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                scheduleSneakPeekHide(after: sneakPeekDuration)
            } else {
                sneakPeekTask?.cancel()
            }
        }
    }

    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium,
        autoHideDuration: TimeInterval? = nil
    ) {
        Task { @MainActor in
            withAnimation(.smooth) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
                self.expandingView.browser = browser
                self.expandingView.autoHideDuration = autoHideDuration
            }
        }
    }

    private var expandingViewTask: Task<Void, Never>?

    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                expandingViewTask?.cancel()
                do {
                    let duration = expandingView.autoHideDuration ?? 3
                    expandingViewTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(duration))
                        guard let self = self, !Task.isCancelled else { return }
                        self.toggleExpandingView(status: false, type: .battery)
                    }
                }
            } else {
                expandingViewTask?.cancel()
            }
        }
    }

    func showEmpty() {
        currentView = .home
    }

    // MARK: - Clipboard Management
    @Published var shouldToggleClipboardPopover: Bool = false

    func toggleClipboardPopover() {
        // Toggle the published property to trigger UI updates
        shouldToggleClipboardPopover.toggle()
    }
}
