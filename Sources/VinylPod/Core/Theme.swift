import SwiftUI

/// VinylPod design-system tokens.
///
/// Mood: **dark minimalist** over a **static landscape** background, with
/// **glassmorphism** panels and a single accent color that is *adaptively
/// extracted from the current album art* (see `AppSettings.accentColor`).
///
/// Hard rule: the large background never changes color with the track —
/// only the small accent elements (progress fill, active buttons) breathe.
enum VPTheme {

    // MARK: - Text
    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let textMuted     = Color.white.opacity(0.40)

    // MARK: - Surfaces / glass
    /// Dark scrim laid over the landscape so text stays legible on any image.
    static let scrim         = Color.black.opacity(0.35)
    static let scrimStrong   = Color.black.opacity(0.55)
    /// Tint applied on top of the frosted-glass blur.
    static let glassTint     = Color.white.opacity(0.06)
    static let glassStroke   = Color.white.opacity(0.12)
    static let panel         = Color.white.opacity(0.08)

    // MARK: - Accent fallback (used when adaptive accent is off / unavailable)
    static let accentFallback = Color.white.opacity(0.90)

    // MARK: - Shape language
    /// Single corner radius token for visual cohesion (rounded rectangles).
    static let radius: CGFloat        = 14
    static let radiusSmall: CGFloat   = 10
    static let radiusLarge: CGFloat   = 22

    // MARK: - Motion
    /// Smooth fade used for empty ↔ playing and error transitions (no spinners).
    static let fade = Animation.easeInOut(duration: 0.45)
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.7)

    // MARK: - Fonts (Apple system sans-serif)
    static func title(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .semibold) }
    static func body(_ size: CGFloat = 12)  -> Font { .system(size: size, weight: .regular) }
    static func caption(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .medium) }
}

/// CLT workaround: the macOS 26+ SDK declares `@State` as a *macro* whose
/// `SwiftUIMacros` plugin ships only with full Xcode, not Command Line Tools.
/// Aliasing the property-wrapper TYPE dodges the macro of the same name, so
/// view-local state uses `@VPState` instead of `@State`. Identical behavior.
typealias VPState = SwiftUI.State
