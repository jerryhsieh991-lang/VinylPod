import SwiftUI
import AppKit

/// The "Capture" tab of the Settings window: an OPTIONAL, experimental path that
/// reads Now Playing directly from desktop apps (Spotify.app / Music.app) via
/// the private MediaRemote framework, in addition to the default browser
/// extension bridge.
///
/// PERF: observes only `AppSettings`. It does NOT observe `NowPlayingService`
/// (whose `position` is rewritten ~10×/sec) — the "MediaRemote returned data"
/// indicator is refreshed by a slow 1 s timer that reads a plain Bool, so this
/// view never re-renders on the playback tick.
@MainActor
struct CaptureSettingsSection: View {
    @ObservedObject var settings: AppSettings

    /// Slow-polled snapshot of whether the native adapter has seen real data.
    /// Updated at 1 Hz by a timer — decoupled from the playback tick.
    @VPState private var didReceiveData = false
    @VPState private var indicatorTimer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                SettingsGroup("Desktop app capture") {
                    Toggle("Capture desktop apps (Spotify/Music) natively — experimental",
                           isOn: $settings.nativeCaptureEnabled)
                        .onChange(of: settings.nativeCaptureEnabled) { _ in
                            // Start/stop the adapter to match the toggle.
                            AppEnvironment.shared.nowPlaying
                                .attachNativeCapture(settings: settings)
                            refreshIndicator()
                        }

                    Text("""
                    When on, VinylPod tries to read the currently playing track \
                    straight from Spotify.app or Music.app using macOS's private \
                    “Now Playing” system, in addition to the browser extension \
                    (which stays the default source). This is best-effort: on \
                    macOS 15.4 and later Apple gates this data behind a private \
                    entitlement, so it may report nothing — in that case the \
                    browser extension keeps working normally.
                    """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsGroup("Status") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(indicatorColor)
                            .frame(width: 9, height: 9)
                        Text(indicatorLabel)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { startIndicatorTimer() }
        .onDisappear { stopIndicatorTimer() }
    }

    // MARK: - Live indicator

    private var indicatorColor: Color {
        if !settings.nativeCaptureEnabled { return .secondary }
        return didReceiveData ? .green : .orange
    }

    private var indicatorLabel: String {
        if !settings.nativeCaptureEnabled {
            return "Native capture off — using the browser extension."
        }
        return didReceiveData
            ? "MediaRemote is returning data."
            : "Native capture on, but MediaRemote hasn't returned data yet (it may be entitlement-gated on this macOS version)."
    }

    private func startIndicatorTimer() {
        refreshIndicator()
        stopIndicatorTimer()
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in refreshIndicator() }
        }
        RunLoop.main.add(timer, forMode: .common)
        indicatorTimer = timer
    }

    private func stopIndicatorTimer() {
        indicatorTimer?.invalidate()
        indicatorTimer = nil
    }

    private func refreshIndicator() {
        didReceiveData = AppEnvironment.shared.nowPlaying.nativeCaptureDidReceiveData
    }
}
