// MacKit feature reduction, modified 2026-11-08.
// See THIRD_PARTY_NOTICES.md; GPL-3.0-or-later.
// MacKit host adaptation, modified 2026-11-08.
// See THIRD_PARTY_NOTICES.md for the host integration changes; GPL-3.0-or-later.
/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See THIRD_PARTY_NOTICES.md for the original NOTICE and attribution.
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
import Foundation
import SwiftUI

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel

    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var reminderManager = ReminderLiveActivityManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @ObservedObject var privacyManager = PrivacyIndicatorManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @ObservedObject var lockScreenManager = LockScreenManager.shared
    @ObservedObject var capsLockManager = CapsLockManager.shared
    @ObservedObject var localSendService = LocalSendService.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared

    @Default(.enableReminderLiveActivity) var enableReminderLiveActivity
    @Default(.reminderPresentationStyle) var reminderPresentationStyle
    private let showCapsLockLabel = NotchConfiguration.showCapsLockLabel
    private let capsLockTintMode = NotchConfiguration.capsLockIndicatorTintMode
    private let enableDoNotDisturbDetection = true
    @Default(.showDoNotDisturbIndicator) var showDoNotDisturbIndicator
    private let enableScreenRecordingDetection = true
    @Default(.enableCapsLockIndicator) var enableCapsLockIndicator
    @Default(.showStandardMediaControls) var showStandardMediaControls
    @Default(.externalDisplayStyle) var externalDisplayStyle
    @Default(.hideNonNotchUntilHover) var hideNonNotchUntilHover
    @Default(.terminalStickyMode) var terminalStickyMode

    // Battery settings reactivity
    @Default(.showPowerStatusNotifications) var showPowerStatusNotifications
    @Default(.showChargingBatteryHUD) var showChargingBatteryHUD
    @Default(.showLowBatteryHUD) var showLowBatteryHUD
    @Default(.showFullBatteryHUD) var showFullBatteryHUD
    @Default(.inlineHUD) private var inlineHUDLayout
    @Default(.hideLyricsWhenPaused) private var hideLyricsPreference
    @Default(.showLyricsBelowBuiltinNotch) private var showBuiltinLyrics
    @Default(.hideNonNotchUntilHover) private var hideExternalUntilHover
    @State private var onlyBuiltinDisplay = BuiltinLyricAvailability.hasOnlyBuiltinDisplay
    @Default(.showOnAllDisplays) var showOnAllDisplays
    private let lowBatteryHUDStyle = NotchConfiguration.lowBatteryHUDStyle
    private let fullBatteryHUDStyle = NotchConfiguration.fullBatteryHUDStyle

    // Dynamic sizing based on view type and graph count with smooth transitions
    var dynamicNotchSize: CGSize {
        let baseSize =
            NotchConfiguration.enableMinimalisticUI
            ? minimalisticOpenNotchSize(isDynamicIslandMode: isDynamicIslandMode) : openNotchSize

        // When inline sneak peek is active in closed notch, use the wider inline width
        // so the outer maxWidth frame doesn't clip the expanded content
        let airPodsListeningModeSneakActive =
            vm.notchState == .closed
            && coordinator.sneakPeek.show
            && coordinator.sneakPeek.type == .bluetoothAudio
            && coordinator.sneakPeek.value < 0
            && AirPodsListeningMode.fromHUDSymbol(coordinator.sneakPeek.icon) != nil
        let inlineSneakPeekActive =
            vm.notchState == .closed
            && (coordinator.expandingView.show
                && (coordinator.expandingView.type == .music)
                && Defaults[.sneakPeekStyles] == .inline
                || airPodsListeningModeSneakActive)
            && NotchConfiguration.enableSneakPeek
        if inlineSneakPeekActive {
            let inlineWidth: CGFloat =
                airPodsListeningModeSneakActive
                ? InlineHUD.airPodsListeningModeWidth(
                    closedNotchWidth: vm.closedNotchSize.width,
                    gestureProgress: gestureProgress,
                    minimalistic: NotchConfiguration.enableMinimalisticUI
                ) + notchHorizontalPadding * 2
                : 460
            return CGSize(width: max(baseSize.width, inlineWidth), height: baseSize.height)
        }

        // Handle battery HUD expansion sizing
        if vm.notchState == .closed && coordinator.expandingView.show && coordinator.expandingView.type == .battery
            && isBatteryHUDVisibleOnCurrentScreen
        {

            if vm.notchState == .closed && coordinator.expandingView.show && coordinator.expandingView.type == .battery
                && isBatteryHUDVisibleOnCurrentScreen && batteryModel.activeTemporaryHUDKind != nil
            {
                return CGSize(width: vm.closedNotchSize.width + 176, height: vm.effectiveClosedNotchHeight)
            }
        }

        var size = NotchOpenLayout.size(for: coordinator.currentView, screenName: vm.screen)
        if vm.notchState == .closed {
            size.width = max(
                size.width, vm.closedNotchSize.width + 2 * reminderActivityWingWidth + notchHorizontalPadding * 2 + 8)
        }
        return size
    }

    @State private var hoverTask: Task<Void, Never>?
    @State private var pendingHoverState: Bool?
    @State private var isHovering: Bool = false
    @State private var lastHapticTime: Date = Date()
    @State private var hoverClickMonitor: Any?
    @State private var hoverClickLocalMonitor: Any?
    @State private var stickyTerminalClickMonitor: Any?
    @State private var hiddenEdgeHoverPollingTask: Task<Void, Never>?
    @State private var isHoveringClosedMusicWaveformControl: Bool = false

    private let gestureProgress: CGFloat = 0
    @State private var skipFeedbackActiveDirection: MusicManager.SkipDirection?

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    private let useMusicVisualizer = NotchConfiguration.useMusicVisualizer

    private let useModernCloseAnimation = NotchConfiguration.useModernCloseAnimation
    private let enableMinimalisticUI = NotchConfiguration.enableMinimalisticUI

    private func runAfter(_ delay: TimeInterval, _ action: @escaping @Sendable @MainActor () -> Void) {
        guard delay >= 0 else { return }
        Task { @MainActor in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            action()
        }
    }

    private var dynamicNotchResizeAnimation: Animation? {
        nil
    }

    private let zeroHeightHoverPadding: CGFloat = 10

    // MARK: - Tab switch direction for smooth transitions

    private var tabSwitchTransition: AnyTransition {
        if coordinator.tabSwitchForward {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    private var standardMediaControlsActive: Bool {
        showStandardMediaControls && !enableMinimalisticUI
    }

    private var closedMusicContentEnabled: Bool {
        enableMinimalisticUI || showStandardMediaControls
    }

    private var isMusicHUDDeferredAfterUnlock: Bool {
        lockScreenManager.shouldDelayPostUnlockMusicHUD
    }

    private var interactionsEnabled: Bool {
        !lockScreenManager.isLocked
    }

    private var isIslandMode: Bool {
        isDynamicIslandMode
    }

    private var notchHorizontalPadding: CGFloat {
        guard vm.notchState == .open else {
            if !closedMediaVisible, mediaIndicatorItems.count == 1, mediaIndicatorItems.first?.id == "calendar" {
                return 6
            }
            return activeCornerRadiusInsets.closed.bottom
        }

        return activeCornerRadiusInsets.opened.top - 5

        return activeCornerRadiusInsets.opened.bottom - 5
    }

    private var notchBottomPadding: CGFloat {
        currentShadowPadding
    }

    private var pillTopOffset: CGFloat {
        isIslandMode ? dynamicIslandTopOffset : 0
    }

    private func closedMusicPairingEligible(hasActiveMusicSnapshot: Bool) -> Bool {
        vm.notchState == .closed
            && hasActiveMusicSnapshot
            && coordinator.musicLiveActivityEnabled
            && closedMusicContentEnabled
            && !vm.hideOnClosed
            && !lockScreenManager.isLocked
            && !isMusicHUDDeferredAfterUnlock
    }

    private var closedLiveActivitySwapTransition: AnyTransition {
        .opacity.animation(.smooth(duration: 0.28))
    }

    // Use minimalistic corner radius ONLY when opened, keep normal when closed
    private var activeCornerRadiusInsets:
        (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat))
    {

        return cornerRadiusInsets
    }

    private var currentShadowPadding: CGFloat {
        notchShadowPaddingValue(isMinimalistic: enableMinimalisticUI)
    }

    private var currentNotchShape: NotchShape {
        let topRadius =
            (vm.notchState == .open && NotchConfiguration.cornerRadiusScaling)
            ? activeCornerRadiusInsets.opened.top
            : activeCornerRadiusInsets.closed.top
        let bottomRadius =
            (vm.notchState == .open && NotchConfiguration.cornerRadiusScaling)
            ? activeCornerRadiusInsets.opened.bottom
            : activeCornerRadiusInsets.closed.bottom
        return NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
    }

    /// Whether the current screen should render as a Dynamic Island pill
    /// rather than the standard notch shape. Always false on physical notch screens.
    private var isDynamicIslandMode: Bool {
        shouldUseDynamicIslandMode(for: currentScreenName)
    }

    private var currentScreenName: String {
        vm.screen ?? coordinator.selectedScreen
    }

    /// Whether the current screen lacks a physical notch.
    private var hidePausedLyrics: Bool {
        !musicManager.isPlaying && Defaults[.pausedMediaHideDelay] < 0 && Defaults[.hideLyricsWhenPaused]
    }

    private var builtinIsOnlyPersistentIsland: Bool {
        if onlyBuiltinDisplay || Defaults[.hideNonNotchUntilHover] { return true }
        if Defaults[.showOnAllDisplays] { return false }
        let preferred = coordinator.selectedScreen
        return NSScreen.screens.first(where: { $0.localizedName == preferred })?.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ]
        .flatMap { $0 as? NSNumber }.map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
    }

    private var builtinLyricShelfVisible: Bool {
        guard musicManager.lyricsReadyForCurrentTrack, !hidePausedLyrics, showBuiltinLyrics,
            builtinIsOnlyPersistentIsland, vm.notchState == .closed,
            !musicManager.isPlayerIdle, !lockScreenManager.isLocked,
            let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }),
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return false }
        return CGDisplayIsBuiltin(number.uint32Value) != 0
    }

    private var isNonNotchScreen: Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return true
        }
        return screen.safeAreaInsets.top <= 0
    }

    /// Whether the global sneak peek is visible on this specific screen.
    private var isSneakPeekVisibleOnCurrentScreen: Bool {
        guard coordinator.sneakPeek.show else { return false }
        if [.capsLock, .privacy, .recording, .doNotDisturb].contains(coordinator.sneakPeek.type) { return false }
        guard Defaults[.showOnAllDisplays] else { return true }
        guard let targetScreenName = coordinator.sneakPeek.targetScreenName else { return true }
        return currentScreenName == targetScreenName
    }

    /// Whether the notch/island should hide off-screen when closed on a non-notch display.
    /// Temporarily reveals the notch when a sneakPeek HUD (volume, brightness, music, etc.) is active.
    private var shouldHideUntilHover: Bool {
        hideNonNotchUntilHover && isNonNotchScreen && vm.notchState == .closed && !isSneakPeekVisibleOnCurrentScreen
    }

    /// Whether the fallback top-edge hover detector should run.
    /// This is only needed when the notch is fully hidden off-screen and
    /// regular `.onHover` hit-testing may not trigger reliably.
    private var shouldUseHiddenEdgeHoverPolling: Bool {
        hideNonNotchUntilHover && isNonNotchScreen && !lockScreenManager.isLocked
    }

    /// Whether the LocalSend live activity should be shown
    private var localSendLiveActivityActive: Bool {
        localSendService.isSending || localSendService.transferState == .completed || isLocalSendFailedOrRejected
    }

    private var isLocalSendFailedOrRejected: Bool {
        if case .failed = localSendService.transferState { return true }
        if case .rejected = localSendService.transferState { return true }
        return false
    }

    /// Pill shape for Dynamic Island mode with animated corner radius transitions.
    private var currentPillShape: DynamicIslandPillShape {
        let radius: CGFloat
        if vm.notchState == .open {
            radius =
                enableMinimalisticUI
                ? minimalisticCornerRadiusInsets.opened.top
                : dynamicIslandPillCornerRadiusInsets.opened
        } else {
            // Use half the closed height for a true capsule shape
            radius = max(vm.closedNotchSize.height / 2, dynamicIslandPillCornerRadiusInsets.closed.standard)
        }
        return DynamicIslandPillShape(cornerRadius: radius)
    }

    private var isBatteryHUDVisibleOnCurrentScreen: Bool {
        guard coordinator.expandingView.show, coordinator.expandingView.type == .battery else { return false }
        guard showPowerStatusNotifications else { return false }
        guard batteryModel.activeTemporaryHUDKind != nil else { return false }
        if showOnAllDisplays { return true }
        guard let targetScreenName = batteryModel.activeTemporaryHUDTargetScreenName else { return true }
        return currentScreenName == targetScreenName
    }

    private var isCurrentScreenExpansionVisible: Bool {
        guard coordinator.expandingView.show else { return false }
        if [.capsLock, .privacy, .recording, .doNotDisturb].contains(coordinator.expandingView.type) { return false }
        if coordinator.expandingView.type == .battery {
            return isBatteryHUDVisibleOnCurrentScreen
        }
        return true
    }

    private var currentScreenExpansionType: SneakContentType? {
        isCurrentScreenExpansionVisible ? coordinator.expandingView.type : nil
    }

    private var activeClosedBatterySurfaceShape: AnyShape? {
        guard vm.notchState == .closed else { return nil }
        guard isBatteryHUDVisibleOnCurrentScreen else { return nil }
        guard let kind = batteryModel.activeTemporaryHUDKind else { return nil }

        if isDynamicIslandMode {
            let radius = dynamicIslandPillCornerRadiusInsets.opened
            return AnyShape(DynamicIslandPillShape(cornerRadius: radius))
        } else {
            let topRadius = activeCornerRadiusInsets.closed.top
            let bottomRadius = activeCornerRadiusInsets.closed.bottom
            return AnyShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
        }
    }

    /// Resolves the clip/content shape per-screen: pill on non-notch screens
    /// when dynamic island mode is active, standard notch shape otherwise.
    private var resolvedClipShape: AnyShape {
        if let activeClosedBatterySurfaceShape {
            return activeClosedBatterySurfaceShape
        }
        if isDynamicIslandMode {
            return AnyShape(currentPillShape)
        }
        return AnyShape(currentNotchShape)
    }

    var body: some View {
        installRootLifecycleHandlers(on: rootBodyView)
    }

    private var mainLayoutBase: some View {
        NotchLayout()
            .frame(alignment: .top)
            .padding(.horizontal, notchHorizontalPadding)
            .padding(.horizontal, vm.notchState == .open ? 12 : 0)
            .padding(.bottom, vm.notchState == .open ? (isIslandMode || coordinator.currentView == .terminal ? 4 : 12) : 0)
            .background(.black)
            .clipShape(resolvedClipShape)
            .compositingGroup()
            .shadow(
                color: ((vm.notchState == .open || isHovering) && NotchConfiguration.enableShadow)
                    ? .black.opacity(0.6)
                    : .clear,
                radius: NotchConfiguration.cornerRadiusScaling ? 10 : 5
            )
            // Extra horizontal inset for Dynamic Island mode so the shadow
            // is not clipped by the outer frame constraint
            .padding(.horizontal, isIslandMode ? dynamicIslandShadowInset : 0)
            .padding(.bottom, isIslandMode ? dynamicIslandShadowInset : 0)
            .padding(.top, pillTopOffset)
            .offset(x: closedActivityHorizontalOffset)
            .accessibilityIdentifier("AtollNotch")
            .background(NotchInteractionRegion())
    }

    private var configuredMainLayout: some View {
        mainLayoutBase
            .conditionalModifier(!useModernCloseAnimation) { view in
                let hoverAnimation = Animation.smooth(duration: 0.2)
                let notchStateAnimation = Animation.spring(response: 0.38, dampingFraction: 0.92)
                return
                    view
                    .animation(hoverAnimation, value: isHovering)
                    .animation(notchStateAnimation, value: vm.notchState)
                    .animation(.smooth, value: gestureProgress)
                    .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
            }
            .conditionalModifier(useModernCloseAnimation) { view in
                let hoverAnimation = Animation.smooth(duration: 0.2)
                let openAnimation = Animation.spring(response: 0.38, dampingFraction: 0.92, blendDuration: 0)
                let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                let notchAnimation = vm.notchState == .open ? openAnimation : closeAnimation
                return
                    view
                    .animation(hoverAnimation, value: isHovering)
                    .animation(notchAnimation, value: vm.notchState)
                    .animation(.smooth, value: gestureProgress)
            }
            .conditionalModifier(interactionsEnabled) { view in
                view
                    .contentShape(resolvedClipShape)
                    .onHover { hovering in
                        // The revealed panel moves away from the screen edge;
                        // only the stable global detector owns hover in this mode.
                        if !shouldUseHiddenEdgeHoverPolling { handleHover(hovering) }
                    }
                    .onTapGesture {
                        if !shouldUseHiddenEdgeHoverPolling && handleClosedMusicWaveformTapIfNeeded() {
                            return
                        }
                        if vm.notchState == .closed && Defaults[.enableHaptics] {
                            triggerHapticIfAllowed()
                        }
                        openNotch()
                    }

            }

            // Shadow bottom padding and hide-until-hover offset applied AFTER
            // interaction modifiers so .contentShape / .onHover only covers
            // the actual notch content, not the shadow clearance below it.

            .overlay(alignment: .bottom) {
                if interactionsEnabled && vm.notchState == .open {
                    Color.clear.frame(height: 20).offset(y: 20).contentShape(Rectangle())
                        .onHover { if !shouldUseHiddenEdgeHoverPolling { handleHover($0) } }
                }
            }
            .padding(.bottom, notchBottomPadding)
            .offset(
                y: shouldHideUntilHover && !isHovering
                    ? -(vm.closedNotchSize.height + pillTopOffset + currentShadowPadding + 10)
                    : 0
            )
            .onAppear(perform: {
                if coordinator.firstLaunch {
                    // Single open during first launch; closeHello() handles the timed close.
                    runAfter(1) {
                        withAnimation(vm.animation) {
                            openNotch()
                        }
                    }
                }
            })
            .onChange(of: vm.notchState) { _, newState in
                pendingHoverState = nil
                // Update smart monitoring based on notch state

                // Reset hover state when notch state changes
                if newState == .closed && isHovering {
                    withAnimation {
                        isHovering = false
                    }
                }
                if newState != .closed {
                    isHoveringClosedMusicWaveformControl = false
                }
                if newState == .closed {
                    removeStickyTerminalClickMonitor()
                } else {
                    // Install the outside-click monitor for terminal opens that don't
                    // change `currentView` (e.g. shortcut re-opening with the terminal
                    // tab already selected, where the cursor never enters the notch).
                    syncStickyTerminalOutsideClickMonitor()
                }
                #if os(macOS)
                    if newState == .open {
                    }
                #endif
            }
            .onChange(of: vm.isBatteryPopoverActive) { _, newPopoverState in
                runAfter(0.1) {
                    if !newPopoverState && !isHovering && vm.notchState == .open && !shouldPreventAutoClose() {
                        vm.close()
                    }
                }
            }

            .onChange(of: vm.shouldRecheckHover) { _, _ in
                // Recheck hover state when popovers are closed
                runAfter(0.1) {
                    if vm.notchState == .open && !shouldPreventAutoClose() && !isHovering {
                        vm.close()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                runAfter(0.1) {
                    if vm.notchState == .open && !isHovering && !shouldPreventAutoClose() {
                        vm.close()
                    }
                }
            }
            .onChange(of: coordinator.sneakPeek.show) { _, sneakPeekShowing in
                // When sneak peek finishes, check if user is still hovering and open notch if needed
                if !sneakPeekShowing {
                    runAfter(0.2) {
                        if isHovering && vm.notchState == .closed && !coordinator.isHoverOpenSuppressed {
                            openNotch()
                        }
                    }
                }
            }
            .onChange(of: coordinator.currentView) { _, newValue in

                syncStickyTerminalOutsideClickMonitor()
            }
            .sensoryFeedback(.alignment, trigger: haptics)
            .contextMenu {
                Button("Settings") {
                    SettingsWindowController.shared.showWindow()
                }
                //                Button("Edit") { // Doesnt work....
                //                    let dn = DynamicNotch(content: EditPanelView())
                //                    dn.toggle()
                //                }
                //                #if DEBUG
                //                .disabled(false)
                //                #else
                //                .disabled(true)
                //                #endif
                //                .keyboardShortcut("E", modifiers: .command)
            }
    }

    private var rootBodyView: some View {
        ZStack(alignment: .top) {
            configuredMainLayout
        }
        .frame(
            maxWidth: (dynamicNotchSize.width + (vm.notchState == .open ? 24 : 0)
                + (isDynamicIslandMode ? dynamicIslandShadowInset * 2 : 0)).rounded(),
            maxHeight: (dynamicNotchSize.height + (vm.notchState == .open ? (isDynamicIslandMode ? 4 : 12) : 0)
                + (isDynamicIslandMode ? dynamicIslandTopOffset + dynamicIslandShadowInset : currentShadowPadding))
                .rounded(),
            alignment: .top
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) {
            _ in
            onlyBuiltinDisplay = BuiltinLyricAvailability.hasOnlyBuiltinDisplay
        }
        .environmentObject(privacyManager)
        .background(dragDetector)
        .environmentObject(vm)
    }

    private func installRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        installSecondaryRootLifecycleHandlers(
            on: installPrimaryRootLifecycleHandlers(on: view)
        )
    }

    private func installPrimaryRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        view.onAppear {
            updateIndicatorLayout()
            startHiddenEdgeHoverPolling()
            vm.onViewTeardown = { performViewTeardown() }
        }.onChange(of: mediaIndicatorItems.map(\.id)) { _, _ in updateIndicatorLayout() }
            .onChange(of: terminalStickyMode) { _, _ in syncStickyTerminalOutsideClickMonitor() }
    }

    private func installSecondaryRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        view.onDisappear {
            performViewTeardown()
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .center, spacing: 0) {
            if vm.notchState == .closed {
                VStack(alignment: .leading, spacing: 0) {
                    if let preview = coordinator.settingsPreview, preview.type == .battery {
                        BatteryTemporaryActivityView(
                            kind: preview.title.contains("不足")
                                ? .lowBattery : (preview.title.contains("充满") ? .fullBattery : .charging),
                            baseWidth: vm.closedNotchSize.width, baseHeight: vm.effectiveClosedNotchHeight,
                            isDynamicIslandMode: isDynamicIslandMode,
                            topCornerRadius: activeCornerRadiusInsets.closed.top,
                            previewLevel: preview.title.contains("不足") ? 20 : (preview.title.contains("充满") ? 100 : 75))
                    } else if coordinator.firstLaunch {
                        Spacer()
                        HelloAnimation().frame(width: 200, height: 80).onAppear(perform: {
                            vm.closeHello()
                        })
                        .padding(.top, 40)
                        Spacer()
                    } else {
                        let hasMusicMetadata =
                            !musicManager.songTitle.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                            || !musicManager.artistName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                .isEmpty
                        let hasActiveMusicSnapshot: Bool = {
                            if musicManager.isPlaying { return true }
                            return !musicManager.isPlayerIdle && hasMusicMetadata
                        }()
                        let musicPairingEligible = closedMusicPairingEligible(
                            hasActiveMusicSnapshot: hasActiveMusicSnapshot)
                        let musicSecondary = resolveMusicSecondaryLiveActivity(
                            isMusicPairingEligible: musicPairingEligible)
                        let activeSneakPeekStyle = resolvedSneakPeekStyle()
                        let expansionMatchesSecondary: Bool = {
                            guard let musicSecondary else { return false }
                            switch musicSecondary {
                            case .reminder: return currentScreenExpansionType == .reminder
                            case .recording: return currentScreenExpansionType == .recording
                            case .focus: return currentScreenExpansionType == .doNotDisturb
                            case .capsLock, .shelf: return false
                            }
                        }()
                        let canShowMusicDuringExpansion =
                            !isCurrentScreenExpansionVisible
                            || currentScreenExpansionType == .music
                            || expansionMatchesSecondary
                        let isAirPodsListeningModeSneak =
                            coordinator.sneakPeek.type == .bluetoothAudio
                            && coordinator.sneakPeek.value < 0
                            && AirPodsListeningMode.fromHUDSymbol(coordinator.sneakPeek.icon) != nil

                        if currentScreenExpansionType == .battery
                            && isBatteryHUDVisibleOnCurrentScreen
                            && vm.notchState == .closed
                            && Defaults[.showPowerStatusNotifications]
                            && batteryModel.activeTemporaryHUDKind != nil
                        {
                            BatteryTemporaryActivityView(
                                kind: batteryModel.activeTemporaryHUDKind ?? .charging,
                                baseWidth: vm.closedNotchSize.width,
                                baseHeight: vm.effectiveClosedNotchHeight,
                                isDynamicIslandMode: isDynamicIslandMode,
                                topCornerRadius: activeCornerRadiusInsets.closed.top,
                            )
                            .id(batteryModel.activeTemporaryHUDToken)
                        } else if isSneakPeekVisibleOnCurrentScreen
                            && (inlineHUDLayout || isAirPodsListeningModeSneak
                                || coordinator.sneakPeek.type == .bluetoothAudio)
                            && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery)
                            && (coordinator.sneakPeek.type != .reminder) && coordinator.sneakPeek.type != .capsLock
                            && coordinator.sneakPeek.type != .privacy && coordinator.sneakPeek.type != .recording
                            && coordinator.sneakPeek.type != .doNotDisturb
                            && ((coordinator.sneakPeek.type != .volume && coordinator.sneakPeek.type != .brightness
                                && coordinator.sneakPeek.type != .backlight) || vm.notchState == .closed)
                        {
                            InlineHUD(
                                type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value,
                                icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering,
                                gestureProgress: .constant(0)
                            )
                            .transition(
                                coordinator.sneakPeek.type == .capsLock
                                    ? AnyTransition.move(edge: .trailing).combined(with: .opacity)
                                    : AnyTransition.opacity
                            )
                        } else if canShowMusicDuringExpansion && vm.notchState == .closed && !lockScreenManager.isLocked
                            && !vm.hideOnClosed && (musicPairingEligible || !mediaIndicatorItems.isEmpty)
                        {
                            MusicLiveActivity(secondary: musicSecondary)
                                .id("closed-music-live-activity")
                                .transition(closedLiveActivitySwapTransition)
                        } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .reminder)
                            && vm.notchState == .closed && reminderManager.isActive && enableReminderLiveActivity
                            && !vm.hideOnClosed
                        {
                            ReminderLiveActivity(matchedWingWidth: reminderActivityWingWidth)
                                .transition(closedLiveActivitySwapTransition)
                        } else if !isCurrentScreenExpansionVisible && vm.notchState == .closed
                            && localSendLiveActivityActive && !vm.hideOnClosed
                        {
                            LocalSendLiveActivity()
                                .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
                        } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .lockScreen)
                            && vm.notchState == .closed && (lockScreenManager.isLocked || !lockScreenManager.isLockIdle)
                            && Defaults[.enableLockScreenLiveActivity] && !vm.hideOnClosed
                        {
                            LockScreenLiveActivity()
                                .id("lock-screen-live-activity")
                                .transition(closedLiveActivitySwapTransition)
                        } else if !coordinator.expandingView.show && vm.notchState == .closed && Defaults[.dynamicShelf] && !shelfState.isEmpty
                            && !vm.hideOnClosed && !lockScreenManager.isLocked && !enableMinimalisticUI
                        {
                            ShelfInlineLiveActivity()
                                .transition(.opacity.animation(.smooth(duration: 0.25)))
                        } else if vm.notchState == .open {
                            DynamicIslandHeader(indicators: mediaIndicatorItems)
                                .frame(
                                    height: (NotchConfiguration.enableMinimalisticUI && isDynamicIslandMode)
                                        ? nil : max(24, vm.effectiveClosedNotchHeight))
                        } else {
                            Rectangle().fill(.clear).frame(
                                width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                        }

                        if isSneakPeekVisibleOnCurrentScreen {
                            if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery)
                                && (coordinator.sneakPeek.type != .reminder)
                                && (coordinator.sneakPeek.type != .capsLock) && coordinator.sneakPeek.type != .privacy
                                && coordinator.sneakPeek.type != .recording
                                && coordinator.sneakPeek.type != .doNotDisturb
                                && coordinator.sneakPeek.type != .bluetoothAudio && !inlineHUDLayout
                                && !isAirPodsListeningModeSneak
                                && ((coordinator.sneakPeek.type != .volume && coordinator.sneakPeek.type != .brightness
                                    && coordinator.sneakPeek.type != .backlight) || vm.notchState == .closed)
                            {
                                SystemEventIndicatorModifier(
                                    eventType: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value,
                                    icon: $coordinator.sneakPeek.icon,
                                    sendEventBack: { _ in
                                        //
                                    }
                                )
                                .padding(.top, 8)
                                .padding(.bottom, builtinLyricShelfVisible ? 6 : 10)
                                .padding(.leading, 4)
                                .padding(.trailing, 8)
                            }
                            // Old sneak peek music
                            else if coordinator.sneakPeek.type == .music {
                                if vm.notchState == .closed && !vm.hideOnClosed && activeSneakPeekStyle == .standard {
                                    HStack(alignment: .center) {
                                        Image(systemName: "music.note")
                                        GeometryReader { geo in
                                            MarqueeText(
                                                .constant(musicManager.songTitle + " - " + musicManager.artistName),
                                                textColor: .gray, minDuration: 1, frameWidth: geo.size.width)
                                        }
                                    }
                                    .foregroundStyle(.gray)
                                    .padding(.bottom, 10)
                                }
                            } else if coordinator.sneakPeek.type == .reminder {
                                if !vm.hideOnClosed && activeSneakPeekStyle == .standard,
                                    let reminder = reminderManager.activeReminder
                                {
                                    GeometryReader { geo in
                                        let chipColor = Color(nsColor: reminder.event.calendar.color)
                                            .ensureMinimumBrightness(factor: 0.7)
                                        let title = reminder.event.title.isEmpty ? "Upcoming Reminder" : reminder.event.title
                                        HStack(spacing: 6) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(chipColor)
                                                .frame(width: 8, height: 12)
                                            Text(title)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                                .layoutPriority(0)
                                            Text("• " + reminderSneakPeekTiming(for: reminder, now: reminderManager.currentDate))
                                                .lineLimit(1)
                                                .fixedSize(horizontal: true, vertical: false)
                                                .layoutPriority(1)
                                        }
                                        .font(.system(size: 13))
                                        .foregroundStyle(reminderColor(for: reminder, now: reminderManager.currentDate))
                                        .frame(maxWidth: geo.size.width, alignment: .center)
                                    }
                                    .padding(.bottom, 10)
                                }
                            }
                            // Extension live activity sneak peek

                        }
                    }
                }
                .conditionalModifier(shouldFixSizeForSneakPeek()) { view in
                    view
                        .fixedSize()
                }
                .zIndex(2)
            } else {
                DynamicIslandHeader(indicators: mediaIndicatorItems).frame(height: max(24, vm.effectiveClosedNotchHeight))
            }
            if builtinLyricShelfVisible {
                let lyricWidth = max(180, vm.closedNotchSize.width + 2 * max(0, vm.effectiveClosedNotchHeight - 12))
                let systemBannerVisible = isSneakPeekVisibleOnCurrentScreen && !inlineHUDLayout
                    && [.volume, .brightness, .backlight].contains(coordinator.sneakPeek.type)
                TimedLyricLine(width: lyricWidth - 20, color: Color(nsColor: musicManager.avgColor))
                    .frame(height: 20, alignment: .center)
                    .matchedGeometryEffect(
                        id: "lyricLine", in: albumArtNamespace, properties: .position, anchor: .leading,
                        isSource: vm.notchState == .closed
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, systemBannerVisible ? 6 : 2)
                    .padding(.bottom, 6)
                    .frame(width: lyricWidth).background(.black)
                    .transition(.opacity)
            }
            ZStack {
                if vm.notchState == .open {
                    Group {
                        switch coordinator.currentView {
                        case .home:
                            NotchHomeView(albumArtNamespace: albumArtNamespace)
                        case .shelf:
                            NotchShelfView()
                        case .terminal:
                            NotchTerminalView()
                        }
                    }
                    .id(coordinator.currentView)
                    .transition(tabSwitchTransition)
                }
            }
            .zIndex(1)
            .allowsHitTesting(vm.notchState == .open)
            .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
            .opacity(abs(gestureProgress) > 0.3 ? min(abs(gestureProgress * 2), 0.8) : 1)
            .animation(.smooth(duration: 0.3), value: coordinator.currentView)
        }
        .animation(.smooth(duration: 0.28), value: musicManager.isPlayerIdle)
        .animation(.smooth(duration: 0.28), value: musicManager.isPlaying)
    }

    private func reminderColor(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> Color {
        if isReminderCritical(reminder, now: now) {
            return .red
        }
        return Color(nsColor: reminder.event.calendar.color).ensureMinimumBrightness(factor: 0.7)
    }

    private func reminderSneakPeekTiming(for entry: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        let remaining = max(entry.event.start.timeIntervalSince(now), 0)
        let window = TimeInterval(Defaults[.reminderSneakPeekDuration])
        let time = reminderTimeFormatter.string(from: entry.event.start)
        if remaining <= 0 || (window > 0 && remaining <= window) { return "now • \(time)" }
        let minutes = Int(ceil(remaining / 60))
        let duration = minutes >= 60
            ? "\(minutes / 60)h" + (minutes % 60 == 0 ? "" : " \(minutes % 60)m")
            : "\(minutes)m"
        return "in \(duration) • \(time)"
    }

    private let reminderTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    @ViewBuilder
    func DynamicIslandFaceAnimation() -> some View {
        let sideSize = max(0, vm.effectiveClosedNotchHeight - 12)
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(width: sideSize, height: sideSize)
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                EmptyView()
                    .frame(width: sideSize, height: sideSize)
            }
        }.frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    private func MusicLiveActivity(secondary preResolvedSecondary: MusicSecondaryLiveActivity? = nil) -> some View {
        let secondary = preResolvedSecondary ?? resolveMusicSecondaryLiveActivity()
        let notchContentHeight = max(0, vm.effectiveClosedNotchHeight - 12)
        let wingBaseWidth = max(0, vm.effectiveClosedNotchHeight - 12 + gestureProgress / 2)
        let rawCenterBaseWidth = vm.closedNotchSize.width + (isHovering ? 8 : 0)
        let centerBaseWidth = max(rawCenterBaseWidth, 96)
        let inlineSneakPeekActive =
            (coordinator.expandingView.show && (coordinator.expandingView.type == .music)
                && NotchConfiguration.enableSneakPeek && Defaults[.sneakPeekStyles] == .inline)
        let leftWingWidth = reminderActivityWingWidth
        let rightWingWidth = leftWingWidth
        let effectiveCenterWidth = inlineSneakPeekActive ? 380 : centerBaseWidth
        let notchWidth = leftWingWidth + effectiveCenterWidth + rightWingWidth
        let badgeBaseSize = max(13, notchContentHeight * 0.36)
        let badgeDisplaySize =
            statusItems.isEmpty ? badgeDisplaySize(for: secondary, baseSize: badgeBaseSize) : badgeBaseSize
        let badgeOffset = badgeOverlayOffset(for: secondary, badgeSize: badgeDisplaySize)

        HStack(spacing: 0) {
            ClosedNotchWingLayout(cellSize: closedActivityCellSize) {
                ForEach(mediaIndicatorItems) { item in
                    Image(systemName: item.symbol)
                        .renderingMode(.template)
                        .resizable().scaledToFit()
                        .frame(width: item.id == "calendar" ? closedActivityCellSize * 0.84 : closedActivityGlyphSize,
                               height: item.id == "calendar" ? closedActivityCellSize * 0.84 : closedActivityGlyphSize)
                        .foregroundStyle(item.color)
                        .transition(.opacity)
                }
                if closedMediaVisible {
                    Image(nsImage: musicManager.albumArt)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: closedActivityCellSize, height: closedActivityCellSize)
                        .clipShape(RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed))
                        .matchedGeometryEffect(
                            id: "albumArt", in: albumArtNamespace, properties: .frame, anchor: .topLeading,
                            isSource: vm.notchState == .closed
                        )
                        .albumArtFlip(angle: musicManager.flipAngle)
                        .transition(.opacity)
                }
            }
            .frame(width: leftWingWidth, height: notchContentHeight, alignment: .trailing)
            .animation(.smooth(duration: 0.3), value: closedMediaVisible)
            .animation(.smooth(duration: 0.3), value: mediaIndicatorItems.map(\.id))

            Rectangle()
                .fill(.black)
                .frame(width: effectiveCenterWidth, height: notchContentHeight)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show && coordinator.expandingView.type == .music {
                            MusicTitleMarqueeView(
                                text: musicManager.songTitle,
                                isExplicit: musicManager.isCurrentTrackExplicit,
                                textColor: NotchConfiguration.coloredSpectrogram
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: max(0, (effectiveCenterWidth - vm.closedNotchSize.width) / 2 - 12),
                                badgeHeight: 13
                            )
                            .padding(.leading, 8)
                            .opacity(
                                (coordinator.expandingView.show && NotchConfiguration.enableSneakPeek
                                    && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                            Spacer(minLength: vm.closedNotchSize.width)
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    NotchConfiguration.coloredSpectrogram
                                        ? Color(nsColor: musicManager.avgColor) : Color.gray
                                )
                                .padding(.trailing, 8)
                                .opacity(
                                    (coordinator.expandingView.show && coordinator.expandingView.type == .music
                                        && NotchConfiguration.enableSneakPeek && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0)
                        } else if showBuiltinLyrics && musicManager.lyricsReadyForCurrentTrack
                            && !builtinIsOnlyPersistentIsland && isNonNotchScreen
                        {
                            TimedLyricLine(
                                width: max(0, effectiveCenterWidth - 16),
                                color: NotchConfiguration.coloredSpectrogram
                                    ? Color(nsColor: musicManager.avgColor) : .white
                            )
                            .matchedGeometryEffect(
                                id: "lyricLine", in: albumArtNamespace, properties: .position, anchor: .leading,
                                isSource: vm.notchState == .closed
                            )
                            .padding(.horizontal, 8)
                        }
                    }
                    .clipped()
                )

            ClosedNotchWingLayout(cellSize: closedActivityCellSize) {
                if closedMediaVisible {
                    spectrumView(forceSpectrum: true)
                        .frame(width: 50, height: notchContentHeight)
                        .scaleEffect(1.0)
                        .frame(width: closedActivityCellSize, height: closedActivityCellSize).clipped()
                        .blur(radius: isHoveringClosedMusicWaveformControl ? 2 : 0)
                        .overlay {
                            if shouldShowClosedMusicWaveformPlayPauseOverlay(for: secondary)
                                && isHoveringClosedMusicWaveformControl
                            {
                                Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                    .padding(3).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .contentShape(Rectangle().inset(by: -4))
                        .onHover { hovering in
                            withAnimation(.smooth(duration: 0.16)) {
                                isHoveringClosedMusicWaveformControl =
                                    hovering && shouldShowClosedMusicWaveformPlayPauseOverlay(for: secondary)
                            }
                        }
                }
                if closedShelfCountVisible {
                    ShelfDocumentBadge(count: shelfState.items.count, height: closedActivityGlyphSize)
                }
                if let secondary, case .reminder(let entry) = secondary {
                    MusicReminderSupplementView(
                        entry: entry, now: reminderManager.currentDate,
                        style: reminderPresentationStyle,
                        accent: reminderColor(for: entry, now: reminderManager.currentDate),
                        notchHeight: closedActivityCellSize
                    )
                    .frame(width: closedActivityCellSize, height: closedActivityCellSize)
                }
            }
            .frame(width: rightWingWidth, height: notchContentHeight, alignment: .leading)
            .contentShape(Rectangle())
            .id(secondary?.id ?? "music-spectrum")
            .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: notchWidth, height: notchContentHeight)
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
        .animation(.smooth(duration: 0.25), value: secondary?.id)
        .animation(.smooth(duration: 0.25), value: shelfState.items.count)
        .animation(.smooth(duration: 0.3), value: mediaIndicatorItems.map(\.id))
    }

    private var mediaIndicatorItems: [PersistentActivityItem] {
        var items = statusItems
        if enableReminderLiveActivity, reminderManager.isActive, let entry = reminderManager.activeReminder {
            items.append(
                .init(
                    id: "calendar", symbol: "calendar.badge.clock",
                    color: reminderColor(for: entry, now: reminderManager.currentDate)))
        }
        if Defaults[.dynamicShelf], !shelfState.isEmpty, !lockScreenManager.isLocked {
            items.append(.init(id: "shelf", symbol: "tray.fill", color: .white))
        }
        return items
    }

    private func updateIndicatorLayout() {
        if let delegate = AtollAppDelegate.shared {
            let window =
                delegate.windows.first(where: { $0.key.localizedName == currentScreenName })?.value ?? delegate.window
            let required = addShadowPadding(to: dynamicNotchSize, isMinimalistic: false)
            if let window, window.frame.width < required.width {
                delegate.ensureWindowSize(required, animated: false, force: true, screenName: vm.screen)
            }
        }
    }

    private var closedMediaVisible: Bool {
        !musicManager.isPlayerIdle && coordinator.musicLiveActivityEnabled && closedMusicContentEnabled
    }

    private var closedActivityCellSize: CGFloat { max(18, vm.effectiveClosedNotchHeight - 12) }
    private var closedActivityGlyphSize: CGFloat { closedActivityCellSize * 0.68 }
    private var closedActivitySlotGap: CGFloat { max(6, closedActivityCellSize * 0.22) }
    private func closedWingWidth(for count: Int) -> CGFloat {
        CGFloat(max(1, count)) * closedActivityCellSize + CGFloat(max(1, count) + 1) * closedActivitySlotGap
    }
    private var closedActivityLeftCount: Int { mediaIndicatorItems.count + (closedMediaVisible ? 1 : 0) }
    private var closedShelfCountVisible: Bool {
        Defaults[.dynamicShelf] && !shelfState.isEmpty && !lockScreenManager.isLocked && !enableMinimalisticUI
    }
    private var closedActivityRightCount: Int {
        let reminder = enableReminderLiveActivity && reminderManager.isActive && reminderManager.activeReminder != nil
        return (closedMediaVisible ? 1 : 0) + (reminder ? 1 : 0) + (closedShelfCountVisible ? 1 : 0)
    }
    private var closedActivityLeftWidth: CGFloat {
        closedWingWidth(for: closedActivityLeftCount)
    }
    private var closedCountdownWidth: CGFloat {
        guard enableReminderLiveActivity, let entry = reminderManager.activeReminder, reminderManager.isActive else {
            return 0
        }
        let size = max(0, vm.effectiveClosedNotchHeight - 12)
        switch reminderPresentationStyle {
        case .ringCountdown: return ReminderSupplementMetrics.ringDiameter(for: size) + 3
        case .digital:
            return ReminderSupplementMetrics.digitalFrameWidth(
                for: ReminderSupplementMetrics.digitalCountdownText(for: entry, now: reminderManager.currentDate))
        case .minutes:
            return ReminderSupplementMetrics.minutesFrameWidth(
                for: ReminderSupplementMetrics.minutesCountdownText(for: entry, now: reminderManager.currentDate))
        }
    }
    private var closedActivityRightContentWidth: CGFloat {
        closedWingWidth(for: closedActivityRightCount)
    }
    private var reminderActivityWingWidth: CGFloat {
        max(closedActivityLeftWidth, closedActivityRightContentWidth)
    }
    private var closedActivityHorizontalOffset: CGFloat {
        guard vm.notchState == .closed, !lockScreenManager.isLocked,
            closedMediaVisible || !mediaIndicatorItems.isEmpty,
            !(isSneakPeekVisibleOnCurrentScreen && (inlineHUDLayout || coordinator.sneakPeek.type == .bluetoothAudio)),
            currentScreenExpansionType != .battery
        else { return 0 }
        // Keep the physical notch gap centered while allowing unequal outer wings.
        return 0
    }

    private var statusItems: [PersistentActivityItem] {
        var values: [PersistentActivityItem] = []
        if coordinator.cleaningActive && Defaults[.enableCleaningIndicator] {
            values.append(.init(id: "cleaning", symbol: "sparkles", color: .cyan))
        }
        if let preview = coordinator.settingsPreview, let type = preview.type,
            [.privacy, .capsLock, .recording, .doNotDisturb].contains(type)
        {
            let tint: Color =
                type == .recording
                ? .red : (type == .privacy ? (preview.symbol == "mic.fill" ? .orange : .green) : .accentColor)
            values.append(
                .init(
                    id: "settings-preview", symbol: preview.symbol == "camera.fill" ? "video.fill" : preview.symbol,
                    color: tint))
        }
        if privacyManager.cameraActive && Defaults[.enableCameraDetection] {
            values.append(.init(id: "camera", symbol: "video.fill", color: .green))
        }
        if privacyManager.microphoneActive && Defaults[.enableMicrophoneDetection] {
            values.append(.init(id: "microphone", symbol: "mic.fill", color: .orange))
        }
        if recordingManager.isRecording && Defaults[.showRecordingIndicator] {
            values.append(.init(id: "recording", symbol: "record.circle.fill", color: .red))
        }
        if capsLockManager.isCapsLockActive && Defaults[.enableCapsLockIndicator] {
            values.append(.init(id: "capslock", symbol: "capslock.fill", color: .accentColor))
        }
        if doNotDisturbManager.isDoNotDisturbActive && Defaults.Keys.enableDoNotDisturbDetection
            && Defaults[.showDoNotDisturbIndicator]
        {
            let mode = FocusModeType.resolve(
                identifier: doNotDisturbManager.currentFocusModeIdentifier,
                name: doNotDisturbManager.currentFocusModeName)
            values.append(.init(id: "focus", symbol: "moon.fill", color: mode.accentColor))
        }
        var symbols = Set<String>()
        return values.filter { symbols.insert($0.symbol).inserted }
    }

    private func resolveMusicSecondaryLiveActivity(isMusicPairingEligible: Bool = true) -> MusicSecondaryLiveActivity? {

        if enableReminderLiveActivity, reminderManager.isActive, let reminder = reminderManager.activeReminder {
            return .reminder(reminder)
        }

        // Shelf: show file count as lowest-priority secondary
        if Defaults[.dynamicShelf] && !shelfState.isEmpty && !lockScreenManager.isLocked && !enableMinimalisticUI {
            return .shelf(count: shelfState.items.count)
        }

        return nil
    }

    private func resolvedRightWingWidth(
        for secondary: MusicSecondaryLiveActivity?, baseWidth: CGFloat, centerBaseWidth: CGFloat, notchHeight: CGFloat
    ) -> CGFloat {
        guard let secondary else { return baseWidth }

        switch secondary {
        case .reminder(let entry):
            return reminderRightWingWidth(
                for: entry, baseWidth: baseWidth, notchHeight: notchHeight, now: reminderManager.currentDate)
        case .capsLock(let showLabel):
            return showLabel
                ? scaledWingWidth(baseWidth: baseWidth, centerBaseWidth: centerBaseWidth, factor: 0.4, extra: 12)
                : baseWidth
        case .focus:
            return focusRightWingWidth(baseWidth: baseWidth)
        case .recording:
            return recordingRightWingWidth(baseWidth: baseWidth)
        case .shelf:
            return baseWidth
        }
    }

    private func reminderRightWingWidth(
        for entry: ReminderLiveActivityManager.ReminderEntry, baseWidth: CGFloat, notchHeight: CGFloat, now: Date
    ) -> CGFloat {
        let padding: CGFloat = 16
        switch reminderPresentationStyle {
        case .ringCountdown:
            let diameter = ReminderSupplementMetrics.ringDiameter(for: notchHeight)
            return max(baseWidth, padding + diameter)
        case .digital:
            let countdownText = ReminderSupplementMetrics.digitalCountdownText(for: entry, now: now)
            let width = ReminderSupplementMetrics.digitalFrameWidth(for: countdownText)
            return max(baseWidth, padding + width)
        case .minutes:
            let minutesText = ReminderSupplementMetrics.minutesCountdownText(for: entry, now: now)
            let width = ReminderSupplementMetrics.minutesFrameWidth(for: minutesText)
            return max(baseWidth, padding + width)
        }
    }

    private func focusRightWingWidth(baseWidth: CGFloat) -> CGFloat {
        // Focus pairings now mirror the default music spectrum width to keep the notch compact.
        return baseWidth
    }

    private func recordingRightWingWidth(baseWidth: CGFloat) -> CGFloat {
        // Keep recording pairings compact by reducing the width relative to the notch height.
        let absoluteMin: CGFloat = 38
        let preferredWidth = max(baseWidth * 0.6, 0)
        let maxWidth = min(baseWidth - 6, 52)
        let clampedPreferred = min(preferredWidth, maxWidth)
        return min(baseWidth, max(absoluteMin, clampedPreferred))
    }

    private func scaledWingWidth(baseWidth: CGFloat, centerBaseWidth: CGFloat, factor: CGFloat, extra: CGFloat)
        -> CGFloat
    {
        max(baseWidth, max(centerBaseWidth * factor, baseWidth + extra))
    }

    @ViewBuilder
    private func albumArtBadge(for secondary: MusicSecondaryLiveActivity?, badgeSize: CGFloat) -> some View {
        if let secondary, badgeSize > 0 {
            ZStack {
                Circle()
                    .fill(Color.black)

                switch secondary {
                case .reminder(let entry):
                    let accent = reminderColor(for: entry, now: reminderManager.currentDate)
                    Image(systemName: "clock")
                        .font(.system(size: badgeSize * 0.55, weight: .semibold))
                        .foregroundStyle(accent)
                case .focus(let mode):
                    mode.resolvedActiveIcon(usePrivateSymbol: true)
                        .renderingMode(.template)
                        .font(.system(size: badgeSize * 0.5, weight: .semibold))
                        .foregroundStyle(mode.accentColor)
                case .recording:
                    Circle()
                        .fill(Color.red)
                        .frame(width: badgeSize * 0.45, height: badgeSize * 0.45)
                        .modifier(PulsingModifier())
                case .capsLock:
                    Image(systemName: "capslock.fill")
                        .font(.system(size: badgeSize * 0.5, weight: .semibold))
                        .foregroundStyle(capsLockTintMode.color)
                case .shelf:
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: badgeSize * 0.50, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: badgeSize, height: badgeSize)
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            .transition(.opacity.combined(with: .scale))
        } else {
            EmptyView()
        }
    }

    private func badgeDisplaySize(for secondary: MusicSecondaryLiveActivity?, baseSize: CGFloat) -> CGFloat {
        guard let secondary else { return baseSize }
        switch secondary {
        default:
            return baseSize
        }
    }

    private func badgeOverlayOffset(for secondary: MusicSecondaryLiveActivity?, badgeSize: CGFloat) -> CGSize {
        guard let secondary else { return CGSize(width: badgeSize * 0.2, height: badgeSize * 0.25) }
        switch secondary {
        default:
            return CGSize(width: badgeSize * 0.2, height: badgeSize * 0.25)
        }
    }

    @ViewBuilder
    private func musicRightWing(
        for secondary: MusicSecondaryLiveActivity?, notchHeight: CGFloat, trailingWidth: CGFloat
    ) -> some View {
        switch secondary {
        case .reminder(let entry):
            MusicReminderSupplementView(
                entry: entry,
                now: reminderManager.currentDate,
                style: reminderPresentationStyle,
                accent: reminderColor(for: entry, now: reminderManager.currentDate),
                notchHeight: notchHeight
            )
        case .capsLock(let showLabel):
            if showLabel {
                MusicCapsLockLabelView(color: capsLockTintMode.color)
            } else {
                spectrumView(forceSpectrum: true)
            }
        case .focus:
            spectrumView(forceSpectrum: true)
        case .recording:
            spectrumView(forceSpectrum: true, trailingInset: 6)
        case .shelf(let count):
            ShelfDocumentBadge(count: count)
        case .none:
            spectrumView(
                forceSpectrum: false,
                enableClosedPlayPauseOverlay: shouldShowClosedMusicWaveformPlayPauseOverlay(for: secondary)
            )
        }
    }

    @ViewBuilder
    private func SpectrumVisualizer(
        useMusicVisualizer: Bool,
        forceSpectrum: Bool
    ) -> some View {
        let width = max(0, CGFloat(Defaults[.visualizerBarCount]) * 4 - 2)

        Rectangle()
            .fill(
                (NotchConfiguration.coloredSpectrogram ? Color(nsColor: musicManager.avgColor) : Color.gray)
                    .readableOnBlack()
            )
            .frame(width: 50, alignment: .center)
            .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
            .mask {
                AudioVisualizerView(isPlaying: $musicManager.isPlaying)
                    .frame(width: width, height: 12)
            }

    }

    @ViewBuilder
    private func spectrumView(
        forceSpectrum: Bool,
        trailingInset: CGFloat = 0,
        enableClosedPlayPauseOverlay: Bool = false
    ) -> some View {

        SpectrumVisualizer(useMusicVisualizer: useMusicVisualizer, forceSpectrum: forceSpectrum)
            .blur(radius: (enableClosedPlayPauseOverlay && isHoveringClosedMusicWaveformControl) ? 2.4 : 0)
            .overlay {
                if enableClosedPlayPauseOverlay {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(isHoveringClosedMusicWaveformControl ? 0.24 : 0.02))

                        Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(isHoveringClosedMusicWaveformControl ? 0.98 : 0.0))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.trailing, trailingInset)
            .animation(.smooth(duration: 0.16), value: isHoveringClosedMusicWaveformControl)
            .animation(.smooth(duration: 0.2), value: musicManager.isPlaying)

    }

    private func reminderIconName(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        isReminderCritical(reminder, now: now)
            ? ReminderLiveActivityManager.criticalIconName : ReminderLiveActivityManager.standardIconName
    }

    private func isReminderCritical(_ reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> Bool {
        let window = TimeInterval(Defaults[.reminderSneakPeekDuration])
        guard window > 0 else { return false }
        let remaining = reminder.event.start.timeIntervalSince(now)
        return remaining > 0 && remaining <= window
    }

    @ViewBuilder
    var dragDetector: some View {
        if lockScreenManager.isLocked {
            EmptyView()
        } else if Defaults[.dynamicShelf] && !NotchConfiguration.enableMinimalisticUI {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.data], isTargeted: $vm.dragDetectorTargeting) { _ in true }
                .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
                    if isTargeted, vm.notchState == .closed {
                        coordinator.currentView = .shelf
                        openNotch()
                    } else if !isTargeted {
                        if vm.dropEvent {
                            vm.dropEvent = false
                            return
                        }

                        vm.dropEvent = false
                        if !shouldPreventAutoClose() {
                            vm.close()
                        }
                    }
                }
        } else {
            EmptyView()
        }
    }

    // MARK: - Private Methods
    private func openNotch() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.92)) {
            vm.open()
        }
    }

    private func shouldShowClosedMusicWaveformPlayPauseOverlay(for secondary: MusicSecondaryLiveActivity?) -> Bool {
        return isClosedMusicContext && !Defaults[.openNotchOnHover]
    }

    private var isClosedMusicContext: Bool {
        vm.notchState == .closed
            && coordinator.musicLiveActivityEnabled
            && closedMusicContentEnabled
            && !vm.hideOnClosed
            && !lockScreenManager.isLocked
            && !isMusicHUDDeferredAfterUnlock
            && (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .reminder)
            && (!musicManager.isPlayerIdle || musicManager.bundleIdentifier != nil)
            && !coordinator.firstLaunch
    }

    private func handleClosedMusicWaveformTapIfNeeded() -> Bool {
        guard shouldShowClosedMusicWaveformPlayPauseOverlay(for: nil),
            isHoveringClosedMusicWaveformControl
        else {
            return false
        }

        if Defaults[.enableHaptics] {
            triggerHapticIfAllowed()
        }
        musicManager.playPause()
        return true
    }

    private func hiddenHoverActivationContainsMouse(_ location: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return false
        }

        let horizontalPadding: CGFloat = 8
        let activationWidth = vm.closedNotchSize.width + horizontalPadding * 2
        let activationHeight = max(vm.closedNotchSize.height + zeroHeightHoverPadding, 14)

        let activationRect = CGRect(
            x: screen.frame.midX - activationWidth / 2,
            y: screen.frame.maxY - activationHeight,
            width: activationWidth,
            height: activationHeight
        )

        // CGRect.contains excludes maxY: at the physical screen edge the
        // cursor can be exactly maxY. Include that edge with a small tolerance.
        return location.x >= activationRect.minX && location.x <= activationRect.maxX
            && location.y >= activationRect.minY && location.y <= screen.frame.maxY + 1
    }

    /// The top-edge activation strip remains valid while the island moves down
    /// during reveal. Native shape tracking alone would report a false exit.
    private func hiddenHoverRegionContainsMouse() -> Bool {
        let point = NSEvent.mouseLocation
        let window = AtollAppDelegate.shared?.windows.first(where: { $0.key.localizedName == currentScreenName })?.value
            ?? AtollAppDelegate.shared?.window
        let inVisibleRegion = (window as? DynamicIslandWindow)?.containsInteractionPoint(point, exitPadding: isHovering ? 8 : 0) ?? false
        return hiddenHoverActivationContainsMouse(point) || inVisibleRegion
    }

    /// Cancels every long-lived task / event monitor this view owns. Called from
    /// `.onDisappear` and from `vm.onViewTeardown` on window close. Idempotent.
    private func performViewTeardown() {
        hoverTask?.cancel()
        pendingHoverState = nil
        stopHoverClickMonitor()
        removeStickyTerminalClickMonitor()
        stopHiddenEdgeHoverPolling()
        isHoveringClosedMusicWaveformControl = false
    }

    private func startHiddenEdgeHoverPolling() {
        guard hiddenEdgeHoverPollingTask == nil else { return }

        hiddenEdgeHoverPollingTask = Task { @MainActor in
            while !Task.isCancelled {
                if self.shouldUseHiddenEdgeHoverPolling {
                    let hovering = self.hiddenHoverRegionContainsMouse()
                    if hovering != self.isHovering || self.pendingHoverState != hovering {
                        self.handleHover(hovering)
                    }
                }

                try? await Task.sleep(for: .milliseconds(50))
            }

            self.hiddenEdgeHoverPollingTask = nil
        }
    }

    private func stopHiddenEdgeHoverPolling() {
        hiddenEdgeHoverPollingTask?.cancel()
        hiddenEdgeHoverPollingTask = nil
    }

    private func startHoverClickMonitor() {
        guard Defaults[.openNotchOnHover] || shouldUseHiddenEdgeHoverPolling else { return }
        guard hoverClickMonitor == nil else { return }

        let handleClick: @Sendable () -> Void = { [weak vm, weak lockScreenManager] in
            Task { @MainActor in
                guard let vm, let lockScreenManager else { return }
                guard !lockScreenManager.isLocked else { return }
                guard vm.notchState == .closed else { return }
                guard !self.coordinator.isHoverOpenSuppressed else { return }
                if self.shouldUseHiddenEdgeHoverPolling {
                    guard self.hiddenHoverRegionContainsMouse() else { return }
                    // Here click means expand the revealed island, even when
                    // hover-to-open is off; it must not toggle media playback.
                    self.pendingHoverState = nil
                    self.hoverTask?.cancel()
                    self.isHovering = true
                } else {
                    guard self.isHovering else { return }
                    guard !self.handleClosedMusicWaveformTapIfNeeded() else { return }
                }
                if Defaults[.enableHaptics] {
                    self.triggerHapticIfAllowed()
                }
                self.openNotch()
            }
        }

        // Global monitor catches clicks outside the app window (e.g. when
        // the cursor is at the very top screen edge and the click goes to
        // the system rather than our panel).
        hoverClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { _ in
            handleClick()
        }

        // Local monitor catches clicks that DO hit our window — at the
        // screen edge SwiftUI's .onTapGesture may not fire reliably, but
        // the NSEvent local monitor will.
        hoverClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            handleClick()
            return event
        }
    }

    private func stopHoverClickMonitor() {
        if let hoverClickMonitor {
            NSEvent.removeMonitor(hoverClickMonitor)
            self.hoverClickMonitor = nil
        }
        if let hoverClickLocalMonitor {
            NSEvent.removeMonitor(hoverClickLocalMonitor)
            self.hoverClickLocalMonitor = nil
        }
    }

    /// Installs the global outside-click monitor whenever the Terminal tab is open
    /// (e.g. keyboard-opened terminal), regardless of sticky mode.
    ///
    /// Sticky mode only controls whether the terminal closes when the cursor leaves
    /// the notch (see `shouldPreventAutoClose`).  An outside click should always close
    /// the terminal — this covers the case where the terminal is opened via the
    /// shortcut and the cursor never enters the notch, so there's no hover-out event
    /// to trigger the normal auto-close.
    ///
    /// While the cursor is hovering inside the notch, hover handling owns close
    /// behavior, so the monitor is not installed; it is re-synced on hover-out.
    private func syncStickyTerminalOutsideClickMonitor() {
        guard vm.notchState == .open, coordinator.currentView == .terminal, !isHovering else {
            removeStickyTerminalClickMonitor()
            return
        }
        installStickyTerminalClickMonitor()
    }

    private func installStickyTerminalClickMonitor() {
        guard stickyTerminalClickMonitor == nil else { return }
        stickyTerminalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak vm] _ in
            Task { @MainActor in
                guard let vm, vm.notchState == .open, !vm.isAutoCloseSuppressed else { return }
                let clickLocation = NSEvent.mouseLocation
                if self.isPointInsideNotchWindow(clickLocation) {
                    return
                }
                vm.close()
            }
        }
    }

    private func removeStickyTerminalClickMonitor() {
        if let stickyTerminalClickMonitor {
            NSEvent.removeMonitor(stickyTerminalClickMonitor)
            self.stickyTerminalClickMonitor = nil
        }
    }

    // MARK: - Hover Management

    /// Handle hover state changes with debouncing
    private func handleHover(_ nativeHovering: Bool) {
        let hovering = shouldUseHiddenEdgeHoverPolling ? hiddenHoverRegionContainsMouse() : nativeHovering
        // Polling and native tracking can report the same leave repeatedly.
        // Do not restart its debounce on every sample or it will never finish.
        if pendingHoverState == hovering { return }
        pendingHoverState = hovering
        hoverTask?.cancel()

        if hovering {
            startHoverClickMonitor()
            removeStickyTerminalClickMonitor()
        } else {
            stopHoverClickMonitor()
            if isHoveringClosedMusicWaveformControl {
                withAnimation(.smooth(duration: 0.16)) {
                    isHoveringClosedMusicWaveformControl = false
                }
            }
        }

        if hovering {
            withAnimation(.smooth(duration: 0.2)) {
                isHovering = true
            }

            if vm.notchState == .closed && Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }

            guard vm.notchState == .closed,
                !isSneakPeekVisibleOnCurrentScreen,
                Defaults[.openNotchOnHover]
            else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.vm.notchState == .closed,
                        self.isHovering,
                        !self.isSneakPeekVisibleOnCurrentScreen,
                        !self.coordinator.isHoverOpenSuppressed
                    else { return }

                    self.openNotch()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    if self.shouldUseHiddenEdgeHoverPolling && self.hiddenHoverRegionContainsMouse() {
                        self.pendingHoverState = nil
                        self.handleHover(true)
                        return
                    }
                    withAnimation(.smooth(duration: 0.2)) {
                        self.isHovering = false
                    }

                    if self.vm.notchState == .open && !self.shouldPreventAutoClose() {
                        self.vm.close()
                    } else if self.vm.notchState == .open
                        && Defaults[.terminalStickyMode]
                        && self.coordinator.currentView == .terminal
                    {
                        // Re-sync monitor state through one code path to avoid
                        // monitor lifecycle races between hover and state updates.
                        self.syncStickyTerminalOutsideClickMonitor()
                    }
                }
            }
        }
    }

    private func isPointInsideNotchWindow(_ point: CGPoint) -> Bool {
        if let appDelegate = AtollAppDelegate.shared {
            if Defaults[.showOnAllDisplays] {
                return appDelegate.windows.values.contains(where: { $0.frame.contains(point) })
            }
            if let window = appDelegate.window {
                return window.frame.contains(point)
            }
        }

        return NSApp.windows.contains(where: { $0.frame.contains(point) })
    }

    // Helper function to check if any popovers are active
    private func hasAnyActivePopovers() -> Bool {
        return vm.isBatteryPopoverActive || vm.isMediaOutputPopoverActive || vm.isReminderPopoverActive
    }

    private func shouldPreventAutoClose() -> Bool {
        coordinator.firstLaunch || hasAnyActivePopovers() || vm.isAutoCloseSuppressed
            || SharingStateManager.shared.preventNotchClose
            || (Defaults[.terminalStickyMode] && coordinator.currentView == .terminal)
    }

    // Helper to prevent rapid haptic feedback
    private func triggerHapticIfAllowed() {
        let now = Date()
        if now.timeIntervalSince(lastHapticTime) > 0.3 {  // Minimum 300ms between haptics
            haptics.toggle()
            lastHapticTime = now
        }
    }

    // Estimate the height required for minimalistic overrides (notably web content) and clamp it to the notch bounds.

    // MARK: - Gesture Handling

    #if os(macOS)

    #else

    #endif

    private func shouldFixSizeForSneakPeek() -> Bool {
        guard isSneakPeekVisibleOnCurrentScreen else { return false }
        let style = resolvedSneakPeekStyle()

        // Check for extension sneak peek

        // Original logic for other types
        let isMusicSneak =
            coordinator.sneakPeek.type == .music && vm.notchState == .closed && !vm.hideOnClosed && style == .standard
        let isReminderSneak = coordinator.sneakPeek.type == .reminder && !vm.hideOnClosed && style == .standard
        let isOtherSneak =
            coordinator.sneakPeek.type != .music && coordinator.sneakPeek.type != .reminder && vm.notchState == .closed

        return isMusicSneak || isReminderSneak || isOtherSneak
    }

    private func resolvedSneakPeekStyle() -> SneakPeekStyle {

        return coordinator.sneakPeek.styleOverride ?? Defaults[.sneakPeekStyles]
    }
}

private enum MusicSecondaryLiveActivity: Equatable {

    case reminder(ReminderLiveActivityManager.ReminderEntry)
    case recording
    case focus(FocusModeType)
    case capsLock(showLabel: Bool)

    case shelf(count: Int)

    var id: String {
        switch self {
        case .reminder(let entry):
            return "reminder-\(entry.id)"
        case .recording:
            return "recording"
        case .focus(let mode):
            return "focus-\(mode.rawValue)"
        case .capsLock(let showLabel):
            return showLabel ? "caps-lock-label" : "caps-lock-icon"
        case .shelf(let count):
            return "shelf-\(count)"
        }
    }
}

private struct MusicReminderSupplementView: View {
    let entry: ReminderLiveActivityManager.ReminderEntry
    let now: Date
    let style: ReminderPresentationStyle
    let accent: Color
    let notchHeight: CGFloat

    var body: some View {
        Group {
            switch style {
            case .ringCountdown:
                ringCountdownView
            case .digital:
                digitalCountdownView
            case .minutes:
                minutesCountdownView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private var ringCountdownView: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progressValue)
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.25), value: progressValue)
        }
        .frame(width: min(ringDiameter, max(4, notchHeight - 6)), height: min(ringDiameter, max(4, notchHeight - 6)))
        .padding(1.5)
        .frame(height: notchHeight, alignment: .center)
    }

    private var digitalCountdownView: some View {
        Text(digitalCountdownText)
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .foregroundColor(accent)
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.25), value: digitalCountdownText)
            .frame(width: digitalFrameWidth, alignment: .trailing)
            .frame(height: notchHeight, alignment: .center)
    }

    private var minutesCountdownView: some View {
        Text(minutesCountdownText)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(accent)
            .frame(width: minutesFrameWidth, alignment: .trailing)
            .frame(height: notchHeight, alignment: .center)
    }

    private var progressValue: Double {
        guard entry.leadTime > 0 else { return 1 }
        let remaining = max(entry.event.start.timeIntervalSince(now), 0)
        let elapsed = entry.leadTime - remaining
        return min(max(elapsed / entry.leadTime, 0), 1)
    }

    private var digitalCountdownText: String {
        ReminderSupplementMetrics.digitalCountdownText(for: entry, now: now)
    }

    private var minutesCountdownText: String {
        ReminderSupplementMetrics.minutesCountdownText(for: entry, now: now)
    }

    private var ringDiameter: CGFloat {
        ReminderSupplementMetrics.ringDiameter(for: notchHeight)
    }

    private var digitalFrameWidth: CGFloat {
        ReminderSupplementMetrics.digitalFrameWidth(for: digitalCountdownText)
    }

    private var minutesFrameWidth: CGFloat {
        ReminderSupplementMetrics.minutesFrameWidth(for: minutesCountdownText)
    }
}

private struct MusicCapsLockLabelView: View {
    let color: Color

    var body: some View {
        Text("Caps Lock")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentTransition(.opacity)
    }
}

#if canImport(AppKit)
    private typealias MusicSupplementFont = NSFont
#elseif canImport(UIKit)
    private typealias MusicSupplementFont = UIFont
#endif

enum ReminderSupplementMetrics {
    static func digitalCountdownText(for entry: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        let remaining = max(entry.event.start.timeIntervalSince(now), 0)
        let totalSeconds = Int(remaining.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func minutesCountdownText(for entry: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        let remaining = max(entry.event.start.timeIntervalSince(now), 0)
        let minutes = max(1, Int(ceil(remaining / 60)))
        return minutes == 1 ? "in 1 min" : "in \(minutes) min"
    }

    static func digitalFrameWidth(for text: String) -> CGFloat {
        let width = musicMeasureText(
            text, font: MusicSupplementFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold))
        return max(width + 18, 76)
    }

    static func minutesFrameWidth(for text: String) -> CGFloat {
        let width = musicMeasureText(text, font: MusicSupplementFont.systemFont(ofSize: 13, weight: .semibold))
        return max(width + 18, 88)
    }

    static func ringDiameter(for notchHeight: CGFloat) -> CGFloat {
        max(min(notchHeight - 12, 22), 16)
    }
}

private func musicMeasureText(_ text: String, font: MusicSupplementFont) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    return CGFloat(ceil(NSAttributedString(string: text, attributes: attributes).size().width))
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }
}

/// Every element has the same square slot. Free width is shared equally by the
/// two outer gaps and all inner gaps, independently on each side of the notch.
private struct ClosedNotchWingLayout: Layout {
    let cellSize: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? CGFloat(subviews.count) * cellSize, height: cellSize)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let gap = max(0, (bounds.width - CGFloat(subviews.count) * cellSize) / CGFloat(subviews.count + 1))
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + gap + CGFloat(index) * (cellSize + gap) + cellSize / 2,
                                   y: bounds.midY), anchor: .center,
                       proposal: ProposedViewSize(width: cellSize, height: cellSize))
        }
    }
}
