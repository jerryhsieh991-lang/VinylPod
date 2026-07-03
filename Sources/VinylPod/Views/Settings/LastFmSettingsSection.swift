import SwiftUI
import AppKit

/// Self-contained Last.fm settings block. No required init args — it reads the
/// shared `LastFmScrobbler` / `LastFmClient` singletons internally. Drop it into
/// any settings surface: `LastFmSettingsSection()`.
///
/// Loosely matches the app's dark liquid-glass aesthetic with a simple tinted
/// rounded panel — no heavy custom backgrounds.
struct LastFmSettingsSection: View {

    @ObservedObject private var scrobbler = LastFmScrobbler.shared
    private let client = LastFmClient.shared

    /// Local UI state for the multi-step auth handshake.
    @VPState private var phase: AuthPhase = .idle
    @VPState private var statusNote: String? = nil

    private enum AuthPhase: Equatable {
        case idle                 // show connect/disconnect per persisted state
        case authorizing          // browser opened; show "Complete connection"
        case working              // a network call is in flight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !client.isConfigured {
                notConfiguredNote
            } else {
                enableRow
                Divider().overlay(VPTheme.glassStroke)
                connectionRow
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: VPTheme.radius, style: .continuous)
                .fill(VPTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VPTheme.radius, style: .continuous)
                .stroke(VPTheme.glassStroke, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .foregroundStyle(VPTheme.iceAccent)
            Text("Last.fm Scrobbling")
                .font(VPTheme.title(14))
                .foregroundStyle(VPTheme.textPrimary)
            Spacer()
        }
    }

    // MARK: - Not-configured note

    private var notConfiguredNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("API key not set", systemImage: "exclamationmark.triangle.fill")
                .font(VPTheme.body(12))
                .foregroundStyle(.yellow)
            Text("Add your Last.fm API key and secret in LastFmClient.swift "
                 + "to enable scrobbling.")
                .font(VPTheme.body(11))
                .foregroundStyle(VPTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Enable toggle

    private var enableRow: some View {
        Toggle(isOn: $scrobbler.enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scrobble tracks")
                    .font(VPTheme.body(12))
                    .foregroundStyle(VPTheme.textPrimary)
                Text("Send plays to your Last.fm profile.")
                    .font(VPTheme.body(11))
                    .foregroundStyle(VPTheme.textSecondary)
            }
        }
        .toggleStyle(.switch)
        .tint(VPTheme.iceAccent)
    }

    // MARK: - Connection row

    @ViewBuilder
    private var connectionRow: some View {
        let connected = client.connectionState.isConnected

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(connected ? Color.green : VPTheme.textMuted)
                    .frame(width: 8, height: 8)
                Text(statusText(connected: connected))
                    .font(VPTheme.body(12))
                    .foregroundStyle(VPTheme.textPrimary)
                Spacer()
            }

            if let note = statusNote {
                Text(note)
                    .font(VPTheme.body(11))
                    .foregroundStyle(VPTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionButtons(connected: connected)
        }
    }

    private func statusText(connected: Bool) -> String {
        if connected, let user = client.username {
            return "Connected as \(user)"
        }
        switch phase {
        case .authorizing: return "Waiting for browser authorization…"
        case .working:     return "Working…"
        case .idle:        return "Not connected"
        }
    }

    @ViewBuilder
    private func actionButtons(connected: Bool) -> some View {
        HStack(spacing: 8) {
            if connected {
                Button("Disconnect", role: .destructive) { disconnect() }
                    .buttonStyle(.bordered)
            } else if phase == .authorizing {
                Button("Complete connection") { completeConnection() }
                    .buttonStyle(.borderedProminent)
                    .tint(VPTheme.iceAccent)
                Button("Cancel") { phase = .idle; statusNote = nil }
                    .buttonStyle(.bordered)
            } else {
                Button("Connect to Last.fm") { startConnection() }
                    .buttonStyle(.borderedProminent)
                    .tint(VPTheme.iceAccent)
                    .disabled(phase == .working)
            }
        }
    }

    // MARK: - Auth actions

    private func startConnection() {
        phase = .working
        statusNote = nil
        Task {
            do {
                let url = try await client.beginAuthorization()
                NSWorkspace.shared.open(url)
                await MainActor.run {
                    phase = .authorizing
                    statusNote = "Approve access in your browser, then click "
                        + "\u{201C}Complete connection\u{201D}."
                }
            } catch {
                await MainActor.run {
                    phase = .idle
                    statusNote = error.localizedDescription
                }
            }
        }
    }

    private func completeConnection() {
        phase = .working
        Task {
            do {
                let session = try await client.completeAuthorization()
                await MainActor.run {
                    phase = .idle
                    statusNote = nil
                    // Nudge the observed scrobbler so any dependent UI refreshes.
                    scrobbler.objectWillChange.send()
                    _ = session
                }
            } catch {
                await MainActor.run {
                    // Stay in .authorizing so the user can retry after approving.
                    phase = .authorizing
                    statusNote = "Couldn't finish: \(error.localizedDescription) "
                        + "Make sure you approved access, then try again."
                }
            }
        }
    }

    private func disconnect() {
        client.clearSession()
        phase = .idle
        statusNote = nil
        scrobbler.objectWillChange.send()
    }
}
