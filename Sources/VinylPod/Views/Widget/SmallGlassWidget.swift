import SwiftUI
import AppKit

/// Pixel-focused small-size widget. This replaces the old play-button-only
/// small mode and matches the compact screenshots: art at top-left, x inside
/// the art, settings dots top-right, and controls in a bottom glass strip.
struct SmallGlassWidget: View {

    var currentLayer: DesktopLayer
    var onSelectLayer: (DesktopLayer) -> Void
    var onSelectSize: (WindowMode) -> Void
    var onQuit: () -> Void

    @EnvironmentObject private var nowPlaying: NowPlayingService

    private let widgetSize = CGSize(width: 162, height: 162)
    private let artworkSize: CGFloat = 98

    var body: some View {
        ZStack(alignment: .topLeading) {
            glassContainer

            AlbumArtCloseButton(
                artwork: nowPlaying.track.artwork,
                cornerRadius: 7,
                alwaysShowCloseButton: true,
                closeButtonSize: 15,
                closeButtonInset: 3,
                focusRingVisible: true,
                currentLayer: currentLayer,
                onSelectLayer: onSelectLayer,
                onQuit: onQuit
            )
            .frame(width: artworkSize, height: artworkSize)
            .offset(x: 11, y: 7)
            .zIndex(3)

            SettingsMenuButton(
                onSelectSize: onSelectSize,
                onQuit: onQuit,
                triggerSize: 18,
                glyphSize: 9,
                menuOffsetY: 23,
                triggerFill: Color.black.opacity(0.82),
                triggerStroke: Color.clear,
                triggerForeground: Color.white.opacity(0.88)
            )
            .offset(x: widgetSize.width - 24, y: 5)
            .zIndex(8)

            bottomStrip
                .frame(width: widgetSize.width, height: 42)
                .offset(y: widgetSize.height - 42)
                .zIndex(2)
        }
        .frame(width: widgetSize.width, height: widgetSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)
    }

    private var glassContainer: some View {
        AdaptiveWidgetGlassBackground(
            cornerRadius: 18,
            bottomShadeHeight: 42,
            accentStrength: 0.24,
            neutralOpacity: 0.30,
            strokeOpacity: 0.16
        )
    }

    private var bottomStrip: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.21, green: 0.16, blue: 0.20).opacity(0.50))

            VStack(alignment: .leading, spacing: 0) {
                Text(primaryLine)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.93))
                    .lineLimit(1)
                Text(secondaryLine)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(1)
            }
            .frame(width: 132, alignment: .leading)
            .offset(x: 10, y: 3)

            HStack(spacing: 16) {
                smallControl("backward.fill") { nowPlaying.previous() }
                Button { nowPlaying.playPause() } label: {
                    Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.96))
                        .frame(width: 25, height: 25)
                        .offset(x: nowPlaying.isPlaying ? 0 : 1)
                }
                .buttonStyle(.plain)
                smallControl("forward.fill") { nowPlaying.next() }
            }
            .offset(x: 28, y: 13)
        }
    }

    private var primaryLine: String {
        if nowPlaying.track.isEmpty { return "Music is stopped." }
        return nowPlaying.track.title.isEmpty ? "Unknown Title" : nowPlaying.track.title
    }

    private var secondaryLine: String {
        if nowPlaying.track.isEmpty { return "Please play music on Spotify." }
        return nowPlaying.track.artist.isEmpty ? nowPlaying.track.source.displayName : nowPlaying.track.artist
    }

    private func smallControl(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 18, height: 24)
        }
        .buttonStyle(.plain)
    }
}

/// Medium-size widget matching the wide compact reference: artwork with the
/// in-art close button on the left, strong stopped/track copy on the right,
/// large transport controls, and the three-dot settings trigger top-right.
struct MediumGlassWidget: View {

    var currentLayer: DesktopLayer
    var onSelectLayer: (DesktopLayer) -> Void
    var onSelectSize: (WindowMode) -> Void
    var onQuit: () -> Void

    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var settings: AppSettings

    private let widgetSize = CGSize(width: 344, height: 132)
    private let artworkSize: CGFloat = 100

    var body: some View {
        ZStack(alignment: .topTrailing) {
            glassContainer

            HStack(spacing: 14) {
                AlbumArtCloseButton(
                    artwork: nowPlaying.track.artwork,
                    cornerRadius: 7,
                    alwaysShowCloseButton: true,
                    closeButtonSize: 15,
                    closeButtonInset: 3,
                    focusRingVisible: false,
                    currentLayer: currentLayer,
                    onSelectLayer: onSelectLayer,
                    onQuit: onQuit
                )
                .frame(width: artworkSize, height: artworkSize)
                .zIndex(4)

                VStack(alignment: .leading, spacing: 7) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(primaryLine)
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(Color.white)
                            .shadow(color: .black.opacity(0.24), radius: 2, x: 0, y: 1)
                            .lineLimit(1)

                        Text(secondaryLine)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .shadow(color: .black.opacity(0.20), radius: 2, x: 0, y: 1)
                            .lineLimit(1)
                    }
                    .frame(width: 184, alignment: .leading)

                    HStack(spacing: 21) {
                        mediumControl("backward.fill") { nowPlaying.previous() }
                        mediumPlayButton
                        mediumControl("forward.fill") { nowPlaying.next() }
                    }
                    .padding(.leading, 18)
                    .padding(.top, 2)

                    if settings.showProgress {
                        progressStrip
                            .frame(width: 184)
                    }
                }
                .padding(.top, 3)
            }
            .padding(.leading, 18)
            .padding(.trailing, 34)
            .frame(width: widgetSize.width, height: widgetSize.height, alignment: .leading)

            SettingsMenuButton(
                onSelectSize: onSelectSize,
                onQuit: onQuit,
                triggerSize: 18,
                glyphSize: 9,
                menuOffsetY: 23,
                triggerFill: Color.black.opacity(0.82),
                triggerStroke: Color.clear,
                triggerForeground: Color.white.opacity(0.88)
            )
            .padding(.top, 9)
            .padding(.trailing, 9)
            .zIndex(10)
        }
        .frame(width: widgetSize.width, height: widgetSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)
    }

    private var glassContainer: some View {
        AdaptiveWidgetGlassBackground(
            cornerRadius: 18,
            bottomShadeHeight: 35,
            accentStrength: 0.24,
            neutralOpacity: 0.32,
            strokeOpacity: 0.18
        )
    }

    private var primaryLine: String {
        if nowPlaying.track.isEmpty { return "Music is stopped." }
        return nowPlaying.track.title.isEmpty ? "Unknown Title" : nowPlaying.track.title
    }

    private var secondaryLine: String {
        if nowPlaying.track.isEmpty { return "Please play music on Spotify or Safari." }
        return nowPlaying.track.artist.isEmpty ? nowPlaying.track.source.displayName : nowPlaying.track.artist
    }

    private var mediumPlayButton: some View {
        Button { nowPlaying.playPause() } label: {
            Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.98))
                .frame(width: 27, height: 27)
                .offset(x: nowPlaying.isPlaying ? 0 : 1)
        }
        .buttonStyle(.plain)
    }

    private var progressStrip: some View {
        HStack(spacing: 5) {
            Text(nowPlaying.track.isEmpty ? "00:00" : Self.timeString(nowPlaying.position))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 38, alignment: .leading)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.42))
                    .frame(height: 3)
                Capsule()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: max(3, 90 * progressFraction), height: 3)
            }
            .frame(width: 90, height: 5)

            Text(nowPlaying.track.isEmpty ? "-00:00" : Self.timeString(nowPlaying.duration))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 43, alignment: .trailing)
        }
    }

    private var progressFraction: CGFloat {
        guard nowPlaying.duration > 0 else { return 0.0 }
        return CGFloat(min(max(nowPlaying.position / nowPlaying.duration, 0), 1))
    }

    private func mediumControl(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: 23, height: 27)
        }
        .buttonStyle(.plain)
    }

    private static func timeString(_ seconds: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }
}

/// Shared uploaded ice-mountain artwork used when no real track art exists.
enum DefaultArtworkAsset {
    static let image: NSImage? = {
        // Bundled resource only — no hardcoded absolute path (it leaked a dev
        // username into the binary and masked any bundling regression).
        Bundle.module.url(
            forResource: "majestic-ice-mountain-stockcake",
            withExtension: "jpg"
        ).flatMap { NSImage(contentsOf: $0) }
    }()
}

/// Default artwork used when no real track art exists. This uses the uploaded
/// ice mountain image directly rather than recreating a procedural image.
struct SmallWidgetDefaultArtwork: View {
    var body: some View {
        Group {
            if let image = DefaultArtworkAsset.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                IceArtworkFallback()
            }
        }
        .overlay(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.clear,
                    Color.black.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipped()
    }
}

private struct IceArtworkFallback: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.46, blue: 0.86),
                Color(red: 0.42, green: 0.88, blue: 0.96),
                Color(red: 0.92, green: 0.98, blue: 1.00)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
