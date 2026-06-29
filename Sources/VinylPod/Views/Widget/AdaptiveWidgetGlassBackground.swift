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
                        .init(color: vibrant.opacity(accentStrength * 0.92 + 0.12), location: 0.00),
                        .init(color: dominant.opacity(accentStrength * 0.72 + 0.10), location: 0.45),
                        .init(color: shadow.opacity(0.16), location: 1.00)
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
                        .init(color: .white.opacity(neutralOpacity * 0.22), location: 0.00),
                        .init(color: muted.opacity(neutralOpacity * 0.26),  location: 0.46),
                        .init(color: shadow.opacity(0.14),                 location: 1.00)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )

            // (3) Album-color bloom from the upper-left. Soft-light so it
            // tints the glass rather than painting over it.
            RadialGradient(
                colors: [
                    vibrant.opacity(accentStrength * 1.55),
                    dominant.opacity(accentStrength * 0.86),
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
                        .init(color: .white.opacity(0.50), location: 0.00),
                        .init(color: vibrant.opacity(0.24), location: 0.06),
                        .init(color: .clear,               location: 0.20)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
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
                                Color.black.opacity(0.20)
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
                            Color.white.opacity(strokeOpacity + 0.34),
                            vibrant.opacity(strokeOpacity + 0.18),
                            shadow.opacity(0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
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
