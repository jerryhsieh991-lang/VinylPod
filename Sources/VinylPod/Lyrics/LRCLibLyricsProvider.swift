import Foundation

/// Production lyrics provider backed by LRCLIB (https://lrclib.net) — a free,
/// keyless catalog of time-synced `.lrc` lyrics.
///
/// Strategy, in order:
///   1. In-memory cache (positive AND negative — a miss is also remembered,
///      so skipping back to a lyric-less track never re-queries).
///   2. `GET /api/get` — exact match on title/artist/album/duration.
///   3. `GET /api/search` — fuzzy fallback; accepts the first result whose
///      duration is within ±4 s of ours (when we know our duration).
///
/// Concurrency: a value-type facade over an internal cache `actor`. The
/// struct is `Sendable` by construction — no `@unchecked` anywhere. Network
/// calls run on URLSession's own pool; cancellation (rapid track skips)
/// propagates out of `URLSession.data` as usual.
struct LRCLibLyricsProvider: LyricsProviding {

    /// Shared instance so every view init reuses one cache. (A fresh
    /// provider per SwiftUI view init would silently defeat caching.)
    static let shared = LRCLibLyricsProvider()

    private let session: URLSession
    private let baseURL: URL
    private let cache = Cache()

    /// Injectable for tests (stub `URLProtocol`) or a self-hosted LRCLIB.
    init(session: URLSession = .shared,
         baseURL: URL = URL(string: "https://lrclib.net/api")!) {
        self.session = session
        self.baseURL = baseURL
    }

    // MARK: LyricsProviding

    func fetchLyrics(for track: TrackMetadata) async throws -> String {
        guard track.isSearchable else { throw LyricsProviderError.invalidQuery }

        if let cached = await cache.lookup(track) {
            // Negative hit: known miss, fail fast without touching the network.
            guard let lrc = cached else { throw LyricsProviderError.notFound }
            return lrc
        }

        do {
            // `??` can't await its right-hand side (autoclosure), so chain manually.
            var lrc = try await exactMatch(track)
            if lrc == nil { lrc = try await searchFallback(track) }
            guard let lrc, !lrc.isEmpty else {
                await cache.store(track, lyrics: nil)
                throw LyricsProviderError.notFound
            }
            await cache.store(track, lyrics: lrc)
            return lrc
        } catch let error as LyricsProviderError {
            if case .notFound = error { await cache.store(track, lyrics: nil) }
            throw error
        }
        // CancellationError / URLError deliberately NOT cached: transient.
    }

    // MARK: - Endpoints

    /// `GET /api/get` — returns nil on a clean 404 (i.e. "not in catalog"),
    /// so the caller can fall through to search.
    private func exactMatch(_ track: TrackMetadata) async throws -> String? {
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        if !track.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: track.album))
        }
        if track.duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))))
        }

        let (data, status) = try await get(path: "get", query: items)
        switch status {
        case 200:
            let record = try decode(LRCLibRecord.self, from: data)
            return record.syncedLyrics.flatMap { $0.isEmpty ? nil : $0 }
        case 404:
            return nil
        default:
            throw LyricsProviderError.badResponse(statusCode: status)
        }
    }

    /// `GET /api/search` — fuzzy; guard against wrong-song matches by
    /// requiring a duration within ±4 s when we know our own.
    private func searchFallback(_ track: TrackMetadata) async throws -> String? {
        var items = [URLQueryItem(name: "track_name", value: track.title)]
        if !track.artist.isEmpty {
            items.append(URLQueryItem(name: "artist_name", value: track.artist))
        }

        let (data, status) = try await get(path: "search", query: items)
        guard status == 200 else { throw LyricsProviderError.badResponse(statusCode: status) }

        let records = try decode([LRCLibRecord].self, from: data)
        return records.first { record in
            guard let lrc = record.syncedLyrics, !lrc.isEmpty else { return false }
            guard track.duration > 0, let candidate = record.duration else { return true }
            return abs(candidate - track.duration) <= 4
        }?.syncedLyrics
    }

    // MARK: - Plumbing

    private func get(path: String, query: [URLQueryItem]) async throws -> (Data, Int) {
        var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = query
        guard let url = components.url else { throw LyricsProviderError.invalidQuery }

        var request = URLRequest(url: url, timeoutInterval: 10)
        // LRCLIB asks clients to identify themselves.
        request.setValue("VinylPod/1.0 (macOS widget)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (data, status)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw LyricsProviderError.malformedPayload }
    }

    /// Subset of LRCLIB's record we care about.
    private struct LRCLibRecord: Decodable {
        let syncedLyrics: String?
        let duration: TimeInterval?
    }

    // MARK: - Cache

    /// Tiny bounded memory cache. `nil` value = negative entry (known miss).
    /// Wholesale eviction at the cap is deliberate: at ≤128 entries there is
    /// nothing meaningful to rank, and it keeps the actor trivially correct.
    private actor Cache {
        private var store: [TrackMetadata: String?] = [:]
        private let capacity = 128

        func lookup(_ key: TrackMetadata) -> String?? { store[key] }

        func store(_ key: TrackMetadata, lyrics: String?) {
            if store.count >= capacity { store.removeAll(keepingCapacity: true) }
            store[key] = lyrics
        }
    }
}
