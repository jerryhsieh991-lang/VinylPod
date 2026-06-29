import SwiftUI
import AppKit

/// A spinning vinyl record with the album art on the center label — shown when
/// the user picks the **Vinyl** style in settings (vs the flat **Image** card).
///
/// It fills whatever frame it's given (drawing the largest centered disc), spins
/// while `isSpinning` is true, and preserves its angle across pause/resume so it
/// doesn't jump. Self-contained: no external theme tokens, purely decorative
/// (`allowsHitTesting(false)` so the X / controls underneath still work).
struct VinylDiskView: View {

    let artwork: NSImage?
    var isSpinning: Bool
    var showTonearm: Bool = true

    /// Seconds per full revolution (~33⅓ rpm feel, a touch slowed for calm).
    private let secondsPerRev: Double = 4.0

    @VPState private var accumulatedAngle: Double = 0
    @VPState private var spinStart: Date = Date()

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                disc(size)

                // Only the grooves + label rotate; the disc body and spindle are static.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isSpinning)) { ctx in
                    let elapsed = isSpinning ? ctx.date.timeIntervalSince(spinStart) : 0
                    let angle = (accumulatedAngle + elapsed / secondsPerRev * 360.0)
                        .truncatingRemainder(dividingBy: 360.0)
                    rotatingCluster(size)
                        .rotationEffect(.degrees(angle))
                }
                .frame(width: size, height: size)

                spindle(size)
                if showTonearm && size >= 120 { tonearm(size) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onChange(of: isSpinning) { now in
            if now {
                spinStart = Date()
            } else {
                let elapsed = Date().timeIntervalSince(spinStart)
                accumulatedAngle = (accumulatedAngle + elapsed / secondsPerRev * 360.0)
                    .truncatingRemainder(dividingBy: 360.0)
            }
        }
        .onAppear { if isSpinning { spinStart = Date() } }
        .allowsHitTesting(false)
    }

    // MARK: - Static disc body

    private func disc(_ size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(white: 0.13), location: 0.0),
                        .init(color: Color(white: 0.06), location: 0.55),
                        .init(color: .black, location: 1.0)
                    ]),
                    center: .init(x: 0.42, y: 0.40),
                    startRadius: size * 0.04,
                    endRadius: size * 0.55
                )
            )
            .overlay(Circle().stroke(Color.white.opacity(0.05), lineWidth: 0.8))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.45), radius: size * 0.03, y: size * 0.012)
    }

    private func spindle(_ size: CGFloat) -> some View {
        Circle()
            .fill(Color(white: 0.05))
            .frame(width: size * 0.03, height: size * 0.03)
            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: - Rotating cluster (grooves + center label)

    private func rotatingCluster(_ size: CGFloat) -> some View {
        ZStack {
            grooves(size)
            centerLabel(size)
        }
        .frame(width: size, height: size)
    }

    private func grooves(_ size: CGFloat) -> some View {
        Canvas { ctx, sz in
            let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let outer = min(sz.width, sz.height) / 2
            let inner = outer * 0.30
            let count = 40
            for i in 0..<count {
                let t = CGFloat(i) / CGFloat(count - 1)
                let r = inner + (outer - inner) * t
                let path = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                                  width: r * 2, height: r * 2))
                let alpha = 0.05 + (1.0 - Double(t)) * 0.04
                ctx.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: 0.5)
            }
        }
    }

    private func centerLabel(_ size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.92))
                .frame(width: size * 0.40, height: size * 0.40)
                .shadow(color: .black.opacity(0.4), radius: size * 0.02, y: 1)

            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Circle().fill(Color(white: 0.82))
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.08, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.55))
                    }
                }
            }
            .frame(width: size * 0.38, height: size * 0.38)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    // MARK: - Tonearm (lifts off when paused, drops on when playing)

    private func tonearm(_ size: CGFloat) -> some View {
        let rotation: Double = isSpinning ? 0 : -14
        let pivot = CGPoint(x: size * 0.98, y: size * 0.02)
        let drop  = CGPoint(x: size * 0.60, y: size * 0.30)

        return ZStack {
            Path { p in
                p.move(to: pivot)
                p.addLine(to: drop)
            }
            .stroke(Color(white: 0.85), style: StrokeStyle(lineWidth: max(2, size * 0.018), lineCap: .round))
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)

            Capsule()
                .fill(Color(white: 0.95))
                .frame(width: size * 0.12, height: size * 0.045)
                .rotationEffect(.degrees(-32))
                .position(drop)

            Circle()
                .fill(Color(white: 0.9))
                .frame(width: size * 0.10, height: size * 0.10)
                .position(pivot)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation), anchor: UnitPoint(x: 0.98, y: 0.02))
        .animation(.spring(response: 0.55, dampingFraction: 0.7), value: isSpinning)
    }
}
