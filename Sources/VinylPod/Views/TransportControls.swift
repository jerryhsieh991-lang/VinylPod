import SwiftUI

/// Previous · Play/Pause · Next.
///
/// The play/pause button is a filled circle tinted with `settings.accentColor`
/// (the single per-track accent), flanked by quieter skip buttons. Each button
/// scales to 1.08 on hover using `VPTheme.spring`, per the design language.
struct TransportControls: View {

    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var settings: AppSettings

    /// Diameter of the central play/pause circle; skip glyphs scale from it.
    var playSize: CGFloat = 56

    var body: some View {
        HStack(spacing: playSize * 0.38) {
            skipButton(symbol: "backward.fill") { nowPlaying.previous() }

            PlayPauseButton(
                isPlaying: nowPlaying.isPlaying,
                accent: settings.accentColor,
                size: playSize
            ) {
                nowPlaying.playPause()
            }

            skipButton(symbol: "forward.fill") { nowPlaying.next() }
        }
    }

    private func skipButton(symbol: String, action: @escaping () -> Void) -> some View {
        HoverScaleButton(action: action) {
            Image(systemName: symbol)
                .font(.system(size: playSize * 0.30, weight: .medium))
                .foregroundStyle(VPTheme.textPrimary)
                .frame(width: playSize * 0.7, height: playSize * 0.7)
                .contentShape(Rectangle())
        }
    }
}

/// The filled, accent-tinted central control.
private struct PlayPauseButton: View {
    let isPlaying: Bool
    let accent: Color
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        HoverScaleButton(action: action) {
            ZStack {
                Circle()
                    .fill(accent)
                    .shadow(color: accent.opacity(0.35), radius: 8, y: 2)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.40, weight: .bold))
                    // Dark glyph reads on the bright accent fill.
                    .foregroundStyle(Color.black.opacity(0.80))
                    // Nudge play triangle to look optically centered.
                    .offset(x: isPlaying ? 0 : size * 0.03)
            }
            .frame(width: size, height: size)
        }
    }
}

/// A borderless button that scales to 1.08 on hover with `VPTheme.spring`.
/// Shared by every transport control for a consistent feel.
private struct HoverScaleButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @VPState private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.08 : 1)
        .animation(VPTheme.spring, value: hovering)
        .onHover { hovering = $0 }
    }
}
