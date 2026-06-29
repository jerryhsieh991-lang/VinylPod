import SwiftUI
import AppKit

/// VinylPod design-system tokens.
///
/// Mood: **album-reactive liquid glass** over a calm landscape base. The
/// current album art drives the palette used by glass, progress, controls, and
/// desktop ambience (see `AppSettings.albumPalette`).
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
    static let glassTint     = Color.white.opacity(0.07)
    static let glassStroke   = Color.white.opacity(0.18)
    static let panel         = Color.white.opacity(0.08)

    // MARK: - Accent fallback (used when adaptive accent is off / unavailable)
    static let iceAccent = Color(red: 0.38, green: 0.78, blue: 0.96)
    static let accentFallback = iceAccent.opacity(0.92)

    // MARK: - Shape language
    /// Single corner radius token for visual cohesion (rounded rectangles).
    static let radius: CGFloat        = 14
    static let radiusSmall: CGFloat   = 10
    static let radiusLarge: CGFloat   = 22

    // MARK: - Motion
    /// Smooth fade used for empty ↔ playing and error transitions (no spinners).
    static let fade = Animation.easeInOut(duration: 0.45)
    static let liquid = Animation.easeInOut(duration: 1.05)
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.7)

    // MARK: - Fonts (Apple system sans-serif)
    static func title(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .bold, design: .default) }
    static func body(_ size: CGFloat = 12)  -> Font { .system(size: size, weight: .semibold, design: .default) }
    static func caption(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .bold, design: .default) }
}

/// CLT workaround: the macOS 26+ SDK declares `@State` as a *macro* whose
/// `SwiftUIMacros` plugin ships only with full Xcode, not Command Line Tools.
/// Aliasing the property-wrapper TYPE dodges the macro of the same name, so
/// view-local state uses `@VPState` instead of `@State`. Identical behavior.
typealias VPState = SwiftUI.State

// MARK: - Album-reactive color tokens

/// Sendable RGB token used by the CoreImage extractor. SwiftUI `Color` is kept
/// on the main actor; background color work moves only simple numbers around.
struct RGBColorToken: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1.0

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(
            calibratedRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }

    func adjusted(saturation minSaturation: CGFloat? = nil, brightness minBrightness: CGFloat? = nil) -> RGBColorToken {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        (nsColor.usingColorSpace(.deviceRGB) ?? nsColor)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let outputSaturation = minSaturation.map { max(saturation, $0) } ?? saturation
        let outputBrightness = minBrightness.map { max(brightness, $0) } ?? brightness
        let adjusted = NSColor(
            hue: hue,
            saturation: min(outputSaturation, 0.94),
            brightness: min(outputBrightness, 0.98),
            alpha: alpha
        )
        return RGBColorToken(nsColor: adjusted)
    }

    func darkened(_ amount: CGFloat) -> RGBColorToken {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        (nsColor.usingColorSpace(.deviceRGB) ?? nsColor)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let adjusted = NSColor(
            hue: hue,
            saturation: min(saturation + 0.06, 0.92),
            brightness: max(brightness * (1 - amount), 0.10),
            alpha: alpha
        )
        return RGBColorToken(nsColor: adjusted)
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(nsColor: NSColor) {
        let rgb = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        red = Double(rgb.redComponent)
        green = Double(rgb.greenComponent)
        blue = Double(rgb.blueComponent)
        alpha = Double(rgb.alphaComponent)
    }
}

/// Four-color palette extracted from album art for liquid glass.
struct AlbumColorPalette: Equatable, Sendable {
    var dominant: RGBColorToken
    var vibrant: RGBColorToken
    var muted: RGBColorToken
    var shadow: RGBColorToken

    static let iceMountain = AlbumColorPalette(
        dominant: RGBColorToken(red: 0.36, green: 0.76, blue: 0.94),
        vibrant: RGBColorToken(red: 0.26, green: 0.68, blue: 0.98),
        muted: RGBColorToken(red: 0.68, green: 0.86, blue: 0.92),
        shadow: RGBColorToken(red: 0.08, green: 0.18, blue: 0.30)
    )
}
