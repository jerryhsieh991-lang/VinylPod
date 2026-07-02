import Foundation

/// One time-synced lyric line. Pure value type — `Sendable` by construction,
/// so it can cross any actor boundary without annotation.
struct LyricLine: Sendable, Equatable, Identifiable, Comparable {
    /// Stable identity for SwiftUI diffing / `scrollTo`. Index-based ids are
    /// assigned by `LyricsTimeline` after sorting, so they survive re-parse
    /// of identical content.
    let id: Int
    /// Absolute position in the track, in seconds, offset-adjusted.
    let time: TimeInterval
    /// The lyric text. May be empty — LRC uses empty timestamped lines to
    /// mark instrumental gaps; the view renders those as "♪".
    let text: String

    static func < (lhs: LyricLine, rhs: LyricLine) -> Bool { lhs.time < rhs.time }
}

/// An immutable, chronologically sorted lyrics document with O(log n) active-
/// line lookup. Value semantics + `Sendable` means the matching logic can run
/// on whatever executor holds the copy (the `LyricsEngine` actor, in practice)
/// with no locking.
struct LyricsTimeline: Sendable, Equatable {
    let lines: [LyricLine]

    static let empty = LyricsTimeline(lines: [])

    var isEmpty: Bool { lines.isEmpty }

    /// What the UI needs for one stretch of playback: the active line index
    /// and the time window for which that index remains valid. The consumer
    /// does ZERO work (no actor hops, no publishes) until playback leaves
    /// `validFrom..<validUntil` — steady-state cost per tick is one range check.
    struct Cue: Sendable, Equatable {
        /// Index into `lines`, or nil before the first timestamp / when empty.
        let activeIndex: Int?
        let validFrom: TimeInterval
        /// `.infinity` after the last line — no further changes will occur.
        let validUntil: TimeInterval

        func covers(_ t: TimeInterval) -> Bool { t >= validFrom && t < validUntil }
    }

    /// Binary-search the active line (last line whose time ≤ `position`).
    /// Handles seeks in both directions — the result depends only on `position`.
    func cue(at position: TimeInterval) -> Cue {
        guard !lines.isEmpty else {
            return Cue(activeIndex: nil, validFrom: 0, validUntil: .infinity)
        }
        // lowerBound: first index whose time is > position.
        var lo = 0, hi = lines.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= position { lo = mid + 1 } else { hi = mid }
        }
        let active = lo - 1   // -1 → before the first line
        return Cue(
            activeIndex: active >= 0 ? active : nil,
            validFrom: active >= 0 ? lines[active].time : 0,
            validUntil: lo < lines.count ? lines[lo].time : .infinity
        )
    }
}
