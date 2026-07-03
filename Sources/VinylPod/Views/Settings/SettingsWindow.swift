import SwiftUI
import AppKit

/// Shared, user-facing constants for the Settings window and the trimmed
/// three-dots dropdown. Kept here (rather than inline `URL(string:)` literals
/// scattered across views) so the "Rate us" / "Share" destinations are defined
/// in exactly one place and are obviously real, not placeholders.
enum VinylPodLinks {
    /// App Store product page. Replace the bundle id / slug with the real one at
    /// submission time — this is intentionally a single labeled constant, not an
    /// inline literal, so there's one place to update.
    static let appStoreURL = URL(string: "https://apps.apple.com/app/vinylpod")!
    /// Marketing site, used for "Share our app".
    static let websiteURL = URL(string: "https://vinylpod.app")!
    /// Browser-extension connect / onboarding guide.
    static let connectURL = URL(string: "https://vinylpod.app/connect")!
}

/// The tabs of the Settings window.
private enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case sources = "Sources"
    case shortcuts = "Shortcuts"
    case about = "About"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general:    return "gearshape"
        case .appearance: return "paintpalette"
        case .sources:    return "dot.radiowaves.left.and.right"
        case .shortcuts:  return "keyboard"
        case .about:      return "info.circle"
        }
    }
}

/// The proper multi-tab Settings window (⌘,).
///
/// PERF INVARIANT: this view — and everything it hosts — observes ONLY
/// `AppSettings`. It must never observe `NowPlayingService` (whose `position`
/// is rewritten ~10×/sec); reading that here would repaint the whole window on
/// every tick. The Sources tab shows the *configured* `musicSource` read-only
/// and does not touch live playback state.
@MainActor
struct SettingsWindow: View {
    @ObservedObject var settings: AppSettings
    @VPState private var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            ForEach(SettingsTab.allCases) { t in
                tabContent(t)
                    .tabItem { Label(t.rawValue, systemImage: t.systemImage) }
                    .tag(t)
            }
        }
        .frame(width: 520, height: 460)
    }

    @ViewBuilder
    private func tabContent(_ t: SettingsTab) -> some View {
        switch t {
        case .general:
            GeneralSettingsSection(settings: settings)
        case .appearance:
            AppearanceSettingsTab(settings: settings)
        case .sources:
            SourcesSettingsTab(settings: settings)
        case .shortcuts:
            ShortcutsSettingsTab()
        case .about:
            AboutSettingsSection()
        }
    }
}

// MARK: - Appearance tab

/// Appearance controls that are safe to bind directly to `AppSettings`.
///
/// The richer accent / palette editor is delivered by another agent; it slots
/// in at the marked INTEGRATION POINT below.
@MainActor
private struct AppearanceSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // INTEGRATION POINT: AppearanceSettingsSection(settings: settings)
                // Another agent delivers the accent-color / adaptive-accent editor.
                // Do NOT reference the type here — it does not exist yet. This
                // placeholder keeps the tab compiling standalone.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accent & Palette")
                        .font(.headline)
                    Text("Accent-color controls appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                SettingsGroup("Widget Look") {
                    Picker("Visual style", selection: $settings.vinylStyle) {
                        ForEach(VinylStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Liquid glass", selection: $settings.glassTintStrength) {
                        ForEach(GlassTintStrength.allCases) { strength in
                            Text(strength.displayName).tag(strength)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                SettingsGroup("Artwork") {
                    Toggle("Show artwork in Dock", isOn: $settings.showArtworkInDock)
                    Toggle("Cover art as wallpaper", isOn: $settings.coverArtAsWallpaper)
                    Toggle("Hide notch in fullscreen", isOn: $settings.hideNotchInFullscreen)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Sources tab

/// Read-only view of the configured source plus a placeholder for the capture /
/// Last.fm / browser-onboarding sections delivered by other agents.
@MainActor
private struct SourcesSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                SettingsGroup("Configured Source") {
                    HStack(spacing: 8) {
                        Image(systemName: settings.musicSource.sfSymbol)
                            .foregroundStyle(.secondary)
                        Text(settings.musicSource.displayName)
                        Spacer()
                        Text("Read-only")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text("VinylPod captures now-playing from a connected browser. This is the configured preference; live capture is shown in the widget.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Connect a Browser…") {
                        NSWorkspace.shared.open(VinylPodLinks.connectURL)
                    }
                }

                Divider()

                // INTEGRATION POINT: CaptureSettingsSection(settings:) + LastFmSettingsSection() + BrowserOnboardingView(nowPlaying:)
                // Other agents deliver capture configuration, Last.fm scrobbling,
                // and the browser-onboarding flow. Do NOT reference those types
                // here — they do not exist yet.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Capture, Last.fm & Onboarding")
                        .font(.headline)
                    Text("Capture configuration, Last.fm scrobbling, and browser onboarding appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shortcuts tab

/// Embeds the existing keyboard-shortcuts editor (unchanged) inside the tab.
@MainActor
private struct ShortcutsSettingsTab: View {
    var body: some View {
        KeyboardShortcutsView()
            .environmentObject(AppEnvironment.shared.shortcuts)
    }
}

// MARK: - Small layout helper

/// A titled group of setting rows, matching the standard macOS settings look.
@MainActor
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Window controller

/// Owns the single reusable Settings `NSWindow` and hosts `SettingsWindow`.
///
/// Mirrors `KeyboardShortcutsWindowController`: an accessory (menu-bar) app has
/// no reliable SwiftUI `Settings` scene, so we drive a plain `NSWindow`. The
/// `AppDelegate` wires ⌘, to `SettingsWindowController.shared.show()`.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    /// Opens (or re-focuses) the Settings window, hosting `SettingsWindow` with
    /// the shared `AppSettings`. Only `AppSettings` is injected — never
    /// `NowPlayingService` — to honor the perf invariant.
    func show() {
        show(settings: AppEnvironment.shared.settings)
    }

    func show(settings: AppSettings) {
        if window == nil {
            let hosting = NSHostingView(rootView: SettingsWindow(settings: settings))
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "VinylPod Settings"
            win.isReleasedWhenClosed = false
            win.contentView = hosting
            win.setContentSize(NSSize(width: 520, height: 460))
            win.center()
            window = win
        }

        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
