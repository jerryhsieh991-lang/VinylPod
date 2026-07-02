import Foundation

/// Deterministic pseudo-beat — the audio-reactive layer's data source, per the
/// 2026-07-02 alignment decision ("節奏模擬"): NO real audio tap. MediaSession /
/// DOM scraping cannot expose live amplitude, so the pulse is synthesized.
///
/// Everything here is a PURE function of (per-track seed, wall-clock date):
/// no timers, no Combine, no `NowPlayingService.$position` reads. Callers
/// sample it inside an EXISTING `TimelineView` frame, so the effect adds zero
/// render clocks and honors the repo's per-tick perf invariant (agents.md).
enum GroovePulse {

    /// Stable per-track seed (FNV-1a over title + artist) — identical across
    /// launches, so a given song always carries the same simulated tempo.
    static func seed(title: String, artist: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(title)\u{1F}\(artist)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// Simulated tempo, 72–132 BPM, picked deterministically per track.
    static func bpm(seed: UInt64) -> Double {
        72.0 + Double(seed % 61)
    }

    /// Beat amplitude in `0...1` at `date`.
    ///
    /// Shape: a hit at each simulated beat that decays smoothly across the
    /// beat (`(1-phase)^2.4`), a stronger accent on every 4th beat (downbeat),
    /// and a slow attenuation swell (×0.70…×1.00, ~9s period) so long
    /// stretches never look mechanical. The product of the three factors is
    /// already ≤ 1; the final `min` is a defensive cap only.
    /// Exactly `0` while paused — idle surfaces must be perfectly still.
    static func amplitude(seed: UInt64, at date: Date, isPlaying: Bool) -> Double {
        guard isPlaying else { return 0 }
        let t = date.timeIntervalSinceReferenceDate
        let beats = t * bpm(seed: seed) / 60.0
        let phase = beats.truncatingRemainder(dividingBy: 1.0)
        let decay = pow(1.0 - phase, 2.4)
        let downbeat = beats.truncatingRemainder(dividingBy: 4.0) < 1.0
        let accent = downbeat ? 1.0 : 0.72
        let swellPhase = t * 0.11 * 2 * .pi + Double(seed % 360) * .pi / 180
        let swell = 0.85 + 0.15 * sin(swellPhase)
        return min(1.0, decay * accent * swell)
    }
}
