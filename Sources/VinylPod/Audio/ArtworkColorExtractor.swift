import Foundation
import AppKit
import CoreGraphics
import SwiftUI

/// Derives a single vivid accent `Color` from album artwork.
///
/// Strategy (dependency-free, CoreGraphics only):
///  1. Downscale the artwork to ~32×32 into a known RGBA8 bitmap. Downscaling is
///     a cheap box-average that smooths noise and makes the pass fast (~1k px).
///  2. Walk the pixels and accumulate a *saturation-weighted* average. A plain
///     mean tends toward gray/brown mud on real covers; weighting by saturation
///     biases the result toward the cover's most colorful region so the accent
///     has life. Near-transparent and near-grayscale pixels are skipped.
///  3. Convert to HSB and clamp brightness (≥0.55) and saturation (0.45…0.95)
///     so the color always reads as a lively accent on VinylPod's dark UI.
///
/// Returns `nil` only if the bitmap can't be created/read.
@MainActor
final class ArtworkColorExtractor: ArtworkColorExtracting {

    init() {}

    func dominantColor(from image: NSImage) -> Color? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // --- 1. Downscale into a fixed RGBA8 bitmap we fully control. ---
        let side = 32
        let bytesPerPixel = 4
        let bytesPerRow = side * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: side * side * bytesPerPixel)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            ctx.interpolationQuality = .low   // box-ish average is enough here
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        // --- 2. Saturation-weighted accumulation. ---
        var rSum = 0.0, gSum = 0.0, bSum = 0.0, weightSum = 0.0
        // Fallback plain average, in case the cover is almost entirely grayscale.
        var rPlain = 0.0, gPlain = 0.0, bPlain = 0.0, plainCount = 0.0

        var i = 0
        while i < pixels.count {
            let r = Double(pixels[i])     / 255.0
            let g = Double(pixels[i + 1]) / 255.0
            let b = Double(pixels[i + 2]) / 255.0
            let a = Double(pixels[i + 3]) / 255.0
            i += bytesPerPixel

            if a < 0.1 { continue }   // skip transparent padding

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let sat = maxC <= 0 ? 0 : (maxC - minC) / maxC

            rPlain += r; gPlain += g; bPlain += b; plainCount += 1

            // Square the saturation so vivid pixels dominate decisively.
            let weight = sat * sat
            rSum += r * weight
            gSum += g * weight
            bSum += b * weight
            weightSum += weight
        }

        // Choose the weighted color when the cover has any real chroma,
        // otherwise fall back to the plain average (a tinted gray cover).
        var rOut: Double, gOut: Double, bOut: Double
        if weightSum > 0.0001 {
            rOut = rSum / weightSum
            gOut = gSum / weightSum
            bOut = bSum / weightSum
        } else if plainCount > 0 {
            rOut = rPlain / plainCount
            gOut = gPlain / plainCount
            bOut = bPlain / plainCount
        } else {
            return nil
        }

        // --- 3. Clamp into a lively accent range via HSB. ---
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, al: CGFloat = 0
        let base = NSColor(
            calibratedRed: CGFloat(rOut),
            green: CGFloat(gOut),
            blue: CGFloat(bOut),
            alpha: 1.0
        )
        // Convert through the HSB-capable color space before reading components.
        (base.usingColorSpace(.deviceRGB) ?? base)
            .getHue(&h, saturation: &s, brightness: &br, alpha: &al)

        let clampedSat = min(max(s, 0.45), 0.95)   // not washed out, not neon-blinding
        let clampedBri = max(br, 0.55)             // never muddy/dark on a dark UI

        let accent = NSColor(
            hue: h,
            saturation: clampedSat,
            brightness: clampedBri,
            alpha: 1.0
        )

        return Color(nsColor: accent)
    }
}
