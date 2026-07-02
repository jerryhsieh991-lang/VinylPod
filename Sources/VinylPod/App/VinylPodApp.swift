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
    // Observed so the "Show in Menu Bar" toggle can insert/remove the menu-bar item.
    @ObservedObject private var settings = AppEnvironment.shared.settings

    init() {
        // Headless snapshot mode (dev tool): renders the widget to PNG and
        // exits before any window/menu-bar machinery starts.
        SnapshotRenderer.runIfRequested()
    }

    var body: some Scene {
        // `isInserted` binds the menu-bar item's presence to the setting. (If it's
        // hidden, SettingsEffects forces the Dock icon on so there's still an
        // entry point.)
        //
        // The binding is wrapped so no-op write-backs are dropped: MenuBarExtra
        // re-sets `isInserted` during scene evaluation, and an unconditional
        // setter would fire objectWillChange → re-evaluate → set again, pinning
        // the app at 100% CPU under any burst of unrelated UI invalidations.
        MenuBarExtra(isInserted: Binding(
            get: { settings.showInMenuBar },
            set: { newValue in
                guard settings.showInMenuBar != newValue else { return }
                settings.showInMenuBar = newValue
            }
        )) {
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
    private var browserBridge: BrowserBridge?
    private var hotKeys: HotKeyManager?
    private var settingsEffects: SettingsEffects?

    /// Local key-event monitor for ⌘1–⌘4. Retained so we can remove it on quit.
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app: no Dock icon, no default window — the menu bar extra and
        // the WindowManager's window are the only surfaces.
        NSApp.setActivationPolicy(.accessory)

        // Dev tool: `--dump-live [out.png]` captures the real window then quits.
        SnapshotRenderer.scheduleLiveDumpIfRequested()

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

        // When a new track's artwork is ready, refresh the full liquid-glass
        // palette. Snapshot to Sendable Data first so no non-Sendable NSImage
        // crosses the detached task boundary.
        env.nowPlaying.onTrackChanged = { t in
            guard let snapshot = t.artwork?.tiffRepresentation else {
                env.settings.setAlbumPalette(from: nil)
                return
            }
            Task.detached(priority: .userInitiated) {
                let palette = NSImage(data: snapshot)
                    .flatMap { ArtworkColorExtractor.paletteOffMain(from: $0) }
                await MainActor.run { env.settings.setAlbumPalette(from: palette) }
            }
        }

        // --- Build the WindowManager with a content factory that injects the
        //     shared environment objects into ModeContentView -------------------
        let wm = WindowManager(
            settings: env.settings,
            content: { mode in
                AnyView(
                    ModeContentView(mode: mode)
                        .environmentObject(env.nowPlaying)
                        .environmentObject(env.settings)
                )
            },
            dynamicIslandContent: { onExpansionChange in
                AnyView(
                    DynamicIslandWidget(
                        onExpansionChange: onExpansionChange,
                        onSelectSize: { mode in
                            WindowCoordinator.shared.manager?.apply(mode: mode)
                        },
                        onQuit: { NSApp.terminate(nil) }
                    )
                    .environmentObject(env.nowPlaying)
                    .environmentObject(env.settings)
                )
            }
        )
        self.windowManager = wm
        // Expose to the menu-bar views and the shortcut handler.
        WindowCoordinator.shared.manager = wm

        // Show the persisted window mode (defaults to .normal).
        wm.show(env.settings.windowMode)

        // --- Browser bridge: receive now-playing from the Chrome extension ----
        // Starts a loopback WebSocket server on ws://127.0.0.1:8787. The
        // "VinylPod Connect" extension pushes web now-playing here, and we route
        // transport commands back to the active tab when the source isn't local.
        let bridge = BrowserBridge(nowPlaying: env.nowPlaying)
        self.browserBridge = bridge
        env.nowPlaying.externalControl = { [weak bridge] action in bridge?.send(action) }
        bridge.start()

        // --- Install ⌘1–⌘4 keyboard shortcuts --------------------------------
        installModeShortcuts()

        // --- Global user-recorded hotkeys (Carbon, system-wide, no permission) -
        let hotKeys = HotKeyManager()
        self.hotKeys = hotKeys
        hotKeys.onAction = { [weak self] action in self?.perform(action) }
        env.shortcuts.onChange = { [weak hotKeys] in
            hotKeys?.reload(from: AppEnvironment.shared.shortcuts)
        }
        hotKeys.reload(from: env.shortcuts)

        // --- Apply app-level settings side effects (Launch at Login, Dock icon,
        //     Dock artwork, cover-art wallpaper) and keep them in sync ----------
        let effects = SettingsEffects(settings: env.settings, nowPlaying: env.nowPlaying)
        self.settingsEffects = effects
        effects.start()

        // --- "Open with" / CLI support ---------------------------------------
        // Any audio file paths passed as launch arguments are played at startup,
        // e.g. `open VinylPod.app --args "/path/Song.mp3"`.
        let argURLs = CommandLine.arguments.dropFirst()
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) && NowPlayingService.isAudio($0) }
        if !argURLs.isEmpty {
            env.nowPlaying.load(urls: Array(argURLs))
        }
    }

    /// Finder "Open With" / drag-onto-icon support.
    func application(_ application: NSApplication, open urls: [URL]) {
        let audio = urls.filter { NowPlayingService.isAudio($0) }
        guard !audio.isEmpty else { return }
        AppEnvironment.shared.nowPlaying.load(urls: audio)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    // MARK: - Global hotkey actions

    /// Routes a fired global hotkey to its behavior.
    private func perform(_ action: ShortcutAction) {
        let env = AppEnvironment.shared
        let wm = WindowCoordinator.shared.manager
        switch action {
        case .playPause:     env.nowPlaying.playPause()
        case .nextTrack:     env.nowPlaying.next()
        case .previousTrack: env.nowPlaying.previous()
        case .openPlayer:
            wm?.show(env.settings.windowMode)
            NSApp.activate(ignoringOtherApps: true)
        case .widgetSize:
            // Cycle to the next window size.
            let all = WindowMode.allCases
            if let i = all.firstIndex(of: env.settings.windowMode) {
                let next = all[(i + 1) % all.count]
                wm?.apply(mode: next)
            }
        case .displayFullscreen:
            wm?.apply(mode: .desktopWidget)
        case .windowTopBottom:
            let next: DesktopLayer = env.settings.desktopLayer == .front ? .back : .front
            env.settings.desktopLayer = next
            wm?.applyStacking(next)
        case .toggleNotch:   env.settings.dynamicNotch.toggle()
        case .toggleMenuBar: env.settings.showInMenuBar.toggle()
        case .togglePopover: break  // the menu-bar popover is system-managed
        }
    }

    // MARK: - Keyboard shortcuts (⌘1–⌘5 → window modes)

    /// Installs a local key-down monitor that maps ⌘1…⌘5 to the
    /// `WindowMode`s. Because this is a menu-bar accessory app there is no normal
    /// window menu to host `.keyboardShortcut` items, so we intercept the events
    /// directly. The local monitor fires when the app has key focus (e.g. the
    /// menu-bar panel or the WindowManager's panel); a global monitor could be
    /// added later for system-wide hotkeys, but that would require Accessibility
    /// permission, so we keep it local for now.
    private func installModeShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Require exactly Command (ignore other modifiers like Shift/Option).
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .command else { return event }

            // Match the typed character against each mode's shortcut digit.
            guard let chars = event.charactersIgnoringModifiers, chars.count == 1,
                  let digit = chars.first else { return event }

            // ⌘, → open the tabbed Settings window (standard macOS shortcut).
            if digit == "," {
                SettingsWindowController.shared.show(settings: AppEnvironment.shared.settings)
                return nil // Consume — handled.
            }

            if let mode = WindowMode.allCases.first(where: { $0.shortcutKey == digit }) {
                WindowCoordinator.shared.manager?.apply(mode: mode)
                return nil // Consume the event — we handled it.
            }
            return event
        }
    }
}
