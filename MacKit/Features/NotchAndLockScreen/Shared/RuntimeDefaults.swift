// MacKit feature reduction, modified 2026-11-08.
// See THIRD_PARTY_NOTICES.md; GPL-3.0-or-later.
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

import Defaults
import Foundation
import SwiftUI

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion =
    "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

enum ThirdPartyDDCProvider: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case betterDisplay
    case lunar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .betterDisplay:
            return "BetterDisplay"
        case .lunar:
            return "Lunar"
        }
    }

    /// Bundle identifiers to try when looking up the app icon.
    var bundleIdentifiers: [String] {
        switch self {
        case .betterDisplay: return ["pro.betterdisplay.BetterDisplay"]
        case .lunar: return ["fyi.lunar.Lunar"]
        }
    }
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    var id: String { rawValue }
    var localizedName: String { String(localized: "Now Playing") }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard = "Default"
    case inline = "Inline"

    var id: String { self.rawValue }

    var LocalizedName: String {
        switch self {
        case .standard: return String(localized: "Default")
        case .inline: return String(localized: "Inline")
        }
    }
}

enum LogLevel: Int, CaseIterable, Identifiable, Defaults.Serializable {
    case none = 0
    case error = 1
    case warning = 2
    case info = 3
    case debug = 4

    var id: Int { self.rawValue }

    var displayName: String {
        switch self {
        case .none: return "No Logging"
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Info"
        case .debug: return "Debug"
        }
    }
}

enum CapsLockIndicatorTintMode {
    case accent
    var color: Color { .accentColor }
}

enum ProgressBarStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case hierarchical = "Hierarchical"
    case gradient = "Gradient"
    case segmented = "Segmented"

    var id: String { self.rawValue }
}

enum BatteryNotificationStyle { case compact }

enum MusicSkipBehavior: String, CaseIterable, Identifiable, Defaults.Serializable {
    case track
    case tenSecond

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .track:
            return String(localized: "Track Skip")
        case .tenSecond:
            return String(localized: "±10 Seconds")
        }
    }

    var description: String {
        switch self {
        case .track:
            return String(localized: "Standard previous/next track controls")
        case .tenSecond:
            return String(localized: "Skip forward or backward by ten seconds")
        }
    }
}

enum FocusMonitoringMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case withoutDevTools = "withoutDevTools"
    case useDevTools = "useDevTools"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .withoutDevTools:
            return "Use without DevTools"
        case .useDevTools:
            return "Use DevTools"
        }
    }
}

enum ReminderPresentationStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case ringCountdown = "Ring"
    case digital = "Digital"
    case minutes = "Minutes"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ringCountdown:
            return String(localized: "Ring")
        case .digital:
            return String(localized: "Digital")
        case .minutes:
            return String(localized: "Minutes")
        }
    }
}

// AI Model types for screen assistant

enum ColorExtractionMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case legacy, vibrant
    var id: Self { self }
}

extension Defaults.Keys {
    static let enableCleaningIndicator = Key<Bool>("enableCleaningIndicator", default: true)
    static let notchEnabled = Key<Bool>("mackit.notchEnabled", default: true)
    static let lockScreenLiveActivityVerticalOffset = Key<Double>("lockScreenLiveActivityVerticalOffset", default: 0)

    static let lockScreenShowCalendarTimeRemaining = Key<Bool>("lockScreenShowCalendarTimeRemaining", default: true)
    // MARK: General
    static let logLevel = Key<LogLevel>("logLevel", default: .none)
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "Fiji")
    static let hideDynamicIslandFromScreenCapture = Key<Bool>("hideDynamicIslandFromScreenCapture", default: false)

    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let externalDisplayStyle = Key<ExternalDisplayStyle>(
        "externalDisplayStyle",
        default: .notch
    )
    static let hideNonNotchUntilHover = Key<Bool>("hideNonNotchUntilHover", default: false)
    static let builtinClosedNotchWidth = Key<Double>("builtinClosedNotchWidth", default: 0)
    static let externalClosedNotchWidth = Key<Double>("externalClosedNotchWidth", default: 184)
    static let openNotchWidth = Key<CGFloat>("openNotchWidth", default: 640)

    //static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)

    // MARK: Appearance
    static let showEmojis = Key<Bool>("showEmojis", default: false)
    //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)

    static let accentColor = Key<Color>("accentColor", default: Color.blue)

    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: false)

    static let visualizerBarCount = Key<Int>("visualizerBarCount", default: 4)

    // MARK: Gestures

    static let swipeDownToExpandNotch = Key<Bool>("swipeDownToExpandNotch", default: false)
    static let swipeToChangeTrack = Key<Bool>("swipeToChangeTrack", default: false)

    // MARK: Media playback

    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)

    static let waitInterval = Key<Double>("waitInterval", default: 3)

    static let musicSkipBehavior = Key<MusicSkipBehavior>("musicSkipBehavior", default: .track)

    static let showStandardMediaControls = Key<Bool>("showStandardMediaControls", default: true)
    static let autoHideInactiveNotchMediaPlayer = Key<Bool>("autoHideInactiveNotchMediaPlayer", default: true)
    static let cachedMusicLiveActivityPreference = Key<Bool?>("cachedMusicLiveActivityPreference", default: nil)
    static let cachedLockScreenMediaWidgetPreference = Key<Bool?>("cachedLockScreenMediaWidgetPreference", default: nil)

    // Enable lock screen media widget (shows the standalone panel when screen is locked)
    static let enableLockScreenMediaWidget = Key<Bool>("enableLockScreenMediaWidget", default: true)
    static let enableLockScreenWeatherWidget = Key<Bool>("enableLockScreenWeatherWidget", default: true)
    static let enableLockScreenFocusWidget = Key<Bool>("enableLockScreenFocusWidget", default: true)

    static let lockScreenWeatherRefreshInterval = Key<TimeInterval>(
        "lockScreenWeatherRefreshInterval", default: 30 * 60)
    static let lockScreenWeatherShowsLocation = Key<Bool>("lockScreenWeatherShowsLocation", default: true)
    static let lockScreenWeatherShowsSunrise = Key<Bool>("lockScreenWeatherShowsSunrise", default: true)
    static let lockScreenWeatherWidgetStyle = Key<LockScreenWeatherWidgetStyle>(
        "lockScreenWeatherWidgetStyle", default: .inline)
    static let lockScreenWeatherTemperatureUnit = Key<LockScreenWeatherTemperatureUnit>(
        "lockScreenWeatherTemperatureUnit", default: .celsius)
    static let lockScreenWeatherShowsAQI = Key<Bool>("lockScreenWeatherShowsAQI", default: true)
    static let lockScreenWeatherAQIScale = Key<LockScreenWeatherAirQualityScale>(
        "lockScreenWeatherAQIScale", default: .us)
    static let lockScreenWeatherUsesGaugeTint = Key<Bool>("lockScreenWeatherUsesGaugeTint", default: false)
    static let lockScreenWeatherProviderSource = Key<LockScreenWeatherProviderSource>(
        "lockScreenWeatherProviderSource", default: .openMeteo)
    static let lockScreenWeatherVerticalOffset = Key<Double>("lockScreenWeatherVerticalOffset", default: 0)
    static let lockScreenMusicVerticalOffset = Key<Double>("lockScreenMusicVerticalOffset", default: 0)
    static let lockScreenMusicPanelWidth = Key<Double>("lockScreenMusicPanelWidth", default: 350)

    static let lockScreenShowAppIcon = Key<Bool>("lockScreenShowAppIcon", default: false)
    static let lockScreenPanelShowsBorder = Key<Bool>("lockScreenPanelShowsBorder", default: false)
    static let lockScreenMusicUsesEnhancedLiquidBorder = Key<Bool>(
        "lockScreenMusicUsesEnhancedLiquidBorder",
        default: true
    )
    static let lockScreenPanelUsesBlur = Key<Bool>("lockScreenPanelUsesBlur", default: true)

    static let lockScreenMusicFullscreenVideoArtwork = Key<Bool>("lockScreenMusicFullscreenVideoArtwork", default: true)

    static let lockScreenReminderChipStyle = Key<LockScreenReminderChipStyle>(
        "lockScreenReminderChipStyle", default: .eventColor)
    static let lockScreenReminderWidgetHorizontalAlignment = Key<String>(
        "lockScreenReminderWidgetHorizontalAlignment", default: "center")
    static let lockScreenReminderWidgetVerticalOffset = Key<Double>(
        "lockScreenReminderWidgetVerticalOffset", default: 0)
    static let lockScreenShowCalendarEvent = Key<Bool>("lockScreenShowCalendarEvent", default: true)
    static let lockScreenCalendarEventLookaheadWindow = Key<String>(
        "lockScreenCalendarEventLookaheadWindow", default: "3h")
    static let lockScreenCalendarSelectionMode = Key<String>("lockScreenCalendarSelectionMode", default: "all")
    static let lockScreenSelectedCalendarIDs = Key<Set<String>>("lockScreenSelectedCalendarIDs", default: [])
    static let lockScreenShowCalendarCountdown = Key<Bool>("lockScreenShowCalendarCountdown", default: true)
    static let lockScreenShowCalendarEventEntireDuration = Key<Bool>(
        "lockScreenShowCalendarEventEntireDuration", default: true)
    static let lockScreenShowCalendarEventAfterStartEnabled = Key<Bool>(
        "lockScreenShowCalendarEventAfterStartEnabled", default: false)

    static let lockScreenShowCalendarStartTimeAfterBegins = Key<Bool>(
        "lockScreenShowCalendarStartTimeAfterBegins", default: true)
    static let lockScreenWeatherWidgetRowOrder = Key<String>(
        "lockScreenWeatherWidgetRowOrder", default: "weather_calendar_focus")

    // MARK: Third-party Calendar Integration

    // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)

    static let showBatteryPercentInside = Key<Bool>("showBatteryPercentInside", default: true)

    static let showChargingBatteryHUD = Key<Bool>("showChargingBatteryHUD", default: true)
    static let showLowBatteryHUD = Key<Bool>("showLowBatteryHUD", default: true)
    static let showFullBatteryHUD = Key<Bool>("showFullBatteryHUD", default: true)

    static let lockScreenBatteryShowsBatteryGauge = Key<Bool>(
        "lockScreenWeatherShowsBatteryGauge",
        default: BatteryActivityManager.shared.hasBattery()
    )
    static let lockScreenBatteryUsesLaptopSymbol = Key<Bool>("lockScreenWeatherBatteryUsesLaptopSymbol", default: true)
    static let lockScreenBatteryShowsCharging = Key<Bool>("lockScreenWeatherShowsCharging", default: true)
    static let lockScreenBatteryShowsChargingPercentage = Key<Bool>(
        "lockScreenWeatherShowsChargingPercentage", default: true)
    static let lockScreenBatteryShowsBluetooth = Key<Bool>("lockScreenWeatherShowsBluetooth", default: true)

    // MARK: HUD
    static let inlineHUD = Key<Bool>("inlineHUD", default: true)
    static let progressBarStyle = Key<ProgressBarStyle>("progressBarStyle", default: .hierarchical)
    // Legacy support - keeping for backward compatibility
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = true
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showProgressPercentages = Key<Bool>("showProgressPercentages", default: true)

    // MARK: Shelf
    static let dynamicShelf = Key<Bool>("dynamicShelf", default: true)

    static let quickShareProvider = Key<String>("quickShareProvider", default: "AirDrop")
    static let localSendSelectedDeviceID = Key<String>("localSendSelectedDeviceID", default: "")

    static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)

    // MARK: Calendar
    static let calendarSelectionState = Key<CalendarSelectionState>("calendarSelectionState", default: .all)

    // MARK: Fullscreen Media Detection

    // MARK: Wobble Animation
    static let enableWobbleAnimation = Key<Bool>("enableWobbleAnimation", default: false)

    // MARK: Media Controller

    static let spotifySPDCCookie = Key<String>("spotifySPDCCookie", default: "")
    static let spotifyAuthAccessToken = Key<String>("spotifyAuthAccessToken", default: "")
    static let spotifyAuthAccessTokenExpiration = Key<Double>("spotifyAuthAccessTokenExpiration", default: 0)
    static let spotifyAuthLastValidatedAt = Key<Double>("spotifyAuthLastValidatedAt", default: 0)

    // MARK: Bluetooth Audio Devices
    static let showBluetoothDeviceConnections = Key<Bool>("showBluetoothDeviceConnections", default: true)

    static let useColorCodedVolumeDisplay = Key<Bool>("useColorCodedVolumeDisplay", default: true)
    static let useSmoothColorGradient = true
    static let useCircularBluetoothBatteryIndicator = Key<Bool>("useCircularBluetoothBatteryIndicator", default: true)

    // MARK: Terminal Feature
    static let enableTerminalFeature = Key<Bool>("enableTerminalFeature", default: false)
    static let terminalShellPath = Key<String>("terminalShellPath", default: "/bin/zsh")
    static let terminalFontFamily = Key<String>("terminalFontFamily", default: "")
    static let terminalFontSize = Key<Double>("terminalFontSize", default: 12.0)

    static let terminalMaxHeightFraction = Key<Double>("terminalMaxHeightFraction", default: 0.4)

    static let terminalStickyMode = Key<Bool>("terminalStickyMode", default: false)

    // MARK: Reminder Live Activity
    static let enableReminderLiveActivity = Key<Bool>("enableReminderLiveActivity", default: true)
    static let reminderPresentationStyle = Key<ReminderPresentationStyle>(
        "reminderPresentationStyle", default: .ringCountdown)
    static let reminderLeadTime = Key<Int>("reminderLeadTime", default: 5)
    static let reminderSneakPeekDuration = Key<Double>("reminderSneakPeekDuration", default: 5)

    // MARK: System HUD Feature
    static let enableSystemHUD = Key<Bool>("enableSystemHUD", default: true)
    static let enableVolumeHUD = Key<Bool>("enableVolumeHUD", default: true)
    static let enableBrightnessHUD = Key<Bool>("enableBrightnessHUD", default: true)
    static let enableKeyboardBacklightHUD = Key<Bool>("enableKeyboardBacklightHUD", default: true)
    static let systemHUDSensitivity = Key<Int>("systemHUDSensitivity", default: 5)

    // Step sizes for hardware media keys (percent of full range, 1-25)
    static let volumeStepPercent = Key<Int>("volumeStepPercent", default: 6)
    static let volumeFineStepPercent = Key<Int>("volumeFineStepPercent", default: 2)
    static let brightnessStepPercent = Key<Int>("brightnessStepPercent", default: 6)
    static let brightnessFineStepPercent = Key<Int>("brightnessFineStepPercent", default: 2)

    // MARK: Custom OSD Window Feature

    static let enableVerticalHUD = Key<Bool>("enableVerticalHUD", default: false)

    // Vertical HUD Customization
    static let verticalHUDShowValue = Key<Bool>("verticalHUDShowValue", default: true)
    static let verticalHUDInteractive = Key<Bool>("verticalHUDInteractive", default: true)

    static let verticalHUDUseAccentColor = Key<Bool>("verticalHUDUseAccentColor", default: false)

    // Circular HUD Customization

    // MARK: Third-Party DDC Integration
    static let enableThirdPartyDDCIntegration = Key<Bool>("enableThirdPartyDDCIntegration", default: false)
    static let thirdPartyDDCProvider = Key<ThirdPartyDDCProvider>("thirdPartyDDCProvider", default: .betterDisplay)
    static let enableExternalVolumeControlListener = Key<Bool>("enableExternalVolumeControlListener", default: false)
    static let didMigrateThirdPartyDDCIntegration = Key<Bool>("didMigrateThirdPartyDDCIntegration", default: false)

    // Legacy keys retained for migration/backward compatibility
    static let enableBetterDisplayIntegration = Key<Bool>("enableBetterDisplayIntegration", default: false)
    static let enableLunarIntegration = Key<Bool>("enableLunarIntegration", default: false)

    static let hasSeenOSDAlphaWarning = Key<Bool>("hasSeenOSDAlphaWarning", default: false)

    // MARK: Screen Recording Detection Feature
    static let enableScreenRecordingDetection = true
    static let showRecordingIndicator = Key<Bool>("showRecordingIndicator", default: true)
    // Polling removed - now uses event-driven private API detection (CGSIsScreenWatcherPresent)
    // static let enableScreenRecordingPolling = Key<Bool>("enableScreenRecordingPolling", default: false)

    // MARK: Focus / Do Not Disturb Detection
    static let enableDoNotDisturbDetection = true
    static let focusMonitoringMode = Key<FocusMonitoringMode>("focusMonitoringMode", default: .withoutDevTools)
    static let showDoNotDisturbIndicator = Key<Bool>("showDoNotDisturbIndicator", default: true)

    // MARK: Privacy Indicators (Camera & Microphone Detection)
    static let enableCameraDetection = Key<Bool>("enableCameraDetection", default: true)
    static let enableMicrophoneDetection = Key<Bool>("enableMicrophoneDetection", default: true)

    // MARK: Lock Screen Features
    static let enableLockScreenLiveActivity = Key<Bool>("enableLockScreenLiveActivity", default: true)
    static let enableLockSounds = Key<Bool>("enableLockSounds", default: true)

    // MARK: Caps Lock Indicator
    static let enableCapsLockIndicator = Key<Bool>("enableCapsLockIndicator", default: true)

    // MARK: ImageService
    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCacheV1", default: false)

    // MARK: Minimalistic UI Mode

    // MARK: Lyrics Feature
    static let enableLyrics = Key<Bool>("enableLyrics", default: true)

    // Helper to determine the default media controller based on macOS version
    static var defaultMediaController: MediaControllerType { .nowPlaying }

    // Migration helper to convert from legacy enableGradient Boolean to new ProgressBarStyle enum
    static func migrateProgressBarStyle() {
        // Check if migration is needed by seeing if the old Boolean was set to gradient
        let wasGradientEnabled = Defaults[.enableGradient]

        // Only migrate if we're still using the default hierarchical value but gradient was enabled
        if wasGradientEnabled && Defaults[.progressBarStyle] == .hierarchical {
            Defaults[.progressBarStyle] = .gradient
        }
    }

    static func migrateThirdPartyDDCIntegration() {
        if Defaults[.didMigrateThirdPartyDDCIntegration] == false {
            let legacyBetterDisplayEnabled = Defaults[.enableBetterDisplayIntegration]
            let legacyLunarEnabled = Defaults[.enableLunarIntegration]

            if legacyBetterDisplayEnabled || legacyLunarEnabled {
                Defaults[.enableThirdPartyDDCIntegration] = true
                Defaults[.thirdPartyDDCProvider] =
                    (legacyLunarEnabled && !legacyBetterDisplayEnabled) ? .lunar : .betterDisplay
            }

            Defaults[.didMigrateThirdPartyDDCIntegration] = true
        }

        syncLegacyThirdPartyDDCKeys()
    }

    static func syncLegacyThirdPartyDDCKeys() {
        let isIntegrationEnabled = Defaults[.enableThirdPartyDDCIntegration]
        let selectedProvider = Defaults[.thirdPartyDDCProvider]
        Defaults[.enableBetterDisplayIntegration] = isIntegrationEnabled && selectedProvider == .betterDisplay
        Defaults[.enableLunarIntegration] = isIntegrationEnabled && selectedProvider == .lunar
    }

    static let hideLyricsWhenPaused = Key<Bool>("hideLyricsWhenPaused", default: false)
    static let pausedMediaHideDelay = Key<Double>("pausedMediaHideDelay", default: 3)
    static let showLyricsBelowBuiltinNotch = Key<Bool>("showLyricsBelowBuiltinNotch", default: false)
}
