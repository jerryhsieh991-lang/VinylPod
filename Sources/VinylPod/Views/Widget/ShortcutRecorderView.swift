import SwiftUI
import AppKit

/// A single "pill" control for recording a global shortcut for one
/// `ShortcutAction`. Matches a row in the dark "Keyboard shortcuts" window.
///
/// Resting state shows the bound combo (with a tiny ✕ to clear) or
/// "Record Shortcut" when nothing is bound. Clicking enters recording mode,
/// where a local key-down monitor captures the next key combination.
struct ShortcutRecorderView: View {
    let action: ShortcutAction
    @EnvironmentObject var store: ShortcutStore

    /// CLT macro workaround: use `@VPState`, never `@State` (see Theme.swift).
    @VPState private var recording = false
    /// Strong reference to the installed local event monitor so we can remove
    /// it again. `nil` means no monitor is currently installed.
    @VPState private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 6) {
                Text(label)
                    .font(VPTheme.body(12))
                    .foregroundColor(recording ? VPTheme.textPrimary : VPTheme.textSecondary)
                    .lineLimit(1)

                // Trailing clear (✕) target — only when a combo exists and we
                // aren't mid-recording. Tapping it clears the binding without
                // triggering the pill's record action.
                if !recording, store.combo(for: action) != nil {
                    Spacer(minLength: 0)
                    Button {
                        store.clear(action)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(VPTheme.textMuted)
                            .padding(2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 150, height: 24, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VPTheme.radiusSmall, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: VPTheme.radiusSmall, style: .continuous)
                    .strokeBorder(VPTheme.glassStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(VPTheme.spring, value: recording)
        // Belt-and-suspenders: never leak a monitor if the view goes away
        // while recording. `stopRecording()` is idempotent.
        .onDisappear(perform: stopRecording)
    }

    /// Resting label: the bound combo's display, or the prompt text. While
    /// recording we show a hint instead.
    private var label: String {
        if recording { return "Press keys" }
        if let combo = store.combo(for: action) { return combo.display }
        return "Record Shortcut"
    }

    private func toggleRecording() {
        if recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        recording = true
        // Install a LOCAL key-down monitor. Returning nil from the handler
        // SWALLOWS the event so the captured keystroke doesn't type/act
        // anywhere else in the app while we're recording.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Escape (keyCode 53) cancels recording without binding anything.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            // Otherwise try to build a combo. `from` returns nil if no modifier
            // is held — in that case we keep listening (and still swallow it).
            if let combo = KeyCombo.from(event) {
                store.set(combo, for: action)
                stopRecording()
            }
            return nil // swallow the event regardless
        }
    }

    /// Tear down recording state and remove the monitor. Guarded against
    /// double-removal so it is safe to call from the handler, the button, and
    /// `.onDisappear`.
    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if recording {
            withAnimation(VPTheme.fade) { recording = false }
        }
    }
}
