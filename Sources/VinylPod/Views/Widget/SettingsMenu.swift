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
    @EnvironmentObject var nowPlaying: NowPlayingService

    /// Called when a size row is chosen (parent also persists `settings.windowMode`).
    var onSelectSize: (WindowMode) -> Void
    /// Called when the "Quit" row is chosen.
    var onQuit: () -> Void

    @VPState private var open = false
    @VPState private var triggerHovered = false

    // Layout constants for the dropdown panel.
    private let menuWidth: CGFloat = 230
    private let menuMaxHeight: CGFloat = 460

    var body: some View {
        trigger
            .overlay(alignment: .topTrailing) {
                if open {
                    // Float the dropdown above everything, anchored just under
                    // the trigger's top-trailing corner.
                    dropdown
                        .frame(width: menuWidth)
                        .offset(y: 30)
                        .transition(
                            .scale(scale: 0.96, anchor: .topTrailing)
                                .combined(with: .opacity)
                        )
                        .zIndex(1000)
                }
            }
            // Invisible full-screen catcher that closes the menu on outside tap.
            .background(alignment: .topTrailing) {
                if open {
                    outsideCatcher
                }
            }
    }

    // MARK: - Trigger

    private var trigger: some View {
        Button {
            withAnimation(VPTheme.spring) { open.toggle() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(
                    triggerHovered ? VPTheme.textPrimary : VPTheme.textSecondary
                )
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(triggerHovered ? VPTheme.glassTint : Color.clear)
                )
                .overlay(
                    Circle().strokeBorder(VPTheme.glassStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { triggerHovered = $0 }
    }

    // MARK: - Outside catcher

    /// A transparent screen-filling layer that dismisses the menu when clicked
    /// anywhere outside the dropdown. Placed behind the dropdown (lower zIndex).
    private var outsideCatcher: some View {
        Color.clear
            .frame(width: 4000, height: 4000)
            .contentShape(Rectangle())
            .offset(x: 2000, y: -2000) // recenter the oversized rect over the screen
            .onTapGesture {
                withAnimation(VPTheme.fade) { open = false }
            }
            .zIndex(900)
    }

    // MARK: - Dropdown panel

    private var dropdown: some View {
        GlassPanel(cornerRadius: VPTheme.radius) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    menuContent
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: menuMaxHeight)
        }
        // Inner top-lit bevel border (brighter top → darker bottom).
        .overlay(
            RoundedRectangle(cornerRadius: VPTheme.radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.black.opacity(0.25)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 6)
    }

    // MARK: - Menu content (exact hierarchy, top → bottom)

    @ViewBuilder
    private var menuContent: some View {
        // "You're a Pro" — dimmed, non-interactive status row.
        proStatusRow

        // Music Player Source (radio).
        sectionHeader("Music Player Source")
        checkRow(title: "Apple Music",
                 checked: settings.musicSource == .appleMusic) {
            settings.musicSource = .appleMusic
        }
        checkRow(title: "Spotify",
                 checked: settings.musicSource == .spotify) {
            settings.musicSource = .spotify
        }
        checkRow(title: "Safari Music",
                 checked: settings.musicSource == .browser) {
            settings.musicSource = .browser
        }
        // Non-checkable action row.
        checkRow(title: "Safari Music Guide", checked: false, showsCheckColumn: true) {
            print("[SettingsMenu] Safari Music Guide tapped")
        }

        // Music Player Size (radio over WindowMode.allCases).
        sectionHeader("Music Player Size")
        ForEach(WindowMode.allCases) { mode in
            checkRow(title: mode.displayName,
                     checked: settings.windowMode == mode) {
                settings.windowMode = mode
                onSelectSize(mode)
            }
        }

        divider

        // Toggles.
        checkRow(title: "Dynamic notch", checked: settings.dynamicNotch) {
            settings.dynamicNotch.toggle()
        }
        checkRow(title: "Show in Menu Bar", checked: settings.showInMenuBar) {
            settings.showInMenuBar.toggle()
        }

        // Vinyl Style (radio).
        sectionHeader("Vinyl Style")
        checkRow(title: "Vinyl", checked: settings.vinylStyle == .vinyl) {
            settings.vinylStyle = .vinyl
        }
        checkRow(title: "Image", checked: settings.vinylStyle == .image) {
            settings.vinylStyle = .image
        }

        checkRow(title: "Show progress", checked: settings.showProgress) {
            settings.showProgress.toggle()
        }

        divider

        // Window / system toggles.
        checkRow(title: "Keep Window in Front", checked: settings.keepWindowInFront) {
            settings.keepWindowInFront.toggle()
        }
        checkRow(title: "Launch at Login", checked: settings.launchAtLogin) {
            settings.launchAtLogin.toggle()
        }
        checkRow(title: "Show Artwork in Dock", checked: settings.showArtworkInDock) {
            settings.showArtworkInDock.toggle()
        }
        checkRow(title: "Hide Dock Icon", checked: settings.hideDockIcon) {
            settings.hideDockIcon.toggle()
        }
        checkRow(title: "Cover art as wallpaper", checked: settings.coverArtAsWallpaper) {
            settings.coverArtAsWallpaper.toggle()
        }
        checkRow(title: "Hide notch in fullscreen", checked: settings.hideNotchInFullscreen) {
            settings.hideNotchInFullscreen.toggle()
        }

        divider

        // Plain action rows (no-op / print for now).
        checkRow(title: "Keyboard shortcuts", checked: false, showsCheckColumn: true) {
            print("[SettingsMenu] Keyboard shortcuts tapped")
        }
        checkRow(title: "Appearance", checked: false, showsCheckColumn: true) {
            print("[SettingsMenu] Appearance tapped")
        }

        divider

        checkRow(title: "Rate us", checked: false, showsCheckColumn: true) {
            print("[SettingsMenu] Rate us tapped")
        }
        actionRow(title: "Share our app", glyph: "square.and.arrow.up") {
            print("[SettingsMenu] Share our app tapped")
        }
        checkRow(title: "About", checked: false, showsCheckColumn: true) {
            print("[SettingsMenu] About tapped")
        }

        divider

        // Quit.
        checkRow(title: "Quit", checked: false, showsCheckColumn: true) {
            withAnimation(VPTheme.fade) { open = false }
            onQuit()
        }
    }

    // MARK: - "You're a Pro" status row

    private var proStatusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(VPTheme.textMuted)
            Text("You're a Pro")
                .font(VPTheme.body(13))
                .foregroundColor(VPTheme.textMuted)
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
            .foregroundColor(VPTheme.textMuted)
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
                            .foregroundColor(VPTheme.textPrimary)
                    }
                }
                .frame(width: 16, alignment: .center)
                .opacity(showsCheckColumn ? 1 : 0)

                Text(title)
                    .font(VPTheme.body(13))
                    .foregroundColor(VPTheme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: VPTheme.radiusSmall, style: .continuous)
                    .fill(hovered ? Color.white.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 4)
            )
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
                    .foregroundColor(VPTheme.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: glyph)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(VPTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: VPTheme.radiusSmall, style: .continuous)
                    .fill(hovered ? Color.white.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
    }

    /// Thin divider tinted with the glass stroke, with small vertical padding.
    private var divider: some View {
        Divider()
            .overlay(VPTheme.glassStroke)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
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
        .onHover { hovered = $0 }
    }
}
