import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// THE entry view required by the contract. Renders the correct layout for a
/// given `WindowMode` over the shared static landscape, handles empty state,
/// and accepts drag-and-dropped audio files.
///
/// Design rules honored here:
///   • The landscape is always at the back and never reacts to the track.
///   • Only small accents use `settings.accentColor`.
///   • Track changes / empty↔playing use `VPTheme.fade`. No spinners anywhere.
///   • Desktop-widget controls are hidden at rest and fade in on hover.
struct ModeContentView: View {

    let mode: WindowMode

    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var settings: AppSettings

    /// True while a valid drag is hovering the window (drives the highlight).
    @VPState private var isDropTargeted = false

    init(mode: WindowMode) {
        self.mode = mode
    }

    var body: some View {
        ZStack {
            // Static landscape behind every mode.
            LandscapeBackground()

            // Mode-specific content.
            content
                // Smoothly cross-fade whenever the track identity changes.
                .animation(VPTheme.fade, value: nowPlaying.track)
                .animation(VPTheme.fade, value: nowPlaying.isPlaying)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Non-widget modes are rounded floating panels; the widget fills the
        // screen with square corners.
        .clipShape(RoundedRectangle(
            cornerRadius: mode == .desktopWidget ? 0 : VPTheme.radiusLarge,
            style: .continuous
        ))
        // Subtle highlight border while a drop is in progress.
        .overlay(dropHighlight)
        // Drag & drop: resolve file URLs and hand them to the shared service.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted.animation(VPTheme.fade)) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Per-mode content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .small:          smallContent
        case .normal:         normalContent
        case .large:          largeContent
        case .desktopWidget:  widgetContent
        }
    }

    /// Small: just the play/pause control over the landscape, on a small glass
    /// backing. Minimal — no text.
    private var smallContent: some View {
        TransportControls(playSize: 64)
            // Hide the skip buttons in the tiniest mode by clipping width.
            .frame(width: 64, height: 64, alignment: .center)
            .clipped()
            .padding(18)
            .glassBackground(cornerRadius: VPTheme.radius)
            .padding(20)
    }

    /// Normal: a glass panel with title/artist, progress, and transport.
    private var normalContent: some View {
        VStack(spacing: 14) {
            if nowPlaying.track.isEmpty {
                emptyHint
            } else {
                trackHeader(titleSize: 15, artistSize: 12, alignment: .center)
                ProgressBarView()
                TransportControls(playSize: 46)
                    .padding(.top, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: 340)
        .glassBackground(cornerRadius: VPTheme.radius)
        .padding(18)
    }

    /// Large: album artwork, full metadata + source chip, progress, transport.
    private var largeContent: some View {
        VStack(spacing: 20) {
            artwork(size: 260)

            if nowPlaying.track.isEmpty {
                emptyHint
            } else {
                VStack(spacing: 6) {
                    trackHeader(titleSize: 20, artistSize: 14, alignment: .center)
                    if !nowPlaying.track.album.isEmpty {
                        Text(nowPlaying.track.album)
                            .font(VPTheme.body(12))
                            .foregroundStyle(VPTheme.textMuted)
                            .lineLimit(1)
                    }
                    sourceChip
                        .padding(.top, 4)
                }

                ProgressBarView()
                TransportControls(playSize: 60)
                    .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: 380)
        .glassBackground(cornerRadius: VPTheme.radiusLarge)
        .padding(24)
    }

    /// Desktop widget: visual-first. A large calm composition (the artwork if
    /// present, else the bare landscape with a tasteful caption). The controls
    /// live in a glass overlay that is HIDDEN at rest and FADES IN on hover.
    private var widgetContent: some View {
        WidgetCanvas()
    }

    // MARK: - Shared pieces

    /// Album artwork rounded rect, or a `music.note` placeholder.
    private func artwork(size: CGFloat) -> some View {
        Group {
            if let art = nowPlaying.track.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    VPTheme.panel
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.30, weight: .light))
                        .foregroundStyle(VPTheme.textMuted)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: VPTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VPTheme.radius, style: .continuous)
                .strokeBorder(VPTheme.glassStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.30), radius: 12, y: 6)
    }

    /// Title + artist stack.
    private func trackHeader(titleSize: CGFloat,
                             artistSize: CGFloat,
                             alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(nowPlaying.track.title.isEmpty ? "Unknown Title" : nowPlaying.track.title)
                .font(VPTheme.title(titleSize))
                .foregroundStyle(VPTheme.textPrimary)
                .lineLimit(1)
            if !nowPlaying.track.artist.isEmpty {
                Text(nowPlaying.track.artist)
                    .font(VPTheme.body(artistSize))
                    .foregroundStyle(VPTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    /// Small pill showing where this track is coming from.
    private var sourceChip: some View {
        let source = nowPlaying.track.source
        return HStack(spacing: 5) {
            Image(systemName: source.sfSymbol)
            Text(source.displayName)
        }
        .font(VPTheme.caption())
        .foregroundStyle(VPTheme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(VPTheme.panel))
        .overlay(Capsule().strokeBorder(VPTheme.glassStroke, lineWidth: 1))
    }

    /// Faint centered hint shown in `.normal` / `.large` empty state.
    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 26, weight: .light))
            Text("Drag a song here")
                .font(VPTheme.body(13))
        }
        .foregroundStyle(VPTheme.textMuted)
        .padding(.vertical, 8)
        .transition(.opacity)
    }

    /// Highlighted border drawn while a file is being dragged over the window.
    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(
                cornerRadius: mode == .desktopWidget ? 0 : VPTheme.radiusLarge,
                style: .continuous
            )
            .strokeBorder(settings.accentColor.opacity(0.9), lineWidth: 2)
            .background(
                RoundedRectangle(
                    cornerRadius: mode == .desktopWidget ? 0 : VPTheme.radiusLarge,
                    style: .continuous
                )
                .fill(settings.accentColor.opacity(0.06))
            )
            .transition(.opacity)
        }
    }

    // MARK: - Drop handling

    /// Resolves dropped `NSItemProvider`s into file URLs and forwards them to
    /// the shared NowPlaying service (per the contract: `AppEnvironment.shared`).
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            AppEnvironment.shared.nowPlaying.load(urls: urls)
        }
        return true
    }
}

// MARK: - Desktop widget canvas (hover-reveal controls)

/// The visual-first widget surface. The composition fills the screen; the
/// transport + progress overlay is invisible at rest and gently fades in when
/// the mouse enters the widget (`.onHover` → `controlsVisible` → `.opacity`
/// animated with `VPTheme.fade`), then fades back out on exit.
private struct WidgetCanvas: View {

    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var settings: AppSettings

    /// Drives the hover-reveal. Starts hidden so the resting state is pure calm.
    @VPState private var controlsVisible = false

    var body: some View {
        ZStack {
            // Big calm composition. If we have artwork, show it large and
            // softened; otherwise the bare landscape (already behind us) reads
            // through and we keep the surface clear.
            if let art = nowPlaying.track.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .overlay(VPTheme.scrim)               // keep caption legible
                    .clipped()
            }

            // Tasteful now-playing caption pinned bottom-leading, always faint.
            if !nowPlaying.track.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(nowPlaying.track.title)
                                .font(VPTheme.title(28))
                                .foregroundStyle(VPTheme.textPrimary)
                            if !nowPlaying.track.artist.isEmpty {
                                Text(nowPlaying.track.artist)
                                    .font(VPTheme.body(18))
                                    .foregroundStyle(VPTheme.textSecondary)
                            }
                        }
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                        Spacer()
                    }
                    .padding(40)
                }
            }

            // Hover-reveal control cluster, centered in a glass panel.
            VStack(spacing: 18) {
                if !nowPlaying.track.isEmpty {
                    ProgressBarView()
                        .frame(maxWidth: 420)
                }
                TransportControls(playSize: 64)
            }
            .padding(28)
            .glassBackground(cornerRadius: VPTheme.radiusLarge)
            .frame(maxWidth: 480)
            // Invisible at rest; revealed on hover.
            .opacity(controlsVisible ? 1 : 0)
            .animation(VPTheme.fade, value: controlsVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // Mouse enter → reveal; exit → fade away. This is the entire
        // hover-reveal mechanism for the desktop widget.
        .onHover { inside in
            controlsVisible = inside
        }
    }
}
