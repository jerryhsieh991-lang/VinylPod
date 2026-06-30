import SwiftUI

/// The compact glass popover shown when the user clicks the VinylPod menu-bar
/// icon. It shows the current track, transport controls, a window-mode picker,
/// the desktop front/behind toggle (only in Desktop Widget mode), and Quit.
///
/// It observes the shared `NowPlayingService` / `AppSettings` (injected by the
/// `MenuBarExtra` in `VinylPodApp`) and drives the window via
/// `WindowCoordinator.shared.manager`.
struct MenuBarContentView: View {

    // NOTE: `nowPlaying` is deliberately NOT observed here. `NowPlayingService`
    // republishes `position` on every playback tick (~10×/sec local, ~1×/sec
    // bridge). If this always-on menu surface observed it, the whole body —
    // including the `WindowMode` Picker/ForEach — would re-diff every tick,
    // which `sample` showed as `MainMenuItemHost.requestUpdate` →
    // `ForEachState.update` churn. Only the small `NowPlayingMenuSection` child
    // observes the service, so position ticks can't invalidate the picker.
    @EnvironmentObject var settings: AppSettings

    private var manager: WindowManager? { WindowCoordinator.shared.manager }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NowPlayingMenuSection()
            Divider()
            modePicker
            if settings.windowMode == .desktopWidget {
                desktopLayerToggle
            }
            Divider()
            Button("Quit VinylPod") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(VPTheme.textSecondary)
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - Window mode picker

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Window Size")
                .font(VPTheme.caption())
                .foregroundStyle(VPTheme.textMuted)

            Picker("Window Size", selection: modeBinding) {
                ForEach(WindowMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// Setting the mode updates persisted settings AND drives the WindowManager.
    private var modeBinding: Binding<WindowMode> {
        Binding(
            get: { settings.windowMode },
            set: { newMode in
                manager?.apply(mode: newMode)
            }
        )
    }

    // MARK: - Desktop layer toggle (widget only)

    private var desktopLayerToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Desktop Layer")
                .font(VPTheme.caption())
                .foregroundStyle(VPTheme.textMuted)

            Picker("Desktop Layer", selection: layerBinding) {
                ForEach(DesktopLayer.allCases, id: \.self) { layer in
                    Text(layer.displayName).tag(layer)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// Setting the layer updates persisted settings AND drives the WindowManager.
    private var layerBinding: Binding<DesktopLayer> {
        Binding(
            get: { settings.desktopLayer },
            set: { newLayer in
                settings.desktopLayer = newLayer
                manager?.apply(desktopLayer: newLayer)
            }
        )
    }
}

// MARK: - Now-playing section (the only `NowPlayingService` observer)

/// Header (source chip + title/artist) and transport row.
///
/// This is the lone subview that observes `NowPlayingService`, so the
/// high-frequency `position` republish is contained here and can never reach
/// the parent's `WindowMode` picker. It reads only `track` / `isPlaying`; the
/// per-tick `position` field is never touched, so a tick re-runs this tiny body
/// with identical leaf content and no `ForEach` re-diff.
private struct NowPlayingMenuSection: View {

    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            nowPlayingHeader
            transportRow
        }
    }

    private var nowPlayingHeader: some View {
        let track = nowPlaying.track
        return VStack(alignment: .leading, spacing: 6) {
            // Tiny source chip: SF symbol + source name, tinted with the accent.
            HStack(spacing: 5) {
                Image(systemName: track.source.sfSymbol)
                    .font(.caption2)
                Text(track.source.displayName)
                    .font(VPTheme.caption())
            }
            .foregroundStyle(settings.accentColor)

            if track.isEmpty {
                Text("Nothing playing")
                    .font(VPTheme.title())
                    .foregroundStyle(VPTheme.textPrimary)
                Text("Drop a music file onto the window")
                    .font(VPTheme.caption())
                    .foregroundStyle(VPTheme.textMuted)
            } else {
                Text(track.title)
                    .font(VPTheme.title())
                    .foregroundStyle(VPTheme.textPrimary)
                    .lineLimit(1)
                Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                    .font(VPTheme.caption())
                    .foregroundStyle(VPTheme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var transportRow: some View {
        HStack(spacing: 24) {
            Spacer()
            Button { nowPlaying.previous() } label: {
                Image(systemName: "backward.fill")
            }
            Button { nowPlaying.playPause() } label: {
                Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            Button { nowPlaying.next() } label: {
                Image(systemName: "forward.fill")
            }
            Spacer()
        }
        .buttonStyle(.plain)
        .foregroundStyle(settings.accentColor)
        .disabled(nowPlaying.track.isEmpty)
    }
}
