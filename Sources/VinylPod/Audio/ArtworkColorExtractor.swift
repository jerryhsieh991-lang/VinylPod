import Foundation
import AppKit
import CoreImage
import SwiftUI

/// Derives an album-reactive palette from artwork using CoreImage.
///
/// The pipeline intentionally returns more than one color:
/// - dominant: `CIAreaAverage`, stable background mood
/// - vibrant: saturation-weighted sample, readable controls/progress
/// - muted: lower-chroma sample, glass fill and soft shadow gradients
/// - shadow: darkened dominant, depth under the glass
@MainActor
final class ArtworkColorExtractor: ArtworkColorExtracting {

    init() {}

    func palette(from image: NSImage) -> AlbumColorPalette? {
        Self.paletteOffMain(from: image)
    }

    /// Backward-compatible single accent for older call sites.
    func dominantColor(from image: NSImage) -> Color? {
        Self.paletteOffMain(from: image)?.vibrant.color
    }

    /// Safe to call from a detached task after the caller snapshots artwork to
    /// `Data` and recreates `NSImage` inside the task.
    nonisolated static func paletteOffMain(from image: NSImage) -> AlbumColorPalette? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)
        // Keep these local to the nonisolated extractor. Static properties on
        // this @MainActor class become actor-isolated and trigger Swift 6
        // warnings when read from the detached color-analysis path.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CIContext(options: [.workingColorSpace: colorSpace])

        guard let dominant = areaAverage(from: ciImage, context: context, colorSpace: colorSpace) else {
            return nil
        }

        let stats = samplePalette(from: ciImage, context: context, colorSpace: colorSpace)
        let rawVibrant = stats.vibrant ?? dominant
        let hasUsefulChroma = max(rawVibrant.chroma, stats.averageSaturation) > 0.10
            && stats.vibrantWeight > 0.035

        let vibrant = rawVibrant.adjusted(
            saturation: hasUsefulChroma ? 0.48 : nil,
            brightness: hasUsefulChroma ? 0.56 : 0.46,
            maximumBrightness: 0.90
        )
        let dominantMood = dominant
            .mixed(with: vibrant, amount: hasUsefulChroma ? 0.24 : 0.0)
            .adjusted(
                saturation: hasUsefulChroma ? 0.24 : nil,
                brightness: dominant.relativeLuminance < 0.08 ? 0.22 : nil,
                maximumBrightness: 0.82
            )
        let muted = (stats.muted ?? dominantMood)
            .mixed(with: vibrant, amount: hasUsefulChroma ? 0.16 : 0.0)
            .adjusted(
                saturation: hasUsefulChroma ? 0.18 : nil,
                brightness: 0.30,
                maximumBrightness: 0.76
            )

        return AlbumColorPalette(
            dominant: dominantMood,
            vibrant: vibrant,
            muted: muted,
            shadow: dominantMood.darkened(0.68)
        )
    }

    nonisolated static func dominantColorOffMain(from image: NSImage) -> Color? {
        paletteOffMain(from: image)?.vibrant.color
    }

    /// Async liquid-disc palette parser for callers that already recreated an
    /// `NSImage` inside a detached/off-main task. The return value contains only
    /// plain RGB numbers, so it is safe to pass between actors.
    nonisolated static func liquidTokensOffMain(from image: NSImage) async -> [RGBColorToken] {
        paletteOffMain(from: image)?.liquidDiscTokens ?? AlbumColorPalette.iceMountain.liquidDiscTokens
    }

    /// Preferred actor-boundary API: snapshot artwork to `Data` on the main
    /// actor, then call this from any async context. The `NSImage` is decoded
    /// inside this nonisolated function and never leaks across the boundary.
    nonisolated static func liquidTokensOffMain(from imageData: Data?) async -> [RGBColorToken] {
        guard let imageData, let image = NSImage(data: imageData) else {
            return AlbumColorPalette.iceMountain.liquidDiscTokens
        }
        return await liquidTokensOffMain(from: image)
    }

    private nonisolated static func areaAverage(
        from image: CIImage,
        context: CIContext,
        colorSpace: CGColorSpace
    ) -> RGBColorToken? {
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var rgba = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &rgba,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: colorSpace
        )

        return RGBColorToken(
            red: Double(rgba[0]) / 255.0,
            green: Double(rgba[1]) / 255.0,
            blue: Double(rgba[2]) / 255.0,
            alpha: 1.0
        )
    }

    private nonisolated static func samplePalette(
        from image: CIImage,
        context: CIContext,
        colorSpace: CGColorSpace
    ) -> SampleStats {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0 else { return SampleStats() }

        let maxSide: CGFloat = 52
        let scale = min(maxSide / extent.width, maxSide / extent.height)
        let sampleWidth = max(1, Int((extent.width * scale).rounded()))
        let sampleHeight = max(1, Int((extent.height * scale).rounded()))

        let translated = image.transformed(
            by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
        )
        let scaled = translated.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * bytesPerPixel)

        context.render(
            scaled,
            toBitmap: &pixels,
            rowBytes: bytesPerRow,
            bounds: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight),
            format: .RGBA8,
            colorSpace: colorSpace
        )

        var vibrantR = 0.0
        var vibrantG = 0.0
        var vibrantB = 0.0
        var vibrantWeight = 0.0

        var mutedR = 0.0
        var mutedG = 0.0
        var mutedB = 0.0
        var mutedWeight = 0.0
        var saturationTotal = 0.0
        var acceptedPixels = 0

        var i = 0
        while i < pixels.count {
            let r = Double(pixels[i]) / 255.0
            let g = Double(pixels[i + 1]) / 255.0
            let b = Double(pixels[i + 2]) / 255.0
            let a = Double(pixels[i + 3]) / 255.0
            i += bytesPerPixel

            guard a > 0.18 else { continue }

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let saturation = maxC <= 0 ? 0 : (maxC - minC) / maxC
            let brightness = maxC
            guard brightness > 0.04, brightness < 0.98 else { continue }
            saturationTotal += saturation
            acceptedPixels += 1

            let midtoneBias = 1.0 - min(abs(brightness - 0.56) / 0.56, 1.0) * 0.34
            let darkColorLift = brightness < 0.24 ? 1.35 : 1.0
            let vividWeight = pow(saturation, 1.65)
                * pow(max(brightness, 0.18), 0.72)
                * midtoneBias
                * darkColorLift
            vibrantR += r * vividWeight
            vibrantG += g * vividWeight
            vibrantB += b * vividWeight
            vibrantWeight += vividWeight

            let mutedSaturationWindow = max(0.05, 1.0 - abs(saturation - 0.30) * 1.35)
            let mutedBrightnessWindow = max(0.12, 1.0 - abs(brightness - 0.50) * 1.20)
            let mutedCandidate = mutedSaturationWindow * mutedBrightnessWindow
            mutedR += r * mutedCandidate
            mutedG += g * mutedCandidate
            mutedB += b * mutedCandidate
            mutedWeight += mutedCandidate
        }

        return SampleStats(
            vibrant: color(r: vibrantR, g: vibrantG, b: vibrantB, weight: vibrantWeight),
            muted: color(r: mutedR, g: mutedG, b: mutedB, weight: mutedWeight),
            vibrantWeight: acceptedPixels == 0 ? 0 : vibrantWeight / Double(acceptedPixels),
            averageSaturation: acceptedPixels == 0 ? 0 : saturationTotal / Double(acceptedPixels)
        )
    }

    private nonisolated static func color(r: Double, g: Double, b: Double, weight: Double) -> RGBColorToken? {
        guard weight > 0.0001 else { return nil }
        return RGBColorToken(red: r / weight, green: g / weight, blue: b / weight)
    }

    private struct SampleStats {
        var vibrant: RGBColorToken?
        var muted: RGBColorToken?
        var vibrantWeight: Double = 0
        var averageSaturation: Double = 0
    }
}
