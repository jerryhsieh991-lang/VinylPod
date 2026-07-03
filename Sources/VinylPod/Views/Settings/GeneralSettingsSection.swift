import SwiftUI
import AppKit

/// The "General" tab of the Settings window: the long-tail system toggles that
/// used to crowd the three-dots dropdown now live here.
///
/// PERF: observes only `AppSettings`. Never touches `NowPlayingService`.
@MainActor
struct GeneralSettingsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                SettingsGroup("Visibility") {
                    Toggle("Show in Menu Bar", isOn: $settings.showInMenuBar)
                    Toggle("Hide Dock icon", isOn: $settings.hideDockIcon)
                    Text("Hiding both the menu bar item and the Dock icon leaves no entry point, so the app keeps one visible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SettingsGroup("Window") {
                    Toggle("Keep window in front", isOn: $settings.keepWindowInFront)
                        .onChange(of: settings.keepWindowInFront) { keep in
                            // Native window layering (NSWindowLevel), not z-index —
                            // mirrors the dropdown's old behavior.
                            WindowCoordinator.shared.manager?
                                .applyStacking(keep ? .front : .back)
                        }
                    Toggle("Dynamic Island notch", isOn: $settings.dynamicNotch)
                }

                SettingsGroup("Startup") {
                    Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
