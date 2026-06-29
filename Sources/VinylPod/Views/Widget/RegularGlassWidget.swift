import SwiftUI
import AppKit

/// Regular-size VinylPod widget: a tall artwork card with in-art window behavior,
/// top-right settings, floating transport controls, and a bottom title gradient.
struct RegularGlassWidget: View {

    var currentLayer: DesktopLayer
    var onSelectLayer: (DesktopLayer) -> Void
    var onSelectSize: (WindowMode) -> Void
    var onQuit: () -> Void

    @EnvironmentObject private var nowPlaying: NowPlayingService
    @VPState private var hovering = false

    private let widgetSize = CGSize(width: 300, height: 360)
    private let cornerRadius: CGFloat = 12

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AlbumArtCloseButton(
                artwork: nowPlaying.track.artwork,
                cornerRadius: cornerRadius,
                alwaysShowCloseButton: true,
                closeButtonSize: 15,
                closeButtonInset: 7,
                focusRingVisible: false,
                currentLayer: currentLayer,
                onSelectLayer: onSelectLayer,
                onQuit: onQuit
            )
            .frame(width: widgetSize.width, height: widgetSize.height)
            .zIndex(1)

            artworkTone
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .allowsHitTesting(false)
                .zIndex(2)

            transportControls
                .frame(width: widgetSize.width)
                .offset(y: 151)
                .opacity(hovering ? 1 : 0)
                .animation(VPTheme.fade, value: hovering)
                .zIndex(4)

            bottomCaption
                .frame(width: widgetSize.width, height: 86)
                .frame(maxHeight: .infinity, alignment: .bottom)
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
            .padding(.top, 9)
            .padding(.trailing, 9)
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

    private var artworkTone: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.clear,
                    Color.black.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [
                    Color.clear,
                    Color(red: 0.48, green: 0.24, blue: 0.48).opacity(0.34)
                ],
                startPoint: UnitPoint(x: 0.5, y: 0.58),
                endPoint: .bottom
            )
        }
    }

    private var transportControls: some View {
        HStack(spacing: 24) {
            controlButton("backward.fill", size: 25) { nowPlaying.previous() }
            Button { nowPlaying.playPause() } label: {
                Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.98))
                    .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
                    .frame(width: 34, height: 38)
                    .offset(x: nowPlaying.isPlaying ? 0 : 2)
            }
            .buttonStyle(.plain)
            controlButton("forward.fill", size: 25) { nowPlaying.next() }
        }
    }

    private var bottomCaption: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.clear,
                    Color(red: 0.50, green: 0.25, blue: 0.49).opacity(0.74),
                    Color(red: 0.47, green: 0.24, blue: 0.47).opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 5) {
                Text(primaryLine)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .shadow(color: .black.opacity(0.22), radius: 2, x: 0, y: 1)
                    .lineLimit(1)

                Text(secondaryLine)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .shadow(color: .black.opacity(0.20), radius: 2, x: 0, y: 1)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
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

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(Color.white.opacity(0.98))
                .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
                .frame(width: 28, height: 34)
        }
        .buttonStyle(.plain)
    }
}
