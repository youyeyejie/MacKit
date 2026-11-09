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
import Foundation

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    func updatePlaybackInfo() async { await refreshSnapshot() }

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: "", title: "", artist: "", album: ""
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }
    
    var isWorking: Bool {
        return process != nil && process?.isRunning == true
    }
    private var lastMusicItem:
        (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?)?

    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    private let MRMediaRemoteSetShuffleModeFunction: @convention(c) (Int) -> Void
    private let MRMediaRemoteSetRepeatModeFunction: @convention(c) (Int) -> Void

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var sessionObservers: [NSObjectProtocol] = []
    private let snapshots = SystemMediaSnapshotReader()
    private var refreshingSnapshot = false
    private var startingStream = false
    private var stopped = false
    private var lastReceivedAt = Date.distantPast

    // MARK: - Initialization
    init?() {
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
            let MRMediaRemoteSendCommandPointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSendCommand" as CFString),
            let MRMediaRemoteSetElapsedTimePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetElapsedTime" as CFString),
            let MRMediaRemoteSetShuffleModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetShuffleMode" as CFString),
            let MRMediaRemoteSetRepeatModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetRepeatMode" as CFString)
            
        else { return nil }

        mediaRemoteBundle = bundle
        MRMediaRemoteSendCommandFunction = unsafeBitCast(
            MRMediaRemoteSendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        MRMediaRemoteSetElapsedTimeFunction = unsafeBitCast(
            MRMediaRemoteSetElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)
        MRMediaRemoteSetShuffleModeFunction = unsafeBitCast(
            MRMediaRemoteSetShuffleModePointer, to: (@convention(c) (Int) -> Void).self)
        MRMediaRemoteSetRepeatModeFunction = unsafeBitCast(
            MRMediaRemoteSetRepeatModePointer, to: (@convention(c) (Int) -> Void).self)

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.setupNowPlayingObserver()
            await self.refreshSnapshot()
            self.installRecoveryObservers()
        }
    }

    deinit {
        refreshTask?.cancel()
        restartTask?.cancel()
        streamTask?.cancel()
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        if let reader = pipeHandler { Task { await reader.close() } }
        for token in sessionObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }

    func stopMonitoring() {
        stopped = true
        refreshTask?.cancel()
        restartTask?.cancel()
        streamTask?.cancel()
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        if let reader = pipeHandler { Task { await reader.close() } }
    }

    // MARK: - Protocol Implementation
    func play() async {
        MRMediaRemoteSendCommandFunction(0, nil)
    }

    func pause() async {
        MRMediaRemoteSendCommandFunction(1, nil)
    }

    func togglePlay() async {
        MRMediaRemoteSendCommandFunction(2, nil)
    }

    func nextTrack() async {
        MRMediaRemoteSendCommandFunction(4, nil)
    }

    func previousTrack() async {
        MRMediaRemoteSendCommandFunction(5, nil)
    }

    func seek(to time: Double) async {
        MRMediaRemoteSetElapsedTimeFunction(time)
    }

    func isActive() -> Bool {
        return true
    }
    
    @MainActor func toggleShuffle() async {
        await refreshSnapshot()
        // MediaRemoteAdapter defines disabled=1, albums=2, tracks=3.
        // Send through the Apple-signed bridge rather than relying on host-private calls.
        let mode = playbackState.isShuffled ? 1 : 3
        if !(await snapshots.setShuffle(mode)) { MRMediaRemoteSetShuffleModeFunction(mode) }
        try? await Task.sleep(for: .milliseconds(250))
        await refreshSnapshot()
    }
    
    func toggleRepeat() async {
        // MRMediaRemoteSendCommandFunction(7, nil)
        let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        MRMediaRemoteSetRepeatModeFunction(newRepeatMode)
    }
    
    @MainActor private func refreshSnapshot() async {
        guard !stopped, !refreshingSnapshot else { return }
        refreshingSnapshot = true
        defer { refreshingSnapshot = false }
        guard let payload = await snapshots.read() else { return }
        await handleAdapterUpdate(NowPlayingUpdate(payload: payload, diff: false))
    }

    @MainActor private func scheduleRestart() {
        guard !stopped else { return }
        restartTask?.cancel()
        restartTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            await self?.setupNowPlayingObserver()
            await self?.refreshSnapshot()
        }
    }

    @MainActor private func installRecoveryObservers() {
        guard refreshTask == nil else { return }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let token = NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.process?.terminationHandler = nil
                    if self.process?.isRunning == true { self.process?.terminate() }
                    self.process = nil
                    await self.setupNowPlayingObserver()
                    await self.refreshSnapshot()
                }
            }
            sessionObservers.append(token)
        }
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard let self else { return }
                if self.process?.isRunning != true { await self.setupNowPlayingObserver() }
                if Date().timeIntervalSince(self.lastReceivedAt) >= 10 { await self.refreshSnapshot() }
            }
        }
    }

    // MARK: - Setup Methods
    @MainActor private func setupNowPlayingObserver() async {
        guard !stopped, !startingStream, process?.isRunning != true else { return }
        startingStream = true
        defer { startingStream = false }
        streamTask?.cancel()
        process?.terminationHandler = nil
        if let reader = pipeHandler { await reader.close() }
        guard !stopped, let resources = Bundle.main.resourceURL else { return }
        let next = Process()
        next.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        next.arguments = [resources.appendingPathComponent("mediaremote-adapter.pl").path,
                          resources.appendingPathComponent("MediaRemoteAdapter.framework").path, "stream"]
        let reader = JSONLinesPipeHandler()
        let output = await reader.getPipe()
        next.standardOutput = output
        next.standardError = FileHandle.nullDevice
        next.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleRestart() }
        }
        process = next
        pipeHandler = reader
        do {
            try next.run()
            try? output.fileHandleForWriting.close()
            streamTask = Task { [weak self, reader] in
                await reader.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
                    await self?.handleAdapterUpdate(update)
                }
            }
        } catch {
            scheduleRestart()
        }
    }

    // MARK: - Async Stream Processing


    // MARK: - Update Methods
    @MainActor private func handleAdapterUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let diff = update.diff ?? false
        let source = payload.parentApplicationBundleIdentifier ?? payload.bundleIdentifier
        let changedSource = source != nil && source != playbackState.bundleIdentifier
        // Full snapshots can omit metadata during play/pause transitions too.
        // Preserve omitted fields for the same source instead of briefly publishing
        // an empty track (which refetches lyrics and flips the artwork twice).
        var value = changedSource ? PlaybackState(bundleIdentifier: source ?? "", title: "", artist: "", album: "") : playbackState
        if let title = payload.title, title != playbackState.title {
            // Metadata and the elapsed-time update can arrive separately.
            // Never use the preceding song's clock to select the new song's lyric.
            value.currentTime = 0
            value.duration = 0
            value.lastUpdated = Date()
            value.artwork = nil
            value.contentIdentifier = nil
            value.contentURL = nil
        }
        value.title = payload.title ?? value.title
        value.artist = payload.artist ?? value.artist
        value.album = payload.album ?? value.album
        value.duration = payload.duration ?? value.duration
        value.currentTime = payload.elapsedTime ?? value.currentTime
        value.contentIdentifier = payload.contentItemIdentifier ?? value.contentIdentifier
        value.contentURL = payload.contentURL ?? value.contentURL
        if let source { value.bundleIdentifier = source }
        if let mode = payload.shuffleMode { value.isShuffled = mode != 1 }
        if let mode = payload.repeatMode { value.repeatMode = RepeatMode(rawValue: mode) ?? .off }
        if let artwork = payload.artworkData {
            value.artwork = Data(base64Encoded: artwork.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let timestamp = payload.timestamp {
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            value.lastUpdated = parser.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp) ?? Date()
        } else if payload.elapsedTime != nil || !diff {
            value.lastUpdated = Date()
        }
        if let playing = payload.playing {
            if playing != playbackState.isPlaying && payload.elapsedTime == nil && !changedSource {
                let elapsed = playbackState.isPlaying ? max(0, Date().timeIntervalSince(playbackState.lastUpdated)) * playbackState.playbackRate : 0
                value.currentTime = playbackState.currentTime + elapsed
                if value.duration > 0 { value.currentTime = min(value.currentTime, value.duration) }
                value.lastUpdated = Date()
            }
            value.isPlaying = playing
        }
        if payload.playing == nil, let rate = payload.playbackRate { value.isPlaying = rate > 0 }
        value.playbackRate = payload.playbackRate ?? (value.isPlaying ? (diff ? playbackState.playbackRate : 1) : 0)
        lastReceivedAt = Date()
        playbackState = value
    }
}

struct NowPlayingUpdate: Codable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

struct NowPlayingPayload: Codable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let shuffleMode: Int?
    let repeatMode: Int?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
    let contentItemIdentifier: String?
    let contentURL: String?
}

// Drain complete UTF-8 lines: partial multibyte characters must not discard a snapshot.
actor JSONLinesPipeHandler {
    private let pipe = Pipe()
    func getPipe() -> Pipe { pipe }
    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async {
        do {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                guard !Task.isCancelled else { return }
                guard !line.isEmpty, line.utf8.count <= 16_777_216,
                      let decoded = try? JSONDecoder().decode(type, from: Data(line.utf8)) else { continue }
                await onLine(decoded)
            }
        } catch {
            if !Task.isCancelled { print("MacKit: media stream interrupted; recovery will refresh its snapshot.") }
        }
    }
    func close() {
        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
    }
}

private actor SystemMediaSnapshotReader {
    func setShuffle(_ mode: Int) -> Bool {
        guard let resources = Bundle.main.resourceURL else { return false }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = [resources.appendingPathComponent("mediaremote-adapter.pl").path, resources.appendingPathComponent("MediaRemoteAdapter.framework").path, "shuffle", String(mode)]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do { try child.run() } catch { return false }
        let timeout = DispatchWorkItem { if child.isRunning { child.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3, execute: timeout)
        child.waitUntilExit(); timeout.cancel()
        return child.terminationStatus == 0
    }
    func read() -> NowPlayingPayload? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = [resources.appendingPathComponent("mediaremote-adapter.pl").path,
                           resources.appendingPathComponent("MediaRemoteAdapter.framework").path, "get"]
        let output = Pipe()
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        do { try child.run() } catch { return nil }
        try? output.fileHandleForWriting.close()
        let deadline = DispatchWorkItem { if child.isRunning { child.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3, execute: deadline)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        child.waitUntilExit()
        deadline.cancel()
        guard child.terminationStatus == 0 else { return nil }
        return try? JSONDecoder().decode(NowPlayingPayload.self, from: data)
    }
}
