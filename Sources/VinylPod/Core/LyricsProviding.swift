import Foundation

// MARK: - Lyrics provider seam (Core layer)

/// A text-only, `Sendable` snapshot of the currently playing track — the
/// query key for lyrics lookups. `Track` itself cannot cross actor
/// boundaries (it carries an `NSImage`), so providers receive this instead.
struct TrackMetadata: Sendable, Equatable, Hashable {
    var title: String
    var artist: String
    var album: String
    /// Seconds; 0 when the source didn't report one.
    var duration: TimeInterval

    init(title: String = "", artist: String = "", album: String = "", duration: TimeInterval = 0) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    init(track: Track) {
        self.init(title: track.title, artist: track.artist,
                  album: track.album, duration: track.duration)
    }

    /// A lookup needs at least a title; artist-less queries are allowed but
    /// title-less ones can only return junk.
    var isSearchable: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// Anything that can produce a raw LRC block for a track.
/// `Sendable` so implementations can be handed to views, actors, and tasks
/// freely under strict concurrency.
protocol LyricsProviding: Sendable {
    /// Returns the raw `.lrc` text for the track.
    /// Throws `LyricsProviderError.notFound` when the catalog has no synced
    /// lyrics; throws `CancellationError` if the surrounding task is
    /// cancelled (rapid track skips) — callers should treat that as silence,
    /// not failure.
    func fetchLyrics(for track: TrackMetadata) async throws -> String
}

/// Failure modes a provider can report. Deliberately small: the UI only
/// distinguishes "nothing to show" from "try again later".
enum LyricsProviderError: Error, Equatable {
    /// The track is missing the fields needed to query (e.g. no title).
    case invalidQuery
    /// The service answered but has no synced lyrics for this track.
    case notFound
    /// Unexpected HTTP status.
    case badResponse(statusCode: Int)
    /// The service answered 200 with a body we couldn't decode.
    case malformedPayload
}
