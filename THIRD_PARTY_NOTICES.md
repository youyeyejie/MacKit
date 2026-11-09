# Third-Party Notices

## Vorssaint

- Source: https://github.com/vorssaint/vorssaint-utils
- License: GNU GPL version 3 or later (GPL-3.0-or-later); full text: [LICENSES/Vorssaint-GPL-3.0.txt](LICENSES/Vorssaint-GPL-3.0.txt).
- Copyright: Copyright (C) 2026 Vorssaint.
- Usage: Window-switching and Dock behavior were implemented after consulting upstream source. To avoid treating potentially substantive adaptations as merely independent design references, the current combined distribution is released under GPL-3.0-or-later.
- Scope: `MacKit/Features/WindowTools/`, `DockClickPolicy.swift`, and `DockGeometry.swift`, including click commitment/replay, intent handling, window previews and hover behavior. These files differ from upstream and are not verbatim upstream releases.
- Modifications (2026-11-04): Integration with MacKit's architecture, native own-window operations, shared window enumeration and snapshots, custom card/UI layout, local preferences, system-app quit protection and lifecycle handling. License/provenance annotations were added on this date.

## Phosphene

- Source: https://github.com/kageroumado/phosphene
- License: MIT License
- Copyright: Copyright (c) 2026 kageroumado
- Usage: Parts of the native macOS wallpaper extension in `Extensions/Wallpaper/` are adapted from Phosphene, including the private WallpaperExtensionKit protocol bridge, video rendering, snapshots, settings-provider models and playback lifecycle.
- Modifications: Integrated with MacKit's local-video management UI and build/signing workflow; added lock-screen video routing, transition handling and configurable occlusion detection. Removed Wallpaper Engine integration, optimization-file selection, diagnostic probes, legacy single-video migration and automatic WallpaperAgent restart recovery.

The complete original copyright and license notice is preserved, unmodified, in [LICENSES/Phosphene-LICENSE.txt](LICENSES/Phosphene-LICENSE.txt). Adapted source files retain attribution comments. This notice does not claim that the adapted extension is wholly original MacKit code.

MacKit does not include Phosphene's Wallpaper Engine renderer, Steam integration, online catalog, telemetry or updater. User-imported wallpaper media are not supplied by MacKit and are not covered by this source-code license.

Distributed app bundles include this notice as `Contents/Resources/THIRD_PARTY_NOTICES.md`, the original license as `Contents/Resources/Licenses/Phosphene-LICENSE.txt`, and MacKit's own license as `Contents/Resources/Licenses/MacKit-LICENSE.txt`. All are accessible from the app's About page.

## Atoll / boring.notch

- Source: https://github.com/Ebullioscopic/Atoll
- License: GNU GPL version 3 or later (GPL-3.0-or-later); full text: [LICENSES/Atoll-GPL-3.0.txt](LICENSES/Atoll-GPL-3.0.txt).
- Copyright: Copyright (C) 2024–2026 Atoll Contributors. Portions originate from boring.notch; original source headers and notices are retained.
- Usage: MacKit includes adapted source for the notch UI and animations, system Now Playing/media/lyrics, calendar events, file tray, interactive terminal, activity/device/power/system-control indicators, and lock-screen media/weather/calendar/focus components. Required artwork, sounds, animations and the MediaRemoteAdapter bridge are also retained. This is a substantial code adaptation, not merely a design reference.
- Scope: `MacKit/Features/NotchRuntime/`, with host integration in `MacKit/Features/Atoll/`, the main settings UI and project-generation/build scripts. Third-party dependencies are listed separately below; their copyright is not attributed to MacKit or collectively to Atoll.
- Modifications (2026-11-08–2026-11-09): Integrated into one MacKit application lifecycle and settings window; removed notes, global gesture/shortcut configuration, download monitoring, color picking, screen assistant, clipboard history, statistics, extension/XPC interfaces, user timers and EventKit reminder tasks. Added Chinese settings, fixed configurations, multi-display sizing and lyric placement, playback-driven lyrics and additional lookup, per-application volume controls, file-tray keyboard handling, terminal settings, shared activity/preview presentation, and lock-screen layout adjustments. The standalone Atoll application, update feed, tests and development previews are not shipped. The runtime and resources were relocated into MacKit; the original standalone project was replaced by a trimmed build template.

MacKit modifications are Copyright (c) 2026 youyeyejie and distributed under GPL-3.0-or-later. Original notices are preserved below verbatim; statements describing Atoll's branding describe upstream Atoll, not MacKit. Source-code licensing does not grant trademark rights or transfer ownership of assets.

## MacKit distribution

The current combined program is distributed under GPL-3.0-or-later. MacKit modifications are Copyright (c) 2026 youyeyejie. The root LICENSE contains GPLv3. The `or later` grant is stated here and in the applicable source notices. Phosphene portions retain the MIT copyright/permission notices above; the MIT license permits their inclusion in a GPL distribution.

Earlier MacKit material already released under MIT remains available under that grant; its original notice is retained in `LICENSES/MacKit-Original-MIT.txt`. This update does not revoke recipients' existing MIT permissions.

Release binaries must be accompanied by equivalent access to their corresponding complete source, including these notices, third-party source modifications and the build/signing scripts. A generic link to a changing main branch is not a substitute for an exact release source snapshot. Do not distribute private signing keys; they are not part of the source package.

Bundled license copies and a source-code link are exposed through About → Open Source Licenses. No statement here guarantees the absence of disputes or substitutes for review of actual release artifacts and source availability.

Dependency cleanup (2026-11-09): retained lock animations use Lottie directly, without LottieUI. The unused updater UI, Sparkle framework, LaunchAtLogin-Modern and SwiftUI Introspect imports/products have been removed. Login startup remains implemented by MacKit using Apple's ServiceManagement API. Defaults' optional macro targets depend on Swift Syntax, but MacKit uses the ordinary Defaults target and its `@Default` property wrapper, not those macros. Swift Syntax may remain in package-resolution metadata because it is declared by the package; it is not linked/bundled and its license is no longer included as a distributed application component. The corresponding package source/license remains available through SwiftPM when fetching that build dependency graph.
