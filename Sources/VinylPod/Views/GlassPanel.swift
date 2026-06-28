import SwiftUI

/// A reusable frosted-glass container: `VisualEffectBlur` + a faint
/// `VPTheme.glassTint` wash + a hairline `VPTheme.glassStroke` border,
/// all clipped to a rounded rectangle (`VPTheme.radius`).
///
/// This is the single surface used for every floating UI element so panels
/// share one shape language and read as "light, translucent layers — never
/// opaque solid blocks."
struct GlassPanel<Content: View>: View {

    var cornerRadius: CGFloat = VPTheme.radius
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                ZStack {
                    VisualEffectBlur()
                    VPTheme.glassTint
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(VPTheme.glassStroke, lineWidth: 1)
            )
    }
}

/// `ViewModifier` form of `GlassPanel` for callers that prefer
/// `.glassBackground()` over wrapping their content.
struct GlassBackgroundModifier: ViewModifier {
    var cornerRadius: CGFloat = VPTheme.radius

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffectBlur()
                    VPTheme.glassTint
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(VPTheme.glassStroke, lineWidth: 1)
            )
    }
}

extension View {
    /// Apply the standard VinylPod frosted-glass surface behind this view.
    func glassBackground(cornerRadius: CGFloat = VPTheme.radius) -> some View {
        modifier(GlassBackgroundModifier(cornerRadius: cornerRadius))
    }
}
