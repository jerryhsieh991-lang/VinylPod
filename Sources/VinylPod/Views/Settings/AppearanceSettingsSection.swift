import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Surfaces the app's existing-but-hidden appearance settings into a single,
/// reusable SwiftUI section. It is a *pure UI* layer: every control binds
/// straight to an already-persisted `AppSettings` field — this view neither
/// changes how those fields are stored nor how they are consumed downstream
/// (`Theme.swift` + `LandscapeBackground.swift` already turn them into the
/// live look).
///
/// Contents:
///   1. Adaptive-accent toggle (`useAdaptiveAccent`).
///   2. A manual accent `ColorPicker` (`accentColor`) plus preset swatches,
///      disabled/greyed while adaptive accent is on.
///   3. Custom background image chooser (`customBackgroundURL`) via
///      `NSOpenPanel`, with a "Clear" action.
///
/// PERF: observes only `AppSettings` — never touches `NowPlayingService.position`.
///
/// CLT note: uses `@VPState` (typealias to `SwiftUI.State`) per the project's
/// toolchain rule — `@State`'s macro plugin is unavailable under Command Line
/// Tools.
@MainActor
struct AppearanceSettingsSection: View {

    @ObservedObject var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// A small palette of preset accents users can tap without opening the
    /// system color picker. Purely a convenience over `accentColor`.
    private let presetSwatches: [Color] = [
        Color(red: 0.55, green: 0.78, blue: 0.94),   // ice blue
        Color(red: 0.62, green: 0.55, blue: 0.94),   // periwinkle
        Color(red: 0.94, green: 0.55, blue: 0.70),   // rose
        Color(red: 0.98, green: 0.72, blue: 0.42),   // amber
        Color(red: 0.55, green: 0.90, blue: 0.72),   // mint
        Color(red: 0.85, green: 0.85, blue: 0.88)    // silver
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            accentSection
            Divider().opacity(0.25)
            backgroundSection
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Accent

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accent")
                .font(.headline)

            Toggle("Use adaptive accent (from album art)", isOn: $settings.useAdaptiveAccent)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 10) {
                ColorPicker("Accent color", selection: $settings.accentColor, supportsOpacity: false)
                    .disabled(settings.useAdaptiveAccent)

                HStack(spacing: 8) {
                    ForEach(Array(presetSwatches.enumerated()), id: \.offset) { _, swatch in
                        Button {
                            settings.accentColor = swatch
                        } label: {
                            Circle()
                                .fill(swatch)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.35), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Use this accent")
                    }
                }
                .disabled(settings.useAdaptiveAccent)

                Text("Manual accent is used only when adaptive accent is off. "
                     + "With adaptive accent on, the color is derived from the current album art.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .opacity(settings.useAdaptiveAccent ? 0.45 : 1.0)
        }
    }

    // MARK: - Custom background

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background")
                .font(.headline)

            if let url = settings.customBackgroundURL {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                    Text(url.lastPathComponent)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text("Using the default landscape.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Choose Image…") {
                    chooseBackgroundImage()
                }

                Button("Clear") {
                    settings.customBackgroundURL = nil
                }
                .disabled(settings.customBackgroundURL == nil)
            }

            Text("Pick a PNG, JPEG, or HEIC image to sit behind the widget. "
                 + "Clearing restores the built-in landscape.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - NSOpenPanel

    /// Presents a single-file image picker on the main thread and assigns the
    /// chosen URL to `settings.customBackgroundURL` — matching how the field is
    /// already consumed elsewhere (a plain file URL, no bookmarking).
    private func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose Background Image"
        panel.prompt = "Choose"

        let types: [UTType] = [.png, .jpeg, .heic]
        panel.allowedContentTypes = types

        if panel.runModal() == .OK, let url = panel.url {
            settings.customBackgroundURL = url
        }
    }
}
