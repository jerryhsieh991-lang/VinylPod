import SwiftUI
import AppKit

/// Top-center dynamic-island companion shown when `settings.dynamicNotch` is on.
/// It deliberately lives in its own panel so the normal widget can stay anywhere
/// while the island remains pinned to the menu-bar/notch area.
struct DynamicIslandWidget: View {

    var onExpansionChange: (Bool) -> Void
    var onSelectSize: (WindowMode) -> Void
    var onQuit: () -> Void

    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var settings: AppSettings

    @VPState private var expanded = false

    private let compactSize = CGSize(width: 390, height: 30)
    private let expandedSize = CGSize(width: 430, height: 700)

    var body: some View {
        ZStack(alignment: .top) {
            if expanded {
                expandedPanel
                    .padding(.top, 42)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .scale(scale: 0.92, anchor: .top)).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity)
                    ))
                    .zIndex(1)
            }

            compactPill
                .frame(width: compactSize.width, height: compactSize.height)
                .zIndex(3)
        }
        .frame(
            width: expanded ? expandedSize.width : compactSize.width,
            height: expanded ? expandedSize.height : compactSize.height,
            alignment: .top
        )
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: expanded)
    }

    // MARK: - Compact island

    private var compactPill: some View {
        HStack(spacing: 10) {
            Button {
                toggleExpanded()
            } label: {
                HStack(spacing: 10) {
                    artwork(size: 22, cornerRadius: 6)

                    Text(compactTitle)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.22), radius: 1, y: 1)

                    Spacer(minLength: 6)

                    EqualizerBars(active: nowPlaying.isPlaying, barColor: Color.white.opacity(0.68), compact: true)
                        .frame(width: 28, height: 16)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SettingsMenuButton(
                onSelectSize: onSelectSize,
                onQuit: onQuit,
                triggerSize: 20,
                glyphSize: 10,
                triggerFill: Color.white.opacity(0.12),
                triggerStroke: Color.white.opacity(0.24),
                triggerForeground: Color.white.opacity(0.96)
            )
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(width: compactSize.width, height: compactSize.height)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.24))
                .background(
                    Capsule(style: .continuous)
                        .fill(settings.accentColor.opacity(0.14))
                        .blendMode(.softLight)
                )
                .background(
                    VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                        .clipShape(Capsule(style: .continuous))
                )
        )
        .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 6)
    }

    // MARK: - Expanded island

    private var expandedPanel: some View {
        ZStack(alignment: .top) {
            DynamicIslandBump()
                .fill(Color.white.opacity(0.36))
                .frame(width: 58, height: 30)
                .background(
                    DynamicIslandBump()
                        .fill(settings.accentColor.opacity(0.16))
                        .blendMode(.softLight)
                )
                .offset(y: -13)
                .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 3)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.black.opacity(0.20))
                .background(
                    VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(settings.accentColor.opacity(0.16))
                        .blendMode(.softLight)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.9)
                )
                .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 14)

            expandedContent
        }
        .frame(width: 420, height: 650)
    }

    private var expandedContent: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                artwork(size: 370, cornerRadius: 18)
                    .padding(.top, 38)

                Spacer().frame(height: 34)

                Text(primaryLine)
                    .font(.system(size: 31, weight: .semibold, design: .default))
                    .foregroundStyle(Color.white.opacity(0.98))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 360)
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)

                Spacer().frame(height: 10)

                Text(secondaryLine)
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundStyle(Color.black.opacity(0.54))
                    .lineLimit(1)
                    .frame(width: 340)

                Spacer().frame(height: 28)

                HStack(spacing: 12) {
                    Text(elapsedText)
                    islandProgress
                    Text(remainingText)
                }
                .font(.system(size: 20, weight: .bold, design: .default))
                .foregroundStyle(Color.white.opacity(0.92))
                .monospacedDigit()

                Spacer().frame(height: 24)

                HStack(spacing: 44) {
                    islandControl("backward.end.fill", size: 38) { nowPlaying.previous() }
                    islandControl(nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 46) { nowPlaying.playPause() }
                    islandControl("forward.end.fill", size: 38) { nowPlaying.next() }
                }

                Spacer(minLength: 0)
            }
            .frame(width: 420, height: 650)

            EqualizerBars(active: nowPlaying.isPlaying, barColor: Color.white.opacity(0.46), compact: false)
                .frame(width: 58, height: 62)
                .padding(.top, 516)
                .padding(.trailing, 28)

            SettingsMenuButton(
                onSelectSize: onSelectSize,
                onQuit: onQuit,
                triggerSize: 28,
                glyphSize: 13,
                triggerFill: Color.white.opacity(0.16),
                triggerStroke: Color.white.opacity(0.24),
                triggerForeground: Color.white.opacity(0.96)
            )
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
    }

    private var islandProgress: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(height: 5)
                Capsule()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: max(4, width * progressFraction), height: 5)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(width: 220, height: 14)
    }

    // MARK: - Shared pieces

    private func artwork(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let art = nowPlaying.track.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
            } else {
                SmallWidgetDefaultArtwork()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 6)
    }

    private func islandControl(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.96))
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleExpanded() {
        let next = !expanded
        onExpansionChange(next)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            expanded = next
        }
    }

    private var compactTitle: String {
        if nowPlaying.track.isEmpty { return "VinylPod" }
        let title = nowPlaying.track.title.isEmpty ? "Unknown Title" : nowPlaying.track.title
        let artist = nowPlaying.track.artist
        return artist.isEmpty ? title : "\(artist) • \(title)"
    }

    private var primaryLine: String {
        if nowPlaying.track.isEmpty { return "Music is stopped." }
        return nowPlaying.track.title.isEmpty ? "Unknown Title" : nowPlaying.track.title
    }

    private var secondaryLine: String {
        if nowPlaying.track.isEmpty { return "Please play music on Spotify or Music" }
        return nowPlaying.track.artist.isEmpty ? nowPlaying.track.source.displayName : nowPlaying.track.artist
    }

    private var elapsedText: String {
        nowPlaying.track.isEmpty ? "00:00" : ProgressBarView.timeString(nowPlaying.position)
    }

    private var remainingText: String {
        if nowPlaying.track.isEmpty { return "-00:00" }
        return "-" + ProgressBarView.timeString(max(nowPlaying.duration - nowPlaying.position, 0))
    }

    private var progressFraction: CGFloat {
        guard nowPlaying.duration > 0 else { return 0 }
        return CGFloat(min(max(nowPlaying.position / nowPlaying.duration, 0), 1))
    }
}

private struct EqualizerBars: View {
    var active: Bool
    var barColor: Color
    var compact: Bool

    var body: some View {
        // Cap at 30fps and PAUSE when not playing — this view is always on
        // screen when the notch is enabled, and at full display refresh it was
        // a permanent idle CPU/GPU drain even while paused.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: compact ? 3 : 8) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(barColor)
                        .frame(
                            width: compact ? 3 : 10,
                            height: barHeight(index: index, time: t)
                        )
                }
            }
        }
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        let base = compact ? CGFloat(8 + index * 2) : CGFloat(38 + index * 5)
        guard active else { return base * 0.72 }
        let phase = time * 2.2 + Double(index) * 0.92
        let wave = (sin(phase) + 1) / 2
        let minHeight = compact ? CGFloat(8) : CGFloat(34)
        let maxHeight = compact ? CGFloat(18) : CGFloat(72)
        return minHeight + CGFloat(wave) * (maxHeight - minHeight)
    }
}

private struct DynamicIslandBump: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.midX
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: mid - 10, y: rect.maxY * 0.38),
            control1: CGPoint(x: mid - 28, y: rect.maxY),
            control2: CGPoint(x: mid - 21, y: rect.maxY * 0.48)
        )
        path.addCurve(
            to: CGPoint(x: mid + 10, y: rect.maxY * 0.38),
            control1: CGPoint(x: mid - 4, y: rect.minY),
            control2: CGPoint(x: mid + 4, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control1: CGPoint(x: mid + 21, y: rect.maxY * 0.48),
            control2: CGPoint(x: mid + 28, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
