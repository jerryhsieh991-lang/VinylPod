import Foundation
import AppKit

/// OPTIONAL, best-effort native "Now Playing" capture for desktop apps
/// (Spotify.app / Music.app) via the PRIVATE `MediaRemote` framework.
///
/// This adapter is deliberately defensive:
///   * All MediaRemote entry points are resolved at runtime via `dlopen` /
///     `dlsym` of `/System/Library/PrivateFrameworks/MediaRemote.framework`.
///     Nothing links against the private framework, so the app still loads
///     even when the framework or its symbols are absent.
///   * On recent macOS (15.4 "Sequoia" and later) `MRMediaRemoteGetNowPlayingInfo`
///     is entitlement-gated and typically returns an EMPTY dictionary to
///     third-party unsigned apps. When that happens this adapter simply never
///     reports data — it logs a single diagnostic line and no-ops forever. It
///     must never crash the host app.
///   * Updates are pushed to `onUpdate` on the **main queue** at **≤ 1 Hz**.
///     There is no always-on high-frequency loop: we listen for MediaRemote's
///     own "now playing changed" notifications and, in addition, poll at a slow
///     1 s cadence purely to advance the elapsed position. The callback only
///     fires when something actually changed (or ~1×/sec while playing to keep
///     elapsed fresh) — never faster.
///
/// The browser bridge remains the DEFAULT capture path; this only supplements
/// it when the user opts in via `AppSettings.nativeCaptureEnabled`.
@MainActor
final class NativeMediaRemoteCapture {

    /// A single now-playing snapshot delivered on the main queue.
    struct Snapshot: Equatable {
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
        var elapsed: TimeInterval
        var isPlaying: Bool
        /// Bundle identifier of the app that owns the now-playing session, when
        /// determinable (e.g. "com.spotify.client", "com.apple.Music").
        var bundleIdentifier: String?
    }

    /// Fired on the main queue at ≤ 1 Hz, only on a real change.
    var onUpdate: ((Snapshot) -> Void)?

    /// True after `start()` if MediaRemote symbols were resolved AND at least
    /// one non-empty now-playing dictionary was observed. The settings UI shows
    /// this as a "MediaRemote returned data" indicator.
    private(set) var didReceiveData: Bool = false

    /// Whether the private framework + required symbols were resolvable at all.
    private(set) var isAvailable: Bool = false

    private var isRunning = false
    private var pollTimer: Timer?
    private var lastSnapshot: Snapshot?
    /// Wall-clock instant at which the last elapsed value was sampled, used to
    /// extrapolate elapsed between the slow polls without hammering MediaRemote.
    private var lastElapsedSampleDate: Date?

    // MARK: - Resolved private symbols

    // MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t, void(^)(CFDictionaryRef))
    private typealias GetNowPlayingInfo =
        @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    // MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_queue_t, void(^)(Bool))
    private typealias GetIsPlaying =
        @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    // MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_queue_t)
    private typealias RegisterForNotifications =
        @convention(c) (DispatchQueue) -> Void

    private var frameworkHandle: UnsafeMutableRawPointer?
    private var getNowPlayingInfo: GetNowPlayingInfo?
    private var getIsPlaying: GetIsPlaying?
    private var registerForNotifications: RegisterForNotifications?

    private static var loggedUnavailable = false

    // MediaRemote CFDictionary keys (string constants exported by the framework,
    // hard-coded here so we don't need to dlsym every key symbol).
    private enum Key {
        static let title    = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist   = "kMRMediaRemoteNowPlayingInfoArtist"
        static let album    = "kMRMediaRemoteNowPlayingInfoAlbum"
        static let duration = "kMRMediaRemoteNowPlayingInfoDuration"
        static let elapsed  = "kMRMediaRemoteNowPlayingInfoElapsedTime"
        static let rate     = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    }

    private static let nowPlayingDidChange =
        Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
    private static let isPlayingDidChange =
        Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")

    init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        resolveSymbolsIfNeeded()
        guard isAvailable else {
            Self.logUnavailableOnce("MediaRemote unavailable — native capture is a no-op.")
            return
        }
        isRunning = true

        // Ask MediaRemote to start posting change notifications; harmless if it
        // silently does nothing under the entitlement gate.
        registerForNotifications?(DispatchQueue.main)

        NotificationCenter.default.addObserver(
            self, selector: #selector(mediaRemoteChanged),
            name: Self.nowPlayingDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(mediaRemoteChanged),
            name: Self.isPlayingDidChange, object: nil)

        // Slow 1 Hz poll: advances elapsed and catches apps that don't post
        // notifications. This is the ONLY timer and it is intentionally 1 s.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollOnce() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        pollOnce()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        pollTimer?.invalidate()
        pollTimer = nil
        NotificationCenter.default.removeObserver(self, name: Self.nowPlayingDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: Self.isPlayingDidChange, object: nil)
        lastSnapshot = nil
        lastElapsedSampleDate = nil
    }

    deinit {
        // NotificationCenter observers are auto-removed on modern OSes, but be
        // explicit. Cannot touch @MainActor timer here; stop() should be called.
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Symbol resolution

    private func resolveSymbolsIfNeeded() {
        guard frameworkHandle == nil else { return }
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            isAvailable = false
            return
        }
        frameworkHandle = handle

        func sym<T>(_ name: String, as _: T.Type) -> T? {
            guard let raw = dlsym(handle, name) else { return nil }
            return unsafeBitCast(raw, to: T.self)
        }

        getNowPlayingInfo = sym("MRMediaRemoteGetNowPlayingInfo", as: GetNowPlayingInfo.self)
        getIsPlaying = sym("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlaying.self)
        registerForNotifications = sym("MRMediaRemoteRegisterForNowPlayingNotifications",
                                       as: RegisterForNotifications.self)

        // We only strictly require the info getter; the others are optional.
        isAvailable = (getNowPlayingInfo != nil)
    }

    // MARK: - Polling / notifications

    @objc private func mediaRemoteChanged() {
        Task { @MainActor in self.pollOnce() }
    }

    /// Read the current now-playing info once. Called at ≤ 1 Hz (timer) plus on
    /// change notifications. Never spins.
    private func pollOnce() {
        guard isRunning, let getInfo = getNowPlayingInfo else { return }
        getInfo(DispatchQueue.main) { [weak self] info in
            // Already on main via the DispatchQueue.main we passed in.
            guard let self else { return }
            self.handleInfo(info)
        }
    }

    private func handleInfo(_ info: [String: Any]) {
        guard isRunning else { return }
        guard !info.isEmpty else {
            // Empty dict is the entitlement-gate signature on macOS 15.4+.
            return
        }

        let title  = (info[Key.title]  as? String) ?? ""
        let artist = (info[Key.artist] as? String) ?? ""
        let album  = (info[Key.album]  as? String) ?? ""
        let duration = (info[Key.duration] as? NSNumber)?.doubleValue ?? 0
        var elapsed  = (info[Key.elapsed]  as? NSNumber)?.doubleValue ?? 0
        let rate     = (info[Key.rate]     as? NSNumber)?.doubleValue ?? 0

        // Nothing meaningful to report.
        if title.isEmpty && artist.isEmpty && album.isEmpty { return }

        didReceiveData = true

        // Determine playing state: prefer the async is-playing query; fall back
        // to playback rate. To keep things ≤ 1 Hz and avoid extra callbacks, we
        // use the rate synchronously and let the is-playing notification correct
        // us on the next tick.
        let playing = rate > 0.0

        // Extrapolate elapsed forward from the last sample so the position keeps
        // moving smoothly between the 1 s polls, without asking MediaRemote more
        // often. We still cap growth to duration.
        if playing, let last = lastSnapshot, let sampledAt = lastElapsedSampleDate,
           abs(elapsed - last.elapsed) < 0.001 {
            // MediaRemote returned the same elapsed it gave last time; advance it
            // by the real time delta so the UI doesn't stall.
            elapsed = min(last.elapsed + Date().timeIntervalSince(sampledAt),
                          duration > 0 ? duration : .greatestFiniteMagnitude)
        }
        lastElapsedSampleDate = Date()

        let bundleID = frontmostMediaBundleIdentifier()

        let snapshot = Snapshot(
            title: title, artist: artist, album: album,
            duration: duration, elapsed: elapsed,
            isPlaying: playing, bundleIdentifier: bundleID)

        // Only emit on a REAL change (ignoring elapsed drift smaller than ~0.75s
        // so we don't fire more than needed). This preserves the perf invariant:
        // state is only mutated downstream when something changed.
        if let prev = lastSnapshot, !meaningfullyDifferent(prev, snapshot) {
            return
        }
        lastSnapshot = snapshot
        onUpdate?(snapshot)
    }

    /// Treat two snapshots as different when metadata/playing changed, or when
    /// elapsed moved by ≥ ~0.75s (roughly one 1 Hz tick). Prevents redundant
    /// downstream writes for sub-second jitter.
    private func meaningfullyDifferent(_ a: Snapshot, _ b: Snapshot) -> Bool {
        if a.title != b.title || a.artist != b.artist || a.album != b.album { return true }
        if a.isPlaying != b.isPlaying { return true }
        if abs(a.duration - b.duration) > 0.5 { return true }
        if abs(a.elapsed - b.elapsed) >= 0.75 { return true }
        return false
    }

    /// Best-effort guess of which media app owns the session. MediaRemote does
    /// expose the origin via a private "now playing client" API, but that is
    /// even more heavily gated; instead we inspect running apps and prefer a
    /// frontmost / active media player, defaulting to Spotify.
    private func frontmostMediaBundleIdentifier() -> String? {
        let running = NSWorkspace.shared.runningApplications
        let spotify = running.first { $0.bundleIdentifier == "com.spotify.client" }
        let music   = running.first { $0.bundleIdentifier == "com.apple.Music" }
        // Prefer whichever is frontmost if either is; else Spotify if running;
        // else Music if running; else nil.
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           front == "com.spotify.client" || front == "com.apple.Music" {
            return front
        }
        if spotify != nil { return "com.spotify.client" }
        if music != nil { return "com.apple.Music" }
        return nil
    }

    // MARK: - Logging

    private static func logUnavailableOnce(_ message: String) {
        guard !loggedUnavailable else { return }
        loggedUnavailable = true
        NSLog("[VinylPod] NativeMediaRemoteCapture: \(message)")
    }
}
