# Third-Party Notices

MacKit includes adapted third-party code and bundled dependencies. Original copyright notices and license texts are retained in source headers and [LICENSES](LICENSES/). MacKit modifications are Copyright (c) 2026 youyeyejie.

## Adapted projects

### Atoll / boring.notch

- **Source:** https://github.com/Ebullioscopic/Atoll
- **License:** GPL-3.0-or-later; [full text](LICENSES/Atoll-GPL-3.0.txt).
- **Copyright:** Copyright (C) 2024–2026 Atoll Contributors. Includes code originating from boring.notch; original headers and notices are retained.
- **Scope:** `MacKit/Features/NotchRuntime/`, host integration in `MacKit/Features/Atoll/`, and associated settings, resources and project-generation code. Includes notch UI, media/lyrics, calendar, file tray, terminal, system indicators and lock-screen components.
- **Changes:** Integrated into one application lifecycle; replaced standalone settings with MacKit's grouped root/child pages; adapted multi-display behavior, media/lyrics, activity presentation and lock-screen layout. Removed unused upstream features, standalone app/update paths and obsolete settings views.

### Vorssaint

- **Source:** https://github.com/vorssaint/vorssaint-utils
- **License:** GPL-3.0-or-later; [full text](LICENSES/Vorssaint-GPL-3.0.txt).
- **Copyright:** Copyright (C) 2026 Vorssaint.
- **Scope:** Window-switching and Dock-related files in `MacKit/Features/WindowTools/`, plus `DockClickPolicy.swift` and `DockGeometry.swift`. Excludes `MissionControlService.swift`, attributed below.
- **Changes:** Adapted input handling, hover/click behavior, window enumeration, thumbnails and preview controls to MacKit; added native own-window actions, preferences, lifecycle management and system-app quit protection.

### Phosphene

- **Source:** https://github.com/kageroumado/phosphene
- **License:** MIT; [full copyright and permission notice](LICENSES/Phosphene-LICENSE.txt).
- **Copyright:** Copyright (c) 2026 kageroumado.
- **Scope:** Native wallpaper extension in `Extensions/Wallpaper/`, including the WallpaperExtensionKit bridge, rendering, snapshots, settings and playback lifecycle.
- **Changes:** Added local-video management, lock-screen video routing, transitions, occlusion detection and MacKit's build/signing integration. Wallpaper Engine rendering, Steam integration, online catalog, telemetry and updater are not included. User-imported videos are not part of this source-code license.

### CloseUp

- **Source:** https://github.com/oomol-lab/CloseUp (reference revision `facdb5f23cebe02e3d68b164390c66f82c8c8ba5`).
- **License:** GPL-3.0; [full text](LICENSES/CloseUp-GPL-3.0.txt).
- **Scope:** `MacKit/Features/WindowTools/MissionControlService.swift`; adapted from `MissionControlSurface.swift`, `WindowInfo.swift`, `MissionControlEngine.swift` and `AXWindow.swift`.
- **Changes:** Integrated Mission Control surface detection, CGWindowID hit testing and AX window lookup with MacKit's independent Cmd-Q/W toggle, background input filter, native actions and system-app protection. Includes accessory/own-app handling and action-time window revalidation. CloseUp overlays, updater and application shell are not included.

## Bundled dependencies

Dependency revisions are pinned in [Config/RuntimePackages.resolved](Config/RuntimePackages.resolved). Each component retains its original copyright and terms in the following bundled license:

| Component | License / notice |
| --- | --- |
| Defaults | [MIT](LICENSES/Defaults-license.txt) |
| Lottie | [Apache-2.0](LICENSES/lottie-spm-LICENSE.txt) |
| SkyLightWindow | [MIT](LICENSES/SkyLightWindow-LICENSE.txt) |
| Swift Collections | [Apache-2.0 with Swift Runtime Library Exception](LICENSES/swift-collections-LICENSE.txt) |
| SwiftTerm | [MIT](LICENSES/SwiftTerm-LICENSE.txt) |
| MediaRemoteAdapter | [BSD-3-Clause](LICENSES/MediaRemoteAdapter-BSD-3-Clause.txt) |

## Distribution

The combined MacKit program is distributed under GPL-3.0-or-later; see [LICENSE](LICENSE). Third-party portions retain their original terms and attribution. Earlier MacKit code released under MIT retains that grant; see [the original notice](LICENSES/MacKit-Original-MIT.txt). Source-code licenses do not grant trademark rights.

Release distributions include this document and the license texts in `Contents/Resources/`, accessible from About → Open Source Licenses. Provide access to the corresponding complete source for the exact release, including modifications and build scripts. Local signing keys and certificates are not included.
