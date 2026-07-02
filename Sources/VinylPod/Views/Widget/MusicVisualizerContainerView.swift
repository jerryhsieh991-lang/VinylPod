import SwiftUI
import AppKit

// MARK: - Container

/// The single artwork/visualizer surface for every widget size. Switches
/// reactively on `AppSettings.vinylStyle` — pick a new style in the settings
/// dropdown and the running widget re-renders in place, no restart.
///
/// Chrome contract (matches the pre-rewrite call sites): card-like styles
/// (`.image`, `.cassette`) are clipped to `cornerRadius` here, and the CALL
/// SITE applies its own bevel/shadow when `!style.rendersOwnEdge`. Edge-drawing
/// styles (`.vinyl`, `.liquidDisc`) manage their own silhouette.
///
/// CLT note: uses `@VPState` (typealias to `SwiftUI.State`) per the project's
/// toolchain rule — `@State`'s macro plugin is unavailable under Command Line
/// Tools.
@MainActor
struct MusicVisualizerContainerView: View {

    /// The current track's artwork; nil renders each style's placeholder.
    let artwork: NSImage?
    /// Corner radius for the card-like styles (`.image`, `.cassette`).
    var cornerRadius: CGFloat = 5
    /// Playback state + track identity arrive as PLAIN VALUES instead of a
    /// whole-object `NowPlayingService` observation: the service republishes
    /// `position` on every tick, and an `@EnvironmentObject` here would
    /// re-evaluate this body once per tick for data it never reads. The parent
    /// widgets already observe the service — they hand down only these three.
    var isPlaying: Bool = false
    var trackTitle: String = ""
    var trackArtist: String = ""

    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        // Exhaustive on purpose: a future style must be handled here, not
        // silently swallowed by a `default`.
        switch settings.vinylStyle {
        case .vinyl:
            VinylDiskView(artwork: artwork,
                          isSpinning: isPlaying,
                          beatSeed: beatSeed)

        case .image:
            flatCard

        case .cassette:
            CassetteDeckView(artwork: artwork, isPlaying: isPlaying)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

        case .liquidDisc:
            LiquidDiscView(artwork: artwork,
                           isPlaying: isPlaying,
                           beatSeed: beatSeed,
                           paletteKey: paletteKey)
        }
    }

    /// Per-track pulse seed so the vinyl grooves and the liquid disc agree on
    /// the same simulated tempo for the same song.
    private var beatSeed: UInt64 {
        GroovePulse.seed(title: trackTitle, artist: trackArtist)
    }

    /// CONTENT-based identity for palette extraction — never pointer identity
    /// (`ObjectIdentifier` can collide when a deallocated image's address is
    /// reused, and re-runs needlessly for equal content). Includes the pixel
    /// size so the high-res artwork upgrade for the SAME track re-extracts.
    private var paletteKey: String {
        let dims = artwork.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "none"
        return "\(trackTitle)\u{1F}\(trackArtist)\u{1F}\(dims)"
    }

    /// The legacy flat album-art card (previous `.image` branch, verbatim).
    @ViewBuilder
    private var flatCard: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(VPTheme.scrimStrong)
                    .overlay(SmallWidgetDefaultArtwork())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Async palette extraction

/// Fully asynchronous, nonisolated artwork-palette extraction.
///
/// The static functions are nonisolated `async`, so they execute on the
/// concurrent executor — the CoreImage sampling never runs on (or blocks) the
/// main actor. `AlbumColorPalette` and `RGBColorToken` are `Sendable` value
/// types, so the result is a disconnected value that crosses back to the
/// `@MainActor` caller without any `nonisolated(unsafe)` / `@unchecked` help.
enum AsyncArtworkPalette {

    /// Extract the full four-color palette off the main actor.
    ///
    /// Takes a `Data` snapshot (e.g. `tiffRepresentation`) rather than the
    /// `NSImage` itself: `NSImage` is a non-Sendable reference type the main
    /// actor keeps drawing with, so it must never cross the actor boundary.
    /// The `NSImage` decoded here is task-local and never escapes.
    static func palette(fromArtworkData data: Data) async -> AlbumColorPalette? {
        guard let image = NSImage(data: data) else { return nil }
        return ArtworkColorExtractor.paletteOffMain(from: image)
    }

    /// Primary/secondary/tertiary colors for ambient rendering, ordered
    /// strongest-first. Falls back to the built-in palette when the artwork
    /// data yields nothing usable.
    static func liquidColors(fromArtworkData data: Data) async -> [RGBColorToken] {
        let palette = await Self.palette(fromArtworkData: data) ?? .iceMountain
        return [palette.vibrant, palette.dominant, palette.muted]
    }
}

// MARK: - Cassette deck (.cassette)

/// A vintage cassette shell with two gear hubs. Both hubs derive their angle
/// from the SAME `TimelineView` date and the same accumulated phase, so they
/// are synchronized by construction — there is no per-hub timer to drift.
///
/// Pause/resume preserves the angle (the `accumulatedAngle` pattern from
/// `VinylDiskView`) so the reels never jump.
@MainActor
private struct CassetteDeckView: View {

    let artwork: NSImage?
    var isPlaying: Bool

    /// Seconds per full hub revolution — slow, tape-deck calm.
    private let secondsPerRev: Double = 2.4

    @VPState private var accumulatedAngle: Double = 0
    @VPState private var spinStart: Date = Date()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                shell

                VStack(spacing: h * 0.04) {
                    labelStrip(width: w, height: h * 0.30)

                    // Reel window: two synced hubs behind a smoked cutout.
                    ZStack {
                        RoundedRectangle(cornerRadius: h * 0.10, style: .continuous)
                            .fill(Color.black.opacity(0.55))
                            .overlay(
                                RoundedRectangle(cornerRadius: h * 0.10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                            )

                        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { ctx in
                            let elapsed = isPlaying ? ctx.date.timeIntervalSince(spinStart) : 0
                            let angle = (accumulatedAngle + elapsed / secondsPerRev * 360.0)
                                .truncatingRemainder(dividingBy: 360.0)
                            HStack(spacing: w * 0.16) {
                                hub(diameter: h * 0.26, angle: angle)
                                hub(diameter: h * 0.26, angle: angle)
                            }
                        }
                    }
                    .frame(height: h * 0.38)
                    .padding(.horizontal, w * 0.14)
                }
                .padding(.vertical, h * 0.08)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: isPlaying) { now in
            if now {
                spinStart = Date()
            } else {
                let elapsed = Date().timeIntervalSince(spinStart)
                accumulatedAngle = (accumulatedAngle + elapsed / secondsPerRev * 360.0)
                    .truncatingRemainder(dividingBy: 360.0)
            }
        }
        .onAppear { if isPlaying { spinStart = Date() } }
        .allowsHitTesting(false)
    }

    // MARK: Shell + label

    private var shell: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.16), Color(white: 0.09)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            )
    }

    /// The paper label across the cassette's top, showing the artwork if any.
    private func labelStrip(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(white: 0.88))
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "music.note")
                        Rectangle().frame(height: 1).opacity(0.25)
                    }
                    .font(.system(size: height * 0.32, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .padding(.horizontal, 8)
                }
            }
            .frame(height: height - 6)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .padding(3)
        }
        .frame(height: height)
        .padding(.horizontal, width * 0.10)
    }

    // MARK: Gear hub

    /// One toothed hub. Angle comes in from the shared timeline so every hub
    /// on screen renders the identical rotation phase.
    private func hub(diameter: CGFloat, angle: Double) -> some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.22))
            GearHubShape(teeth: 6)
                .fill(Color(white: 0.85), style: FillStyle(eoFill: true))
                .rotationEffect(.degrees(angle))
            Circle()
                .fill(Color(white: 0.10))
                .frame(width: diameter * 0.28, height: diameter * 0.28)
        }
        .frame(width: diameter, height: diameter)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8))
    }
}

/// A cassette-hub gear: a ring with `teeth` inward notches, drawn as one path
/// so it can be filled and rotated as a unit.
private struct GearHubShape: Shape {
    var teeth: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.62

        // Ring body.
        path.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer,
                                   width: outer * 2, height: outer * 2))
        path.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner,
                                   width: inner * 2, height: inner * 2))

        // Teeth: small radial bars bridging the ring toward the spindle.
        let toothWidth = outer * 0.16
        for i in 0..<max(teeth, 3) {
            let theta = Double(i) / Double(max(teeth, 3)) * 2 * .pi
            let dir = CGPoint(x: cos(theta), y: sin(theta))
            let from = CGPoint(x: center.x + dir.x * inner * 0.55,
                               y: center.y + dir.y * inner * 0.55)
            let to = CGPoint(x: center.x + dir.x * inner,
                             y: center.y + dir.y * inner)
            let barRect = CGRect(x: min(from.x, to.x) - toothWidth / 2,
                                 y: min(from.y, to.y) - toothWidth / 2,
                                 width: abs(to.x - from.x) + toothWidth,
                                 height: abs(to.y - from.y) + toothWidth)
            path.addRoundedRect(in: barRect, cornerSize: CGSize(width: toothWidth / 3,
                                                                height: toothWidth / 3))
        }
        // Rendered with `FillStyle(eoFill: true)` — the inner ellipse punches
        // the ring hole and the teeth re-fill their bars by parity.
        // (`Path.normalized(eoFill:)` would bake this in, but it's macOS 14+.)
        return path
    }
}

// MARK: - Liquid disc (.liquidDisc)

/// Boundary-less ambient disc: three soft radial blobs, tinted by the current
/// artwork's palette, slowly orbiting while playback is active. The heavy
/// palette extraction is fully async and off-main (`AsyncArtworkPalette`);
/// this view only ever receives the finished `Sendable` tokens.
///
/// Perf: one 30fps `TimelineView` (paused while idle), one `Canvas`, one blur.
@MainActor
private struct LiquidDiscView: View {

    let artwork: NSImage?
    var isPlaying: Bool
    /// Per-track seed for the simulated beat swell (`GroovePulse`).
    var beatSeed: UInt64 = 0
    /// Content-based identity of (track, artwork) — drives re-extraction.
    var paletteKey: String = ""

    @EnvironmentObject private var settings: AppSettings

    /// Palette extracted from `artwork`; nil until the async extraction lands
    /// (we render from `settings.albumPalette` in the meantime).
    @VPState private var extracted: [RGBColorToken]? = nil

    /// Seconds per full blob orbit.
    private let secondsPerOrbit: Double = 14.0

    var body: some View {
        // Resolved ONCE per body evaluation, outside the frame closure — the
        // per-frame path below must not allocate or re-read observed state.
        let tokens = colors
        return GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { ctx in
                let phase = ctx.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: secondsPerOrbit) / secondsPerOrbit * 2 * .pi
                // Same frame clock, same pulse as the vinyl grooves.
                let pulse = GroovePulse.amplitude(seed: beatSeed, at: ctx.date, isPlaying: isPlaying)
                canvas(size: size, phase: phase, pulse: pulse, tokens: tokens)
            }
            .frame(width: size, height: size)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        // Re-extract when the CONTENT identity changes; `task(id:)` cancels a
        // stale extraction automatically on a fast track skip. The artwork is
        // snapshotted to Sendable `Data` HERE (on the main actor) so no
        // NSImage crosses the actor boundary.
        .task(id: paletteKey) {
            guard let artwork, let data = artwork.tiffRepresentation else {
                extracted = nil
                return
            }
            extracted = await AsyncArtworkPalette.liquidColors(fromArtworkData: data)
        }
        .allowsHitTesting(false)
    }

    /// Colors to render right now: freshly extracted if ready, else the app's
    /// live album palette, else the built-in fallback.
    private var colors: [RGBColorToken] {
        if let extracted, !extracted.isEmpty { return extracted }
        let p = settings.albumPalette
        return [p.vibrant, p.dominant, p.muted]
    }

    private func canvas(size: CGFloat, phase: Double, pulse: Double, tokens: [RGBColorToken]) -> some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            // Beat swell: blobs breathe up to +6% radius on each simulated hit.
            let baseRadius = size * 0.34 * (1.0 + CGFloat(pulse) * 0.06)

            // Soft dark backing so the blobs read on any wallpaper.
            let disc = Path(ellipseIn: CGRect(x: center.x - size * 0.46,
                                              y: center.y - size * 0.46,
                                              width: size * 0.92, height: size * 0.92))
            context.fill(disc, with: .color(.black.opacity(0.30)))

            for (index, token) in tokens.enumerated() {
                let offset = Double(index) * 2 * .pi / Double(tokens.count)
                let orbit = size * 0.13
                let blobCenter = CGPoint(
                    x: center.x + CGFloat(cos(phase + offset)) * orbit,
                    y: center.y + CGFloat(sin(phase + offset)) * orbit
                )
                let radius = baseRadius * (index == 0 ? 1.0 : 0.78)
                let rect = CGRect(x: blobCenter.x - radius, y: blobCenter.y - radius,
                                  width: radius * 2, height: radius * 2)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(colors: [token.color.opacity(0.78), token.color.opacity(0.0)]),
                        center: blobCenter,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
        }
        // Clip to the disc, then blur OUTWARD so the silhouette melts — the
        // "boundary-less" edge. compositingGroup keeps the blur off siblings.
        .clipShape(Circle())
        .compositingGroup()
        .blur(radius: size * 0.03)
    }
}
