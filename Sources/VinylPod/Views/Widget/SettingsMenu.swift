import SwiftUI
import AppKit

/// The "three-dots" settings menu for the compact glass widget.
///
/// Renders a small `ellipsis` glass trigger; clicking it floats a long,
/// scrollable glass dropdown above everything else (anchored top-trailing
/// under the trigger). The hierarchy mirrors the reference screenshots and the
/// "Three-dots Settings dropdown" section of `design_system.md` exactly.
///
/// CLT note: uses `@VPState` (typealias to `SwiftUI.State`) per the project's
/// toolchain rule — `@State`'s macro plugin is unavailable under Command Line
/// Tools.
@MainActor
struct SettingsMenuButton: View {

    @EnvironmentObject var settings: AppSettings

    /// Called when a size row is chosen (parent also persists `settings.windowMode`).
    var onSelectSize: (WindowMode) -> Void
    /// Called when the "Quit" row is chosen.
    var onQuit: () -> Void
    var triggerSize: CGFloat = 24
    var glyphSize: CGFloat = 12
    var triggerFill: Color? = nil
    var triggerStroke: Color? = nil
    var triggerForeground: Color? = nil

    @VPState private var open = false
    @VPState private var triggerHovered = false
    @VPState private var page: MenuPage = .root

    /// One sliding page of the dropdown. `root` hosts the quick rows; the radio
    /// sections live on sub-pages that push in from the trailing edge.
    private enum MenuPage: Equatable {
        case root, size, vinylStyle, glass
    }

    // Layout constants for the dropdown panel.
    private let menuWidth: CGFloat = 242
    private let menuMaxHeight: CGFloat = 760
    private let dropdownAnimation = Animation.timingCurve(0.16, 1.0, 0.30, 1.0, duration: 0.28)
    private let menuInk = Color.black.opacity(0.92)
    private let menuSecondaryInk = Color.black.opacity(0.72)
    private let menuMutedInk = Color.black.opacity(0.56)
    private let menuHoverFill = Color.black.opacity(0.095)
    private let menuDividerInk = Color.black.opacity(0.18)
    private let menuCheckInk = Color.black.opacity(0.88)
    private var triggerHitTarget: CGFloat { max(triggerSize + 8, 28) }
    private var constrainedMenuMaxHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? menuMaxHeight
        return min(menuMaxHeight, max(360, visibleHeight - 96))
    }

    var body: some View {
        trigger
            .popover(isPresented: $open, arrowEdge: .top) {
                dropdown
                    .frame(width: menuWidth)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: settings.windowMode) { _ in
                if open {
                    withAnimation(dropdownAnimation) { open = false }
                }
            }
            .onDisappear {
                open = false
            }
    }

    // MARK: - Trigger

    private var trigger: some View {
        Button {
            page = .root   // always reopen on the root page, without animating
            withAnimation(dropdownAnimation) { open.toggle() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundColor(
                    triggerForeground ?? Color.white.opacity(triggerHovered ? 1.0 : 0.92)
                )
                .frame(width: triggerSize, height: triggerSize)
                .background(
                    Circle()
                        .fill(triggerFill ?? Color.black.opacity(triggerHovered ? 0.58 : 0.48))
                )
                .overlay(
                    Circle().strokeBorder(triggerStroke ?? VPTheme.glassStroke, lineWidth: 1)
                )
                .frame(width: triggerHitTarget, height: triggerHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { triggerHovered = $0 }
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    // MARK: - Dropdown panel

    private var dropdown: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // Tab-slide pages: the root pushes sub-pages in from the trailing
            // edge (native submenu push/pop). Only one page is mounted at a
            // time; `.clipped()` keeps the slide inside the glass panel.
            ZStack(alignment: .top) {
                if page == .root {
                    VStack(alignment: .leading, spacing: 0) { rootContent }
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    VStack(alignment: .leading, spacing: 0) { subPageContent }
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .padding(.vertical, 6)
            .clipped()
            .animation(dropdownAnimation, value: page)
        }
        .frame(maxHeight: constrainedMenuMaxHeight)
        // Single light glass surface. The menu ink colors are tuned for this
        // light backing; the content was previously *also* wrapped in a
        // `GlassPanel`, whose own dark `VisualEffectBlur` + tint drew underneath
        // and double-clipped against the surface below. Removed so only this
        // intended surface renders.
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: VPTheme.radius, style: .continuous))
                RoundedRectangle(cornerRadius: VPTheme.radius, style: .continuous)
                    .fill(Color.white.opacity(0.93))
                RoundedRectangle(cornerRadius: VPTheme.radius, style: .continuous)
                    .fill(settings.albumPalette.vibrant.color.opacity(0.11))
                    .blendMode(.multiply)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.42),
                        settings.albumPalette.muted.color.opacity(0.07),
                        Color.black.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: VPTheme.radius, style: .continuous))
            }
        )
        // Inner top-lit bevel border (brighter top → darker bottom).
        .overlay(
            RoundedRectangle(cornerRadius: VPTheme.radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.68),
                            settings.albumPalette.vibrant.color.opacity(0.22),
                            Color.black.opacity(0.16)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 22, x: 0, y: 10)
        .compositingGroup()
        .overlay(
            SettingsMenuWindowConfigurator { window in
                configureMenuWindow(window)
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        )
    }

    // MARK: - Root page (quick rows; radio sections push to sub-pages)

    @ViewBuilder
    private var rootContent: some View {
        // "You're a Pro" — dimmed, non-interactive status row.
        proStatusRow

        // Now Playing From — a LIVE source indicator. Replaces the old
        // Apple Music / Spotify / Safari radio: the BrowserBridge ignores
        // `musicSource` as a capture filter, so that radio changed nothing and
        // only misrepresented what was actually being captured.
        sectionHeader("Now Playing From")
        NowPlayingSourceRow()
        // Browser setup guide (the extension supports BOTH Chrome and Safari).
        checkRow(title: "Connect a Browser…", checked: false, showsCheckColumn: true) {
            if let url = URL(string: "https://vinylpod.app/connect") {
                NSWorkspace.shared.open(url)
            }
        }

        chevronRow(title: "Music Player Size",
                   value: menuTitle(for: settings.windowMode)) {
            withAnimation(dropdownAnimation) { page = .size }
        }

        divider

        // Toggles.
        checkRow(title: "Dynamic Island", checked: settings.dynamicNotch) {
            settings.dynamicNotch.toggle()
        }
        checkRow(title: "Show in Menu Bar", checked: settings.showInMenuBar) {
            settings.showInMenuBar.toggle()
        }

        chevronRow(title: "Vinyl Style",
                   value: settings.vinylStyle.displayName) {
            withAnimation(dropdownAnimation) { page = .vinylStyle }
        }

        checkRow(title: "Show progress", checked: settings.showProgress) {
            settings.showProgress.toggle()
        }

        chevronRow(title: "Liquid Glass",
                   value: settings.glassTintStrength.displayName) {
            withAnimation(dropdownAnimation) { page = .glass }
        }

        divider

        // The long-tail system/window toggles (Launch at Login, Show Artwork in
        // Dock, Hide Dock Icon, Cover art as wallpaper, Hide notch in fullscreen,
        // Keep Window in Front) and the About / Keyboard-shortcuts actions moved
        // OUT of this dropdown into the proper Settings window (⌘,). The dropdown
        // now keeps only the quick, frequently-touched controls above plus the
        // actions below.

        // "Appearance" label reflects the current adaptive-accent state so the
        // row is informative at a glance.
        checkRow(title: appearanceRowTitle, checked: false, showsCheckColumn: true) {
            withAnimation(VPTheme.fade) { open = false }
            SettingsWindowController.shared.show(settings: settings)
        }

        // Open the full, tabbed Settings window (⌘,).
        checkRow(title: "Open Settings…", checked: false, showsCheckColumn: true) {
            withAnimation(VPTheme.fade) { open = false }
            SettingsWindowController.shared.show(settings: settings)
        }

        divider

        checkRow(title: "Rate us", checked: false, showsCheckColumn: true) {
            NSWorkspace.shared.open(VinylPodLinks.appStoreURL)
        }
        actionRow(title: "Share our app", glyph: "square.and.arrow.up") {
            // Share link copied to clipboard.
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(VinylPodLinks.websiteURL.absoluteString, forType: .string)
        }

        divider

        // Quit.
        checkRow(title: "Quit", checked: false, showsCheckColumn: true) {
            withAnimation(VPTheme.fade) { open = false }
            onQuit()
        }
    }

    // MARK: - Sub-pages (slide in from the trailing edge)

    @ViewBuilder
    private var subPageContent: some View {
        switch page {
        case .size:
            backHeader("Music Player Size")
            ForEach(WindowMode.allCases) { mode in
                checkRow(title: menuTitle(for: mode),
                         checked: settings.windowMode == mode) {
                    withAnimation(VPTheme.fade) { open = false }
                    guard settings.windowMode != mode else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        onSelectSize(mode)
                    }
                }
            }
        case .vinylStyle:
            backHeader("Vinyl Style")
            ForEach(VinylStyle.allCases) { style in
                checkRow(title: style.displayName,
                         checked: settings.vinylStyle == style) {
                    settings.vinylStyle = style
                    withAnimation(dropdownAnimation) { page = .root }
                }
            }
        case .glass:
            backHeader("Liquid Glass")
            ForEach(GlassTintStrength.allCases) { strength in
                checkRow(title: strength.displayName,
                         checked: settings.glassTintStrength == strength) {
                    settings.glassTintStrength = strength
                    withAnimation(dropdownAnimation) { page = .root }
                }
            }
        case .root:
            EmptyView()   // never mounted: the ZStack only shows sub-pages here
        }
    }

    /// Navigation row that pushes a sub-page: title, current value, chevron.
    private func chevronRow(title: String,
                            value: String,
                            action: @escaping () -> Void) -> some View {
        HoverRow {
            action()
        } content: { hovered in
            HStack(spacing: 8) {
                Color.clear.frame(width: 16, height: 1)   // check-column gutter
                Text(title)
                    .font(VPTheme.body(13))
                    .foregroundColor(menuInk)
                    .shadow(color: .white.opacity(0.35), radius: 0.5, x: 0, y: 1)
                Spacer(minLength: 0)
                Text(value)
                    .font(VPTheme.caption())
                    .foregroundColor(menuMutedInk)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(menuSecondaryInk)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: VPTheme.radiusSmall, style: .continuous)
                    .fill(hovered ? menuHoverFill : Color.clear)
                    .padding(.horizontal, 4)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        // Deterministic AX name — the e2e harness looks buttons up by exact
        // title, and the concatenated row text would include the value.
        .accessibilityLabel(title)
    }

    /// Sub-page header: a back chevron + page title; pops back to the root.
    private func backHeader(_ title: String) -> some View {
        HoverRow {
            withAnimation(dropdownAnimation) { page = .root }
        } content: { hovered in
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(menuCheckInk)
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .font(VPTheme.body(13).weight(.semibold))
                    .foregroundColor(menuInk)
                    .shadow(color: .white.opacity(0.35), radius: 0.5, x: 0, y: 1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: VPTheme.radiusSmall, style: .continuous)
                    .fill(hovered ? menuHoverFill : Color.clear)
                    .padding(.horizontal, 4)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Back")
    }

    /// "Appearance" row label, showing the current accent state.
    private var appearanceRowTitle: String {
        settings.useAdaptiveAccent ? "Appearance — Adaptive" : "Appearance — Custom accent"
    }

    private func menuTitle(for mode: WindowMode) -> String {
        mode == .desktopWidget ? "Desktop Widget" : mode.displayName
    }

    private func configureMenuWindow(_ window: NSWindow) {
        // The host panels can sit at status-window level; lift the popover just
        // above them so it stays visible and clickable over VinylPod chrome.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hidesOnDeactivate = false
        window.orderFrontRegardless()

        var behavior = window.collectionBehavior
        behavior.insert(.fullScreenAuxiliary)
        behavior.insert(.ignoresCycle)
        window.collectionBehavior = behavior
    }

    // MARK: - "You're a Pro" status row

    private var proStatusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(menuMutedInk)
            Text("You're a Pro")
                .font(VPTheme.body(13))
                .foregroundColor(menuSecondaryInk)
                .shadow(color: .white.opacity(0.35), radius: 0.5, x: 0, y: 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }

    // MARK: - Reusable helpers

    /// Dimmed, non-interactive section header.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(VPTheme.caption())
            .foregroundColor(menuMutedInk)
            .shadow(color: .white.opacity(0.30), radius: 0.5, x: 0, y: 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 3)
            .allowsHitTesting(false)
    }

    /// A full-width tappable row with a leading 16pt checkmark column.
    ///
    /// - Parameters:
    ///   - title: Row label.
    ///   - checked: Whether the leading checkmark is shown.
    ///   - showsCheckColumn: Keep the leading 16pt gutter for alignment even
    ///     when the row can never be checked (action rows). Defaults to `true`.
    ///   - action: Tap handler.
    private func checkRow(title: String,
                          checked: Bool,
                          showsCheckColumn: Bool = true,
                          action: @escaping () -> Void) -> some View {
        HoverRow {
            action()
        } content: { hovered in
            HStack(spacing: 8) {
                ZStack {
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(menuCheckInk)
                    }
                }
                .frame(width: 16, alignment: .center)
                .opacity(showsCheckColumn ? 1 : 0)

                Text(title)
                    .font(VPTheme.body(13))
                    .foregroundColor(menuInk)
                    .shadow(color: .white.opacity(0.35), radius: 0.5, x: 0, y: 1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: VPTheme.radiusSmall, style: .continuous)
                    .fill(hovered ? menuHoverFill : Color.clear)
                    .padding(.horizontal, 4)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    /// A full-width action row with a trailing glyph (e.g. share).
    private func actionRow(title: String,
                           glyph: String,
                           action: @escaping () -> Void) -> some View {
        HoverRow {
            action()
        } content: { hovered in
            HStack(spacing: 8) {
                // Keep the leading 16pt gutter for alignment.
                Color.clear.frame(width: 16, height: 1)
                Text(title)
                    .font(VPTheme.body(13))
                    .foregroundColor(menuInk)
                    .shadow(color: .white.opacity(0.35), radius: 0.5, x: 0, y: 1)
                Spacer(minLength: 0)
                Image(systemName: glyph)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(menuSecondaryInk)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: VPTheme.radiusSmall, style: .continuous)
                    .fill(hovered ? menuHoverFill : Color.clear)
                    .padding(.horizontal, 4)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    /// Thin divider tinted with the glass stroke, with small vertical padding.
    private var divider: some View {
        Divider()
            .overlay(menuDividerInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
    }
}

// MARK: - Live "now playing from" row

/// A tiny LEAF view that surfaces the CURRENT capture source (read from the live
/// track), replacing the old static source radio.
///
/// It is the only piece of the settings menu that observes `NowPlayingService`.
/// Keeping it a leaf is deliberate: a `position` tick re-evaluates just this
/// small body — whose output is stable across a track, so SwiftUI coalesces it —
/// without invalidating the menu trigger or the `WindowMode` picker above it.
/// Reads `track` only, never `position`.
@MainActor
private struct NowPlayingSourceRow: View {
    @EnvironmentObject var nowPlaying: NowPlayingService

    var body: some View {
        let track = nowPlaying.track
        let connected = nowPlaying.bridgeConnected
        let playing = !track.isEmpty

        // Three honest states: actively playing (show the live source), socket
        // up but idle, or no live connection at all.
        let symbol: String
        let primary: String
        let dim: Bool
        if playing {
            symbol = track.source.sfSymbol
            primary = track.source.displayName
            dim = false
        } else if connected {
            symbol = "dot.radiowaves.left.and.right"
            primary = "Connected — waiting for playback"
            dim = false
        } else {
            symbol = "circle.dashed"
            primary = "Not connected — open music in a browser"
            dim = true
        }

        return HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.black.opacity(dim ? 0.5 : 0.85))
                .frame(width: 16, alignment: .center)
            Text(primary)
                .font(VPTheme.body(13))
                .foregroundColor(Color.black.opacity(dim ? 0.62 : 0.92))
                .shadow(color: .white.opacity(0.35), radius: 0.5, x: 0, y: 1)
                .lineLimit(1)
            Spacer(minLength: 0)
            if playing, !track.artist.isEmpty {
                Text(track.artist)
                    .font(VPTheme.caption())
                    .foregroundColor(Color.black.opacity(0.56))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .allowsHitTesting(false)
    }
}

// MARK: - Hover row helper

/// A `.plain` button that exposes its hover state to a content closure, so each
/// menu row can paint a highlight without each call site re-declaring hover
/// `@VPState`. Keeps `checkRow` / `actionRow` DRY.
@MainActor
private struct HoverRow<Content: View>: View {
    var action: () -> Void
    @ViewBuilder var content: (Bool) -> Content

    @VPState private var hovered = false

    var body: some View {
        Button(action: action) {
            content(hovered)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

// MARK: - Popover window configurator

/// Gives the SwiftUI popover's backing window the same stacking priority as the
/// floating app chrome, without scanning or mutating unrelated app windows.
@MainActor
private struct SettingsMenuWindowConfigurator: NSViewRepresentable {
    var configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> ConfiguringView {
        ConfiguringView(configure: configure)
    }

    func updateNSView(_ nsView: ConfiguringView, context: Context) {
        nsView.configure = configure
        nsView.configureWindowIfNeeded()
    }

    final class ConfiguringView: NSView {
        var configure: (NSWindow) -> Void

        init(configure: @escaping (NSWindow) -> Void) {
            self.configure = configure
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindowIfNeeded()
        }

        func configureWindowIfNeeded() {
            guard let window else { return }
            configure(window)
        }
    }
}
