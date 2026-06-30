import SwiftUI

/// A thin, rounded progress/seek bar.
///   • Track  → `VPTheme.panel` (faint translucent white).
///   • Fill   → `settings.accentColor` (the adaptive, per-track accent).
///   • Drag   → seeks: maps the gesture's x to a time and calls
///     `nowPlaying.seek(to:)`.
/// Elapsed / remaining labels sit beneath in `VPTheme.caption()`.
struct ProgressBarView: View {

    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var settings: AppSettings

    /// True while the user is actively dragging the knob; we preview the
    /// dragged value locally and only commit on release for a smooth feel.
    @VPState private var isDragging = false
    @VPState private var dragValue: TimeInterval = 0

    /// Real track length. May be 0 for live streams / not-yet-loaded media,
    /// in which case we render an empty (indeterminate) bar rather than a
    /// bogus full one.
    private var duration: TimeInterval { max(nowPlaying.duration, 0) }
    private var position: TimeInterval {
        isDragging ? dragValue : nowPlaying.position
    }
    private var fraction: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(position / duration, 0), 1))
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(VPTheme.panel)
                        .frame(height: 4)

                    // Fill — tinted by the adaptive accent.
                    Capsule()
                        .fill(settings.accentColor)
                        .frame(width: width * fraction, height: 4)

                    // Knob
                    Circle()
                        .fill(settings.accentColor)
                        .frame(width: 11, height: 11)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: max(0, width * fraction - 5.5))
                        .scaleEffect(isDragging ? 1.25 : 1)
                        .animation(VPTheme.spring, value: isDragging)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            isDragging = true
                            guard width > 0 else { return }   // avoid x/0 → NaN seek
                            let f = min(max(g.location.x / width, 0), 1)
                            dragValue = Double(f) * duration
                        }
                        .onEnded { _ in
                            nowPlaying.seek(to: dragValue)
                            isDragging = false
                        }
                )
            }
            .frame(height: 14)

            // Elapsed (left) / remaining (right) time labels. With an unknown
            // duration (live streams) there's no meaningful "remaining", so the
            // trailing label falls back to the total placeholder.
            HStack {
                Text(Self.timeString(position))
                Spacer()
                Text(duration > 0 ? "-" + Self.timeString(duration - position) : "--:--")
            }
            .font(VPTheme.caption())
            .foregroundStyle(VPTheme.textMuted)
            .monospacedDigit()
        }
    }

    /// Formats seconds as m:ss (or h:mm:ss for long tracks).
    static func timeString(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
