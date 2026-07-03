import Foundation

// MARK: - Last.fm value types
//
// Small, self-contained model layer for the Last.fm scrobbling subsystem.
// Nothing here touches the main-thread render loop — these are plain value
// types moved between the client, the scrobbler, and the settings UI.

/// A single scrobble candidate, derived from a `Track` at the moment it starts
/// playing. Kept independent of the app's `Track` so the scrobbler can hold a
/// pending item without retaining `NSImage` artwork or other UI state.
struct LastFmScrobbleItem: Equatable {
    var artist: String
    var track: String
    var album: String
    /// The wall-clock time (UNIX seconds) at which the user STARTED listening.
    /// Last.fm requires the start timestamp, not the submit time.
    var startedAt: Date
    /// Track length in seconds, if known (0 == unknown).
    var duration: TimeInterval

    /// Last.fm requires a non-empty artist and track to accept a scrobble.
    var isSubmittable: Bool {
        !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !track.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Stable identity used to dedupe "have I already handled this track?".
    /// Case-insensitive on artist+title so trivial re-pushes don't re-scrobble.
    var dedupeKey: String {
        (artist + "\u{1}" + track).lowercased()
    }
}

/// Result of the desktop-auth handshake once the user authorizes in-browser.
struct LastFmSession: Equatable {
    var username: String
    var sessionKey: String
}

/// Connection state surfaced to the settings UI. Deliberately coarse — the UI
/// only needs to know which affordance to show.
enum LastFmConnectionState: Equatable {
    /// API key/secret constants are still the empty-string placeholders.
    case notConfigured
    /// Configured, but no session persisted yet.
    case disconnected
    /// A `auth.getToken` has been fetched and the browser opened; awaiting the
    /// user to click "Complete connection".
    case awaitingAuthorization
    /// Fully connected as `username`.
    case connected(username: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Errors the client can surface. All are non-fatal — callers log and move on.
enum LastFmError: Error, LocalizedError {
    case notConfigured
    case noSession
    case network(String)
    case api(code: Int, message: String)
    case decoding(String)
    case noPendingToken

    var errorDescription: String? {
        switch self {
        case .notConfigured:        return "Last.fm API key/secret not set."
        case .noSession:            return "Not connected to Last.fm."
        case .network(let m):       return "Network error: \(m)"
        case .api(let code, let m): return "Last.fm error \(code): \(m)"
        case .decoding(let m):      return "Response error: \(m)"
        case .noPendingToken:       return "No pending authorization to complete."
        }
    }
}
