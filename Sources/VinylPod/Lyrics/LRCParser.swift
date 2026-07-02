import Foundation

/// Stateless LRC (.lrc) parser. A caseless enum with only static pure
/// functions: nonisolated, no shared state, `Sendable` in and out — callable
/// from any concurrency context (the `LyricsEngine` actor calls it off-main).
///
/// Supported input, all defensively tolerated rather than assumed:
///   [mm:ss.xx] text          — standard timestamped line (2- or 3-digit fraction)
///   [mm:ss] text             — fraction omitted
///   [t1][t2] text            — multiple timestamps sharing one text (repeated chorus)
///   [offset:±ms]             — global shift; positive plays lyrics EARLIER (LRC convention)
///   [ti:…] [ar:…] [al:…] …   — metadata tags: ignored
///   malformed lines           — skipped, never fatal
enum LRCParser {

    /// Parse a raw LRC block into a chronologically sorted timeline.
    /// Deterministic and total: any input (including garbage) yields a valid,
    /// possibly empty, timeline.
    static func parse(_ raw: String) -> LyricsTimeline {
        var offsetSeconds: TimeInterval = 0
        var entries: [(time: TimeInterval, text: String)] = []

        // Handles \n, \r\n and classic-Mac \r via whitespacesAndNewlines split.
        raw.enumerateLines { line, _ in
            let (stamps, text, offset) = Self.scanLine(line)
            if let offset { offsetSeconds = offset }
            for t in stamps {
                entries.append((t, text))
            }
        }

        guard !entries.isEmpty else { return .empty }

        // LRC convention: positive offset (ms) means lyrics display earlier,
        // i.e. subtract from every timestamp. Clamp at 0 so a large offset
        // can't produce negative times.
        let adjusted = entries.map { (max(0, $0.time - offsetSeconds), $0.text) }

        // Stable sort keeps same-timestamp lines in file order, then ids are
        // assigned post-sort so they equal the display order.
        let sorted = adjusted.enumerated()
            .sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }
            .map { $0.element }

        let lines = sorted.enumerated().map { idx, entry in
            LyricLine(id: idx, time: entry.0, text: entry.1)
        }
        return LyricsTimeline(lines: lines)
    }

    // MARK: - Line scanning

    /// Extract every leading `[...]` group, classify it, and return the
    /// remaining text. Character-scanning (no regex) — O(n), allocation-light,
    /// and immune to pathological-backtracking inputs.
    private static func scanLine(_ line: String) -> (stamps: [TimeInterval], text: String, offset: TimeInterval?) {
        var stamps: [TimeInterval] = []
        var offset: TimeInterval? = nil
        var rest = Substring(line)

        while rest.first == "[" {
            guard let close = rest.firstIndex(of: "]") else { break }   // unclosed bracket → treat as text
            let tag = rest[rest.index(after: rest.startIndex)..<close]
            rest = rest[rest.index(after: close)...]

            if let t = parseTimestamp(tag) {
                stamps.append(t)
            } else if let ms = parseOffsetTag(tag) {
                offset = ms / 1000.0
            }
            // else: metadata tag ([ti:], [ar:], …) — ignore.
        }

        return (stamps, rest.trimmingCharacters(in: .whitespaces), offset)
    }

    /// `mm:ss`, `mm:ss.x`, `mm:ss.xx`, `mm:ss.xxx`; also tolerates `hh:mm:ss.xx`.
    /// Returns nil for anything that isn't purely a timestamp.
    private static func parseTimestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        var components: [Double] = []
        for (i, part) in parts.enumerated() {
            let isLast = i == parts.count - 1
            // Only the seconds field may carry a fraction.
            guard let value = Double(part), value >= 0,
                  isLast || part.allSatisfy(\.isNumber) else { return nil }
            components.append(value)
        }

        switch components.count {
        case 2:  return components[0] * 60 + components[1]
        case 3:  return components[0] * 3600 + components[1] * 60 + components[2]
        default: return nil
        }
    }

    /// `offset:+500` / `offset:-500` (milliseconds). Case-insensitive key.
    private static func parseOffsetTag(_ tag: Substring) -> Double? {
        guard let colon = tag.firstIndex(of: ":") else { return nil }
        let key = tag[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
        guard key == "offset" else { return nil }
        let value = tag[tag.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return Double(value)
    }
}
