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

import Foundation
import Defaults
import CoreGraphics

public enum Style {
    case notch
    case floating
}

/// Controls how Atoll renders on external and non-notched displays.
/// - `notch`: Standard notch shape (concave top corners blending into the screen edge).
/// - `dynamicIsland`: Pill-shaped island with continuously rounded corners,
///   inspired by DynamicNotchKit's floating style. Only applies to screens
///   that do NOT have a physical notch.
enum ExternalDisplayStyle: String, CaseIterable, Defaults.Serializable, Identifiable {
    case notch = "Standard Notch"
    case dynamicIsland = "Dynamic Island"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .notch:
            return String(localized: "Standard Notch")
        case .dynamicIsland:
            return String(localized: "Dynamic Island")
        }
    }

    var description: String {
        switch self {
        case .notch:
            return String(localized: "Classic notch shape that blends into the top screen edge")
        case .dynamicIsland:
            return String(localized: "Pill-shaped island with rounded corners, similar to iPhone's Dynamic Island")
        }
    }
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    case closed
    case open
}

public enum NotchViews {
    case home
    case shelf






    case terminal

}



enum SettingsEnum {
    case general
    case about
    case charge

    case mediaPlayback
    case hud
    case shelf

}





enum MirrorShapeEnum: String, Defaults.Serializable {
    case rectangle = "Rectangular"
    case circle = "Circular"
}


enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
    
    var localizedName: String {
        switch self {
            case .white:
                return String(localized: "Standard")
            case .albumArt:
                return String(localized: "Custom Liquid")
            case .accent:
            return String(localized: "Accent color")
        }
    }
}

enum LockScreenGlassStyle: String, Defaults.Serializable { case liquid = "Liquid Glass" }

enum LockScreenGlassCustomizationMode: String, Defaults.Serializable {
    case customLiquid = "Custom Liquid"
    var allowsVariantSelection: Bool { true }
}



enum LockScreenWeatherWidgetStyle: String, CaseIterable, Defaults.Serializable, Identifiable {
    case inline = "Inline"
    case circular = "Circular"

    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .inline:
            return String(localized: "Inline")
        case .circular:
            return "环形"
        }
    }
}

enum LockScreenWeatherProviderSource: String, CaseIterable, Defaults.Serializable, Identifiable {
    case wttr = "wttr.in"
    case openMeteo = "Open Meteo"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var supportsAirQuality: Bool {
        switch self {
        case .wttr:
            return false
        case .openMeteo:
            return true
        }
    }
}

enum LockScreenWeatherTemperatureUnit: String, CaseIterable, Defaults.Serializable, Identifiable {
    case celsius = "Celsius"
    case fahrenheit = "Fahrenheit"

    var id: String { rawValue }

    var usesMetricSystem: Bool { self == .celsius }

    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    var openMeteoTemperatureParameter: String? {
        switch self {
        case .celsius: return nil
        case .fahrenheit: return "fahrenheit"
        }
    }
}

enum LockScreenWeatherAirQualityScale: String, CaseIterable, Defaults.Serializable, Identifiable {
    case us = "U.S. AQI"
    case european = "EAQI"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var compactLabel: String {
        switch self {
        case .us:
            return String(localized: "AQI")
        case .european:
            return String(localized: "EAQI")
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .us:
            return String(localized: "AQI")
        case .european:
            return String(localized: "EAQI")
        }
    }

    var queryParameter: String {
        switch self {
        case .us:
            return "us_aqi"
        case .european:
            return "european_aqi"
        }
    }

    var gaugeRange: ClosedRange<Double> {
        switch self {
        case .us:
            return 0...500
        case .european:
            return 0...120
        }
    }
}

enum LockScreenReminderChipStyle: String, CaseIterable, Defaults.Serializable, Identifiable {
    case eventColor = "Event color"
    case monochrome = "White"

    var id: String { rawValue }
    
    var localizedName: String {
            switch self {
            case .eventColor:
                return String(localized: "Event color")
            case .monochrome:
                return String(localized: "White")
            }
        }
}



