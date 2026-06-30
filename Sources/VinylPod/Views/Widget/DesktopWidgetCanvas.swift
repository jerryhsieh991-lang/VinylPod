import SwiftUI
import AppKit

/// Full-screen desktop widget: timer ecosystem, display picker, music controls,
/// and animated vinyl deck. This is intentionally independent from the floating
/// card widgets so the desktop composition can use a full-screen layout grid.
@MainActor
struct DesktopWidgetCanvas: View {

    var onSelectSize: (WindowMode) -> Void
    var onQuit: () -> Void

    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var settings: AppSettings

    @VPState private var countdownDuration: TimeInterval = 400
    @VPState private var countdownStartedAt = Date()
    @VPState private var timerMode: DesktopTimerMode = .countdown
    @VPState private var showCountdownEditor = false
    @VPState private var showDisplayPicker = false
    @VPState private var showTimerMenu = false
    @VPState private var countdownDraft = "10"
    @VPState private var displayName = NSScreen.main?.localizedName ?? "Built-in Retina Display"
    @VPState private var tonearmIsWhite = false
    @VPState private var recordRotation = 0.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                desktopBackground

                desktopChrome
                    .padding(.top, 18)
                    .padding(.leading, 20)
                    .zIndex(20)

                if !showCountdownEditor {
                    countdownBlock
                        .padding(.top, max(108, geo.size.height * 0.14))
                        .padding(.leading, max(60, geo.size.width * 0.055))
                        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .topLeading)))
                        .zIndex(4)

                    timerMenuButton
                        .position(
                            x: max(430, geo.size.width * 0.055 + 450),
                            y: max(108, geo.size.height * 0.14) + 12
                        )
                        .transition(.opacity)
                        .zIndex(28)
                }

                playbackBlock
                    .padding(.leading, max(60, geo.size.width * 0.055))
                    .padding(.bottom, max(86, geo.size.height * 0.13))
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
                    .zIndex(5)

                vinylDeck(in: geo.size)
                    .zIndex(3)

                if showCountdownEditor {
                    countdownEditor
                        .position(x: min(max(360, geo.size.width * 0.28), 560), y: 142)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .zIndex(30)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .animation(.easeInOut(duration: 0.18), value: showCountdownEditor)
        }
        .onAppear { syncRecordAnimation() }
        .onChange(of: nowPlaying.isPlaying) { _ in syncRecordAnimation() }
    }

    private var desktopBackground: some View {
        let palette = settings.albumPalette
        let dominant = palette.dominant.color
        let vibrant = palette.vibrant.color
        let muted = palette.muted.color
        let shadow = palette.shadow.color

        return ZStack {
            if nowPlaying.track.isEmpty, let image = DefaultArtworkAsset.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 18)
                    .scaleEffect(1.08)
                    .overlay(Color.black.opacity(0.10))
            }

            LinearGradient(
                colors: [
                    vibrant.opacity(nowPlaying.track.isEmpty ? 0.62 : 0.76),
                    muted.opacity(nowPlaying.track.isEmpty ? 0.48 : 0.60),
                    shadow.opacity(nowPlaying.track.isEmpty ? 0.70 : 0.82)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(nowPlaying.track.isEmpty ? 0.34 : 0.25),
                    Color.clear
                ],
                center: UnitPoint(x: 0.34, y: 0.20),
                startRadius: 30,
                endRadius: 560
            )

            RadialGradient(
                colors: [
                    dominant.opacity(nowPlaying.track.isEmpty ? 0.50 : 0.64),
                    Color.clear
                ],
                center: UnitPoint(x: 0.48, y: 0.18),
                startRadius: 30,
                endRadius: 460
            )

            settings.accentColor
                .opacity(nowPlaying.track.isEmpty ? 0.28 : 0.24)
                .blendMode(.overlay)

            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(nowPlaying.track.isEmpty ? 0.18 : 0.12)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    vibrant.opacity(0.18),
                    shadow.opacity(0.13)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .blendMode(.overlay)
        }
        .ignoresSafeArea()
        .animation(VPTheme.liquid, value: settings.albumPalette)
    }

    private var desktopChrome: some View {
        HStack(spacing: 18) {
            chromeButton("xmark.circle.fill") { onQuit() }
            timerShortcutButton
            displayPickerButton
            SettingsMenuButton(
                onSelectSize: onSelectSize,
                onQuit: onQuit,
                triggerSize: 16,
                glyphSize: 8,
                triggerFill: Color.white.opacity(0.18),
                triggerStroke: Color.clear,
                triggerForeground: Color.white.opacity(0.82)
            )
        }
    }

    private var timerShortcutButton: some View {
        Button {
            timerMode = timerMode == .countdown ? .time : .countdown
            resetCountdown()
        } label: {
            Image(systemName: "clock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.74))
        }
        .buttonStyle(.plain)
    }

    private var displayPickerButton: some View {
        Button {
            showDisplayPicker.toggle()
        } label: {
            Image(systemName: "display")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.74))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDisplayPicker, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                displayRow("Built-in Retina Display")
                displayRow("SB220Q")
            }
            .padding(.vertical, 7)
            .frame(width: 180)
            .background(.ultraThinMaterial)
        }
    }

    private func chromeButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.74))
        }
        .buttonStyle(.plain)
    }

    private func displayRow(_ title: String) -> some View {
        Button {
            displayName = title
        } label: {
            HStack(spacing: 8) {
                Image(systemName: displayName == title ? "checkmark" : "")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 13)
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                Spacer()
            }
            .foregroundStyle(Color.black.opacity(0.86))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private var countdownBlock: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let parts = timerParts(at: context.date)
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text(parts.main)
                    .font(.system(size: 138, weight: .heavy, design: .default))
                    .tracking(-8)
                    .monospacedDigit()
                    .foregroundStyle(Color.white)

                if parts.secondsVisible {
                    Text(parts.seconds)
                        .font(.system(size: 45, weight: .heavy, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                        .baselineOffset(3)
                }
            }
        }
    }

    private var timerMenuButton: some View {
        Button {
            showTimerMenu.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color(red: 0.63, green: 0.35, blue: 0.60))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.white.opacity(0.82)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTimerMenu, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                timerMenuRow("Time", checked: timerMode == .time) {
                    timerMode = .time
                    showTimerMenu = false
                }
                timerMenuRow("Countdown", checked: timerMode == .countdown) {
                    timerMode = .countdown
                    resetCountdown()
                    showTimerMenu = false
                }
                Divider().padding(.horizontal, 14).padding(.vertical, 6)
                timerMenuRow("Countdown Settings", checked: false) {
                    countdownDraft = String(max(1, Int(countdownDuration / 60)))
                    showCountdownEditor = true
                    showTimerMenu = false
                }
            }
            .padding(.vertical, 8)
            .frame(width: 174, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(.ultraThinMaterial)
        }
    }

    private func timerMenuRow(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: checked ? "checkmark" : "")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 13)
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                Spacer()
            }
            .foregroundStyle(Color.black.opacity(0.86))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private var countdownEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Countdown time")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                Spacer()
                Button {
                    showCountdownEditor = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.white.opacity(0.90))
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField("", text: $countdownDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(Color.black)
                    .frame(width: 190)
                    .onSubmit { applyCountdownDraft() }

                Text("mins")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.48))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 342, height: 89, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
        }
        .padding(18)
        .frame(width: 390)
    }

    private var playbackBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(primaryLine)
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(secondaryLine)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 48) {
                controlButton("backward.fill", size: 22) { nowPlaying.previous() }
                controlButton(nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 26) { nowPlaying.playPause() }
                controlButton("forward.fill", size: 22) { nowPlaying.next() }
            }
            .padding(.top, 15)

            if settings.showProgress {
                desktopProgress
                    .frame(width: 410)
            }
        }
        .frame(width: 620, alignment: .leading)
    }

    private var desktopProgress: some View {
        HStack(spacing: 6) {
            Text(nowPlaying.track.isEmpty ? "00:00" : ProgressBarView.timeString(nowPlaying.position))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 46, alignment: .leading)
            Capsule()
                .fill(Color.white.opacity(0.54))
                .frame(width: 286, height: 3)
            Text(nowPlaying.track.isEmpty ? "-00:00" : "-" + ProgressBarView.timeString(max(nowPlaying.duration - nowPlaying.position, 0)))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 66, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Color.white)
        .monospacedDigit()
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 34)
        }
        .buttonStyle(.plain)
    }

    private func vinylDeck(in size: CGSize) -> some View {
        let recordSize = min(560, size.width * 0.285)
        let coverSize = min(560, size.width * 0.285)

        return ZStack {
            coverArt
                .frame(width: coverSize, height: coverSize)
                .rotationEffect(.degrees(-8))
                .offset(x: -250, y: 36)
                .opacity(0.80)

            vinylRecord
                .frame(width: recordSize, height: recordSize)
                .rotationEffect(.degrees(recordRotation))
                .offset(x: 112, y: 22)

            tonearm
                .frame(width: 250, height: 520)
                .offset(x: min(500, size.width * 0.255), y: -300)
                .rotationEffect(.degrees(nowPlaying.isPlaying ? 10 : -8), anchor: .top)
                .animation(.spring(response: 0.65, dampingFraction: 0.78), value: nowPlaying.isPlaying)
                .onTapGesture { tonearmIsWhite.toggle() }
        }
        .frame(width: size.width, height: size.height, alignment: .center)
        .position(x: size.width * 0.625, y: size.height * 0.465)
    }

    private var coverArt: some View {
        Group {
            if let art = nowPlaying.track.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
            } else {
                SmallWidgetDefaultArtwork()
            }
        }
        .clipped()
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 7)
    }

    private var vinylRecord: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.11, green: 0.11, blue: 0.11),
                            Color.black.opacity(0.98),
                            Color.black
                        ],
                        center: UnitPoint(x: 0.37, y: 0.28),
                        startRadius: 12,
                        endRadius: 330
                    )
                )
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.075),
                                    Color.clear,
                                    Color.black.opacity(0.36)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.plusLighter)
                )
                .shadow(color: .black.opacity(0.36), radius: 18, x: 0, y: 14)

            ForEach(0..<42, id: \.self) { idx in
                Circle()
                    .stroke(
                        Color.white.opacity(idx.isMultiple(of: 6) ? 0.050 : 0.023),
                        lineWidth: idx.isMultiple(of: 6) ? 0.75 : 0.42
                    )
                    .padding(CGFloat(idx) * 5.6 + 10)
            }

            ForEach(0..<22, id: \.self) { idx in
                Circle()
                    .stroke(Color.black.opacity(idx.isMultiple(of: 3) ? 0.42 : 0.24), lineWidth: 0.55)
                    .padding(CGFloat(idx) * 8.9 + 18)
            }

            Circle()
                .fill(Color.black.opacity(0.86))
                .frame(width: 286, height: 286)
                .shadow(color: .black.opacity(0.56), radius: 22, x: 0, y: 0)

            Group {
                if let art = nowPlaying.track.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                } else {
                    SmallWidgetDefaultArtwork()
                }
            }
            .frame(width: 238, height: 238)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
        }
    }

    private var tonearm: some View {
        let armColor = tonearmIsWhite ? Color.white : Color.black.opacity(0.88)
        return ZStack(alignment: .top) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [armColor.opacity(0.95), Color.black.opacity(tonearmIsWhite ? 0.08 : 0.92)],
                        center: .topTrailing,
                        startRadius: 4,
                        endRadius: 74
                    )
                )
                .frame(width: 104, height: 104)
                .overlay(Circle().stroke(Color.white.opacity(tonearmIsWhite ? 0.55 : 0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.34), radius: 10, x: 0, y: 8)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(armColor)
                .frame(width: 10, height: 390)
                .offset(y: 68)
                .shadow(color: .black.opacity(0.24), radius: 6, x: 4, y: 5)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(armColor)
                .frame(width: 34, height: 88)
                .rotationEffect(.degrees(-8))
                .offset(x: 66, y: 420)
                .shadow(color: .black.opacity(0.28), radius: 7, x: 0, y: 6)
        }
    }

    private func timerParts(at date: Date) -> DesktopTimerParts {
        switch timerMode {
        case .time:
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            return DesktopTimerParts(
                main: String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0),
                seconds: "",
                secondsVisible: false
            )
        case .countdown:
            let elapsed = date.timeIntervalSince(countdownStartedAt)
            let remaining = max(0, countdownDuration - elapsed)
            let total = Int(remaining.rounded(.down))
            let fractional = Int(((remaining - floor(remaining)) * 100).rounded(.down))
            return DesktopTimerParts(
                main: String(format: "%02d:%02d", total / 60, total % 60),
                seconds: String(format: "%02d", fractional),
                secondsVisible: true
            )
        }
    }

    private var primaryLine: String {
        if nowPlaying.track.isEmpty { return "Music is stopped." }
        return nowPlaying.track.title.isEmpty ? "Unknown Title" : nowPlaying.track.title
    }

    private var secondaryLine: String {
        if nowPlaying.track.isEmpty { return "Drop a track here or connect a source." }
        return nowPlaying.track.artist.isEmpty ? nowPlaying.track.source.displayName : nowPlaying.track.artist
    }

    private func resetCountdown() {
        countdownStartedAt = Date()
    }

    private func applyCountdownDraft() {
        let minutes = max(1, min(999, Int(countdownDraft) ?? 10))
        countdownDuration = TimeInterval(minutes * 60)
        resetCountdown()
        showCountdownEditor = false
    }

    private func syncRecordAnimation() {
        if nowPlaying.isPlaying {
            recordRotation = 0
            withAnimation(.linear(duration: 18.0).repeatForever(autoreverses: false)) {
                recordRotation = 360
            }
        } else {
            withAnimation(.linear(duration: 0.16)) {
                recordRotation = recordRotation.truncatingRemainder(dividingBy: 360)
            }
        }
    }
}

private enum DesktopTimerMode {
    case time
    case countdown
}

private struct DesktopTimerParts {
    var main: String
    var seconds: String
    var secondsVisible: Bool
}
