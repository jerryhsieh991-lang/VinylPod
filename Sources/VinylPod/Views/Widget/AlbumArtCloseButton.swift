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
    var currentLayer: DesktopLayer          // which window-behavior is active now
    var onSelectLayer: (DesktopLayer) -> Void
    var onQuit: () -> Void

    // View-local state (CLT workaround: @VPState, never @State).
    @VPState private var showPopover = false
    @VPState private var hovering = false

    var body: some View {
        // ZStack with `.topLeading` alignment so BOTH the X button and the
        // popover anchor to the art's top-left corner — the X sits inset inside
        // the art bounds, and the popover floats out from just below/right of it.
        ZStack(alignment: .topLeading) {

            // ── Album art (or placeholder) — fills the frame as a rounded square.
            artworkLayer
                // Inner 3D bevel: top-lit linear-gradient stroke (white→black).
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.black.opacity(0.25)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )

            // ── The 'X' button — INSIDE the art, top-left, inset ~8pt via padding.
            // It is part of this same `.topLeading` ZStack, so it pins to the
            // art's top-left corner rather than floating outside the square.
            closeButton
                .padding(8)
                // Visible on hover over the art, and held visible while the
                // popover is open.
                .opacity(hovering || showPopover ? 1 : 0)
                .animation(VPTheme.fade, value: hovering)
                .animation(VPTheme.fade, value: showPopover)

            // ── The Window-behavior popover — anchored top-left, floats above art.
            if showPopover {
                popover
                    // Offset so it appears just below / right of the X glyph
                    // (X is at padding 8 + ~22pt circle), not on top of it.
                    .offset(x: 8, y: 36)
                    .zIndex(100)
                    .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
            }
        }
        // Hover tracking drives the X fade-in across the whole art surface.
        .onHover { hovering = $0 }
    }

    // MARK: - Album art layer

    @ViewBuilder
    private var artworkLayer: some View {
        if let artwork {
            Image(nsImage: artwork)
                .resizable()
                .scaledToFill()
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            // Tasteful placeholder: dark glass square + centered music.note.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(VPTheme.scrimStrong)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundColor(VPTheme.textMuted)
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
                    .frame(width: 22, height: 22)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.9))
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Window-behavior popover

    private var popover: some View {
        ZStack(alignment: .topLeading) {
            // Invisible full-bleed catcher: tapping outside the menu (but within
            // this view) dismisses the popover. Parent also handles outside-click.
            Color.clear
                .frame(width: 4000, height: 4000)
                .contentShape(Rectangle())
                .offset(x: -2000, y: -2000)
                .onTapGesture { dismiss() }

            GlassPanel(cornerRadius: VPTheme.radius) {
                VStack(alignment: .leading, spacing: 2) {
                    // Section header — non-interactive, dimmed.
                    Text("Window behavior")
                        .font(VPTheme.caption())
                        .foregroundColor(VPTheme.textMuted)
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
                        .overlay(VPTheme.glassStroke)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                    menuRow(title: "Quit", checked: false) {
                        onQuit()
                    }
                }
                .padding(.bottom, 6)
                .frame(width: 188, alignment: .leading)
            }
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
            .fixedSize()
        }
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
                            .foregroundColor(VPTheme.textPrimary)
                    }
                }
                .frame(width: 14, alignment: .center)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(VPTheme.textPrimary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VPTheme.radiusSmall, style: .continuous)
                    .fill(hovering ? Color.white.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
    }
}
