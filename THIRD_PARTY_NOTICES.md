# Third-Party Notices

## Phosphene

- Source: https://github.com/kageroumado/phosphene
- License: MIT License
- Copyright: Copyright (c) 2026 kageroumado
- Usage: Parts of the native macOS wallpaper extension in `Extensions/Wallpaper/` are adapted from Phosphene, including the private WallpaperExtensionKit protocol bridge, video rendering, snapshots, settings-provider models and playback lifecycle.
- Modifications: Integrated with MacKit's local-video management UI and build/signing workflow; added lock-screen video routing, transition handling and configurable occlusion detection. Removed Wallpaper Engine integration, optimization-file selection, diagnostic probes, legacy single-video migration and automatic WallpaperAgent restart recovery.

The complete original copyright and license notice is preserved, unmodified, in [LICENSES/Phosphene-LICENSE.txt](LICENSES/Phosphene-LICENSE.txt). Adapted source files retain attribution comments. This notice does not claim that the adapted extension is wholly original MacKit code.

MacKit does not include Phosphene's Wallpaper Engine renderer, Steam integration, online catalog, telemetry or updater. User-imported wallpaper media are not supplied by MacKit and are not covered by this source-code license.

Distributed app bundles include this notice as `Contents/Resources/THIRD_PARTY_NOTICES.md`, the original license as `Contents/Resources/Licenses/Phosphene-LICENSE.txt`, and MacKit's own license as `Contents/Resources/Licenses/MacKit-LICENSE.txt`. All are accessible from the app's About page.

## Vorssaint

- Source: https://github.com/vorssaint/vorssaint-utils
- License: GNU GPL version 3 or later (GPL-3.0-or-later); full text: [LICENSES/Vorssaint-GPL-3.0.txt](LICENSES/Vorssaint-GPL-3.0.txt).
- Copyright: Copyright (C) 2026 Vorssaint.
- Usage: Window-switching and Dock behavior were implemented after consulting upstream source. To avoid treating potentially substantive adaptations as merely independent design references, the current combined distribution is released under GPL-3.0-or-later.
- Scope: `MacKit/Features/WindowTools/`, `DockClickPolicy.swift`, and `DockGeometry.swift`, including click commitment/replay, intent handling, window previews and hover behavior. These files differ from upstream and are not verbatim upstream releases.
- Modifications (2026-11-04): Integration with MacKit's architecture, native own-window operations, shared window enumeration and snapshots, custom card/UI layout, local preferences, system-app quit protection and lifecycle handling. License/provenance annotations were added on this date.

## MacKit distribution

The current combined program is distributed under GPL-3.0-or-later. MacKit modifications are Copyright (c) 2026 youyeyejie. The root LICENSE contains GPLv3. Phosphene portions retain the MIT copyright/permission notices above; the MIT license permits their inclusion in a GPL distribution.

Earlier MacKit material already released under MIT remains available under that grant; its original notice is retained in `LICENSES/MacKit-Original-MIT.txt`. This update does not revoke recipients' existing MIT permissions.

Release binaries must be accompanied by equivalent access to their corresponding complete source, including these notices, third-party source modifications and the build/signing scripts. A generic link to a changing main branch is not a substitute for an exact release source snapshot. Do not distribute private signing keys; they are not part of the source package.

Bundled license copies and a source-code link are exposed through About → Open Source Licenses. No statement here guarantees the absence of disputes or substitutes for review of actual release artifacts and source availability.
