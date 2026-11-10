// MacKit lock-screen preview data, adapted from Atoll; GPL-3.0-or-later.
import AppKit
import Defaults
import SwiftUI

@MainActor enum LockScreenPreviewData {
    static func weather() -> LockScreenWeatherSnapshot {
        let unit = Defaults[.lockScreenWeatherTemperatureUnit]
        let temperatureValue: Double = unit == .celsius ? 21 : 72
        let temperatureText = "\(Int(round(temperatureValue)))°"
        let temperatureInfo = LockScreenWeatherSnapshot.TemperatureInfo(
            current: temperatureValue,
            minimum: temperatureValue - 5,
            maximum: temperatureValue + 6,
            unitSymbol: unit.symbol
        )

        let chargingInfo: LockScreenWeatherSnapshot.ChargingInfo? =
            Defaults[.lockScreenBatteryShowsCharging]
            ? LockScreenWeatherSnapshot.ChargingInfo(
                minutesRemaining: 42,
                isCharging: true,
                isPluggedIn: true,
                batteryLevel: 78
            )
            : nil

        let bluetoothInfo: LockScreenWeatherSnapshot.BluetoothInfo? =
            Defaults[.lockScreenBatteryShowsBluetooth]
            ? LockScreenWeatherSnapshot.BluetoothInfo(
                deviceName: "AirPods Pro",
                batteryLevel: 74,
                iconName: "airpodspro"
            )
            : nil

        let batteryInfo: LockScreenWeatherSnapshot.BatteryInfo? =
            Defaults[.lockScreenBatteryShowsBatteryGauge]
            ? LockScreenWeatherSnapshot.BatteryInfo(
                batteryLevel: 63,
                usesLaptopSymbol: true
            )
            : nil

        let widgetStyle = Defaults[.lockScreenWeatherWidgetStyle]
        let showLocation = widgetStyle == .inline && Defaults[.lockScreenWeatherShowsLocation]
        let providerSource = Defaults[.lockScreenWeatherProviderSource]
        let showsAQI = Defaults[.lockScreenWeatherShowsAQI] && providerSource.supportsAirQuality
        let scale = Defaults[.lockScreenWeatherAQIScale]
        let airQualityIndex = scale == .us ? 42 : 28
        let airQuality =
            showsAQI
            ? LockScreenWeatherSnapshot.AirQualityInfo(
                index: airQualityIndex,
                category: .init(index: airQualityIndex, scale: scale),
                scale: scale
            )
            : nil

        let showsSunrise = Defaults[.lockScreenWeatherShowsSunrise] && widgetStyle == .inline
        let sunCycle = LockScreenWeatherSnapshot.SunCycleInfo(
            sunrise: Date().addingTimeInterval(2 * 3600),
            sunset: Date().addingTimeInterval(9 * 3600)
        )

        return LockScreenWeatherSnapshot(
            temperatureText: temperatureText,
            symbolName: "cloud.sun.fill",
            description: "Partly Cloudy",
            locationName: "Cupertino",
            charging: chargingInfo,
            bluetooth: bluetoothInfo,
            battery: batteryInfo,
            showsLocation: showLocation,
            airQuality: airQuality,
            widgetStyle: widgetStyle,
            showsChargingPercentage: Defaults[.lockScreenBatteryShowsChargingPercentage],
            temperatureInfo: temperatureInfo,
            usesGaugeTint: Defaults[.lockScreenWeatherUsesGaugeTint],
            sunCycle: sunCycle,
            showsSunrise: showsSunrise
        )
    }
}

struct AtollWallpaperPreview: View {
    @State private var wallpaperImage: NSImage?

    var body: some View {
        ZStack {
            if let image = wallpaperImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
                Text("正在加载…")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: loadWallpaper)
    }

    func loadWallpaper() {
        if let url = Bundle.main.url(forResource: "desktop", withExtension: "jpeg"),
            let image = NSImage(contentsOf: url),
            image.size.width > 0,
            image.size.height > 0
        {
            self.wallpaperImage = image
            return
        }

        if let image = NSImage(named: "desktop"),
            image.size.width > 0,
            image.size.height > 0
        {
            self.wallpaperImage = image
            return
        }

        if let screen = LockScreenPreviewScreen.screen,
            let url = NSWorkspace.shared.desktopImageURL(for: screen),
            let image = NSImage(contentsOf: url),
            image.size.width > 0,
            image.size.height > 0
        {
            self.wallpaperImage = image
            return
        }
    }
}
