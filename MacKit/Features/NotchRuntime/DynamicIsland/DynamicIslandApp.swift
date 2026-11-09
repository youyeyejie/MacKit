// MacKit feature reduction, modified 2026-11-08.
// See THIRD_PARTY_NOTICES.md; GPL-3.0-or-later.
// MacKit host adaptation, modified 2026-11-08.
// See THIRD_PARTY_NOTICES.md for the host integration changes; GPL-3.0-or-later.
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

import AVFoundation
import Combine
import Defaults
import SwiftUI
import SkyLightWindow

// MacKit integration: the host owns the application entry point and updater.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

extension AtollAppDelegate {
    static var shared: AtollAppDelegate? {
        AtollIntegration.shared.delegate
    }
}

class AtollAppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windows: [NSScreen: NSWindow] = [:]
    var viewModels: [NSScreen: DynamicIslandViewModel] = [:]
    var window: NSWindow?
    let vm: DynamicIslandViewModel = .init()
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    let calendarManager = CalendarManager.shared
    let dndManager = DoNotDisturbManager.shared  // NEW: DND detection
    let bluetoothAudioManager = BluetoothAudioManager.shared  // NEW: Bluetooth audio detection
    let lockScreenPanelManager = LockScreenPanelManager.shared  // NEW: Lock screen music panel
    var closeNotchWorkItem: DispatchWorkItem?
    private var previousScreens: [NSScreen]?
    private var cancellables = Set<AnyCancellable>()
    private var windowsHiddenForLock = false
    private weak var focusWithoutDevToolsMenuItem: NSMenuItem?
    private weak var focusUseDevToolsMenuItem: NSMenuItem?
    
    // Debouncing mechanism for window size updates
    private var windowSizeUpdateWorkItem: DispatchWorkItem?
//    let calendarManager = CalendarManager.shared
//    var closeNotchWorkItem: DispatchWorkItem?
//    private var previousScreens: [NSScreen]?
//    private var cancellables = Set<AnyCancellable>()
//    
//    // Debouncing mechanism for window size updates
//    private var windowSizeUpdateWorkItem: DispatchWorkItem?
    
    private func debouncedUpdateWindowSize() {
        // Cancel any existing work item
        windowSizeUpdateWorkItem?.cancel()
        
        // Create new work item with delay
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateWindowSizeIfNeeded()
        }
        
        // Store reference and schedule
        windowSizeUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        installTopMenuItemsIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        _ = handleIncomingShelfURLs(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        handleIncomingShelfURLs([URL(fileURLWithPath: filename)])
    }

    private func handleIncomingShelfURLs(_ urls: [URL]) -> Bool {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return false }

        Task { @MainActor [weak self] in
            let items = await ShelfDropService.items(from: fileURLs)
            guard !items.isEmpty else { return }

            ShelfStateViewModel.shared.add(items)
            self?.coordinator.currentView = .shelf
        }

        return true
    }
    
    /// Setup observers for music player state changes to restart AudioTap capture

    
    func applicationWillTerminate(_ notification: Notification) {
        SystemOSDManager.restoreImmediately()
        MusicManager.shared.shutdown()
        // Cancel any pending window size updates
        windowSizeUpdateWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
        
        // Stop AudioTap capture

        // Restore Lunar's native OSD if integration was active
        LunarManager.shared.appWillTerminate()
    }
    
    @objc func onScreenLocked(_: Notification) {
        print("Screen locked")
        hideWindowsForLock()
    }

    @objc func onScreenUnlocked(_: Notification) {
        print("Screen unlocked")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.restoreWindowsAfterLock()
            self.adjustWindowPosition(changeAlpha: true)
        }
    }

    private func hideWindowsForLock() {
        guard !windowsHiddenForLock else { return }
        windowsHiddenForLock = true

        if Defaults[.showOnAllDisplays] {
            for window in windows.values {
                window.alphaValue = 0
                window.orderOut(nil)
            }
        } else if let window = window {
            window.alphaValue = 0
            window.orderOut(nil)
        }
    }

    private func restoreWindowsAfterLock() {
        guard windowsHiddenForLock else { return }
        windowsHiddenForLock = false

        if Defaults[.showOnAllDisplays] {
            for window in windows.values {
                window.orderFrontRegardless()
                window.alphaValue = 1
            }
        } else if let window = window {
            window.orderFrontRegardless()
            window.alphaValue = 1
        }
    }
    
    private func cleanupWindows(shouldInvert: Bool = false) {
        if shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays] {
            for (screen, window) in windows {
                // Tear down the hosted ContentView before dropping the window
                // (`.onDisappear` is unreliable for borderless panels).
                viewModels[screen]?.onViewTeardown?()
                viewModels[screen]?.onViewTeardown = nil
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
                window.close()
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            vm.onViewTeardown?()
            vm.onViewTeardown = nil
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            window.close()
            self.window = nil
        }
    }

    /// Rebuilds the notch's CGSSpace membership from the current hide option and the
    /// live windows. The space pins the notch above every space (fullscreen included)
    /// and is used **only** for "Never hide"; the hide options keep the set empty so
    /// FullscreenMediaDetector can hide the notch. Assigning the whole set lets the
    /// CGSSpace diff additions/removals, so this is safe to call on any change.
    @MainActor
    private func syncNotchSpaceMembership() {
        guard NotchConfiguration.hideNotchOption == .never else {
            NotchSpaceManager.shared.notchSpace.windows = []
            return
        }
        if Defaults[.showOnAllDisplays] {
            NotchSpaceManager.shared.notchSpace.windows = Set(windows.values)
        } else if let window = window {
            NotchSpaceManager.shared.notchSpace.windows = [window]
        } else {
            NotchSpaceManager.shared.notchSpace.windows = []
        }
    }

    private func createDynamicIslandWindow(for screen: NSScreen, with viewModel: DynamicIslandViewModel)
        -> NSWindow
    {
        // Use the current required size instead of always using openNotchSize
        let baseSize = calculateRequiredNotchSize()
        let requiredSize = adjustedSizeForScreen(baseSize, screen: screen)
        let roundedWidth = requiredSize.width.rounded()
        let roundedHeight = requiredSize.height.rounded()
        
        let window = DynamicIslandWindow(
            contentRect: NSRect(
                x: 0, y: 0, width: roundedWidth, height: roundedHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.animationBehavior = .none
        // collectionBehavior is configured in DynamicIslandWindow.init

        window.contentView = FirstMouseHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
                //.moveToSky()
        )
        
        window.orderFrontRegardless()
        // Pin above every space (fullscreen included) only for "Never hide"; the
        // hide options leave the window on the collectionBehavior path so
        // FullscreenMediaDetector can hide it. See NotchSpaceManager.
        if NotchConfiguration.hideNotchOption == .never {
            NotchSpaceManager.shared.notchSpace.windows.insert(window)
        }
        //SkyLightOperator.shared.delegateWindow(window)
        return window
    }

    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false)
    {
        if changeAlpha {
            window.alphaValue = 0
        }
        
        // Use the same centering logic as updateWindowSizeIfNeeded()
        let screenFrame = screen.frame
        let centerX = screenFrame.origin.x + (screenFrame.width / 2)
        let roundedWidth = window.frame.width.rounded()
        let roundedHeight = window.frame.height.rounded()
        let newX = (centerX - (roundedWidth / 2)).rounded()
        let newY = (screenFrame.origin.y + screenFrame.height - roundedHeight).rounded()

        window.setFrame(NSRect(
            x: newX,
            y: newY,
            width: roundedWidth,
            height: roundedHeight
        ), display: false)
        
        if changeAlpha {
            window.alphaValue = 1
        }
    }
    
    private func updateWindowSizeIfNeeded() {
        // Calculate required size based on current state
        let requiredSize = calculateRequiredNotchSize()
        let animateResize = shouldAnimateResize(for: requiredSize)
        resizeWindows(to: requiredSize, animated: animateResize, force: false)
    }

    private func updateWindowSizeForTabSwitch() {
        let requiredSize = calculateRequiredNotchSize()
        resizeWindows(to: requiredSize, animated: false, force: true)
    }
    
    private func calculateRequiredNotchSize() -> CGSize {
        // Check if inline sneak peek is showing and notch is closed
        let airPodsListeningModeSneakActive = vm.notchState == .closed &&
                                      coordinator.sneakPeek.show &&
                                      coordinator.sneakPeek.type == .bluetoothAudio &&
                                      coordinator.sneakPeek.value < 0 &&
                                      AirPodsListeningMode.fromHUDSymbol(coordinator.sneakPeek.icon) != nil
        let isInlineSneakPeekActive = vm.notchState == .closed && 
                                      NotchConfiguration.enableSneakPeek &&
                                      (
                                          coordinator.expandingView.show &&
                                          (coordinator.expandingView.type == .music) &&
                                          Defaults[.sneakPeekStyles] == .inline ||
                                          airPodsListeningModeSneakActive
                                      )
        
        // If inline sneak peek is active, use a wider width to accommodate the expanded content
        if isInlineSneakPeekActive {
            // Calculate required width for inline sneak peek:
            // Album art (~32) + Middle section (380) + Visualizer (~32) + horizontal padding (28) + clip shape margin (12)
            let inlineSneakPeekWidth: CGFloat = 460
            return CGSize(width: inlineSneakPeekWidth, height: vm.effectiveClosedNotchHeight)
        }

        if vm.notchState == .closed && coordinator.expandingView.show && coordinator.expandingView.type == .battery && Defaults[.showPowerStatusNotifications] && BatteryStatusViewModel.shared.activeTemporaryHUDKind != nil {
            return addShadowPadding(to: CGSize(width: vm.closedNotchSize.width + 180, height: vm.effectiveClosedNotchHeight), isMinimalistic: false)
        }

        // Use minimalistic or normal size based on settings
        var baseSize = openNotchSize
        
        // Use a consistent height for different view types
        baseSize = NotchOpenLayout.size(for: coordinator.currentView, screenName: vm.screen)
        
        let adjustedContentSize = baseSize
        var result = addShadowPadding(
            to: adjustedContentSize,
            isMinimalistic: NotchConfiguration.enableMinimalisticUI
        )

        return result
    }

    /// Adjusts a base notch size for a specific screen by adding Dynamic Island
    /// shadow insets and top-offset only when the screen lacks a physical notch
    /// and the user has chosen the Dynamic Island style.
    private func adjustedSizeForScreen(_ baseSize: CGSize, screen: NSScreen) -> CGSize {
        guard shouldUseDynamicIslandMode(for: screen.localizedName) else {
            return baseSize
        }
        var adjusted = baseSize
        adjusted.width += dynamicIslandShadowInset * 2
        adjusted.height += dynamicIslandTopOffset
        return adjusted
    }

    func ensureWindowSize(_ size: CGSize, animated: Bool, force: Bool = false) {
        resizeWindows(to: size, animated: animated, force: force)
    }

    private func resizeWindows(to size: CGSize, animated: Bool, force: Bool) {
        guard size.width > 0, size.height > 0 else { return }

        if Defaults[.showOnAllDisplays] {
            for (screen, window) in windows {
                let screenSize = adjustedSizeForScreen(size, screen: screen)
                if force || window.frame.size != screenSize {
                    resizeWindow(window, on: screen, to: screenSize, animated: animated)
                }
            }
        } else if let window {
            let screen = window.screen ?? NSScreen.screens.first { $0.frame.intersects(window.frame) } ?? NSScreen.main ?? NSScreen.screens.first
            guard let screen else { return }
            let screenSize = adjustedSizeForScreen(size, screen: screen)
            if force || window.frame.size != screenSize {
                resizeWindow(window, on: screen, to: screenSize, animated: animated)
            }
        }
    }

    private func resizeWindow(_ window: NSWindow, on screen: NSScreen, to size: CGSize, animated: Bool) {
        let screenFrame = screen.frame
        // Clamp width to screen width so the notch never extends beyond screen edges on scaled displays
        let clampedWidth = min(size.width, screenFrame.width).rounded()
        let clampedHeight = min(size.height, screenFrame.height).rounded()
        let centerX = screenFrame.midX
        let newX = (centerX - (clampedWidth / 2)).rounded()
        let newY = (screenFrame.origin.y + screenFrame.height - clampedHeight).rounded()
        let targetFrame = NSRect(x: newX, y: newY, width: clampedWidth, height: clampedHeight)

        window.setFrame(targetFrame, display: true)
    }

    private func shouldAnimateResize(for newSize: CGSize) -> Bool {
        
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {        LockScreenLiveActivityWindowManager.shared.configure(viewModel: vm)
        LockScreenManager.shared.configure(viewModel: vm)
        
        // Migrate legacy progress bar settings
        Defaults.Keys.migrateProgressBarStyle()
        Defaults.Keys.migrateThirdPartyDDCIntegration()

        Defaults.publisher(.enableThirdPartyDDCIntegration, options: [])
            .sink { _ in
                Defaults.Keys.syncLegacyThirdPartyDDCKeys()
            }
            .store(in: &cancellables)

        Defaults.publisher(.thirdPartyDDCProvider, options: [])
            .sink { _ in
                Defaults.Keys.syncLegacyThirdPartyDDCKeys()
            }
            .store(in: &cancellables)
        
        // Initialize idle animations (load bundled + built-in face)

        installTopMenuItemsIfNeeded()

        Defaults.publisher(.focusMonitoringMode, options: [])
            .sink { [weak self] _ in
                self?.updateFocusMenuState()
            }
            .store(in: &cancellables)
        
        // Setup SystemHUD Manager
        SystemHUDManager.shared.setup(coordinator: coordinator)

        // Setup BetterDisplay integration
        BetterDisplayManager.shared.configure(coordinator: coordinator)

        // Setup Lunar integration
        LunarManager.shared.configure(coordinator: coordinator)
        
        // Setup ScreenRecording Manager
        if Defaults.Keys.enableScreenRecordingDetection {
            ScreenRecordingManager.shared.startMonitoring()
        }

        // Setup Do Not Disturb Manager
        if Defaults.Keys.enableDoNotDisturbDetection {
            dndManager.startMonitoring()
        }

        // Setup Privacy Indicator Manager (camera/mic; managed by the application lifecycle).
        if true {
            PrivacyIndicatorManager.shared.startMonitoring()
        }
        
        // Setup Real-time Audio Waveform capture if enabled
        
        
        // Observe enableRealTimeWaveform changes
        
        
        // Observe tab changes - use immediate resize to keep the notch pinned
        // Deferred to next run loop tick because @Published fires on willSet,
        // so coordinator.currentView still holds the OLD value at emission time.
        coordinator.$currentView.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateWindowSizeForTabSwitch()
            }
        }.store(in: &cancellables)

        // Observe terminal settings changes
        Defaults.publisher(.enableTerminalFeature, options: []).sink { [weak self] _ in
            self?.debouncedUpdateWindowSize()
        }.store(in: &cancellables)

        Defaults.publisher(.terminalMaxHeightFraction, options: []).sink { [weak self] _ in
            self?.debouncedUpdateWindowSize()
        }.store(in: &cancellables)

        ReminderLiveActivityManager.shared.$activeWindowReminders
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.debouncedUpdateWindowSize()
            }
            .store(in: &cancellables)

        // Pin/unpin the notch above all spaces when the hide option changes:
        // "Never hide" joins the max-level CGSSpace, the hide options leave it.
        
        
        // Observe minimalistic UI setting changes - trigger window resize
        
        
        // Note: Polling setting removed - now uses event-driven private API detection only

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            self?.adjustWindowPosition(changeAlpha: true)
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            self?.adjustWindowPosition()
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            DispatchQueue.main.async {
                window.alphaValue =
                    self.coordinator.selectedScreen == self.coordinator.preferredScreen ? 1 : 0
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            self.coordinator.suppressHoverOpen(for: 1)
            self.vm.closeForLockScreen()
            self.viewModels.values.forEach { $0.closeForLockScreen() }
            self.cleanupWindows(shouldInvert: true)

            if !Defaults[.showOnAllDisplays] {
                let viewModel = self.vm
                let window = self.createDynamicIslandWindow(
                    for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
                self.window = window
                self.adjustWindowPosition(changeAlpha: true)
            } else {
                self.adjustWindowPosition()
            }

        }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(onScreenLocked(_:)),
            name: NSNotification.Name(rawValue: "com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(onScreenUnlocked(_:)),
            name: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"), object: nil)

        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createDynamicIslandWindow(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }
        
        // MacKit settings expose every feature; no second app onboarding window.
        coordinator.firstLaunch = false

        previousScreens = NSScreen.screens

        // Skip weather under UI testing: prepareLocationAccess prompts for Location.
        if Defaults[.enableLockScreenWeatherWidget] {
            LockScreenWeatherManager.shared.prepareLocationAccess()
            Task { @MainActor in
                await LockScreenWeatherManager.shared.refresh(force: true)
            }
        }

    }

    private func installTopMenuItemsIfNeeded() {
        guard let mainMenu = NSApp.mainMenu else { return }
        if mainMenu.items.contains(where: { $0.identifier?.rawValue == "Atoll.Focus.Menu" }) {
            updateFocusMenuState()
            return
        }

        let insertionIndex = preferredMenuInsertionIndex(in: mainMenu)

        let focusMenuItem = NSMenuItem(title: "Focus", action: nil, keyEquivalent: "")
        focusMenuItem.identifier = NSUserInterfaceItemIdentifier("Atoll.Focus.Menu")
        let focusSubmenu = NSMenu(title: "Focus")

        let withoutDevTools = NSMenuItem(
            title: "Use without DevTools",
            action: #selector(selectFocusWithoutDevTools),
            keyEquivalent: ""
        )
        withoutDevTools.target = self

        let useDevTools = NSMenuItem(
            title: "Use DevTools",
            action: #selector(selectFocusUseDevTools),
            keyEquivalent: ""
        )
        useDevTools.target = self

        focusSubmenu.addItem(withoutDevTools)
        focusSubmenu.addItem(useDevTools)
        focusMenuItem.submenu = focusSubmenu
        mainMenu.insertItem(focusMenuItem, at: insertionIndex)

        focusWithoutDevToolsMenuItem = withoutDevTools
        focusUseDevToolsMenuItem = useDevTools

        let accessibilityMenuItem = NSMenuItem(title: "Accessibility", action: nil, keyEquivalent: "")
        accessibilityMenuItem.identifier = NSUserInterfaceItemIdentifier("Atoll.Accessibility.Menu")
        let accessibilitySubmenu = NSMenu(title: "Accessibility")

        let requestAccessibility = NSMenuItem(
            title: "Request Accessibility Access",
            action: #selector(requestAccessibilityAccess),
            keyEquivalent: ""
        )
        requestAccessibility.target = self

        let openAccessibility = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        openAccessibility.target = self

        accessibilitySubmenu.addItem(requestAccessibility)
        accessibilitySubmenu.addItem(openAccessibility)
        accessibilityMenuItem.submenu = accessibilitySubmenu
        mainMenu.insertItem(accessibilityMenuItem, at: insertionIndex + 1)

        let permissionsMenuItem = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        permissionsMenuItem.identifier = NSUserInterfaceItemIdentifier("Atoll.Permissions.Menu")
        let permissionsSubmenu = NSMenu(title: "Permissions")

        let requestFullDisk = NSMenuItem(
            title: "Request Full Disk Access",
            action: #selector(requestFullDiskAccess),
            keyEquivalent: ""
        )
        requestFullDisk.target = self

        let openFullDisk = NSMenuItem(
            title: "Open Full Disk Access Settings",
            action: #selector(openFullDiskAccessSettings),
            keyEquivalent: ""
        )
        openFullDisk.target = self

        let openDevTools = NSMenuItem(
            title: "Open Developer Tools Settings",
            action: #selector(openDeveloperToolsSettingsFromMenu),
            keyEquivalent: ""
        )
        openDevTools.target = self

        permissionsSubmenu.addItem(requestFullDisk)
        permissionsSubmenu.addItem(openFullDisk)
        permissionsSubmenu.addItem(NSMenuItem.separator())
        permissionsSubmenu.addItem(openDevTools)
        permissionsMenuItem.submenu = permissionsSubmenu
        mainMenu.insertItem(permissionsMenuItem, at: insertionIndex + 2)

        let toolsMenuItem = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        toolsMenuItem.identifier = NSUserInterfaceItemIdentifier("Atoll.Tools.Menu")
        let toolsSubmenu = NSMenu(title: "Tools")

        let loggingLevelItem = NSMenuItem(title: "Logging Level", action: nil, keyEquivalent: "")
        let loggingLevelSubmenu = NSMenu(title: "Logging Level")
        
        let levels: [(String, LogLevel)] = [
            ("No Logging", .none),
            ("Error", .error),
            ("Warning", .warning),
            ("Info", .info),
            ("Debug", .debug)
        ]
        
        for (title, level) in levels {
            let item = NSMenuItem(title: title, action: #selector(setLogLevel(_:)), keyEquivalent: "")
            item.target = self
            item.tag = level.rawValue
            item.state = (Defaults[.logLevel] == level) ? NSControl.StateValue.on : NSControl.StateValue.off
            loggingLevelSubmenu.addItem(item)
        }
        loggingLevelItem.submenu = loggingLevelSubmenu
        toolsSubmenu.addItem(loggingLevelItem)

        toolsSubmenu.addItem(NSMenuItem.separator())
        
        let exportLogsItem = NSMenuItem(title: "Export Logs", action: #selector(exportLogs), keyEquivalent: "")
        exportLogsItem.target = self
        toolsSubmenu.addItem(exportLogsItem)

        toolsMenuItem.submenu = toolsSubmenu
        mainMenu.insertItem(toolsMenuItem, at: insertionIndex + 3)

        updateFocusMenuState()
    }

    private func preferredMenuInsertionIndex(in mainMenu: NSMenu) -> Int {
        if let index = mainMenu.items.firstIndex(where: { $0.title == "Window" }) {
            return index
        }
        if let index = mainMenu.items.firstIndex(where: { $0.title == "Help" }) {
            return index
        }
        return max(mainMenu.numberOfItems, 0)
    }

    private func updateFocusMenuState() {
        let mode = Defaults[.focusMonitoringMode]
        focusWithoutDevToolsMenuItem?.state = mode == .withoutDevTools ? .on : .off
        focusUseDevToolsMenuItem?.state = mode == .useDevTools ? .on : .off
    }

    @objc private func selectFocusWithoutDevTools() {
        Defaults[.focusMonitoringMode] = .withoutDevTools
        updateFocusMenuState()
    }

    @objc private func selectFocusUseDevTools() {
        Defaults[.focusMonitoringMode] = .useDevTools
        updateFocusMenuState()
    }

    @objc private func requestAccessibilityAccess() {
        AccessibilityPermissionStore.shared.requestAuthorizationPrompt()
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermissionStore.shared.openSystemSettings()
    }

    @objc private func requestFullDiskAccess() {
        FullDiskAccessPermissionStore.shared.requestAccessPrompt()
    }

    @objc private func openFullDiskAccessSettings() {
        FullDiskAccessPermissionStore.shared.openSystemSettings()
    }

    @objc private func openDeveloperToolsSettingsFromMenu() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_DevTools",
            "x-apple.systempreferences:com.apple.preference.security"
        ]

        for candidate in urls {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    @objc private func setLogLevel(_ sender: NSMenuItem) {
        guard let level = LogLevel(rawValue: sender.tag) else { return }
        Defaults[.logLevel] = level
        
        guard let mainMenu = NSApp.mainMenu,
              let toolsItem = mainMenu.item(withTitle: "Tools"),
              let toolsMenu = toolsItem.submenu,
              let loggingItem = toolsMenu.items.first(where: { $0.title == "Logging Level" }),
              let loggingSubmenu = loggingItem.submenu else { return }
              
        for item in loggingSubmenu.items {
            item.state = (item.tag == level.rawValue) ? NSControl.StateValue.on : NSControl.StateValue.off
        }
    }

    @objc private func exportLogs() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "Atoll_Logs.zip"
        savePanel.title = "Export Logs & Crash Reports"
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            
            Task.detached(priority: .utility) {
                do {
                    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    
                    let logsFile = tempDir.appendingPathComponent("app_logs.txt")
                    let logProcess = Process()
                    logProcess.executableURL = URL(fileURLWithPath: "/usr/bin/log")
                    logProcess.arguments = ["show", "--predicate", "subsystem == 'com.Ebullioscopic.Atoll' OR subsystem == 'com.Ebullioscopic.Atoll.dev'", "--info", "--debug", "--last", "2d"]
                    
                    let pipe = Pipe()
                    logProcess.standardOutput = pipe
                    try logProcess.run()
                    logProcess.waitUntilExit()
                    
                    let logData = pipe.fileHandleForReading.readDataToEndOfFile()
                    try logData.write(to: logsFile)
                    
                    let diagDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/DiagnosticReports")
                    let allFiles = (try? FileManager.default.contentsOfDirectory(at: diagDir, includingPropertiesForKeys: nil)) ?? []
                    for file in allFiles where file.lastPathComponent.contains("Atoll") {
                        try? FileManager.default.copyItem(at: file, to: tempDir.appendingPathComponent(file.lastPathComponent))
                    }
                    
                    let sysDiagDir = URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")
                    let sysFiles = (try? FileManager.default.contentsOfDirectory(at: sysDiagDir, includingPropertiesForKeys: nil)) ?? []
                    for file in sysFiles where file.lastPathComponent.contains("Atoll") {
                        try? FileManager.default.copyItem(at: file, to: tempDir.appendingPathComponent(file.lastPathComponent))
                    }
                    
                    let zipProcess = Process()
                    zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    zipProcess.currentDirectoryURL = tempDir
                    let items = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
                    zipProcess.arguments = ["-r", url.path] + items
                    
                    try zipProcess.run()
                    zipProcess.waitUntilExit()
                    
                    try? FileManager.default.removeItem(at: tempDir)
                    
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Logs Exported"
                        alert.informativeText = "Logs and crash reports have been successfully exported to \(url.lastPathComponent)."
                        alert.alertStyle = .informational
                        alert.runModal()
                    }
                } catch {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Export Failed"
                        alert.informativeText = "Failed to export logs: \(error.localizedDescription)"
                        alert.alertStyle = .critical
                        alert.runModal()
                    }
                }
            }
        }
    }

    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "dynamic", fileExtension: "m4a")
    }
    
    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }
    
    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.map { $0.localizedName })
                != Set(previousScreens?.map { $0.localizedName } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens
        
        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                self?.cleanupWindows()
                self?.adjustWindowPosition()
            }
        }
    }
    
    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreens = Set(NSScreen.screens)
            
            for screen in windows.keys where !currentScreens.contains(screen) {
                if let window = windows[screen] {
                    viewModels[screen]?.onViewTeardown?()
                    viewModels[screen]?.onViewTeardown = nil
                    window.close()
                    windows.removeValue(forKey: screen)
                    viewModels.removeValue(forKey: screen)
                }
            }
            
            for screen in currentScreens {
                if windows[screen] == nil {
                    let viewModel = DynamicIslandViewModel(screen: screen.localizedName)
                    let window = createDynamicIslandWindow(for: screen, with: viewModel)
                    
                    windows[screen] = window
                    viewModels[screen] = viewModel
                }
                
                if let window = windows[screen], let viewModel = viewModels[screen] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)
                    
                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let selectedScreen: NSScreen

            if let preferredScreen = NSScreen.screens.first(where: {
                $0.localizedName == coordinator.preferredScreen
            }) {
                coordinator.selectedScreen = coordinator.preferredScreen
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main {
                coordinator.selectedScreen = mainScreen.localizedName
                selectedScreen = mainScreen
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }
            
            vm.screen = selectedScreen.localizedName
            vm.notchSize = getClosedNotchSize(screen: selectedScreen.localizedName)
            
            if window == nil {
                window = createDynamicIslandWindow(for: selectedScreen, with: vm)
            }
            
            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)
                
                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }
    }
    
    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }
    
    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    @objc func quitAction() {
        NSApplication.shared.terminate(nil)
    }

}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}


