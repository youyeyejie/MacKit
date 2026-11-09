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

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

// MARK: - Lyric Data Structures
struct LyricLine: Identifiable, Codable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String

    init(timestamp: TimeInterval, text: String) {
        self.timestamp = timestamp
        self.text = text
    }
}

private struct LyricsLookupKey: Hashable {
    let title: String
    let artist: String
    let album: String
    var source: String? = nil
    var identifier: String? = nil
    var duration: Int? = nil

    var isValid: Bool {
        !title.isEmpty && !artist.isEmpty
    }
}

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

private struct ITunesExplicitnessSearchResponse: Decodable {
    let results: [ITunesExplicitnessTrack]
}

private struct ITunesExplicitnessTrack: Decodable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let trackExplicitness: String?
}

private actor MusicExplicitnessResolver {
    struct LookupKey: Hashable, Sendable {
        let title: String
        let artist: String
        let album: String

        init(title: String, artist: String, album: String) {
            self.title = MusicExplicitnessResolver.normalize(title)
            self.artist = MusicExplicitnessResolver.normalize(artist)
            self.album = MusicExplicitnessResolver.normalize(album)
        }

        var canResolve: Bool {
            !title.isEmpty && !artist.isEmpty
        }
    }

    static let shared = MusicExplicitnessResolver()

    private let session = URLSession(configuration: .ephemeral)
    private static let cacheLimit = 300
    private var cache: [LookupKey: Bool] = [:]
    private var cacheOrder: [LookupKey] = []
    private var inFlightTasks: [LookupKey: Task<Bool, Never>] = [:]

    private func store(_ value: Bool, for key: LookupKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
            while cacheOrder.count > Self.cacheLimit {
                let evicted = cacheOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        }
        cache[key] = value
    }

    func resolve(title: String, artist: String, album: String) async -> Bool {
        let key = LookupKey(title: title, artist: artist, album: album)
        guard key.canResolve else { return false }

        if let cached = cache[key] {
            return cached
        }

        if let inFlightTask = inFlightTasks[key] {
            return await inFlightTask.value
        }

        let task = Task<Bool, Never> { [session] in
            await Self.fetchExplicitness(for: key, using: session)
        }

        inFlightTasks[key] = task
        let result = await task.value
        store(result, for: key)
        inFlightTasks[key] = nil
        return result
    }

    private static func fetchExplicitness(for key: LookupKey, using session: URLSession) async -> Bool {
        let query = "\(key.title) \(key.artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(
                string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=15")
        else {
            return false
        }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(ITunesExplicitnessSearchResponse.self, from: data)

            let bestMatch = response.results
                .map { track in (track, matchScore(for: track, key: key)) }
                .max { lhs, rhs in lhs.1 < rhs.1 }

            guard let bestMatch,
                  bestMatch.1 >= 8
            else {
                return false
            }

            return bestMatch.0.trackExplicitness?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == "explicit"
        } catch {
            return false
        }
    }

    private static func matchScore(for track: ITunesExplicitnessTrack, key: LookupKey) -> Int {
        let trackTitle = canonicalTitle(track.trackName ?? "")
        guard !trackTitle.isEmpty else { return Int.min }

        let keyTitle = canonicalTitle(key.title)
        let trackArtist = normalize(track.artistName ?? "")
        let trackAlbum = normalize(track.collectionName ?? "")

        var score = 0

        if trackTitle == keyTitle {
            score += 6
        } else if trackTitle.contains(keyTitle) || keyTitle.contains(trackTitle) {
            score += 4
        } else {
            return Int.min
        }

        if !key.artist.isEmpty {
            if trackArtist == key.artist {
                score += 4
            } else if trackArtist.contains(key.artist) || key.artist.contains(trackArtist) {
                score += 2
            }
        }

        if !key.album.isEmpty {
            if trackAlbum == key.album {
                score += 2
            } else if !trackAlbum.isEmpty && (trackAlbum.contains(key.album) || key.album.contains(trackAlbum)) {
                score += 1
            }
        }

        return score
    }

    private static func canonicalTitle(_ value: String) -> String {
        var title = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        title = title.replacingOccurrences(
            of: #"\([^)]*\)|\[[^\]]*\]"#,
            with: " ",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: #"\s-\s(?:\d{4}\s)?(?:remaster(?:ed)?|live|edit|mix|version|mono|stereo).*$"#,
            with: " ",
            options: .regularExpression
        )
        return normalize(title)
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let stripped = folded.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: " ",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private actor SpotifyExplicitnessResolver {
    struct LookupKey: Hashable, Sendable {
        let trackID: String

        init?(contentIdentifier: String?, contentURL: String?) {
            guard let trackID = SpotifyExplicitnessResolver.extractTrackID(from: contentIdentifier)
                ?? SpotifyExplicitnessResolver.extractTrackID(from: contentURL)
            else {
                return nil
            }

            self.trackID = trackID
        }
    }

    static let shared = SpotifyExplicitnessResolver()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0",
            "Accept-Language": "en-US,en;q=0.9"
        ]
        return URLSession(configuration: configuration)
    }()

    private static let cacheLimit = 300
    private var cache: [LookupKey: Bool] = [:]
    private var cacheOrder: [LookupKey] = []
    private var inFlightTasks: [LookupKey: Task<Bool?, Never>] = [:]

    private func store(_ value: Bool, for key: LookupKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
            while cacheOrder.count > Self.cacheLimit {
                let evicted = cacheOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        }
        cache[key] = value
    }

    func resolve(key: LookupKey) async -> Bool? {
        if let cached = cache[key] {
            return cached
        }

        if let inFlightTask = inFlightTasks[key] {
            return await inFlightTask.value
        }

        let task = Task<Bool?, Never> { [session] in
            await Self.fetchExplicitness(for: key, using: session)
        }

        inFlightTasks[key] = task
        let result = await task.value
        if let result {
            store(result, for: key)
        }
        inFlightTasks[key] = nil
        return result
    }

    private static func fetchExplicitness(for key: LookupKey, using session: URLSession) async -> Bool? {
        guard let url = URL(string: "https://open.spotify.com/embed/track/\(key.trackID)") else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8)
            else {
                return nil
            }

            if let isExplicit = parseIsExplicitDirectly(from: html) {
                return isExplicit
            }

            if let nextDataJSON = extractNextDataJSON(from: html),
               let isExplicit = parseIsExplicit(from: nextDataJSON) {
                return isExplicit
            }

            return nil
        } catch {
            return nil
        }
    }

    private static func extractNextDataJSON(from html: String) -> String? {
        let pattern = #"<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > 1,
              let jsonRange = Range(match.range(at: 1), in: html)
        else {
            return nil
        }

        return String(html[jsonRange])
    }

    private static func parseIsExplicitDirectly(from html: String) -> Bool? {
        if let value = captureFirstMatch(
            in: html,
            pattern: #""isExplicit"\s*:\s*(true|false)"#
        ) {
            return value == "true"
        }

        if let label = captureFirstMatch(
            in: html,
            pattern: #""label"\s*:\s*"([A-Z_]+)""#
        ) {
            switch label {
            case "EXPLICIT":
                return true
            case "NON_EXPLICIT":
                return false
            default:
                break
            }
        }

        return nil
    }

    private static func captureFirstMatch(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }

        return String(source[valueRange]).lowercased()
    }

    private static func parseIsExplicit(from nextDataJSON: String) -> Bool? {
        guard let data = nextDataJSON.data(using: .utf8),
              let rootObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = rootObject["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let state = pageProps["state"] as? [String: Any],
              let dataObject = state["data"] as? [String: Any],
              let entity = dataObject["entity"] as? [String: Any]
        else {
            return nil
        }

        if let isExplicit = entity["isExplicit"] as? Bool {
            return isExplicit
        }

        if let contentRating = entity["contentRating"] as? [String: Any],
           let label = contentRating["label"] as? String {
            return label.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "EXPLICIT"
        }

        return nil
    }

    private static func extractTrackID(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("spotify:track:") {
            return validatedTrackID(String(trimmed.split(separator: ":").last ?? ""))
        }

        if let url = URL(string: trimmed) {
            let pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if let trackIndex = pathComponents.firstIndex(of: "track"),
               trackIndex + 1 < pathComponents.count {
                return validatedTrackID(pathComponents[trackIndex + 1])
            }
        }

        return validatedTrackID(trimmed)
    }

    private static func validatedTrackID<S: StringProtocol>(_ candidate: S) -> String? {
        let value = String(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[A-Za-z0-9]{22}$"#, options: .regularExpression) != nil else {
            return nil
        }

        return value
    }
}

class MusicManager: ObservableObject {
    enum SkipDirection: Equatable {
        case backward
        case forward
    }

    struct SkipFeedbackPulse: Equatable {
        let token: Int
        let direction: SkipDirection
        let behavior: MusicSkipBehavior
    }

    static let skipFeedbackSeekInterval: TimeInterval = 10

    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?
    @MainActor private var pendingOptimisticPlayState: Bool?

    // Helper to check if macOS has removed support for NowPlayingController

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Pear Desktop auto-detection

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true
    @Published var isCurrentTrackExplicit: Bool = false

    /// Whether there is an active music session with real metadata.
    /// Returns `false` only when the metadata is still placeholder/fallback defaults
    /// (i.e. nothing has been played since app launch, or the controller returned
    /// unknown/not-playing placeholders). Paused music with real metadata is still
    /// considered an active session.
    private static let placeholderTitles: Set<String> = [
        "i'm handsome", "unknown", "not playing"
    ]
    private static let placeholderArtists: Set<String> = [
        "me", "unknown"
    ]

    var hasActiveSession: Bool {
        if isPlaying { return true }
        let trimmedTitle = songTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedArtist = artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasRealTitle = !trimmedTitle.isEmpty && !Self.placeholderTitles.contains(trimmedTitle)
        let hasRealArtist = !trimmedArtist.isEmpty && !Self.placeholderArtists.contains(trimmedArtist)
        return hasRealTitle || hasRealArtist
    }

    @Published var animations: DynamicIslandAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var secondaryColor: NSColor = .gray
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var isLiveStream: Bool = false
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published private(set) var skipFeedbackPulse: SkipFeedbackPulse?

    // MARK: - Lyrics Properties
    @Published var currentLyrics: String = ""
    @Published private(set) var lyricsReadyForCurrentTrack = false
    @Published var syncedLyrics: [LyricLine] = []
    @Published var showLyrics: Bool = false
    @Published var currentLyricIndex: Int = -1

    // Task used to periodically sync displayed lyric with playback position
    private var lyricSyncTask: Task<Void, Never>?
    private var lyricsFetchTask: Task<Void, Never>?
    private var lyricsFetchKey: LyricsLookupKey?
    private var lyricsMissUntil: [LyricsLookupKey: Date] = [:]
    private var activeLyricsKey: LyricsLookupKey?
    private var lyricsCache: [LyricsLookupKey: [LyricLine]] = [:]
    // Bounded, insertion-order eviction so the cache cannot grow unboundedly.
    private static let lyricsCacheLimit = 80
    private var lyricsCacheOrder: [LyricsLookupKey] = []
    private var explicitLookupTask: Task<Void, Never>?
    private var explicitLookupKey: String?

    /// Inserts lyrics with insertion-order eviction to keep the cache bounded.
    private func storeLyricsInCache(_ lyrics: [LyricLine], for key: LyricsLookupKey) {
        if lyricsCache[key] == nil {
            lyricsCacheOrder.append(key)
            while lyricsCacheOrder.count > Self.lyricsCacheLimit {
                let evicted = lyricsCacheOrder.removeFirst()
                lyricsCache.removeValue(forKey: evicted)
            }
        }
        lyricsCache[key] = lyrics
    }

    private(set) var artworkData: Data? = nil

    @Published var videoArtworkURL: URL? = nil

    private var liveStreamUnknownDurationCount: Int = 0
    private var liveStreamEdgeObservationCount: Int = 0
    private var liveStreamCompletionObservationCount: Int = 0
    private var liveStreamCompletionReleaseCount: Int = 0

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil
    private var lastArtworkContentIdentifier: String? = nil
    private var lastArtworkContentURL: String? = nil

    @Published var flipAngle: Double = 0
    @Published var lastFlipDirection: SkipDirection = .forward
    private let flipAnimationDuration: TimeInterval = 0.45
    private var flipCooldownActive: Bool = false

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?
    private var skipFeedbackToken: Int = 0

    // MARK: - Initialization
    init() {
        Defaults[.enableLyrics] = true
        if UserDefaults.standard.bool(forKey: "showLyricsOnNonNotchDisplays") {
            Defaults[.showLyricsBelowBuiltinNotch] = true
            UserDefaults.standard.removeObject(forKey: "showLyricsOnNonNotchDisplays")
        }
        // Listen for changes to the default controller preference


        Publishers.CombineLatest(Defaults.publisher(.enableLyrics), Defaults.publisher(.showLyricsBelowBuiltinNotch))
            .receive(on: RunLoop.main)
            .sink { [weak self] lyrics, builtin in self?.handleLyricsPreferenceChange(isEnabled: lyrics.newValue || builtin.newValue) }
            .store(in: &cancellables)

        Defaults.publisher(.pausedMediaHideDelay)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.isPlaying else { return }
                self.debounceIdleTask?.cancel()
                self.debounceIdleTask = nil
                self.isPlayerIdle = false
                self.updateIdleState(state: false)
            }.store(in: &cancellables)

        // Observe Pear Desktop launch/terminate for auto-detection

        setActiveControllerBasedOnPreference()
    }

    // MARK: - Pear Desktop Auto-Detection


    deinit {
        destroy()
    }
    
    public func destroy() {
        lyricsRetryTask?.cancel()
        debounceIdleTask?.cancel()
        lyricsFetchTask?.cancel()
        lyricSyncTask?.cancel()
        explicitLookupTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        transitionWorkItem?.cancel()

        // Release active controller
        activeController = nil
    }

    // MARK: - Setup Methods


    private func setActiveControllerBasedOnPreference() {
        controllerCancellables.removeAll()
        activeController = nil
        guard let controller = NowPlayingController() else { return }
        controller.playbackStatePublisher.receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.updateFromPlaybackState(state) }
            .store(in: &controllerCancellables)
        setActiveController(controller)
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        // Set new active controller
        activeController = controller

        // Get current state from active controller
        forceUpdate()
    }

    @MainActor
    private func applyPlayState(_ state: Bool, animation: Animation?) {
        if let animation {
            var transaction = Transaction()
            transaction.animation = animation
            withTransaction(transaction) {
                self.isPlaying = state
            }
        } else {
            self.isPlaying = state
        }

        self.updateIdleState(state: state)
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Check for playback state changes (playing/paused)
        let eventIsPlaying = state.isPlaying
        let expectedState = pendingOptimisticPlayState
        pendingOptimisticPlayState = nil

        if eventIsPlaying != self.isPlaying {
            let animation: Animation? = (expectedState == eventIsPlaying) ? .smooth(duration: 0.18) : .smooth
            applyPlayState(eventIsPlaying, animation: animation)

            if eventIsPlaying && !state.title.isEmpty && !state.artist.isEmpty {
            }
        } else {
            self.updateIdleState(state: eventIsPlaying)
        }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier
        let contentIdentifierChanged = state.contentIdentifier != self.lastArtworkContentIdentifier
        let contentURLChanged = state.contentURL != self.lastArtworkContentURL

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData

        let hasContentChange =
            titleChanged
            || artistChanged
            || albumChanged
            || artworkChanged
            || bundleChanged
            || contentIdentifierChanged
            || contentURLChanged
        let liveArtworkChanged = state.liveArtworkURL != self.videoArtworkURL

        if liveArtworkChanged {
            self.videoArtworkURL = state.liveArtworkURL
        }

        // Handle artwork and visual transitions for changed content
        let shouldAutoPeekOnTrackChange = NotchConfiguration.showSneakPeekOnTrackChange

        let trackChanged = titleChanged || artistChanged || bundleChanged
        if trackChanged {
            withAnimation(.smooth(duration: 0.25)) { lyricsReadyForCurrentTrack = false }
            currentLyrics = ""
            syncedLyrics = []
            currentLyricIndex = -1
            stopLyricSync()
            lyricsFetchTask?.cancel()
            lyricsFetchTask = nil
            lyricsFetchKey = nil
            activeLyricsKey = nil
        }
        if !eventIsPlaying && songDuration > 0 && elapsedTime >= songDuration - 0.25 {
            lyricsReadyForCurrentTrack = false
        }
        if hasContentChange {
            if trackChanged { self.triggerFlipAnimation() }

            if artworkChanged, let artwork = state.artwork {
                self.updateArtwork(artwork)
            } else if state.artwork == nil && trackChanged {
                // Try to use app icon if no artwork but track changed
                if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                    self.usingAppIconForArtwork = true
                    self.updateAlbumArt(newAlbumArt: appIconImage)
                }
            }
            if state.artwork != nil || trackChanged { self.artworkData = state.artwork }

            // Update last artwork change values
            self.lastArtworkTitle = state.title
            self.lastArtworkArtist = state.artist
            self.lastArtworkAlbum = state.album
            self.lastArtworkBundleIdentifier = state.bundleIdentifier
            self.lastArtworkContentIdentifier = state.contentIdentifier
            self.lastArtworkContentURL = state.contentURL

            if let liveArtworkURL = state.liveArtworkURL {
                self.videoArtworkURL = liveArtworkURL
            } else {
                self.fetchVideoArtwork()
            }



            // Only update sneak peek if there's actual content and something changed
            
        } else if state.isExplicit != nil {
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode

        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        if timeChanged {
            self.elapsedTime = state.currentTime
            // Update current lyric based on elapsed time

        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        
        // Lyrics must use the new, fully applied metadata, never the preceding snapshot.
        if trackChanged { prepareLyricsForCurrentTrack() }
        updateLiveStreamState(with: state)
        self.timestampDate = state.lastUpdated
        if !syncedLyrics.isEmpty { updateCurrentLyric(for: estimatedPlaybackPosition()) }

        // Manage lyric sync task based on playback/lyrics availability
        if (Defaults[.enableLyrics] || Defaults[.showLyricsBelowBuiltinNotch]) && !self.syncedLyrics.isEmpty {
            // Ensure syncing runs while lyrics are enabled
            startLyricSync()
        } else {
            stopLyricSync()
        }
    }



    @MainActor
    private func refreshGenericExplicitFlag(title: String, artist: String, album: String) {
        let lookupKey = MusicExplicitnessResolver.LookupKey(
            title: title,
            artist: artist,
            album: album
        )
        let lookupIdentifier = "generic|\(lookupKey.title)|\(lookupKey.artist)|\(lookupKey.album)"

        guard lookupKey.canResolve,
              !Self.placeholderTitles.contains(lookupKey.title),
              !Self.placeholderArtists.contains(lookupKey.artist)
        else {
            explicitLookupTask?.cancel()
            explicitLookupTask = nil
            explicitLookupKey = nil
            if isCurrentTrackExplicit {
                isCurrentTrackExplicit = false
            }
            return
        }

        guard explicitLookupKey != lookupIdentifier else { return }

        explicitLookupTask?.cancel()
        explicitLookupKey = lookupIdentifier

        if isCurrentTrackExplicit {
            isCurrentTrackExplicit = false
        }

        explicitLookupTask = Task { [weak self] in
            let isExplicit = await MusicExplicitnessResolver.shared.resolve(
                title: title,
                artist: artist,
                album: album
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self,
                      self.explicitLookupKey == lookupIdentifier
                else {
                    return
                }

                self.isCurrentTrackExplicit = isExplicit
                self.explicitLookupTask = nil
            }
        }
    }

    private func triggerFlipAnimation() {
        // Debounce: rapid metadata updates (title, artwork, bundle arriving
        // separately for one track change) should only produce a single flip.
        guard !flipCooldownActive else { return }
        flipCooldownActive = true

        // Direction: positive rotation = next (page turn forward),
        //            negative rotation = previous (page turn backward).
        let delta: Double = lastFlipDirection == .forward ? 180 : -180
        withAnimation(.easeInOut(duration: flipAnimationDuration)) {
            flipAngle += delta
        }

        // Reset cooldown after the animation completes so the next
        // genuine track change can flip again.
        DispatchQueue.main.asyncAfter(deadline: .now() + flipAnimationDuration + 0.15) { [weak self] in
            self?.flipCooldownActive = false
        }
    }

    private func updateLiveStreamState(with state: PlaybackState) {
        let duration = state.duration
        let current = max(state.currentTime, elapsedTime)
        let hasKnownDuration = duration.isFinite && duration > 0
        let isPlaying = state.isPlaying

        if hasKnownDuration {
            liveStreamUnknownDurationCount = 0

            let remaining = duration - current
            let clampedDuration = max(duration, 0)
            let clampedCurrent = clampedDuration > 0
                ? max(0, min(current, clampedDuration))
                : max(0, current)
            let progress = clampedDuration > 0 ? clampedCurrent / clampedDuration : 0
            let sliderAppearsComplete = isPlaying && clampedDuration > 0 && progress >= 0.999
            let nearDurationEdge = isPlaying && remaining.isFinite && remaining <= 1.0 && clampedCurrent >= 10

            if sliderAppearsComplete {
                liveStreamCompletionObservationCount = min(liveStreamCompletionObservationCount + 1, 8)
                liveStreamCompletionReleaseCount = 0
            } else {
                liveStreamCompletionReleaseCount = min(liveStreamCompletionReleaseCount + 1, 8)
                if liveStreamCompletionObservationCount > 0 {
                    liveStreamCompletionObservationCount = max(liveStreamCompletionObservationCount - 1, 0)
                }
            }

            if nearDurationEdge || sliderAppearsComplete {
                liveStreamEdgeObservationCount = min(liveStreamEdgeObservationCount + 1, 12)
            } else if liveStreamEdgeObservationCount > 0 {
                liveStreamEdgeObservationCount = max(liveStreamEdgeObservationCount - 1, 0)
            }

            if !isLiveStream {
                if liveStreamCompletionObservationCount >= 3 || liveStreamEdgeObservationCount >= 5 {
                    isLiveStream = true
                }
            } else {
                let shouldClearForKnownDuration =
                    (duration > 10 && remaining > 5)
                    || (liveStreamCompletionObservationCount == 0
                        && liveStreamEdgeObservationCount == 0
                        && liveStreamCompletionReleaseCount >= 4)

                if shouldClearForKnownDuration {
                    isLiveStream = false
                }
            }
        } else if isPlaying {
            liveStreamEdgeObservationCount = max(liveStreamEdgeObservationCount - 1, 0)
            liveStreamCompletionObservationCount = max(liveStreamCompletionObservationCount - 1, 0)
            liveStreamCompletionReleaseCount = 0

            liveStreamUnknownDurationCount = min(liveStreamUnknownDurationCount + 1, 8)
            if liveStreamUnknownDurationCount >= 3 && !isLiveStream {
                isLiveStream = true
            }
        } else {
            liveStreamUnknownDurationCount = 0
            liveStreamEdgeObservationCount = 0
            liveStreamCompletionObservationCount = 0
            liveStreamCompletionReleaseCount = 0
        }
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            debounceIdleTask?.cancel()
            debounceIdleTask = nil
            isPlayerIdle = false
        } else {
            let delay = Defaults[.pausedMediaHideDelay]
            guard delay >= 0 else {
                debounceIdleTask?.cancel()
                debounceIdleTask = nil
                isPlayerIdle = false
                return
            }
            guard !isPlayerIdle, debounceIdleTask == nil else { return }
            debounceIdleTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.debounceIdleTask = nil
                guard !self.isPlaying else { return }
                withAnimation(.smooth) { self.isPlayerIdle = true }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        workItem = DispatchWorkItem { [weak self] in
            withAnimation(.smooth) {
                self?.albumArt = newAlbumArt
                
                    self?.calculateAverageColor()
                
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem!)
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.prominentOpposingColors { [weak self] primary, secondary in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = primary
                    self?.secondaryColor = secondary
                }
            }
        }
    }



    // MARK: - Public Methods for controlling playback
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        guard let controller = activeController else { return }
        let targetState = !isPlaying

        Task {
            await MainActor.run {
                pendingOptimisticPlayState = targetState
                applyPlayState(targetState, animation: .smooth(duration: 0.18))
            }

            if targetState {
                await controller.play()
            } else {
                await controller.pause()
            }
        }
    }

    func nextTrack() {
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        Task {
            await activeController?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
        }
    }

    func seek(by offset: TimeInterval) {
        guard !isLiveStream else { return }
        let duration = songDuration
        guard duration > 0 else { return }

        let current = estimatedPlaybackPosition()
        let magnitude = abs(offset)

        if offset < 0, current <= magnitude {
            previousTrack()
            return
        }

        if offset > 0, (duration - current) <= magnitude {
            nextTrack()
            return
        }

        let target = min(max(0, current + offset), duration)
        seek(to: target)
    }



    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func shutdown() {
        lyricsFetchTask?.cancel()
        lyricsRetryTask?.cancel()
        stopLyricSync()
        (activeController as? NowPlayingController)?.stopMonitoring()
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                await self?.activeController?.updatePlaybackInfo()
            }
        }
    }

    // MARK: - Lyrics Methods
    func fetchLyrics() {
        lyricsRetryTask?.cancel()
        lyricsRetryTask = nil
        lyricsRetryCount = 0
        lyricsFetchTask?.cancel()
        lyricsFetchTask = nil
        lyricsFetchKey = nil
        prepareLyricsForCurrentTrack(forceFetch: true, prioritizeVisibleResult: (Defaults[.enableLyrics] || Defaults[.showLyricsBelowBuiltinNotch]))
    }

    private func handleLyricsPreferenceChange(isEnabled: Bool) {
        guard showLyrics != isEnabled else { return }
        showLyrics = isEnabled

        if isEnabled {
            prepareLyricsForCurrentTrack(forceFetch: true, prioritizeVisibleResult: true)
        } else {
            lyricsFetchTask?.cancel()
            lyricsFetchTask = nil
            lyricsFetchKey = nil
            currentLyrics = ""
            stopLyricSync()
        }
    }

    private var lyricsRetryTask: Task<Void, Never>?
    private var lyricsRetryCount = 0
    private func retryMissingLyrics() {
        guard syncedLyrics.isEmpty, lyricsRetryTask == nil else { return }
        guard lyricsRetryCount < 3 else {
            lyricsReadyForCurrentTrack = false
            return
        }
        let retryDelay = [2.0, 5.0, 10.0][lyricsRetryCount]
        lyricsRetryCount += 1
        let key = activeLyricsKey
        lyricsRetryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(retryDelay)) } catch { return }
            guard let self else { return }
            self.lyricsRetryTask = nil
            guard self.activeLyricsKey == key, self.syncedLyrics.isEmpty else { return }
            self.prepareLyricsForCurrentTrack(forceFetch: true)
        }
    }

    private func prepareLyricsForCurrentTrack(forceFetch: Bool = false, prioritizeVisibleResult: Bool = false) {
        guard Defaults[.enableLyrics] || Defaults[.showLyricsBelowBuiltinNotch] else { return }
        guard let lookup = currentLyricsLookupContext() else {
            // Empty metadata can be a transitional snapshot while changing songs.
            lyricsReadyForCurrentTrack = false
            activeLyricsKey = nil
            lyricsFetchKey = nil
            lyricsFetchTask?.cancel()
            lyricsFetchTask = nil
            syncedLyrics = []
            currentLyrics = ""
            currentLyricIndex = -1
            stopLyricSync()
            return
        }

        let key = lookup.key
        let lyricsEnabled = (Defaults[.enableLyrics] || Defaults[.showLyricsBelowBuiltinNotch])
        let shouldShowLoading = lyricsEnabled && prioritizeVisibleResult
        let trackChanged = activeLyricsKey != key
        activeLyricsKey = key

        if trackChanged {
            lyricsReadyForCurrentTrack = false
            currentLyrics = ""
            lyricsRetryTask?.cancel()
            lyricsRetryTask = nil
            lyricsRetryCount = 0
            syncedLyrics = []
            currentLyricIndex = -1
            currentLyrics = ""
            stopLyricSync()
        }

        if !forceFetch, let until = lyricsMissUntil[key], until > Date() {
            retryMissingLyrics()
            return
        }

        if !forceFetch, let cachedLyrics = lyricsCache[key] {
            applyLyricsToDisplay(cachedLyrics)
            return
        }

        if lyricsFetchKey == key {
            if shouldShowLoading && syncedLyrics.isEmpty {
                currentLyrics = ""
            }
            return
        }

        lyricsFetchTask?.cancel()
        lyricsFetchKey = key

        if shouldShowLoading || (lyricsEnabled && syncedLyrics.isEmpty) {
            currentLyrics = ""
        }

        let requestArtist = lookup.requestArtist
        let requestTitle = lookup.requestTitle
        let requestAlbum = lookup.requestAlbum
        let requestDuration = songDuration
        let requestSource = bundleIdentifier
        let requestIdentifier = lastArtworkContentIdentifier ?? lastArtworkContentURL

        lyricsFetchTask = Task { [weak self] in
            guard let self else { return }

            do {
                let lyrics = try await self.fetchLyricsFromAPI(
                    artist: requestArtist,
                    title: requestTitle,
                    album: requestAlbum, duration: requestDuration, source: requestSource, identifier: requestIdentifier, force: forceFetch
                )
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.activeLyricsKey == key else { return }
                    if !lyrics.isEmpty { self.storeLyricsInCache(lyrics, for: key) }
                    else {
                        self.lyricsMissUntil[key] = Date().addingTimeInterval(30)
                        if self.lyricsMissUntil.count > 80 { self.lyricsMissUntil = [key: Date().addingTimeInterval(30)] }
                    }
                    self.lyricsFetchKey = nil
                    self.lyricsFetchTask = nil
                    self.applyLyricsToDisplay(lyrics)
                    if lyrics.isEmpty { self.retryMissingLyrics() }
                }
            } catch {
                guard !Task.isCancelled else { return }
                print("Failed to fetch lyrics: \(error)")
                await MainActor.run {
                    guard self.activeLyricsKey == key else { return }
                    self.lyricsFetchKey = nil
                    self.lyricsFetchTask = nil
                    self.currentLyrics = ""
                    self.lyricsReadyForCurrentTrack = false
                    self.syncedLyrics = []
                    self.currentLyricIndex = -1
                    self.currentLyrics = ""
                    self.retryMissingLyrics()
                    self.stopLyricSync()
                }
            }
        }
    }

    private func fetchLyricsFromAPI(artist: String, title: String, album: String, duration: Double, source: String?, identifier: String?, force: Bool) async throws -> [LyricLine] {
        try await LyricsProvider.shared.lyrics(for: LyricsTrack(title: title, artist: artist, album: album, duration: duration, source: source, identifier: identifier), force: force)
    }

    private func currentLyricsLookupContext() -> (key: LyricsLookupKey, requestArtist: String, requestTitle: String, requestAlbum: String)? {
        let requestArtist = normalizedLyricsRequestComponent(artistName)
        let requestTitle = normalizedLyricsTitle(songTitle)
        let requestAlbum = normalizedLyricsRequestComponent(album)

        let key = LyricsLookupKey(
            title: requestTitle.lowercased(),
            artist: requestArtist.lowercased(),
            album: requestAlbum.lowercased(), source: bundleIdentifier, identifier: nil, duration: nil
        )

        return key.isValid ? (key, requestArtist, requestTitle, requestAlbum) : nil
    }

    private func normalizedLyricsRequestComponent(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func normalizedLyricsTitle(_ value: String) -> String {
        var normalized = normalizedLyricsRequestComponent(value)
        let cleanupPatterns = [
            "\\s*\\((feat\\.?|ft\\.?|featuring)[^\\)]*\\)",
            "\\s*\\[(feat\\.?|ft\\.?|featuring)[^\\]]*\\]",
            "\\s*-\\s*(feat\\.?|ft\\.?|featuring)\\s+.*$",
            "\\s*\\((remaster(ed)?|live|mono|stereo)[^\\)]*\\)$",
            "\\s*\\[(remaster(ed)?|live|mono|stereo)[^\\]]*\\]$"
        ]

        for pattern in cleanupPatterns {
            normalized = normalized.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return normalizedLyricsRequestComponent(normalized)
    }





    private func applyLyricsToDisplay(_ lyrics: [LyricLine]) {
        currentLyrics = ""
        syncedLyrics = lyrics
        lyricsReadyForCurrentTrack = false
        currentLyricIndex = -1

        guard !lyrics.isEmpty else {
            currentLyrics = ""
            stopLyricSync()
            return
        }

        let playbackPosition = max(estimatedPlaybackPosition(), elapsedTime)
        updateCurrentLyric(for: playbackPosition)

        if currentLyricIndex == -1, let firstLine = lyrics.first?.text {
            currentLyrics = firstLine
        }

        withAnimation(.smooth(duration: 0.25)) { lyricsReadyForCurrentTrack = true }
        if (Defaults[.enableLyrics] || Defaults[.showLyricsBelowBuiltinNotch]) {
            startLyricSync()
        } else {
            stopLyricSync()
        }
    }



    func updateCurrentLyric(for elapsedTime: TimeInterval) {
        guard !syncedLyrics.isEmpty else { return }

        // Find the current lyric based on elapsed time
        var newIndex = -1
        for (index, lyric) in syncedLyrics.enumerated() {
            if elapsedTime >= lyric.timestamp {
                newIndex = index
            } else {
                break
            }
        }

        if newIndex != currentLyricIndex {
            currentLyricIndex = newIndex
            if newIndex >= 0 && newIndex < syncedLyrics.count {
                currentLyrics = syncedLyrics[newIndex].text
            }
        }
    }

    // Start a background task that periodically updates the displayed lyric
    private func startLyricSync() {
        // If already running, keep it
        if lyricSyncTask != nil { return }

        lyricSyncTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Compute estimated playback position and update lyric
                await MainActor.run {
                    self.updateCurrentLyric(for: self.estimatedPlaybackPosition())
                }

                // Sleep ~300ms between updates
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func stopLyricSync() {
        lyricSyncTask?.cancel()
        lyricSyncTask = nil
    }

    // MARK: - Video Artwork

    func fetchVideoArtwork() {
        guard Defaults[.lockScreenMusicFullscreenVideoArtwork] else {
            videoArtworkURL = nil
            return
        }
        // Se il player non è Apple Music, non toccare videoArtworkURL:
        // SpotifyController gestisce il canvas in modo autonomo tramite liveArtworkURL.
        guard bundleIdentifier == "com.apple.Music" else {
            return
        }

        let title = songTitle
        let artist = artistName

        Task {
            let url = await AnimatedArtworkManager.shared.fetchAnimatedArtworkURL(
                title: title, artist: artist
            )
            await MainActor.run {
                self.videoArtworkURL = url
            }
        }
    }

    func toggleLyrics() {
        // Toggle the UI state first so the views can react immediately.
        showLyrics.toggle()

        // If lyrics are requested to be shown but we don't have any yet,
        // show a loading placeholder and start fetching asynchronously.
        if showLyrics && syncedLyrics.isEmpty {
            // Provide immediate feedback so the UI can show a loading state.
            currentLyrics = ""

            Task {
                await fetchLyrics()

                // If fetch completed but no lyrics were found, show a friendly message.
                await MainActor.run {
                    if self.syncedLyrics.isEmpty && self.currentLyrics.isEmpty {
                        self.currentLyrics = ""
                    }
                }
            }
        }
    }
}

// MARK: - Media Branding

extension MusicManager {
    var brandAccentColor: Color {
        Self.brandAccentColor(for: NotchConfiguration.mediaController, bundleIdentifier: bundleIdentifier)
    }

    private static func brandAccentColor(for controller: MediaControllerType, bundleIdentifier: String?) -> Color { .accentColor }

}

// MARK: - Album Art Flip Helper

private struct AlbumArtFlipModifier: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                anchorZ: 0,
                perspective: 0.5
            )
            // Counter-rotate the content so the image never appears mirrored.
            // At odd multiples of 180° the 3D rotation mirrors along X;
            // applying an opposite scaleEffect cancels that out.
            .scaleEffect(x: cosineSign(for: angle), y: 1)
    }

    /// Returns +1 when the front face is showing, −1 when the back face is showing.
    private func cosineSign(for degrees: Double) -> CGFloat {
        let cos = Darwin.cos(degrees * .pi / 180)
        // Use a small tolerance to avoid flickering exactly at 90°/270°.
        if cos > 0.001 { return 1 }
        if cos < -0.001 { return -1 }
        return degrees.truncatingRemainder(dividingBy: 360) >= 0 ? -1 : 1
    }
}

extension View {
    func albumArtFlip(angle: Double) -> some View {
        modifier(AlbumArtFlipModifier(angle: angle))
    }
}
