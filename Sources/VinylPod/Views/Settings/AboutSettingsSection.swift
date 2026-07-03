import SwiftUI
import AppKit

/// The "About" tab: app identity, version, real "Rate us" / "Share" links, and
/// credits. Stateless — no `AppSettings` or `NowPlayingService` observation.
@MainActor
struct AboutSettingsSection: View {

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "VinylPod"
    }

    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)

            Image(systemName: "opticaldisc")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(appName)
                    .font(.title2.weight(.semibold))
                Text(versionString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(VinylPodLinks.appStoreURL)
                } label: {
                    Label("Rate us", systemImage: "star")
                }

                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(VinylPodLinks.websiteURL.absoluteString, forType: .string)
                } label: {
                    Label("Share our app", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.bordered)

            Divider()
                .padding(.horizontal, 60)

            VStack(spacing: 2) {
                Text("Album-reactive liquid-glass now-playing for macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Made with care.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
