import SwiftUI
import AppKit

/// Primary artwork visualizer surface. This replaces the old large-widget
/// inline vinyl/image branch with a renderer switch that can grow with the
/// rebrand without duplicating the surrounding widget chrome.
struct MusicVisualizerContainerView: View {
    let style: VinylStyle
    let artwork: NSImage?
    let isPlaying: Bool
    let palette: AlbumColorPalette

    var body: some View {
        ZStack {
            switch style {
            case .vinyl:
                VinylDiskView(artwork: artwork, isSpinning: isPlaying)

            case .cassette:
                CassetteVisualizerView(
                    artwork: artwork,
                    isPlaying: isPlaying,
                    palette: palette
                )

            case .liquidDisc:
                LiquidDiscVisualizerView(
                    artwork: artwork,
                    isPlaying: isPlaying,
                    palette: palette
                )
            }
        }
        .animation(VPTheme.liquid, value: style)
        .animation(VPTheme.liquid, value: palette)
        .allowsHitTesting(false)
    }
}

private struct CassetteVisualizerView: View {
    let artwork: NSImage?
    let isPlaying: Bool
    let palette: AlbumColorPalette

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let width = side
            let height = side * 0.66
            let corner = side * 0.055
            let accent = palette.vibrant.color
            let bodyColor = palette.shadow.color
            let labelColor = palette.muted.color

            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                bodyColor.opacity(0.94),
                                Color.black.opacity(0.88),
                                palette.dominant.color.opacity(0.74)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.24), radius: side * 0.035, y: side * 0.018)

                RoundedRectangle(cornerRadius: side * 0.026, style: .continuous)
                    .fill(labelColor.opacity(0.28))
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                accent.opacity(0.16),
                                Color.black.opacity(0.20)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: width * 0.74, height: height * 0.28)
                    .offset(y: -height * 0.22)

                tapeWindow(width: width, height: height)

                HStack(spacing: width * 0.19) {
                    CassetteHubView(
                        isPlaying: isPlaying,
                        direction: 1,
                        accent: accent,
                        size: height * 0.32
                    )
                    CassetteHubView(
                        isPlaying: isPlaying,
                        direction: -1,
                        accent: accent,
                        size: height * 0.32
                    )
                }
                .offset(y: height * 0.02)

                bottomNotches(width: width, height: height, accent: accent)
                screwHeads(width: width, height: height)

                artworkBadge(size: side * 0.19)
                    .offset(x: width * 0.26, y: -height * 0.23)
            }
            .frame(width: width, height: height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func tapeWindow(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height * 0.09, style: .continuous)
            .fill(Color.black.opacity(0.42))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
                    .padding(width * 0.025)
            )
            .overlay(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.68),
                                palette.vibrant.color.opacity(0.20),
                                Color.black.opacity(0.72)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 0.54, height: height * 0.08)
            )
            .frame(width: width * 0.69, height: height * 0.34)
            .offset(y: height * 0.02)
    }

    private func bottomNotches(width: CGFloat, height: CGFloat, accent: Color) -> some View {
        HStack(spacing: width * 0.08) {
            RoundedRectangle(cornerRadius: height * 0.025, style: .continuous)
                .fill(Color.black.opacity(0.46))
                .frame(width: width * 0.13, height: height * 0.07)
            Circle()
                .fill(accent.opacity(0.34))
                .frame(width: height * 0.055, height: height * 0.055)
            RoundedRectangle(cornerRadius: height * 0.025, style: .continuous)
                .fill(Color.black.opacity(0.46))
                .frame(width: width * 0.13, height: height * 0.07)
        }
        .offset(y: height * 0.32)
    }

    private func screwHeads(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.13))
                    .frame(width: height * 0.045, height: height * 0.045)
                    .overlay(Circle().stroke(Color.black.opacity(0.36), lineWidth: 0.6))
                    .position(
                        x: index.isMultiple(of: 2) ? width * 0.08 : width * 0.92,
                        y: index < 2 ? height * 0.10 : height * 0.90
                    )
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func artworkBadge(size: CGFloat) -> some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .frame(width: size, height: size)
                    .background(palette.vibrant.color.opacity(0.26))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        )
    }
}

private struct CassetteHubView: View {
    let isPlaying: Bool
    let direction: Double
    let accent: Color
    let size: CGFloat

    @VPState private var rotation = 0.0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.52))
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))

            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? accent.opacity(0.78) : Color.white.opacity(0.58))
                    .frame(width: size * 0.075, height: size * 0.32)
                    .offset(y: -size * 0.16)
                    .rotationEffect(.degrees(Double(index) * 60))
            }

            Circle()
                .fill(Color.black.opacity(0.86))
                .frame(width: size * 0.25, height: size * 0.25)
                .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.7))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation * direction))
        .onAppear(perform: syncAnimation)
        .onChange(of: isPlaying) { _ in syncAnimation() }
    }

    private func syncAnimation() {
        if isPlaying {
            rotation = 0
            withAnimation(.linear(duration: 1.18).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.24)) {
                rotation = rotation.truncatingRemainder(dividingBy: 360)
            }
        }
    }
}

private struct LiquidDiscVisualizerView: View {
    let artwork: NSImage?
    let isPlaying: Bool
    let palette: AlbumColorPalette

    private var tokens: [RGBColorToken] {
        palette.liquidDiscTokens
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let rect = CGRect(
                x: (geo.size.width - side) / 2,
                y: (geo.size.height - side) / 2,
                width: side,
                height: side
            )

            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
                    let phase = isPlaying ? timeline.date.timeIntervalSinceReferenceDate * 0.18 : 0

                    Canvas { context, size in
                        drawLiquidDisc(
                            context: &context,
                            canvasSize: size,
                            rect: rect,
                            phase: phase,
                            side: side
                        )
                    }
                }

                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side * 0.30, height: side * 0.30)
                        .clipShape(Circle())
                        .opacity(0.28)
                        .blur(radius: side * 0.018)
                        .blendMode(.plusLighter)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .shadow(color: tokens[3].color.opacity(0.38), radius: side * 0.08, y: side * 0.035)
        }
    }

    private func drawLiquidDisc(
        context: inout GraphicsContext,
        canvasSize: CGSize,
        rect: CGRect,
        phase: TimeInterval,
        side: CGFloat
    ) {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let base = Path(ellipseIn: rect.insetBy(dx: side * 0.015, dy: side * 0.015))

        context.fill(
            base,
            with: .radialGradient(
                Gradient(colors: [
                    tokens[2].color.opacity(0.98),
                    tokens[0].color.opacity(0.84),
                    tokens[1].color.opacity(0.72),
                    tokens[3].color.opacity(0.92)
                ]),
                center: center,
                startRadius: side * 0.02,
                endRadius: side * 0.58
            )
        )

        for index in tokens.indices {
            let angle = phase + Double(index) * 1.37
            let drift = CGFloat(index + 1) * 0.033
            let x = center.x + cos(angle) * side * (0.15 + drift)
            let y = center.y + sin(angle * 0.84) * side * (0.13 + drift)
            let blobSize = side * (0.38 - CGFloat(index) * 0.024)
            let blobRect = CGRect(
                x: x - blobSize / 2,
                y: y - blobSize / 2,
                width: blobSize,
                height: blobSize
            )

            var layer = context
            layer.blendMode = .plusLighter
            layer.addFilter(.blur(radius: side * 0.042))
            layer.fill(
                Path(ellipseIn: blobRect),
                with: .radialGradient(
                    Gradient(colors: [
                        tokens[index].color.opacity(index == 3 ? 0.44 : 0.74),
                        tokens[index].color.opacity(0.08),
                        Color.clear
                    ]),
                    center: CGPoint(x: x, y: y),
                    startRadius: 1,
                    endRadius: blobSize * 0.55
                )
            )
        }

        var highlight = context
        highlight.blendMode = .screen
        highlight.addFilter(.blur(radius: side * 0.012))
        highlight.stroke(
            Path(ellipseIn: rect.insetBy(dx: side * 0.095, dy: side * 0.12)),
            with: .color(Color.white.opacity(0.15)),
            lineWidth: side * 0.035
        )
    }
}
