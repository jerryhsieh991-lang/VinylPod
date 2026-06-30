import SwiftUI
import AppKit

/// The soul of the app: a calm, static landscape that sits behind every mode.
///
/// Resolution order (per the contract + design system §8):
///   1. If `settings.customBackgroundURL` loads as an `NSImage`, show it
///      `.scaledToFill` and clipped.
///   2. Otherwise show the bundled uploaded ice mountain.
///   3. If that image cannot load, render the procedural ice scene.
///
/// In *all* cases a dark `VPTheme.scrim` is overlaid on top so white text and
/// glass panels stay legible regardless of what is behind them. The scene is
/// deliberately motionless — "the landscape is the soul; the UI is a whisper
/// of glass on top of it."
struct LandscapeBackground: View {

    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let palette = settings.albumPalette
        let dominant = palette.dominant.color
        let vibrant = palette.vibrant.color
        let shadow = palette.shadow.color

        ZStack {
            if let url = settings.customBackgroundURL,
               let image = CustomBackgroundCache.image(for: url) {
                // User-supplied image: fill the frame, crop the overflow.
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else if let image = DefaultArtworkAsset.image {
                // Built-in default: the uploaded ice mountain asset.
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                // Final fallback: procedural ice mountain.
                IceMountainScene()
            }

            LinearGradient(
                colors: [
                    vibrant.opacity(0.24),
                    dominant.opacity(0.20),
                    shadow.opacity(0.22)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .blendMode(.overlay)

            RadialGradient(
                colors: [
                    vibrant.opacity(0.24),
                    Color.clear
                ],
                center: UnitPoint(x: 0.26, y: 0.14),
                startRadius: 8,
                endRadius: 220
            )
            .blendMode(.screen)

            // Consistent dark scrim for legibility on ANY background (§9).
            LinearGradient(
                colors: [
                    Color.black.opacity(0.16),
                    Color.black.opacity(0.28),
                    Color.black.opacity(0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        // Never let the background overflow its window; corners are clipped by
        // the host view (ModeContentView) where appropriate.
        .clipped()
        .ignoresSafeArea()
        .animation(VPTheme.liquid, value: settings.albumPalette)
    }
}

// MARK: - Procedural ice mountain

/// A hand-built ice-mountain scene composed of:
///   • a vertical sky gradient (deep midnight blue → cool slate),
///   • a soft radial horizon glow just above the ridgeline,
///   • three layered triangular mountain silhouettes (back→front) in
///     progressively lighter cool tones for aerial-perspective depth,
///   • a faint haze band over the mountains to soften them.
/// Everything is drawn relative to the available size so it scales cleanly
/// from the 180×180 small window up to a full-screen desktop widget.
private struct IceMountainScene: View {

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // The horizon sits a little below center; mountains rise from it.
            let horizon = h * 0.62

            ZStack {
                // 1. Sky — deep midnight blue at the top easing to a cool slate
                //    near the horizon. This is the only large color and it is
                //    fixed: the background NEVER reacts to the track.
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.06, blue: 0.13),   // midnight blue
                        Color(red: 0.09, green: 0.13, blue: 0.22),   // deep slate-blue
                        Color(red: 0.18, green: 0.24, blue: 0.33)    // cool slate at horizon
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // 2. Soft horizon glow — a wide, low-opacity ellipse of cold
                //    light hugging the ridgeline, suggesting a winter dawn.
                RadialGradient(
                    colors: [
                        Color(red: 0.70, green: 0.82, blue: 0.92).opacity(0.30),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.5, y: horizon / h),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.55
                )

                // 3. Layered mountain silhouettes, back to front. Lighter +
                //    cooler in the distance (aerial perspective), darker and
                //    closer in front. Slightly different peak positions give
                //    the ridgeline a natural, asymmetric profile.
                mountain(
                    width: w, baseY: horizon + h * 0.02,
                    peaks: [0.18, 0.46, 0.78], peakHeights: [0.30, 0.46, 0.34],
                    height: h,
                    color: Color(red: 0.40, green: 0.50, blue: 0.62).opacity(0.85)
                )
                mountain(
                    width: w, baseY: horizon + h * 0.06,
                    peaks: [0.30, 0.62, 0.92], peakHeights: [0.40, 0.30, 0.42],
                    height: h,
                    color: Color(red: 0.26, green: 0.34, blue: 0.46).opacity(0.92)
                )
                mountain(
                    width: w, baseY: horizon + h * 0.12,
                    peaks: [0.10, 0.50, 0.86], peakHeights: [0.52, 0.40, 0.30],
                    height: h,
                    color: Color(red: 0.13, green: 0.18, blue: 0.27)
                )

                // 4. Subtle snow/haze — a soft white band fading upward from the
                //    base, like cold mist pooling at the foot of the range.
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.clear
                    ],
                    startPoint: .bottom,
                    endPoint: .center
                )
                .frame(height: h * 0.45)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .blendMode(.softLight)
            }
        }
    }

    /// Builds one triangular mountain range silhouette.
    /// - Parameters:
    ///   - baseY: the y of the range's foot (the flat bottom edge).
    ///   - peaks: normalized x positions (0…1) of each peak.
    ///   - peakHeights: how far each peak rises above `baseY`, as a fraction
    ///     of the total height.
    private func mountain(width: CGFloat,
                          baseY: CGFloat,
                          peaks: [CGFloat],
                          peakHeights: [CGFloat],
                          height: CGFloat,
                          color: Color) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: baseY))
            for (i, px) in peaks.enumerated() {
                let peakX = px * width
                let rise = (peakHeights[safe: i] ?? 0.35) * height
                let peakY = baseY - rise
                // Valley point sits between the previous peak and this one.
                if i > 0 {
                    let prevX = peaks[i - 1] * width
                    let valleyX = (prevX + peakX) / 2
                    path.addLine(to: CGPoint(x: valleyX, y: baseY - rise * 0.25))
                }
                path.addLine(to: CGPoint(x: peakX, y: peakY))
            }
            // Run down to the bottom-right and close the shape.
            path.addLine(to: CGPoint(x: width, y: baseY + height * 0.1))
            path.addLine(to: CGPoint(x: width, y: height))
            path.addLine(to: CGPoint(x: 0, y: height))
            path.closeSubpath()
        }
        .fill(color)
    }
}

private extension Array {
    /// Safe index access used while reading peak heights.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Custom background decode cache

/// Caches the decoded user-supplied background `NSImage` keyed by its URL.
///
/// `LandscapeBackground.body` re-evaluates on every real track change (it reads
/// `settings.albumPalette`). Without this cache, `NSImage(contentsOf:)` would
/// re-read and re-decode the full user image from disk on the main thread on
/// every track change. We hold a single (url, image) pair: stable while the
/// chosen background is unchanged, and refreshed only when the URL changes.
@MainActor
private enum CustomBackgroundCache {
    private static var cachedURL: URL?
    private static var cachedImage: NSImage?

    static func image(for url: URL) -> NSImage? {
        if cachedURL == url { return cachedImage }
        let image = NSImage(contentsOf: url)
        cachedURL = url
        cachedImage = image
        return image
    }
}
