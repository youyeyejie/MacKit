import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

struct WallpaperVideo: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var filename: String
    var duration: Double
    var fps: Double
    var resolution: CGSize
    var dateAdded: Date
}

@MainActor @Observable
final class WallpaperService {
    private(set) var videos: [WallpaperVideo] = []
    private(set) var busy = false
    var message: String?
    var routing = WallpaperRouting()
    var pauseWhenCovered = true
    private let overview = WallpaperOverviewObserver()
    private var overviewActive = false
    private let thumbnails = NSCache<NSString, NSImage>()
    var supported: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 }
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.mackit.app.wallpaper.extension/Data/Documents", isDirectory: true)
    }
    init() {
        reload()
        overview.changed = { [weak self] active in
            guard let self, self.overviewActive != active else { return }
            self.overviewActive = active
            self.saveOptions()
        }
        if !videos.isEmpty { overview.start(); saveOptions() }
    }
    func stop() {
        overview.stop()
        if overviewActive { overviewActive = false; saveOptions() }
    }
    func reload() {
        let root = Self.directory.appendingPathComponent("videos")
        videos = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .compactMap { try? JSONDecoder().decode(WallpaperVideo.self, from: Data(contentsOf: $0.appendingPathComponent("metadata.json"))) }
            .sorted { $0.dateAdded > $1.dateAdded }
        if let data = try? Data(contentsOf: Self.directory.appendingPathComponent("mackit-routing.json")), let value = try? JSONDecoder().decode(WallpaperRouting.self, from: data) { routing = value }
        if let data = try? Data(contentsOf: Self.directory.appendingPathComponent("phosphene-prefs.json")), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { pauseWhenCovered = value["pauseWhenOccluded"] as? Bool ?? true }
    }
    func importVideos() {
        guard supported, !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let files = panel.urls
        busy = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            do {
                for file in files {
                    let asset = AVURLAsset(url: file)
                    guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CocoaError(.fileReadCorruptFile) }
                    let duration = try await asset.load(.duration).seconds
                    let size = try await track.load(.naturalSize)
                    let fps = try await track.load(.nominalFrameRate)
                    guard duration.isFinite, duration > 0, fps.isFinite else { throw CocoaError(.fileReadCorruptFile) }
                    let video = WallpaperVideo(id: UUID().uuidString, name: file.deletingPathExtension().lastPathComponent,
                                               filename: file.lastPathComponent, duration: duration, fps: Double(fps), resolution: size, dateAdded: Date())
                    // Validate/prepare first, then publish the complete directory atomically.
                    let destination = Self.directory.appendingPathComponent("videos/\(video.id)")
                    let staging = Self.directory.appendingPathComponent(".import-\(video.id)")
                    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                    do {
                        try await Task.detached(priority: .utility) { try FileManager.default.copyItem(at: file, to: staging.appendingPathComponent(video.filename)) }.value
                        try JSONEncoder().encode(video).write(to: staging.appendingPathComponent("metadata.json"), options: .atomic)
                        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try FileManager.default.moveItem(at: staging, to: destination)
                    } catch { try? FileManager.default.removeItem(at: staging); throw error }
                }
                self.reload()
                self.overview.start()
                self.saveOptions()
                Self.notify("libraryChanged")
                self.message = "壁纸已导入。"
            } catch { self.message = "导入失败：\(error.localizedDescription)" }
        }
    }
    func thumbnail(_ video: WallpaperVideo) async -> NSImage? {
        if let cached = thumbnails.object(forKey: video.id as NSString) { return cached }
        let source = Self.directory.appendingPathComponent("videos/\(video.id)/\(video.filename)")
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 100)
        guard let frame = try? await generator.image(at: .zero).image, !Task.isCancelled else { return nil }
        let image = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
        thumbnails.countLimit = 24
        thumbnails.setObject(image, forKey: video.id as NSString)
        return image
    }
    func remove(_ video: WallpaperVideo) {
        guard !busy, UUID(uuidString: video.id) != nil else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除“\(video.name)”？"
        alert.informativeText = "是否确认将 MacKit 导入的副本移到废纸？"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "删除副本").hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do {
            let root = Self.directory.appendingPathComponent("videos").resolvingSymlinksInPath()
            let target = root.appendingPathComponent(video.id)
            guard target.resolvingSymlinksInPath().deletingLastPathComponent() == root else { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.trashItem(at: target, resultingItemURL: nil)
            thumbnails.removeObject(forKey: video.id as NSString)
            reload()
            if routing.lockedVideoID == video.id { routing.lockedVideoID = nil }
            saveOptions()
            Self.notify("libraryChanged")
            message = "已移除导入副本，原文件未删除。"
        } catch { message = "删除失败：\(error.localizedDescription)" }
    }
    func revealLibrary() { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Self.directory.appendingPathComponent("videos").path) }
    func saveOptions() {
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(routing).write(to: Self.directory.appendingPathComponent("mackit-routing.json"), options: .atomic)
            let prefs: [String: Any] = ["pauseWhenOccluded": pauseWhenCovered, "screenSaverIsOurs": true, "missionControlActive": overviewActive]
            try JSONSerialization.data(withJSONObject: prefs).write(to: Self.directory.appendingPathComponent("phosphene-prefs.json"), options: .atomic)
            Self.notify("prefsChanged")
            message = nil
        } catch { message = error.localizedDescription }
    }
    private static func notify(_ suffix: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName("com.mackit.app.wallpaper.\(suffix)" as CFString), nil, nil, true)
    }
    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
