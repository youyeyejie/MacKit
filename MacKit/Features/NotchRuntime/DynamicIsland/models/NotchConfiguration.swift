// Fixed MacKit behavior, 2026-11-08. GPL-3.0-or-later.
import AppKit
import SwiftUI

enum NotchConfiguration {
    static let terminalOptionAsMeta: Bool = true
    static let terminalMouseReporting: Bool = true
    static let openShelfByDefault: Bool = true
    static let autoScrollToNextEvent: Bool = true
    static let showBatteryPercentage: Bool = true
    static let showPowerStatusIcons: Bool = true
    static let showBluetoothBatteryPercentageText: Bool = true
    static let showBluetoothDeviceNameMarquee: Bool = true
    static let useColorCodedBatteryDisplay: Bool = true
    static let showShuffleAndRepeat: Bool = true
    static let showMediaOutputControl: Bool = true
    static let coloredSpectrogram: Bool = true
    static let playerColorTinting: Bool = true
    static let enableShadow: Bool = true
    static let cornerRadiusScaling: Bool = true
    static let useModernCloseAnimation: Bool = true
    static let useMusicVisualizer: Bool = true
    static let enableMinimalisticUI: Bool = false
    static let showFullEventTitles: Bool = false
    static let hideAllDayEvents: Bool = false
    static let showBatteryIndicator: Bool = false
    static let useBluetoothHUD3DIcon: Bool = false
    static let showAirPodsListeningModeChanges: Bool = false
    static let showCapsLockLabel: Bool = false
    static let showDoNotDisturbLabel: Bool = false
    static let focusIndicatorNonPersistent: Bool = false
    static let lockScreenMusicAlbumParallaxEnabled: Bool = false
    static let enableSneakPeek: Bool = false
    static let showSneakPeekOnTrackChange: Bool = false
    static let showLiveCanvasInDynamicIsland: Bool = false
    static let lockScreenMusicFullscreenArtworkEnabled: Bool = false
    static let lockScreenKeepAlbumArtVisibleDuringFullscreenArtwork: Bool = false
    static let showMirror: Bool = false
    static let terminalScrollbackLines: Int = 1000
    static let terminalForegroundColor: Color = Color.white
    static let terminalCursorColor: Color = Color.white
    static let chargingBatteryHUDDuration: Int = 3
    static let lowBatteryHUDDuration: Int = 3
    static let fullBatteryHUDDuration: Int = 3
    static let lowBatteryHUDThreshold: Int = 20
    static let fullBatteryHUDThreshold: Int = 100
    static let lowBatteryHUDStyle: BatteryNotificationStyle = .compact
    static let fullBatteryHUDStyle: BatteryNotificationStyle = .compact
    static let verticalHUDPosition: String = "right"
    static let verticalHUDHeight: CGFloat = 160
    static let verticalHUDWidth: CGFloat = 36
    static let verticalHUDPadding: CGFloat = 24
    static let capsLockIndicatorTintMode: CapsLockIndicatorTintMode = .accent
    static let sliderColor: SliderColorEnum = .albumArt
    static let hideNotchOption: HideNotchOption = .never
    static let musicControlSlots: [MusicControlButton] = [.appVolume, .trackBackward, .playPause, .trackForward, .mediaOutput]
    static let mediaController: MediaControllerType = .nowPlaying
    static let closedNotchWidth: CGFloat = 150
    static let lockScreenGlassStyle: LockScreenGlassStyle = .liquid
    static let lockScreenGlassCustomizationMode: LockScreenGlassCustomizationMode = .customLiquid
    static let lockScreenMusicLiquidGlassVariant: LiquidGlassVariant = .v11
    static let localSendDevicePickerGlassMode: LockScreenGlassCustomizationMode = .customLiquid
    static let localSendDevicePickerLiquidGlassVariant: LiquidGlassVariant = .v11
    static let verticalHUDMaterial: OSDMaterial = .liquid
    static let verticalHUDLiquidGlassCustomizationMode: LockScreenGlassCustomizationMode = .customLiquid
    static let verticalHUDLiquidGlassVariant: LiquidGlassVariant = .v11
    static let osdMaterial: OSDMaterial = .liquid
    static let osdLiquidGlassCustomizationMode: LockScreenGlassCustomizationMode = .customLiquid
    static let osdLiquidGlassVariant: LiquidGlassVariant = .v11
}

// 垂直条只使用 v11 自定义液态玻璃。
enum OSDMaterial: String { case liquid = "Liquid Glass" }
