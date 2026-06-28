import SwiftUI
import AppKit

/// The VinylPod application entry point.
///
/// This is a **menu-bar (accessory) app**: there is no Dock icon and no default
/// SwiftUI window. The only on-screen surfaces are:
///   1. the `MenuBarExtra` (the dropdown panel), and
///   2. the single `NSWindow`/`NSPanel` owned by `WindowManager`.
///
/// All startup wiring (Audio ↔ NowPlayingService, building the WindowManager,
/// installing the ⌘1–⌘4 shortcut monitor) happens in `AppDelegate`.
@main
struct VinylPodApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Hand the shared environment objects to the menu-bar content so it can
    // observe now-playing state and read settings.
    private let env = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(env.nowPlaying)
                .environmentObject(env.settings)
        } label: {
            Image(systemName: "opticaldisc")
        }
        // A rich SwiftUI popover panel rather than a plain NSMenu, so we can show
        // now-playing info, transport controls, and the mode picker.
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App lifecycle / wiring

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Strong references so these live for the app's lifetime.
    private var player: LocalAudioPlayer?
    private var metadata: MetadataReader?
    private var colors: ArtworkColorExtractor?
    private var windowManager: WindowManager?

    /// Local key-event monitor for ⌘1–⌘4. Retained so we can remove it on quit.
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app: no Dock icon, no default window — the menu bar extra and
        // the WindowManager's window are the only surfaces.
        NSApp.setActivationPolicy(.accessory)

        let env = AppEnvironment.shared

        // --- Wire the Audio module into the central NowPlayingService ---------
        let player = LocalAudioPlayer()
        let metadata = MetadataReader()
        let colors = ArtworkColorExtractor()
        self.player = player
        self.metadata = metadata
        self.colors = colors

        env.nowPlaying.player = player
        env.nowPlaying.metadata = metadata

        // Player → service progress + completion callbacks.
        player.onTick = { pos, dur in
            env.nowPlaying.reportTick(position: pos, duration: dur)
        }
        player.onFinish = {
            env.nowPlaying.reportFinished()
        }

        // When a new track's artwork is ready, refresh the adaptive accent.
        env.nowPlaying.onTrackChanged = { t in
            if let art = t.artwork {
                env.settings.setAccent(from: colors.dominantColor(from: art))
            } else {
                env.settings.setAccent(from: nil)
            }
        }

        // --- Build the WindowManager with a content factory that injects the
        //     shared environment objects into ModeContentView -------------------
        let wm = WindowManager(settings: env.settings) { mode in
            AnyView(
                ModeContentView(mode: mode)
                    .environmentObject(env.nowPlaying)
                    .environmentObject(env.settings)
            )
        }
        self.windowManager = wm
        // Expose to the menu-bar views and the shortcut handler.
        WindowCoordinator.shared.manager = wm

        // Show the persisted window mode (defaults to .normal).
        wm.show(env.settings.windowMode)

        // --- Install ⌘1–⌘4 keyboard shortcuts --------------------------------
        installModeShortcuts()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    // MARK: - Keyboard shortcuts (⌘1–⌘4 → window modes)

    /// Installs a local key-down monitor that maps ⌘1…⌘4 to the four
    /// `WindowMode`s. Because this is a menu-bar accessory app there is no normal
    /// window menu to host `.keyboardShortcut` items, so we intercept the events
    /// directly. The local monitor fires when the app has key focus (e.g. the
    /// menu-bar panel or the WindowManager's panel); a global monitor could be
    /// added later for system-wide hotkeys, but that would require Accessibility
    /// permission, so we keep it local for now.
    private func installModeShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Require exactly Command (ignore other modifiers like Shift/Option).
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .command else { return event }

            // Match the typed character against each mode's shortcut digit.
            guard let chars = event.charactersIgnoringModifiers, chars.count == 1,
                  let digit = chars.first else { return event }

            if let mode = WindowMode.allCases.first(where: { $0.shortcutKey == digit }) {
                let env = AppEnvironment.shared
                env.settings.windowMode = mode
                WindowCoordinator.shared.manager?.apply(mode: mode)
                return nil // Consume the event — we handled it.
            }
            return event
        }
    }
}
