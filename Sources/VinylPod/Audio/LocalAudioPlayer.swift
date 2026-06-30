import Foundation
import AVFoundation
import SwiftUI

/// Local-file audio playback backed by `AVAudioPlayer`.
///
/// `AVAudioPlayer` is the simplest fit for finite local files: it exposes
/// `currentTime` and `duration` synchronously, so we can drive a UI progress
/// bar with a lightweight repeating timer rather than KVO/CMTime observers.
///
/// The class is `@MainActor` (the protocol requires it) so all state — the
/// player, the timer, and the closure callbacks — lives on the main actor and
/// needs no extra locking. The one wrinkle is `AVAudioPlayerDelegate`, which
/// AVFoundation calls back on a non-isolated context; we bridge that hop back
/// to the main actor via a small non-isolated `NSObject` helper (see below).
@MainActor
final class LocalAudioPlayer: NSObject, AudioPlaying {

    // MARK: AudioPlaying closures (stored properties from the protocol)

    /// Called ~10×/sec with (currentPosition, duration) while playing.
    var onTick: ((TimeInterval, TimeInterval) -> Void)?
    /// Called once when the current item plays to its end.
    var onFinish: (() -> Void)?

    // MARK: Private state

    private var player: AVAudioPlayer?
    /// Drives `onTick`. Runs only while audio is actively playing; invalidated
    /// on pause/stop so we don't spin the timer (or fire ticks) needlessly.
    private var tickTimer: Timer?
    /// Bridges AVFoundation's non-isolated delegate callback back to us.
    private var delegateBridge: DelegateBridge?

    override init() {
        super.init()
        // Wire the delegate bridge so finish events can hop to the main actor.
        // The bridge is non-isolated; it calls back via a @MainActor closure so
        // we can safely touch our own state when the file finishes.
        let bridge = DelegateBridge { [weak self] in
            // Already on the main actor here (the bridge hops first).
            self?.handleDidFinish()
        }
        self.delegateBridge = bridge
    }

    deinit {
        // If we're torn down mid-playback the tick timer is still scheduled on
        // RunLoop.main, which retains it — its `[weak self]` closure would then
        // fire forever as a no-op instead of stopping. Invalidate it directly.
        // (We can't call the @MainActor `stopTimer()` from a non-isolated deinit;
        // invalidating the Timer reference is sufficient and thread-safe here.)
        tickTimer?.invalidate()
    }

    // MARK: AudioPlaying

    /// Decode `url` and arm the player without starting playback.
    /// Replaces any previous item; the caller follows with `play()`.
    func load(_ url: URL) {
        stopTimer()
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = delegateBridge
            newPlayer.prepareToPlay()   // pre-buffer so play() starts instantly
            player = newPlayer
            // Emit an immediate tick so the UI shows 0 / duration before play.
            onTick?(0, newPlayer.duration)
        } catch {
            // Unreadable / unsupported file: tear down so we don't play stale audio.
            player = nil
            onTick?(0, 0)
        }
    }

    func play() {
        guard let player else { return }
        player.play()
        startTimer()
    }

    func pause() {
        player?.pause()
        stopTimer()   // freeze the progress display; position is preserved.
    }

    func stop() {
        player?.stop()
        // AVAudioPlayer.stop() leaves currentTime where it was; rewind so a
        // subsequent play() restarts from the top, matching "stop" semantics.
        player?.currentTime = 0
        stopTimer()
        onTick?(0, player?.duration ?? 0)
    }

    /// Seek to an absolute position in seconds, clamped to the file length.
    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(seconds, player.duration))
        player.currentTime = clamped
        onTick?(clamped, player.duration)
    }

    // MARK: Tick timer

    private func startTimer() {
        stopTimer()
        // ~10 Hz progress updates. The closure is @MainActor (the class is),
        // so reading player state and calling onTick is isolation-safe.
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop; hop to the actor explicitly to
            // satisfy Swift 6 isolation checking.
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        // Keep ticking during scroll/tracking run-loop modes.
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard let player else { return }
        onTick?(player.currentTime, player.duration)
    }

    // MARK: Finish handling

    /// Invoked (on the main actor) when the delegate bridge reports completion.
    private func handleDidFinish() {
        stopTimer()
        onFinish?()
    }

    // MARK: - Delegate bridge

    /// `AVAudioPlayerDelegate` methods are delivered on a non-isolated context,
    /// so the delegate object itself must NOT be `@MainActor`. This tiny,
    /// non-isolated `NSObject` receives the callback and immediately hops onto
    /// the main actor to invoke the owner's handler.
    private final class DelegateBridge: NSObject, AVAudioPlayerDelegate {
        /// `@MainActor`-isolated handler: the bridge hops onto the main actor
        /// before invoking it, so the owner can touch its main-actor state.
        nonisolated(unsafe) private let onFinish: @MainActor () -> Void

        init(onFinish: @escaping @MainActor () -> Void) {
            self.onFinish = onFinish
        }

        nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            let handler = onFinish
            Task { @MainActor in
                handler()
            }
        }
    }
}
