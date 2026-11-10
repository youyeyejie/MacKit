// MacKit lyric lookup, 2026-11-08. GPL-3.0-or-later.
import Foundation

struct LyricsTrack: Hashable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let source: String?
    let identifier: String?
}

actor LyricsProvider {
    static let shared = LyricsProvider()
    private struct Entry {
        let expires: Date
        let lines: [LyricLine]
    }
    private var cache: [LyricsTrack: Entry] = [:]
    private var order: [LyricsTrack] = []
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config)
    }
    func lyrics(for track: LyricsTrack, force: Bool = false) async throws -> [LyricLine] {
        if !force, let entry = cache[track], entry.expires > Date() { return entry.lines }
        var encounteredError: Error?
        // NetEase playback gets its own catalogue first; all playback still comes from Now Playing.
        if track.source == "com.netease.163music" {
            do {
                let value = try await netease(track)
                if !value.isEmpty {
                    store(value, for: track)
                    return value
                }
            } catch { encounteredError = error }
        }
        do {
            let value = try await lrclib(track)
            if !value.isEmpty {
                store(value, for: track)
                return value
            }
        } catch { encounteredError = error }
        if track.source != "com.netease.163music" {
            do {
                let value = try await netease(track)
                if !value.isEmpty {
                    store(value, for: track)
                    return value
                }
            } catch { encounteredError = error }
        }
        do {
            let backup = try await atollBackup(track)
            if !backup.isEmpty {
                store(backup, for: track)
                return backup
            }
        } catch { encounteredError = error }
        if let encounteredError { throw encounteredError }
        store([], for: track)
        return []
    }
    private func store(_ lines: [LyricLine], for track: LyricsTrack) {
        cache[track] = Entry(expires: Date().addingTimeInterval(lines.isEmpty ? 30 : 3600), lines: lines)
        order.removeAll { $0 == track }
        order.append(track)
        while order.count > 80 { cache.removeValue(forKey: order.removeFirst()) }
    }
    private func request(_ url: URL, form: [String: String]? = nil, netease: Bool = false) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MacKit/0.10 (lyrics)", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        if netease {
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        }
        if let form {
            var body = URLComponents()
            body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return Data() }
        guard (200...299).contains(http.statusCode), data.count <= 4_194_304 else { throw URLError(.badServerResponse) }
        return data
    }
    private func url(_ base: String, _ values: [String: String]) -> URL {
        var parts = URLComponents(string: base)!
        parts.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url!
    }
    private func lrclib(_ track: LyricsTrack) async throws -> [LyricLine] {
        var query = ["track_name": track.title]
        if !track.artist.isEmpty { query["artist_name"] = track.artist }
        var data = try await request(url("https://lrclib.net/api/search", query))
        if let rows = try? JSONDecoder().decode([LRCLyrics].self, from: data), rows.isEmpty, !track.artist.isEmpty {
            data = try await request(url("https://lrclib.net/api/search", ["track_name": track.title]))
        }
        guard !data.isEmpty else { return [] }
        let candidates = try JSONDecoder().decode([LRCLyrics].self, from: data)
        let matches = candidates.compactMap { item -> (LRCLyrics, Double)? in
            guard normalized(item.trackName ?? "") == normalized(track.title),
                artistMatches(track.artist, item.artistName ?? "")
            else { return nil }
            if track.duration > 0, let duration = item.duration, abs(duration - track.duration) > 12 { return nil }
            let distance = abs((item.duration ?? track.duration) - track.duration)
            return (item, distance - (normalized(item.albumName ?? "") == normalized(track.album) ? 5 : 0))
        }.sorted { $0.1 < $1.1 }
        for (item, _) in matches {
            let value = item.lines
            if !value.isEmpty { return value }
        }
        return []
    }
    // Adapted from Atoll MusicManager's original LRCLIB lookup and ranking.
    // Keep it as a final fallback for artist spelling/collaboration differences.
    private func atollBackup(_ track: LyricsTrack) async throws -> [LyricLine] {
        let data = try await request(
            url("https://lrclib.net/api/search", ["track_name": track.title, "artist_name": track.artist]))
        guard !data.isEmpty else { return [] }
        let records = try JSONDecoder().decode([LRCLyrics].self, from: data)
        let ranked = records.compactMap { record -> (LRCLyrics, Int)? in
            let title = normalized(track.title)
            let artist = normalized(track.artist)
            let album = normalized(track.album)
            let candidateTitle = normalized(record.trackName ?? "")
            let candidateArtist = normalized(record.artistName ?? "")
            let candidateAlbum = normalized(record.albumName ?? "")
            let titleScore =
                candidateTitle == title
                ? 8 : ((!title.isEmpty && (candidateTitle.contains(title) || title.contains(candidateTitle))) ? 4 : 0)
            let artistScore =
                candidateArtist == artist
                ? 8
                : ((!artist.isEmpty && (candidateArtist.contains(artist) || artist.contains(candidateArtist))) ? 4 : 0)
            guard titleScore > 0, artistScore > 0 else { return nil }
            // Do not use a different recording's timing just because its title ranks well.
            if let duration = record.duration, duration > 0, track.duration > 0,
                abs(duration - track.duration) > max(8, track.duration * 0.05)
            {
                return nil
            }
            let albumScore = !album.isEmpty && candidateAlbum == album ? 4 : 0
            let timedScore = record.syncedLyrics?.isEmpty == false ? 3 : 0
            return (record, titleScore + artistScore + albumScore + timedScore)
        }.sorted { $0.1 > $1.1 }
        return ranked.first?.0.lines ?? []
    }

    private func netease(_ track: LyricsTrack) async throws -> [LyricLine] {
        if let id = Self.neteaseID(track.identifier, source: track.source) {
            let value = try await neteaseLyrics(id)
            if !value.isEmpty { return value }
        }
        let data = try await request(
            URL(string: "https://music.163.com/api/search/get")!,
            form: ["s": track.title + " " + track.artist, "type": "1", "limit": "12", "offset": "0"], netease: true)
        guard !data.isEmpty else { return [] }
        let response = try JSONDecoder().decode(NetSearch.self, from: data)
        guard response.code == 200 else { throw URLError(.badServerResponse) }
        let candidates = (response.result?.songs ?? []).compactMap { song -> (NetSong, Double)? in
            guard normalized(song.name) == normalized(track.title),
                artistMatches(track.artist, song.artists.map(\.name).joined(separator: " / "))
            else { return nil }
            let seconds = (song.duration ?? 0) / 1000
            if seconds > 0, track.duration > 0, abs(seconds - track.duration) > 12 { return nil }
            let distance = abs(seconds - track.duration)
            return (song, distance - (normalized(song.album?.name ?? "") == normalized(track.album) ? 5 : 0))
        }.sorted { $0.1 < $1.1 }
        for (song, _) in candidates.prefix(3) {
            let value = try await neteaseLyrics(String(song.id))
            if !value.isEmpty { return value }
        }
        return []
    }
    private func neteaseLyrics(_ id: String) async throws -> [LyricLine] {
        let data = try await request(
            url("https://music.163.com/api/song/lyric", ["id": id, "lv": "-1", "kv": "-1", "tv": "-1"]), netease: true)
        guard !data.isEmpty else { return [] }
        let result = try JSONDecoder().decode(NetLyrics.self, from: data)
        guard result.code == 200 else { throw URLError(.badServerResponse) }
        guard result.nolyric != true, let text = result.lrc?.lyric else { return [] }
        return Self.parseLRC(text)
    }
    static func neteaseID(_ value: String?, source: String?) -> String? {
        guard let value else { return nil }
        let numeric: (String) -> Bool = { (5...16).contains($0.count) && $0.utf8.allSatisfy { (48...57).contains($0) } }
        if source == "com.netease.163music", numeric(value) { return value }
        guard let parts = URLComponents(string: value), let host = parts.host,
            host == "music.163.com" || host.hasSuffix(".music.163.com") || (parts.scheme == "orpheus" && host == "song")
        else { return nil }
        let pathID = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if parts.scheme == "orpheus", host == "song", numeric(pathID) { return pathID }
        let query = parts.queryItems ?? []
        if let id = query.first(where: { $0.name == "id" })?.value, numeric(id) { return id }
        if let fragment = parts.fragment, let embedded = URLComponents(string: "https://music.163.com/" + fragment),
            let id = embedded.queryItems?.first(where: { $0.name == "id" })?.value, numeric(id)
        {
            return id
        }
        return nil
    }
    private func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .filter { $0.isLetter || $0.isNumber }
    }
    private func artistMatches(_ lhs: String, _ rhs: String) -> Bool {
        let first = normalized(lhs)
        let second = normalized(rhs)
        if first.isEmpty { return true }
        if first == second { return true }
        let separators = CharacterSet(charactersIn: "/&,、;")
        let a = Set(lhs.components(separatedBy: separators).map(normalized).filter { !$0.isEmpty })
        let b = Set(rhs.components(separatedBy: separators).map(normalized).filter { !$0.isEmpty })
        return !a.intersection(b).isEmpty
    }
    static func parseLRC(_ text: String) -> [LyricLine] {
        let expression = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        var lines: [LyricLine] = []
        var offset: Double = 0
        if let regex = try? NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive),
            let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(found.range(at: 1), in: text)
        {
            offset = (Double(text[range]) ?? 0) / 1000
        }
        var seen: Set<String> = []
        for row in text.components(separatedBy: .newlines) {
            let matches = expression.matches(in: row, range: NSRange(row.startIndex..., in: row))
            guard let last = matches.last, let end = Range(last.range, in: row)?.upperBound else { continue }
            let lyric = String(row[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lyric.isEmpty else { continue }
            for match in matches {
                guard let minutes = Range(match.range(at: 1), in: row), let seconds = Range(match.range(at: 2), in: row)
                else { continue }
                let fraction = Range(match.range(at: 3), in: row).map { Double("0." + row[$0]) ?? 0 } ?? 0
                let time = max(0, (Double(row[minutes]) ?? 0) * 60 + (Double(row[seconds]) ?? 0) + fraction - offset)
                if seen.insert("\(time)|\(lyric)").inserted { lines.append(LyricLine(timestamp: time, text: lyric)) }
            }
        }
        return lines.sorted { $0.timestamp < $1.timestamp }
    }
}

private struct LRCLyrics: Decodable {
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let syncedLyrics: String?
    let plainLyrics: String?
    var lines: [LyricLine] {
        if let syncedLyrics {
            let parsed = LyricsProvider.parseLRC(syncedLyrics)
            if !parsed.isEmpty { return parsed }
        }
        if let text = plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return [LyricLine(timestamp: 0, text: text)]
        }
        return []
    }
}
private struct NetSearch: Decodable {
    let code: Int
    let result: Result?
    struct Result: Decodable { let songs: [NetSong]? }
}
private struct NetSong: Decodable {
    let id: Int64
    let name: String
    let duration: Double?
    let artists: [Artist]
    let album: Album?
    struct Artist: Decodable { let name: String }
    struct Album: Decodable { let name: String }
}
private struct NetLyrics: Decodable {
    let code: Int
    let nolyric: Bool?
    let lrc: Line?
    struct Line: Decodable { let lyric: String? }
}
