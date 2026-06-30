import SwiftUI

/// Album-reactive frosted glass used by the floating widgets.
///
/// Design intent (design_system.md §4): *"Panels float as light, translucent
/// layers — never opaque solid blocks… a whisper of glass on top of the
/// landscape."* So the real `NSVisualEffectView` blur must stay visible; we
/// lay an album-color membrane, a thin top-weighted frost, and a wet specular
/// edge over it. Blue covers must read visibly blue; monochrome covers become
/// neutral gray glass — without going neon.
///
/// Public API (cornerRadius / bottomShadeHeight / accentStrength /
/// neutralOpacity / strokeOpacity) is unchanged so the Small/Regular/Large
/// widget callers are drop-in compatible.
struct AdaptiveWidgetGlassBackground: View {

    @EnvironmentObject private var settings: AppSettings

    var cornerRadius: CGFloat
    var bottomShadeHeight: CGFloat = 0
    var accentStrength: Double = 0.22
    var neutralOpacity: Double = 0.34
    var strokeOpacity: Double = 0.18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let palette = settings.albumPalette
        let dominant = palette.dominant.color
        let vibrant = palette.vibrant.color
        let muted = palette.muted.color
        let shadow = palette.shadow.color
        let chromaBoost = min(palette.vibrant.chroma * 0.18, 0.14)
        let artworkLuminance = palette.dominant.relativeLuminance
        let isBrightArtwork = artworkLuminance > 0.46
        let isDarkArtwork = artworkLuminance < 0.16
        let colorMembraneOpacity = min(accentStrength + 0.13 + chromaBoost, 0.48)
        let dominantMembraneOpacity = min(accentStrength + 0.08 + chromaBoost * 0.65, 0.38)
        let legibilityScrimOpacity = isBrightArtwork ? 0.22 : (isDarkArtwork ? 0.12 : 0.17)
        let depthOpacity = isDarkArtwork ? 0.26 : 0.18

        return ZStack {
            // (1) The glass itself — a live blur of whatever sits behind the
            // floating widget. This IS the translucency; everything above is
            // deliberately thin so it keeps breathing through.
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(shape)

            // (2) Album color membrane — this is the real visual correction.
            // Soft-light was too subtle over bright desktop content, so a thin
            // normal-blended membrane makes the glass visibly inherit the cover.
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: vibrant.opacity(colorMembraneOpacity), location: 0.00),
                        .init(color: dominant.opacity(dominantMembraneOpacity), location: 0.46),
                        .init(color: shadow.opacity(depthOpacity), location: 1.00)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            // (2) Light frost — a gentle top-weighted neutral wash. Lit at the
            // top rim, near-clear through the body, a hair of shade at the
            // bottom for depth. Replaces the old flat white+black fills that
            // turned the glass milky.
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(neutralOpacity * 0.28), location: 0.00),
                        .init(color: muted.opacity(neutralOpacity * 0.22),  location: 0.42),
                        .init(color: shadow.opacity(0.12 + depthOpacity),   location: 1.00)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )

            // (3) Text-safety vignette — album colors can be bright or pastel,
            // so this thin multiply layer preserves white text contrast without
            // muting the cover hue as much as an opaque black rectangle would.
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(legibilityScrimOpacity * 0.20), location: 0.00),
                        .init(color: Color.black.opacity(legibilityScrimOpacity * 0.44), location: 0.58),
                        .init(color: Color.black.opacity(legibilityScrimOpacity), location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blendMode(.multiply)

            // (3) Album-color bloom from the upper-left. Soft-light so it
            // tints the glass rather than painting over it.
            RadialGradient(
                colors: [
                    vibrant.opacity(min(accentStrength * 1.70 + chromaBoost, 0.56)),
                    dominant.opacity(min(accentStrength * 0.92 + chromaBoost * 0.55, 0.36)),
                    .clear
                ],
                center: UnitPoint(x: 0.18, y: 0.02),
                startRadius: 6,
                endRadius: 230
            )
            .clipShape(shape)
            .blendMode(.overlay)

            // (4) Specular "wet edge" — a crisp bright sliver along the top
            // rim where light catches the glass. Replaces the old blurry
            // rotated capsule smudge with a clean, fast top-edge highlight.
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(isDarkArtwork ? 0.62 : 0.52), location: 0.00),
                        .init(color: vibrant.opacity(0.30), location: 0.055),
                        .init(color: .clear,                location: 0.22)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .blendMode(.screen)
            .allowsHitTesting(false)

            RadialGradient(
                colors: [
                    Color.white.opacity(isDarkArtwork ? 0.24 : 0.16),
                    .clear
                ],
                center: UnitPoint(x: 0.10, y: 0.08),
                startRadius: 0,
                endRadius: 135
            )
            .clipShape(shape)
            .blendMode(.screen)
            .allowsHitTesting(false)

            // (5) Optional bottom shade — kept for callers that darken under
            // their content for legibility (behavior unchanged).
            if bottomShadeHeight > 0 {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.04),
                                Color.black.opacity(isBrightArtwork ? 0.28 : 0.22)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: bottomShadeHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .clipShape(shape)
            }

            // (6) Rim — bright top-left highlight → faint accent → soft dark
            // bottom-right. The thin liquid edge that lifts the glass off the
            // landscape without reading as a heavy border.
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(strokeOpacity + (isDarkArtwork ? 0.42 : 0.34)),
                            vibrant.opacity(strokeOpacity + 0.24),
                            shadow.opacity(isBrightArtwork ? 0.42 : 0.32)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )

            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .clear,
                            shadow.opacity(isBrightArtwork ? 0.34 : 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.6
                )
                .blur(radius: 0.35)
                .blendMode(.multiply)
        }
        .animation(VPTheme.liquid, value: settings.albumPalette)
    }
}

struct LiquidAlbumGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var bottomShadeHeight: CGFloat = 0
    var accentStrength: Double = 0.22
    var neutralOpacity: Double = 0.34
    var strokeOpacity: Double = 0.18

    func body(content: Content) -> some View {
        content.background(
            AdaptiveWidgetGlassBackground(
                cornerRadius: cornerRadius,
                bottomShadeHeight: bottomShadeHeight,
                accentStrength: accentStrength,
                neutralOpacity: neutralOpacity,
                strokeOpacity: strokeOpacity
            )
        )
    }
}

extension View {
    func liquidAlbumGlass(
        cornerRadius: CGFloat,
        bottomShadeHeight: CGFloat = 0,
        accentStrength: Double = 0.22,
        neutralOpacity: Double = 0.34,
        strokeOpacity: Double = 0.18
    ) -> some View {
        modifier(
            LiquidAlbumGlassModifier(
                cornerRadius: cornerRadius,
                bottomShadeHeight: bottomShadeHeight,
                accentStrength: accentStrength,
                neutralOpacity: neutralOpacity,
                strokeOpacity: strokeOpacity
            )
        )
    }
}
