import SwiftUI

/// Frosted-glass widget backdrop that tints itself with the current album
/// accent color.
///
/// Layering, bottom to top:
///   1. `.ultraThinMaterial` — system blur so the desktop shows through.
///   2. Neutral dark fill (`neutralOpacity`) — keeps text legible over any
///      wallpaper, independent of the artwork's brightness.
///   3. Accent wash (`accentStrength`) — a soft top-leading gradient of the
///      adaptive `AppSettings.accentColor`, so the glass picks up the album's
///      hue without overpowering the content.
///   4. Optional bottom shade (`bottomShadeHeight`) — extra scrim behind
///      transport controls pinned to the widget's lower edge.
///   5. Hairline stroke (`strokeOpacity`) — defines the glass edge.
struct AdaptiveWidgetGlassBackground: View {

    @EnvironmentObject private var settings: AppSettings

    var cornerRadius: CGFloat
    var bottomShadeHeight: CGFloat = 0
    var accentStrength: Double = 0.22
    var neutralOpacity: Double = 0.34
    var strokeOpacity: Double = 0.18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let accent = settings.accentColor

        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Color.black.opacity(neutralOpacity)))
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(accentStrength),
                            accent.opacity(accentStrength * 0.35),
                            .clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(alignment: .bottom) {
                if bottomShadeHeight > 0 {
                    LinearGradient(
                        colors: [.clear, VPTheme.scrimStrong],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: bottomShadeHeight)
                    .allowsHitTesting(false)
                }
            }
            .overlay(shape.strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 1))
            .clipShape(shape)
            .animation(VPTheme.fade, value: accent)
    }
}
