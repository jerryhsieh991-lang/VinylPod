import SwiftUI

// MARK: - Off-main matching engine

/// Owns the parsed timeline and answers "which line is active at time t?"
/// off the main actor. Being an `actor`, all parsing and binary-search work
/// runs on the cooperative pool — the main actor only ever receives tiny
/// `Sendable` results (`LyricsTimeline.Cue`, `[LyricLine]`).
actor LyricsEngine {
    private var timeline: LyricsTimeline = .empty

    /// Parse (off-main) and retain the timeline; returns the sorted lines
    /// once so the view can lay them out. Passing nil/empty clears state.
    func load(lrc: String?) -> [LyricLine] {
        timeline = lrc.map(LRCParser.parse) ?? .empty
        return timeline.lines
    }

    func cue(at position: TimeInterval) -> LyricsTimeline.Cue {
        timeline.cue(at: position)
    }
}

// MARK: - Main-actor sync model

/// Bridges the ~10 Hz playback-position stream to the UI while keeping
/// re-renders to the bare minimum:
///
///  * Steady state — the current `Cue`'s validity window covers the incoming
///    position: one range check, no actor hop, no publish, no render.
///  * Line boundary or seek (any direction) — one hop to `LyricsEngine`,
///    and `activeIndex` publishes only if the index actually changed.
///
/// Lifetime safety: the only unstructured `Task` is the µs-scale engine hop,
/// guarded by `resolveInFlight` (never more than one) and `[weak self]`
/// (never outlives the model). Parsing runs inside the view's `.task(id:)`,
/// so it is cancelled/restarted by SwiftUI when the track changes.
@MainActor
final class LiveLyricsModel: ObservableObject {

    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var activeIndex: Int? = nil

    private let engine = LyricsEngine()
    private var currentCue: LyricsTimeline.Cue? = nil
    private var resolveInFlight = false

    /// Structured entry point — called from the view's `.task(id: lrcText)`.
    func load(lrc: String?) async {
        currentCue = nil
        activeIndex = nil
        lines = await engine.load(lrc: lrc)
    }

    /// Called on every position tick (from `.onReceive`). Cheap by design.
    func positionChanged(_ position: TimeInterval) {
        guard !lines.isEmpty else { return }
        if let cue = currentCue, cue.covers(position) { return }   // steady state
        guard !resolveInFlight else { return }                     // coalesce bursts
        resolveInFlight = true
        Task { [weak self] in
            guard let self else { return }
            let cue = await self.engine.cue(at: position)
            self.apply(cue)
        }
    }

    private func apply(_ cue: LyricsTimeline.Cue) {
        resolveInFlight = false
        currentCue = cue
        if activeIndex != cue.activeIndex {   // publish only on real changes
            activeIndex = cue.activeIndex
        }
    }
}

// MARK: - Lyrics view

/// Vertically auto-scrolling synced lyrics with faded edges. The active line
/// glows with the adaptive artwork accent; neighbors dim progressively.
///
/// Fully reactive: watches `NowPlayingService.track`, fetches LRC text via
/// the injected `LyricsProviding`, parses off-main, and animates in sync
/// with playback. Drop-in usage inside any widget:
///     LiveLyricsScrollView()
/// It reads `NowPlayingService` / `AppSettings` from the environment like the
/// other widget views, so no extra wiring is needed at the call site.
struct LiveLyricsScrollView: View {

    /// Lyrics source. Defaults to the shared LRCLIB provider so all views
    /// reuse one cache; injectable for previews and tests.
    var provider: any LyricsProviding = LRCLibLyricsProvider.shared

    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = LiveLyricsModel()

    /// Where the fetch pipeline currently stands, for placeholder rendering.
    private enum FetchPhase { case idle, loading, ready, unavailable }
    @VPState private var phase: FetchPhase = .idle

    var body: some View {
        Group {
            if model.lines.isEmpty {
                placeholder
            } else {
                lyricsScroller
            }
        }
        // Reactive pipeline, fully structured: SwiftUI cancels + restarts
        // this task whenever the track's text metadata changes, and kills it
        // with the view — no unowned Tasks, no leaks, no stale fetches.
        .task(id: TrackMetadata(track: nowPlaying.track)) {
            await fetchLyrics(for: TrackMetadata(track: nowPlaying.track))
        }
        .onReceive(nowPlaying.$position) { model.positionChanged($0) }
    }

    private func fetchLyrics(for meta: TrackMetadata) async {
        await model.load(lrc: nil)                     // clear previous track's lines
        guard meta.isSearchable else { phase = .idle; return }
        phase = .loading
        do {
            // Debounce: rapid next/next/next skips cancel here before any
            // network round-trip is spent on tracks the user blew past.
            try await Task.sleep(nanoseconds: 250_000_000)
            let lrc = try await provider.fetchLyrics(for: meta)
            await model.load(lrc: lrc)
            model.positionChanged(nowPlaying.position) // sync immediately after load
            phase = .ready
        } catch is CancellationError {
            // Superseded by a newer track — say nothing, the new task owns the UI.
        } catch {
            // notFound, network trouble, bad payload: the widget shows the
            // quiet placeholder either way; detail isn't actionable here.
            if !Task.isCancelled { phase = .unavailable }
        }
    }

    private var lyricsScroller: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    // Top/bottom spacers let the first/last lines center.
                    Color.clear.frame(height: 60)
                    ForEach(model.lines) { line in
                        lineView(line)
                            .id(line.id)
                    }
                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, 18)
            }
            .mask(edgeFade)
            .onChange(of: model.activeIndex) { index in
                guard let index else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: LyricLine) -> some View {
        let isActive = line.id == model.activeIndex
        let accent = settings.accentColor
        let display = line.text.isEmpty ? "♪" : line.text

        Text(display)
            .font(.system(size: isActive ? 17 : 15, weight: isActive ? .bold : .medium, design: .rounded))
            .foregroundStyle(isActive ? VPTheme.textPrimary : VPTheme.textSecondary)
            .opacity(dimming(for: line))
            .scaleEffect(isActive ? 1.0 : 0.97, anchor: .leading)
            // Ambient glow: two stacked accent shadows read as illumination
            // on the frosted glass; zero-radius when inactive so the modifier
            // tree stays stable (no view identity churn while animating).
            .shadow(color: accent.opacity(isActive ? 0.85 : 0), radius: isActive ? 9 : 0)
            .shadow(color: accent.opacity(isActive ? 0.35 : 0), radius: isActive ? 22 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.35), value: model.activeIndex)
    }

    /// Non-active lines fade with distance from the active line.
    private func dimming(for line: LyricLine) -> Double {
        guard let active = model.activeIndex else { return 0.45 }
        switch abs(line.id - active) {
        case 0:  return 1.0
        case 1:  return 0.55
        case 2:  return 0.40
        default: return 0.28
        }
    }

    /// Soft vertical fade so lines melt into the widget edges.
    private var edgeFade: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.14),
                .init(color: .black, location: 0.86),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 6) {
            if case .loading = phase {
                ProgressView()
                    .controlSize(.small)
                Text("Finding lyrics…")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            } else {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 20, weight: .light))
                Text("No synced lyrics")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
        }
        .foregroundStyle(VPTheme.textMuted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
