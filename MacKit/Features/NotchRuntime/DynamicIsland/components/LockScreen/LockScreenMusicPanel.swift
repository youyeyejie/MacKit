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

import SwiftUI
import Defaults

struct LockScreenMusicPanel: View {


    static let collapsedHeight: CGFloat = 180
    static let defaultCollapsedWidth: CGFloat = 420
    static var collapsedSize: CGSize {
        CGSize(width: CGFloat(Defaults[.lockScreenMusicPanelWidth]), height: collapsedHeight)
    }
    static let expandedSize = CGSize(width: 720, height: 340)

    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject private var routeManager = AudioRouteManager.shared
    @StateObject private var volumeModel = MediaOutputVolumeViewModel()
    @ObservedObject private var animator: LockScreenPanelAnimator
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @State private var isActive = true
    @State private var isExpanded = false
    @State private var isVolumeSliderVisible = false
    @State private var isAirPlayPopoverPresented = false
    
    @State private var collapseWorkItem: DispatchWorkItem?
    private let lockScreenGlassStyle = NotchConfiguration.lockScreenGlassStyle
    private let glassCustomizationMode = NotchConfiguration.lockScreenGlassCustomizationMode
    private let musicGlassVariant = NotchConfiguration.lockScreenMusicLiquidGlassVariant
    @Default(.lockScreenShowAppIcon) var showAppIcon
    @Default(.lockScreenPanelShowsBorder) var showPanelBorder
    @Default(.lockScreenMusicUsesEnhancedLiquidBorder) private var useEnhancedLiquidBorder
    @Default(.lockScreenPanelUsesBlur) var enableBlur
    private let showMediaOutputControl = NotchConfiguration.showMediaOutputControl
    private let showShuffleAndRepeat = NotchConfiguration.showShuffleAndRepeat
    private let slotConfig = NotchConfiguration.musicControlSlots
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.enableLyrics) private var enableLyrics
    private let lockScreenParallaxEnabled = NotchConfiguration.lockScreenMusicAlbumParallaxEnabled
    @Default(.lockScreenMusicPanelWidth) private var collapsedPanelWidth
    private let fullscreenArtworkEnabled = NotchConfiguration.lockScreenMusicFullscreenArtworkEnabled
    private let keepAlbumArtVisibleDuringFullscreenArtwork = NotchConfiguration.lockScreenKeepAlbumArtVisibleDuringFullscreenArtwork

    init(animator: LockScreenPanelAnimator) {
        _animator = ObservedObject(wrappedValue: animator)
    }
    
    private let collapsedPanelCornerRadius: CGFloat = 28
    private let expandedPanelCornerRadius: CGFloat = 52
    private let collapsedAlbumArtCornerRadius: CGFloat = 16
    private let expandedAlbumArtCornerRadius: CGFloat = 60
    private let expandedContentSpacing: CGFloat = 40
    private let collapseTimeout: TimeInterval = 5
    private let collapsedSliderExtraHeight: CGFloat = 72
    private let expandedSliderExtraHeight: CGFloat = 88
    private let collapsedLyricsExtraHeight: CGFloat = 64
    private let expandedLyricsExtraHeight: CGFloat = 96

    private var shouldUseFrostedBlur: Bool { false }

    private var currentSize: CGSize {
        let base = isExpanded ? Self.expandedSize : collapsedPanelSize
        return CGSize(width: base.width, height: base.height + totalExtraHeight)
    }

    private var collapsedPanelSize: CGSize {
        CGSize(width: CGFloat(collapsedPanelWidth), height: Self.collapsedHeight)
    }

    private var panelCornerRadius: CGFloat {
        isExpanded ? expandedPanelCornerRadius : collapsedPanelCornerRadius
    }

    private var usesCustomLiquidGlass: Bool { true }

    private var usesStandardLiquidGlass: Bool { false }

    private var usesLiquidGlass: Bool { true }

    private var usesEnhancedCustomLiquidBorder: Bool {
        usesCustomLiquidGlass && useEnhancedLiquidBorder
    }

    private var hidesInlineArtworkForSpotifyCanvasFallback: Bool { false }

    private var usesSpotifyCanvasFallbackContentPresentation: Bool { false }

    private var showsDetachedFullscreenLyrics: Bool { false }

    private var shouldShowInlineLyrics: Bool {
        enableLyrics
    }
    
    var body: some View {
        if isActive && musicManager.hasActiveSession {
            panelContent
        } else {
            Color.clear
                .frame(width: collapsedPanelSize.width, height: collapsedPanelSize.height)
        }
    }
    
    private var panelContent: some View {
        ZStack(alignment: .topLeading) {
            panelBackgroundLayer
            panelForeground
                .shadow(
                    color: false ? Color.black.opacity(0.55) : .clear,
                    radius: false ? 10 : 0,
                    x: 0,
                    y: false ? 2 : 0
                )
        }
        .frame(width: currentSize.width, height: currentSize.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .overlay {
            if showPanelBorder {
                panelBorderOverlay
            }
        }
        .shadow(
            color: false ? Color.black.opacity(0.35) : Color.black.opacity(0.3),
            radius: false ? 26 : 20,
            x: 0,
            y: false ? 14 : 10
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.28), value: isExpanded)
        .animation(.easeInOut(duration: 0.24), value: shouldShowVolumeSlider)
        .onAppear {
            sliderValue = musicManager.elapsedTime
            isActive = true
            updatePanelSize(animated: false)
            routeManager.refreshDevices()
            
        }
        .onDisappear {
            isActive = false
            cancelCollapseTimer()
            isVolumeSliderVisible = false
        }
        
        .onChange(of: isExpanded) { _, expanded in
            updatePanelSize()
        }
        .onChange(of: showMediaOutputControl) { _, enabled in
            if !enabled {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    isVolumeSliderVisible = false
                }
            }
            updatePanelSize()
        }
        
        
        .onChange(of: routeManager.devices) { _, _ in
            
                updatePanelSize()
            
        }
        .onChange(of: enableLyrics) { _, _ in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                updatePanelSize()
            }
        }
        
        .onChange(of: glassCustomizationMode) { _, _ in
        }
        .onChange(of: musicGlassVariant) { _, _ in
            
            
        }
        .scaleEffect(animator.isPresented ? 1 : 0.9, anchor: .center)
        .opacity(animator.isPresented ? 1 : 0)
        .animation(.spring(response: 0.52, dampingFraction: 0.8), value: animator.isPresented)
    }

    @ViewBuilder
    private var panelForeground: some View {
        Group {
            if isExpanded {
                expandedLayout
            } else {
                collapsedLayout
            }
        }
        .padding(.horizontal, false ? (isExpanded ? 24 : 22) : (isExpanded ? 24 : 20))
        .padding(.vertical, false ? (isExpanded ? 18 : 14) : (isExpanded ? 22 : 16))
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: false ? .center : .topLeading
        )
    }

    private var collapsedLayout: some View {
        VStack(spacing: 12) {
            collapsedHeader
            progressBar
                .padding(.top, 4)
                .frame(maxWidth: .infinity)
            playbackControls(alignment: .center)
                .padding(.top, 4)
        }
    }

    private var expandedLayout: some View {
        Group {
            
                HStack(alignment: .center, spacing: expandedContentSpacing) {
                    albumArtButton(size: 230, cornerRadius: expandedAlbumArtCornerRadius)
                        .frame(width: 230, height: 230)

                    VStack(alignment: .leading, spacing: 20) {
                        expandedHeader
                        progressBar
                            .padding(.top, 10)
                            .frame(maxWidth: .infinity)
                        playbackControls(alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var collapsedHeader: some View {
        HStack(alignment: .center, spacing: false ? 10 : 16) {
            
                albumArtButton(size: 60, cornerRadius: collapsedAlbumArtCornerRadius)
            

            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 1) {
                    MusicTitleMarqueeView(
                        text: musicManager.songTitle.isEmpty ? "No Music Playing" : musicManager.songTitle,
                        isExplicit: !musicManager.songTitle.isEmpty && musicManager.isCurrentTrackExplicit,
                        font: .system(size: 12, weight: .semibold),
                        nsFont: .subheadline,
                        textColor: .white,
                        minDuration: 0.45,
                        frameWidth: geo.size.width,
                        badgeSpacing: 5,
                        badgeLabel: "E",
                        badgeHeight: 13,
                        badgeForegroundColor: Color.black.opacity(0.72),
                        badgeBackgroundColor: Color.white.opacity(0.46),
                        badgeHorizontalPadding: 4,
                        badgeMinWidth: 14,
                        badgeCornerRadius: 4
                    )

                    Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(NotchConfiguration.playerColorTinting ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                        .lineLimit(1)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .leading)

            visualizer(height: 16)
        }
        .frame(height: 60)
    }

    private var expandedHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 6) {
                    MusicTitleMarqueeView(
                        text: musicManager.songTitle.isEmpty ? "No Music Playing" : musicManager.songTitle,
                        isExplicit: !musicManager.songTitle.isEmpty && musicManager.isCurrentTrackExplicit,
                        font: .system(size: 18, weight: .semibold),
                        nsFont: .title3,
                        textColor: .white,
                        minDuration: 0.55,
                        frameWidth: geo.size.width,
                        badgeSpacing: 6,
                        badgeLabel: "E",
                        badgeHeight: 16,
                        badgeForegroundColor: Color.black.opacity(0.74),
                        badgeBackgroundColor: Color.white.opacity(0.5),
                        badgeHorizontalPadding: 5,
                        badgeMinWidth: 17,
                        badgeCornerRadius: 5
                    )

                    Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(NotchConfiguration.playerColorTinting ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.7) : .gray)
                        .lineLimit(2)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)

            visualizer(height: 20)
        }
    }

    private func albumArtButton(size: CGFloat, cornerRadius: CGFloat) -> some View {
        let artworkCornerRadius = resolvedArtworkCornerRadius(from: cornerRadius)

        return ZStack(alignment: .bottomTrailing) {
            
                albumArtImage(size: size, cornerRadius: cornerRadius)
                if showAppIcon, let icon = lockScreenAppIcon {
                    icon
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: appIconSize, height: appIconSize)
                        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 4)
                        .offset(x: appIconOffset, y: appIconOffset)
                        .transition(.scale.combined(with: .opacity))
                }
            
        }
        .albumArtFlip(angle: false && !keepAlbumArtVisibleDuringFullscreenArtwork ? 0 : musicManager.flipAngle)
        
        .frame(width: size)
        .background(albumArtBackground(cornerRadius: artworkCornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
        .opacity(musicManager.isPlaying ? 1 : 0.4)
        .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
        .animation(.easeInOut(duration: 0.2), value: musicManager.isPlaying)
        .animation(.easeInOut(duration: 0.28), value: false)
        .onTapGesture {
            toggleExpanded()
        }
        
    }

    @ViewBuilder
    private func visualizer(height: CGFloat) -> some View {
        let width = CGFloat(Defaults[.visualizerBarCount]) * 4
        
            Rectangle()
                .fill((NotchConfiguration.coloredSpectrogram ? Color(nsColor: musicManager.avgColor) : Color.gray).readableOnBlack())
                .mask {
                    AudioVisualizerView(isPlaying: .constant(musicManager.isPlaying))
                        .frame(width: width, height: height)
                }
                .frame(width: width, height: height)
        
    }

    private func toggleExpanded() {
        let newState = !isExpanded
        withAnimation(.easeInOut(duration: 0.28)) {
            isExpanded = newState
        }

        if newState {
            registerInteraction()
        } else {
            cancelCollapseTimer()
        }
    }



    private func registerInteraction() {
        cancelCollapseTimer()
        guard isExpanded else { return }

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.28)) {
                isExpanded = false
            }
        }

        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseTimeout, execute: workItem)
    }



    private func cancelCollapseTimer() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    private var isProgressTimelinePaused: Bool {
        !musicManager.isPlaying || musicManager.isLiveStream || musicManager.playbackRate <= 0
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        TimelineView(
            .animation(
                paused: isProgressTimelinePaused
            )
        ) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: Binding(
                    get: { musicManager.songDuration },
                    set: { musicManager.songDuration = $0 }
                ),
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                isLiveStream: musicManager.isLiveStream,
                onValueChange: { newValue in
                    registerInteraction()
                    musicManager.seek(to: newValue)
                },
                labelLayout: .inline,
                trailingLabel: .remaining,
                restingTrackHeight: 7,
                draggingTrackHeight: 11
            )
        }
        .onAppear {
            sliderValue = musicManager.elapsedTime
        }
        .onChange(of: musicManager.isLiveStream) { _, isLive in
            if isLive {
                dragging = false
                sliderValue = 0
            }
        }
    }

    private var sliderColor: Color {
        switch NotchConfiguration.sliderColor {
        case .white:
            return .white
        case .albumArt:
            return Color(nsColor: musicManager.avgColor)
        case .accent:
            return .accentColor
        }
    }

    private var brandAccentColor: Color {
        musicManager.brandAccentColor
    }
    
    // MARK: - Playback Controls
    
    private func playbackControls(alignment: Alignment) -> some View {
        let spacing: CGFloat = isExpanded ? 24 : 20
        let verticalSpacing: CGFloat = (shouldShowVolumeSlider || shouldShowInlineLyrics) ? 14 : 10

        return VStack(spacing: verticalSpacing) {
            controlsRow(alignment: alignment, spacing: spacing)

            if shouldShowVolumeSlider {
                volumeSlider
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .transition(.scale(scale: 0.98, anchor: .top).combined(with: .opacity))

                if shouldShowRouteSelector {
                    mediaOutputDevicesSection
                        .frame(maxWidth: .infinity, alignment: alignment)
                        .transition(.scale(scale: 0.98, anchor: .top).combined(with: .opacity))
                }
            }

            if shouldShowInlineLyrics {
                lyricsSection(alignment: alignment)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.top, isExpanded ? 6 : 2)
        .animation(.easeInOut(duration: 0.24), value: shouldShowVolumeSlider)
        .animation(.easeInOut(duration: 0.24), value: false)
        .animation(.easeInOut(duration: 0.24), value: shouldShowRouteSelector)
        .animation(.easeInOut(duration: 0.24), value: enableLyrics)
    }

    private func controlsRow(alignment: Alignment, spacing: CGFloat) -> some View {
        let skipNudge: CGFloat = isExpanded ? 14 : 9

        return HStack(spacing: spacing) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot, skipNudge: skipNudge)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }
    
    private var displayedSlots: [MusicControlButton] { MusicControlButton.defaultLayout }



    @ViewBuilder
    private func slotView(for control: MusicControlButton, skipNudge: CGFloat) -> some View {
        let seekInterval: TimeInterval = 10

        switch control {
        case .playPause:
            playPauseButton
        case .trackBackward:
            controlButton(
                icon: "backward.fill",
                size: 18,
                interaction: .nudge(-skipNudge),
                symbolEffect: .replace
            ) {
                musicManager.previousTrack()
            }
        case .trackForward:
            controlButton(
                icon: "forward.fill",
                size: 18,
                interaction: .nudge(skipNudge),
                symbolEffect: .replace
            ) {
                musicManager.nextTrack()
            }
        case .appVolume:
            AppVolumeButton(iconSize: isExpanded ? 26 : 18, buttonSize: isExpanded ? 56 : 32)
        case .mediaOutput:
            mediaOutputControlButton
        }
    }

    private var playPauseButton: some View {
        let frameSize: CGFloat = isExpanded ? 80 : 54
        let iconName = musicManager.isPlaying ? "pause.fill" : "play.fill"

        return HoverButton(
            icon: iconName,
            iconColor: .white,
            scale: .large,
            pressEffect: nil
        ) {
            registerInteraction()
            musicManager.togglePlay()
        }
        .frame(width: frameSize, height: frameSize)
    }
    
    private func controlButton(
        icon: String,
        size: CGFloat = 18,
        isActive: Bool = false,
        activeColor: Color? = nil,
        interaction: PanelControlButton.Interaction = .none,
        symbolEffect: PanelControlButton.SymbolEffectStyle = .replace,
        action: @escaping () -> Void
    ) -> some View {
        let resolvedActiveColor = activeColor ?? brandAccentColor
        let frameSize: CGFloat = isExpanded ? 56 : 32
        let iconSize: CGFloat = isExpanded ? max(size, 24) : size
        let iconColor = isActive ? resolvedActiveColor : .white.opacity(0.8)
        let backgroundOpacity: Double = isActive ? 0.22 : 0.0

        return PanelControlButton(
            icon: icon,
            frameSize: frameSize,
            iconSize: iconSize,
            iconColor: iconColor,
            backgroundOpacity: backgroundOpacity,
            interaction: interaction,
            symbolEffect: symbolEffect
        ) {
            registerInteraction()
            action()
        }
    }
    
    private var mediaOutputControlButton: some View {
        let frameSize: CGFloat = isExpanded ? 56 : 32
        let iconSize: CGFloat = isExpanded ? 26 : 18

        return PanelControlButton(
            icon: mediaOutputIcon,
            frameSize: frameSize,
            iconSize: iconSize,
            iconColor: shouldShowVolumeSlider ? .accentColor : .white.opacity(0.8),
            backgroundOpacity: shouldShowVolumeSlider ? 0.22 : 0.0,
            interaction: .none,
            symbolEffect: .replace,
            action: toggleVolumeSlider
        )
        .accessibilityLabel("Media output")
    }



    private func lyricsSection(alignment: Alignment) -> some View {
        let line = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        let transition: AnyTransition = .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )

        return HStack(spacing: 8) {
            if !line.isEmpty {
                Image(systemName: "music.note")
                    .font(.system(size: isExpanded ? 14 : 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .symbolRenderingMode(.monochrome)

                Text(line)
                    .font(.system(size: isExpanded ? 14 : 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 6)
                    .id(line)
                    .transition(transition)
            }
        }
        .padding(.horizontal, isExpanded ? 10 : 8)
        .padding(.top, isExpanded ? 12 : 8)
        .frame(maxWidth: .infinity, alignment: alignment)
        .animation(.smooth(duration: 0.32), value: line)
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private var mediaOutputIcon: String {
        routeManager.activeDevice?.iconName ?? "speaker.wave.2"
    }

    private var volumeSlider: some View {
        HStack(spacing: 14) {
            Image(systemName: volumeIconName)
                .font(.system(size: isExpanded ? 16 : 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            Slider(
                value: Binding(
                    get: { Double(volumeModel.level) },
                    set: { newValue in
                        registerInteraction()
                        volumeModel.setVolume(Float(newValue))
                    }
                ),
                in: 0 ... 1
            )
            .tint(sliderColor)

            Text(volumePercentage)
                .font(.system(size: isExpanded ? 12 : 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: isExpanded ? 16 : 12, style: .continuous)
                .fill(sliderBackgroundFill)
        )
    }



    private var mediaOutputDevicesSection: some View {
        accessorySectionContainer {
            if routeManager.devices.isEmpty {
                Text("No audio outputs available")
                    .font(.system(size: isExpanded ? 13 : 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.68))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(routeManager.devices) { device in
                            Button {
                                registerInteraction()
                                routeManager.select(device: device)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: device.iconName)
                                        .font(.system(size: isExpanded ? 14 : 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.82))
                                    Text(device.name)
                                        .font(.system(size: isExpanded ? 13 : 11, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    if device.id == routeManager.activeDeviceID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: isExpanded ? 12 : 10, weight: .bold))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: accessorySectionScrollMaxHeight)
            }
        }
        .padding(.vertical, 8)
    }

    private func accessorySectionContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: isExpanded ? 16 : 12, style: .continuous)
                    .fill(sliderBackgroundFill)
            )
    }

    private var sliderBackgroundFill: Color {
        if usesLiquidGlass {
            return Color.white.opacity(0.05)
        }
        return Color.white.opacity(0.08)
    }

    private var isAppleMusicActive: Bool { false }

    private var useMergedAirPlayOutput: Bool { false }

    private var shouldShowAirPlay: Bool { false }

    private var shouldShowRouteSelector: Bool {
        !false && shouldShowVolumeSlider
    }

    private var shouldShowAccessorySection: Bool {
        shouldShowRouteSelector
    }

    private var shouldShowVolumeSlider: Bool {
        showMediaOutputControl && isVolumeSliderVisible
    }

    private var sliderExtraHeight: CGFloat {
        sliderHeight(forExpanded: isExpanded, visible: shouldShowVolumeSlider)
    }

    private var accessorySectionScrollMaxHeight: CGFloat {
        isExpanded ? 170 : 130
    }

    private var lyricsExtraHeight: CGFloat {
        lyricsHeight(forExpanded: isExpanded, enabled: shouldShowInlineLyrics)
    }

    private var accessorySectionExtraHeight: CGFloat {
        guard shouldShowAccessorySection else { return 0 }
        

        let totalCount = max(routeManager.devices.count, 1)
        let deviceRows: CGFloat = CGFloat(totalCount) * 30 + CGFloat(max(totalCount - 1, 0)) * 6
        return min(deviceRows + 24, accessorySectionScrollMaxHeight + 16)
    }

    private var totalExtraHeight: CGFloat {
        sliderExtraHeight + accessorySectionExtraHeight + lyricsExtraHeight
    }

    private func lyricsHeight(forExpanded expanded: Bool, enabled: Bool) -> CGFloat {
        guard enabled else { return 0 }
        return expanded ? expandedLyricsExtraHeight : collapsedLyricsExtraHeight
    }

    private func panelAdditionalHeight(forExpanded expanded: Bool) -> CGFloat {
        sliderHeight(forExpanded: expanded, visible: shouldShowVolumeSlider) +
        accessorySectionExtraHeight +
        lyricsHeight(forExpanded: expanded, enabled: shouldShowInlineLyrics)
    }

    private func updatePanelSize(animated: Bool = true) {
        LockScreenPanelManager.shared.updatePanelSize(
            expanded: isExpanded,
            additionalHeight: panelAdditionalHeight(forExpanded: isExpanded),
            animated: animated
        )
    }

    private var volumeIconName: String {
        if volumeModel.isMuted || volumeModel.level <= 0.001 {
            return "speaker.slash.fill"
        } else if volumeModel.level < 0.33 {
            return "speaker.wave.1.fill"
        } else if volumeModel.level < 0.66 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    private var volumePercentage: String {
        "\(Int(round(volumeModel.level * 100)))%"
    }

    private func toggleVolumeSlider() {
        guard showMediaOutputControl else {
            isVolumeSliderVisible = false
            return
        }

        registerInteraction()
        let newState = !isVolumeSliderVisible
        if newState {
            routeManager.refreshDevices()
            
        }

        withAnimation(.easeInOut(duration: 0.24)) {
            isVolumeSliderVisible = newState
        }

        updatePanelSize()
    }

    private func sliderHeight(forExpanded expanded: Bool, visible: Bool) -> CGFloat {
        guard visible else { return 0 }
        return expanded ? expandedSliderExtraHeight : collapsedSliderExtraHeight
    }

    @ViewBuilder
    private var panelBackgroundLayer: some View { customLiquidPanelBackdrop }





    @ViewBuilder
    private var customLiquidPanelBackdrop: some View {
        LiquidGlassBackground(variant: musicGlassVariant, cornerRadius: panelCornerRadius) {
            Color.white.opacity(0.04)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }





    @ViewBuilder
    private var panelBorderOverlay: some View {
        if usesEnhancedCustomLiquidBorder {
            ZStack {
                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .stroke(
                        Color.white.opacity(0.22),
                        lineWidth: 1.05
                    )

                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .inset(by: 0.85)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.1),
                                Color.black.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )

                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .inset(by: 1.55)
                    .stroke(
                        Color.black.opacity(0.16),
                        lineWidth: 0.55
                    )
            }
            .allowsHitTesting(false)
        } else if usesLiquidGlass {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .stroke(
                    Color.white.opacity(usesCustomLiquidGlass ? 0.15 : 0.14),
                    lineWidth: usesCustomLiquidGlass ? 0.95 : 0.9
                )
                .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1.4)
                .allowsHitTesting(false)
        }
    }

    private func albumArtImage(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: resolvedArtworkCornerRadius(from: cornerRadius), style: .continuous))
    }

    @ViewBuilder
    private func albumArtBackground(cornerRadius: CGFloat) -> some View {
        
            customLiquidAlbumArtBackground(cornerRadius: cornerRadius)
         
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.35))
        
    }

    private var lockScreenAppIcon: Image? {
        guard showAppIcon, !musicManager.usingAppIconForArtwork else { return nil }
        let bundleIdentifier = musicManager.bundleIdentifier ?? "com.apple.Music"
        return AppIcon(for: bundleIdentifier)
    }

    private var appIconSize: CGFloat {
        isExpanded ? 58 : 34
    }

    private var appIconCornerRadius: CGFloat {
        isExpanded ? 18 : 12
    }

    private var appIconOffset: CGFloat {
        isExpanded ? 18 : 12
    }

    private func resolvedArtworkCornerRadius(from baseCornerRadius: CGFloat) -> CGFloat {
        let aspectRatio = musicManager.albumArt.size.height > 0
            ? musicManager.albumArt.size.width / musicManager.albumArt.size.height
            : 1
        return aspectRatio > 1.0 ? baseCornerRadius / 3 : baseCornerRadius
    }

    

    @ViewBuilder
    private func customLiquidAlbumArtBackground(cornerRadius: CGFloat) -> some View {
        LiquidGlassBackground(variant: musicGlassVariant, cornerRadius: cornerRadius) {
            Color.clear
        }
    }






}

private struct PanelControlButton: View {
    let icon: String
    let frameSize: CGFloat
    let iconSize: CGFloat
    let iconColor: Color
    let backgroundOpacity: Double
    let interaction: Interaction
    let symbolEffect: SymbolEffectStyle
    let action: () -> Void

    @State private var isHovering = false
    @State private var pressOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    @State private var wiggleToken: Int = 0

    var body: some View {
        Button(action: {
            triggerPressEffect()
            action()
        }) {
            RoundedRectangle(cornerRadius: frameSize / 2, style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    iconView
                )
        }
        .frame(width: frameSize, height: frameSize)
        .buttonStyle(PlainButtonStyle())
        .offset(x: pressOffset)
        .rotationEffect(.degrees(rotationAngle))
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.24)) {
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        let hoveredOpacity = max(backgroundOpacity + 0.08, 0.18)
        let appliedOpacity = isHovering ? hoveredOpacity : backgroundOpacity
        return Color.white.opacity(min(appliedOpacity, 0.32))
    }

    private func triggerPressEffect() {
        switch interaction {
        case .none: break
        case .nudge(let amount):
            withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                pressOffset = amount
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    pressOffset = 0
                }
            }
        case .wiggle(let direction):
            guard #available(macOS 14.0, *) else { return }
            wiggleToken += 1
            let angle: Double = direction == .clockwise ? 10 : -10

            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) {
                rotationAngle = angle
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                    rotationAngle = 0
                }
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        let base = Image(systemName: icon)
            .font(.system(size: iconSize, weight: .medium))
            .foregroundStyle(iconColor)

        switch symbolEffect {
        case .replace:
            base.contentTransition(.symbolEffect(.replace))
        case .replaceAndBounce:
            if #available(macOS 14.0, *) {
                base
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: icon)
            } else {
                base.contentTransition(.symbolEffect(.replace))
            }
        case .wiggle:
            if #available(macOS 15.0, *) {
                base
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.wiggle.byLayer, options: .nonRepeating, value: wiggleToken)
            } else {
                base.contentTransition(.symbolEffect(.replace))
            }
        }
    }

    enum Interaction {
        case none
        case nudge(CGFloat)
        case wiggle(WiggleDirection)
    }

    enum SymbolEffectStyle {
        case replace
        case replaceAndBounce
        case wiggle
    }

    enum WiggleDirection {
        case clockwise
        case counterClockwise
    }
}



// MARK: - Right Click Gesture
