import SwiftUI
import AppKit

/// The compact-widget album-art tile with an in-art "X" close button that opens
/// the **Window behavior** popover (Above all windows / Below all windows / Quit).
///
/// Visual contract (see design_system.md → "Compact Glass Widget"):
/// - Album art fills the given frame as a rounded square with a top-lit inner bevel.
/// - The "X" lives INSIDE the art square, top-left corner, inset ~8pt — it is NOT
///   a chrome button outside the art. It fades in on hover and stays while the
///   popover is open.
/// - Clicking the "X" toggles a glass popover anchored to the top-left, floating
///   above the art with a high zIndex.
struct AlbumArtCloseButton: View {

    let artwork: NSImage?
    var cornerRadius: CGFloat = VPTheme.radius
    var alwaysShowCloseButton = false
    var closeButtonSize: CGFloat = 22
    var closeButtonInset: CGFloat = 8
    var focusRingVisible = false
    var showsArtworkLayer = true
    var currentLayer: DesktopLayer          // which window-behavior is active now
    var onSelectLayer: (DesktopLayer) -> Void
    var onQuit: () -> Void

    // Drives the selected visualizer style. Read from the environment so call
    // sites don't need to pass another visual setting around.
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var nowPlaying: NowPlayingService

    // View-local state (CLT workaround: @VPState, never @State).
    @VPState private var showPopover = false
    @VPState private var hovering = false

    /// True when the artwork layer is a visualizer rather than a flat card.
    private var isVisualizerArt: Bool { showsArtworkLayer }

    var body: some View {
        // ZStack with `.topLeading` alignment so BOTH the X button and the
        // popover anchor to the art's top-left corner — the X sits inset inside
        // the art bounds, and the popover floats out from just below/right of it.
        ZStack(alignment: .topLeading) {

            // ── Album art (or placeholder) — fills the frame as a rounded square,
            // or delegates to the selected visualizer style.
            artworkLayer
                // Inner 3D bevel: top-lit linear-gradient stroke (white→black).
                // Skipped for rigid visualizers that have their own edges.
                .overlay {
                    if !isVisualizerArt {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.35), Color.black.opacity(0.25)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                }

            // ── The 'X' button — INSIDE the art, top-left, inset ~8pt via padding.
            // It is part of this same `.topLeading` ZStack, so it pins to the
            // art's top-left corner rather than floating outside the square.
            closeButton
                .padding(closeButtonInset)
                // Visible on hover over the art, and held visible while the
                // popover is open.
                .opacity(alwaysShowCloseButton || hovering || showPopover ? 1 : 0)
                .animation(VPTheme.fade, value: hovering)
                .animation(VPTheme.fade, value: showPopover)

        }
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            popover
                .frame(width: 188)
                .fixedSize(horizontal: false, vertical: true)
                .padding(0)
        }
        // Hover tracking drives the X fade-in across the whole art surface.
        .onHover { hovering = $0 }
    }

    // MARK: - Album art layer

    @ViewBuilder
    private var artworkLayer: some View {
        if !showsArtworkLayer {
            Color.clear
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            MusicVisualizerContainerView(
                style: settings.vinylStyle,
                artwork: artwork,
                isPlaying: nowPlaying.isPlaying,
                palette: settings.albumPalette
            )
        }
    }

    // MARK: - The 'X' button

    private var closeButton: some View {
        Button {
            withAnimation(VPTheme.spring) { showPopover.toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: closeButtonSize, height: closeButtonSize)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                focusRingVisible ? Color(red: 0.42, green: 0.50, blue: 0.95).opacity(0.95) : Color.clear,
                                lineWidth: 2
                            )
                    )
                Image(systemName: "xmark")
                    .font(.system(size: closeButtonSize * 0.43, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.9))
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Window-behavior popover

    private var popover: some View {
        GlassPanel(cornerRadius: VPTheme.radius) {
            VStack(alignment: .leading, spacing: 2) {
                // Section header — non-interactive, dimmed.
                Text("Window behavior")
                    .font(VPTheme.caption())
                    .foregroundColor(PopoverMenuPalette.muted)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                menuRow(
                    title: DesktopLayer.front.behaviorLabel,  // "Above all windows"
                    checked: currentLayer == .front
                ) {
                    onSelectLayer(.front)
                    dismiss()
                }

                menuRow(
                    title: DesktopLayer.back.behaviorLabel,   // "Below all windows"
                    checked: currentLayer == .back
                ) {
                    onSelectLayer(.back)
                    dismiss()
                }

                Divider()
                    .overlay(PopoverMenuPalette.divider)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                menuRow(title: "Quit", checked: false) {
                    onQuit()
                }
            }
            .padding(.bottom, 6)
            .frame(width: 188, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: VPTheme.radius, style: .continuous)
                .fill(Color.white.opacity(0.80))
        )
        // Top-lit inner bevel to match the glass depth cue.
        .overlay(
            RoundedRectangle(cornerRadius: VPTheme.radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.black.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 6)
    }

    // MARK: - Menu row

    private func menuRow(title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        MenuRow(title: title, checked: checked, action: action)
    }

    // MARK: - Helpers

    private func dismiss() {
        withAnimation(VPTheme.fade) { showPopover = false }
    }
}

/// A single tappable row in the Window-behavior popover: leading checkmark
/// column + ~13pt label, with a `white @ 0.06` hover highlight and rounded
/// corners. Split into its own view so each row owns its hover state.
private struct MenuRow: View {
    let title: String
    let checked: Bool
    let action: () -> Void

    @VPState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Leading checkmark column (fixed width so labels align).
                ZStack {
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(PopoverMenuPalette.ink)
                    }
                }
                .frame(width: 14, alignment: .center)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PopoverMenuPalette.ink)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VPTheme.radiusSmall, style: .continuous)
                    .fill(hovering ? PopoverMenuPalette.hoverFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
    }
}

private enum PopoverMenuPalette {
    static let ink = Color.black.opacity(0.86)
    static let muted = Color.black.opacity(0.46)
    static let divider = Color.black.opacity(0.12)
    static let hoverFill = Color.black.opacity(0.07)
}
