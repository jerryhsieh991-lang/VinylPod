import Foundation
import Combine
import SwiftUI

/// Observes real track changes from `NowPlayingService` and drives Last.fm
/// scrobbling: a "now playing" push on every new track, and a permanent
/// scrobble once the standard threshold (50% of length OR 4 minutes) is met.
///
/// PERF INVARIANT: this subscribes to `NowPlayingService.$track` ONLY. It never
/// observes `position` (rewritten ~10×/sec) — the scrobble threshold is timed
/// off a wall-clock start timestamp, not off playback position. So no always-on
/// per-tick observer is introduced anywhere.
@MainActor
final class LastFmScrobbler: ObservableObject {

    /// Shared instance the app wires at startup and the settings UI observes.
    static let shared = LastFmScrobbler()

    /// User toggle, persisted. When false the scrobbler does nothing.
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if !enabled { cancelPendingScrobble() }
        }
    }

    private static let enabledKey = "lastfm.scrobblingEnabled"

    private let client: LastFmClient
    private var trackSubscription: AnyCancellable?
    private var attached = false

    /// Dedupe key of the track we last reacted to, so a re-emitted-but-identical
    /// `$track` value never double-fires now-playing / scrobble.
    private var lastHandledKey: String?

    /// The track currently being "counted" toward a scrobble.
    private var pendingItem: LastFmScrobbleItem?
    /// Timer that fires when the scrobble threshold elapses. Not a render loop —
    /// a single one-shot per track, invalidated on the next change.
    private var scrobbleTimer: Timer?

    init(client: LastFmClient = .shared) {
        self.client = client
        self.enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false
    }

    // MARK: - Attachment

    /// Wire the scrobbler to the app's now-playing state. Safe to call exactly
    /// once at app start; repeat calls are ignored.
    func attach(to nowPlaying: NowPlayingService) {
        guard !attached else { return }
        attached = true

        // React to REAL track changes only. `Track` is Equatable on
        // title+artist+album+url+source, and Combine's `.removeDuplicates()`
        // collapses re-emissions — but we still dedupe on artist+title below,
        // because a legitimate album/url tweak shouldn't re-scrobble.
        trackSubscription = nowPlaying.$track
            .removeDuplicates()
            .sink { [weak self] track in
                self?.handleTrackChange(track)
            }
    }

    // MARK: - Track change handling

    private func handleTrackChange(_ track: Track) {
        // Any change ends the previous track's scrobble window.
        cancelPendingScrobble()

        guard enabled, client.isConfigured, client.sessionKey != nil else { return }
        guard !track.isEmpty else { lastHandledKey = nil; return }

        let item = LastFmScrobbleItem(
            artist: track.artist,
            track: track.title,
            album: track.album,
            startedAt: Date(),
            duration: track.duration)

        guard item.isSubmittable else { lastHandledKey = nil; return }

        // Dedupe: identical artist+title as the one we just handled → ignore.
        if item.dedupeKey == lastHandledKey { return }
        lastHandledKey = item.dedupeKey
        pendingItem = item

        // 1) Immediate "now playing" push.
        Task { await client.updateNowPlaying(item) }

        // 2) Schedule the eventual scrobble at the standard threshold:
        //    min(50% of duration, 4 minutes). Tracks shorter than 30s are not
        //    eligible per Last.fm rules; if duration is unknown, use 4 minutes.
        let delay = Self.scrobbleDelay(for: item.duration)
        guard delay > 0 else { return }

        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fireScrobble(for: item) }
        }
        RunLoop.main.add(timer, forMode: .common)
        scrobbleTimer = timer
    }

    /// Standard Last.fm threshold. Returns 0 for ineligible tracks (<30s).
    static func scrobbleDelay(for duration: TimeInterval) -> TimeInterval {
        let fourMinutes: TimeInterval = 240
        if duration <= 0 {
            // Unknown length: fall back to the 4-minute cap.
            return fourMinutes
        }
        if duration < 30 { return 0 }             // too short to scrobble
        return min(duration / 2, fourMinutes)
    }

    private func fireScrobble(for item: LastFmScrobbleItem) {
        // Only scrobble if this is still the track we've been counting.
        guard let pending = pendingItem, pending.dedupeKey == item.dedupeKey else { return }
        guard enabled, client.isConfigured, client.sessionKey != nil else { return }
        pendingItem = nil
        scrobbleTimer = nil
        Task { await client.scrobble(item) }
    }

    private func cancelPendingScrobble() {
        scrobbleTimer?.invalidate()
        scrobbleTimer = nil
        pendingItem = nil
    }
}
