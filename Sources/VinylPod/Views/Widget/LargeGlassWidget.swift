import SwiftUI
import AppKit

/// Large-size VinylPod widget: centered album art, clear text hierarchy,
/// visible playback controls, and hover-revealed X / settings chrome.
struct LargeGlassWidget: View {

    var currentLayer: DesktopLayer
    var onSelectLayer: (DesktopLayer) -> Void
    var onSelectSize: (WindowMode) -> Void
    var onQuit: () -> Void

    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var settings: AppSettings
    @VPState private var hovering = false

    private let widgetSize = CGSize(width: 320, height: 432)
    private let artworkSize: CGFloat = 260
    private let cornerRadius: CGFloat = 12

    var body: some View {
        ZStack(alignment: .topTrailing) {
            glassContainer

            artworkCard
                .frame(width: artworkSize, height: artworkSize)
                .frame(width: widgetSize.width, height: widgetSize.height, alignment: .top)
                .offset(y: 31)
                .zIndex(2)

            VStack(spacing: 0) {
                Spacer().frame(height: 302)
                titleStack
                Spacer().frame(height: 20)
                transportControls
                Spacer().frame(height: 12)
                if settings.showProgress {
                    progressStrip
                        .padding(.horizontal, 22)
                }
            }
            .frame(width: widgetSize.width, height: widgetSize.height, alignment: .top)
            .zIndex(3)

            AlbumArtCloseButton(
                artwork: nil,
                cornerRadius: cornerRadius,
                alwaysShowCloseButton: true,
                closeButtonSize: 15,
                closeButtonInset: 0,
                focusRingVisible: false,
                showsArtworkLayer: false,
                currentLayer: currentLayer,
                onSelectLayer: onSelectLayer,
                onQuit: onQuit
            )
            .frame(width: 20, height: 20)
            .padding(.top, 8)
            .padding(.leading, 8)
            .frame(width: widgetSize.width, height: widgetSize.height, alignment: .topLeading)
            .opacity(hovering ? 1 : 0)
            .animation(VPTheme.fade, value: hovering)
            .zIndex(9)

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
            .opacity(hovering ? 1 : 0)
            .animation(VPTheme.fade, value: hovering)
            .zIndex(10)
        }
        .frame(width: widgetSize.width, height: widgetSize.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 10)
        .onHover { hovering = $0 }
    }

    private var glassContainer: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.82, green: 0.56, blue: 0.72).opacity(0.82),
                        Color(red: 0.59, green: 0.35, blue: 0.57).opacity(0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RadialGradient(
                    colors: [
                        Color(red: 1.00, green: 0.67, blue: 0.86).opacity(0.28),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.72, y: 0.06),
                    startRadius: 8,
                    endRadius: 210
                )
            )
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.clear,
                        Color.black.opacity(0.04)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var artworkCard: some View {
        Group {
            if let artwork = nowPlaying.track.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                SmallWidgetDefaultArtwork()
            }
        }
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 5)
    }

    private var titleStack: some View {
        VStack(spacing: 8) {
            Text(primaryLine)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Color.white.opacity(0.98))
                .shadow(color: .black.opacity(0.22), radius: 2, x: 0, y: 1)
                .lineLimit(1)

            Text(secondaryLine)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.84))
                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
    }

    private var transportControls: some View {
        HStack(spacing: 28) {
            controlButton("backward.fill", size: 25) { nowPlaying.previous() }
            Button { nowPlaying.playPause() } label: {
                Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 31, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.98))
                    .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
                    .frame(width: 34, height: 38)
                    .offset(x: nowPlaying.isPlaying ? 0 : 2)
            }
            .buttonStyle(.plain)
            controlButton("forward.fill", size: 25) { nowPlaying.next() }
        }
    }

    private var progressStrip: some View {
        HStack(spacing: 6) {
            Text(nowPlaying.track.isEmpty ? "00:00" : Self.timeString(nowPlaying.position))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 34, alignment: .leading)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.42))
                    .frame(height: 3)
                Capsule()
                    .fill(Color.white.opacity(0.94))
                    .frame(width: max(3, 198 * progressFraction), height: 3)
            }
            .frame(width: 198, height: 5)

            Text(nowPlaying.track.isEmpty ? "-00:00" : Self.timeString(max(nowPlaying.duration - nowPlaying.position, 0)))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.84))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var primaryLine: String {
        if nowPlaying.track.isEmpty { return "Music is stopped." }
        return nowPlaying.track.title.isEmpty ? "Unknown Title" : nowPlaying.track.title
    }

    private var secondaryLine: String {
        if nowPlaying.track.isEmpty { return "Please play music on Spotify or Music" }
        return nowPlaying.track.artist.isEmpty ? nowPlaying.track.source.displayName : nowPlaying.track.artist
    }

    private var progressFraction: CGFloat {
        guard nowPlaying.duration > 0 else { return 0.0 }
        return CGFloat(min(max(nowPlaying.position / nowPlaying.duration, 0), 1))
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(Color.white.opacity(0.98))
                .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
                .frame(width: 30, height: 34)
        }
        .buttonStyle(.plain)
    }

    private static func timeString(_ seconds: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }
}
