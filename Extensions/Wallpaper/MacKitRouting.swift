import Foundation

enum MacKitRouting {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("mackit-routing.json")
    }
    static func load() -> WallpaperRouting {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(WallpaperRouting.self, from: data) else { return WallpaperRouting() }
        return value
    }
    static func refreshAll() {
        let state = PlaybackStore.snapshot
        for key in SurfaceRegistry.shared.surfaceKeys {
            apply(key: key, mode: state.surfaces[key]?.mode ?? .default)
        }
    }
    static func lockChanged(_ locked: Bool) {
        let state = PlaybackStore.snapshot
        for key in SurfaceRegistry.shared.surfaceKeys {
            let reported = state.surfaces[key]?.mode ?? .default
            apply(key: key, mode: locked ? .locked : (reported == .locked ? .default : reported))
        }
    }
    static func snapshotURL(id: Any?) -> URL? {
        let key = extractWallpaperUUID(fromID: id).flatMap { SurfaceRegistry.shared.key(forWallpaperID: $0) }
        let state = PlaybackStore.snapshot
        var mode = key.flatMap { state.surfaces[$0]?.mode } ?? .default
        if state.screenLocked, mode == .default { mode = .locked }
        let original = key.flatMap { SurfaceRegistry.shared.surface(for: $0)?.videoID } ?? PlaybackStore.currentVideoID
        let selected = load().choice(mode: mode.description, systemChoice: original, isLocked: state.screenLocked)
        return ShuffleController.shared.resolveChoice(selected).flatMap { VideoLibrary.shared.videoURL(for: $0) }
    }
    static func mayShuffle(_ renderer: VideoRenderer) -> Bool {
        let state = PlaybackStore.snapshot
        for key in SurfaceRegistry.shared.surfaceKeys {
            guard let surface = SurfaceRegistry.shared.surface(for: key), surface.renderer === renderer else { continue }
            if surface.isPreview { return true }
            let mode = state.screenLocked ? "locked" : (state.surfaces[key]?.mode.description ?? "default")
            let selected = load().choice(mode: mode, systemChoice: surface.videoID, isLocked: state.screenLocked)
            return selected == shuffleChoiceID
        }
        return false
    }
    /// Called on the serialized XPC lifecycle queue, before playback policy
    /// changes. A new acquire is reconciled by the host's following update.
    static func apply(key: SurfaceKey?, mode: PresentationMode) {
        let routing = load()
        let keys = key.map { [$0] } ?? SurfaceRegistry.shared.surfaceKeys
        for key in keys {
            guard let surface = SurfaceRegistry.shared.surface(for: key), !surface.isPreview,
                  let renderer = surface.renderer else { continue }
            let logical = routing.choice(mode: mode.description, systemChoice: surface.videoID, isLocked: PlaybackStore.snapshot.screenLocked)
            let resolved = ShuffleController.shared.resolveChoice(logical)
            guard let id = resolved, let url = VideoLibrary.shared.videoURL(for: id) else { continue }
            extensionLog("[MacKitRouting] surface=\(key) reported=\(mode) locked=\(PlaybackStore.snapshot.screenLocked) selected=\(id)")
            renderer.switchVideo(to: url, selector: makeVideoSelector(choice: id, fallback: url))
        }
    }
}
