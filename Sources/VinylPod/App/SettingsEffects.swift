import AppKit
import Combine
import ServiceManagement

/// Applies app-level side effects whenever the relevant `AppSettings` values
/// (or the current track) change. This is the single place that translates
/// user-facing toggles into real OS behavior: login items, Dock activation
/// policy, the Dock icon image, and the desktop wallpaper.
///
/// Every applier is written to be **idempotent** and **crash-safe** (optionals
/// guarded, all OS calls wrapped in `try?`), so it is safe to run them on every
/// emission of a Combine sink without `.dropFirst()` — the initial `applyAll()`
/// in `start()` establishes the baseline, and re-applying the same state is a
/// no-op.
@MainActor
final class SettingsEffects {

    private let settings: AppSettings
    private let nowPlaying: NowPlayingService

    /// Retains the Combine subscriptions for the lifetime of this instance.
    private var cancellables = Set<AnyCancellable>()

    /// Saved desktop wallpapers, keyed by `NSScreen.localizedName`, captured the
    /// moment "Cover art as wallpaper" is enabled so the user's original desktop
    /// can be restored exactly when it is disabled.
    private var savedWallpapers: [String: URL] = [:]

    init(settings: AppSettings, nowPlaying: NowPlayingService) {
        self.settings = settings
        self.nowPlaying = nowPlaying
    }

    /// Apply current state once, then begin observing for changes.
    func start() {
        applyAll()
        observe()
    }

    // MARK: - Initial / full apply

    private func applyAll() {
        applyLaunchAtLogin()
        applyDockPolicy()
        applyDockArtwork()
        applyWallpaper()
    }

    // MARK: - Observation

    private func observe() {
        // NOTE: every applier below reads the CURRENT property off `settings`/
        // `nowPlaying` (not the value the publisher emits) because most of them
        // depend on several properties at once. `@Published` fires its publisher
        // in `willSet`, i.e. BEFORE the stored property is updated — so a plain
        // `.sink` would read the stale, pre-change value and apply the wrong
        // state (e.g. toggling "Show artwork in Dock" on would read `false` and
        // do nothing; a new track's artwork would lag one track behind). Hop to
        // the next main-runloop tick so the property holds its new value by the
        // time the applier runs. `applyAll()` already set the synchronous
        // baseline in `start()`.

        // 1. Launch at Login.
        settings.$launchAtLogin
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyLaunchAtLogin() }
            .store(in: &cancellables)

        // 2 + 3. Dock policy depends on hideDockIcon + showInMenuBar; whenever the
        // policy may change we must also re-evaluate the Dock artwork (artwork is
        // only shown while the Dock icon is actually visible).
        settings.$hideDockIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDockPolicy()
                self?.applyDockArtwork()
            }
            .store(in: &cancellables)

        settings.$showInMenuBar
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDockPolicy()
                self?.applyDockArtwork()
            }
            .store(in: &cancellables)

        // 3. Show Artwork in Dock.
        settings.$showArtworkInDock
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyDockArtwork() }
            .store(in: &cancellables)

        // 4. Cover art as wallpaper.
        settings.$coverArtAsWallpaper
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyWallpaper() }
            .store(in: &cancellables)

        // 3 + 4. A new track refreshes both the Dock artwork and (if enabled) the
        // wallpaper.
        nowPlaying.$track
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDockArtwork()
                self?.applyWallpaper()
            }
            .store(in: &cancellables)

        // 5. `dynamicNotch` is owned by WindowManager because it creates an
        // independent non-activating panel.
        //
        // AUDIT (hideNotchInFullscreen): intentionally NOT observed. The app has
        // no fullscreen-detection path to hook into — there is no
        // will/didEnterFullScreen observer anywhere in the codebase, and the
        // dynamic-island panel's visibility is driven solely by the `dynamicNotch`
        // toggle in WindowManager.syncDynamicIsland() (a file this module does not
        // own). The only `.fullScreenAuxiliary` usages are NSWindow collection
        // behaviors that let panels float OVER other apps' fullscreen Spaces; they
        // are not a hook for "this app entered fullscreen". Implementing a real
        // effect would require adding a fullscreen observer inside WindowManager.
        // Until that exists this toggle is inert. RECOMMEND REMOVAL — see
        // docs/settings-audit.md.
    }

    // MARK: - 1. Launch at Login

    private func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        if settings.launchAtLogin {
            try? service.register()
        } else {
            try? service.unregister()
        }
    }

    // MARK: - 2. Dock activation policy

    /// `.accessory` (no Dock icon) only when the Dock icon is hidden AND the menu
    /// bar is present — that guarantees the app always keeps at least one entry
    /// point (the Dock icon, the menu bar, or both). Otherwise `.regular`.
    private func applyDockPolicy() {
        guard NSApp != nil else { return }   // no-op before the app finishes launching
        let policy: NSApplication.ActivationPolicy =
            (settings.hideDockIcon && settings.showInMenuBar) ? .accessory : .regular
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    /// Whether the Dock icon is currently visible (i.e. policy is `.regular`).
    private var dockIconVisible: Bool {
        !(settings.hideDockIcon && settings.showInMenuBar)
    }

    // MARK: - 3. Show Artwork in Dock

    // AUDIT (showArtworkInDock): WORKING. Real effect implemented here — sets
    // `NSApp.applicationIconImage` to the current album artwork when the toggle is
    // on and the Dock icon is visible, clears it otherwise. Driven by `$track`
    // (never `$position`, preserving the per-tick perf invariant) and by the Dock
    // policy changes. No change recommended.
    private func applyDockArtwork() {
        guard NSApp != nil else { return }
        // Only paint artwork onto the Dock when both the toggle is on and the
        // Dock icon is actually visible; otherwise clear back to the default icon.
        if settings.showArtworkInDock, dockIconVisible {
            NSApp.applicationIconImage = nowPlaying.track.artwork // nil → default icon
        } else {
            NSApp.applicationIconImage = nil
        }
    }

    // MARK: - 4. Cover art as wallpaper (reversible, confirmed)

    /// Set once the user has explicitly confirmed the wallpaper takeover in the
    /// current enable, so we don't re-prompt on every track change / re-apply.
    private var wallpaperConfirmed = false

    /// AUDIT (coverArtAsWallpaper): overwriting the user's desktop wallpaper via
    /// `NSWorkspace.setDesktopImageURL` is an invasive, system-wide side effect —
    /// it touches every screen and every Space, not just this app's window. The
    /// safe-correct behavior is to (a) require an explicit one-time confirmation
    /// before the FIRST takeover of an enable session, and (b) keep the restore
    /// path fully automatic (undoing an unwanted change must never require a
    /// prompt). If confirmation is declined we revert the toggle. This keeps the
    /// feature but removes the "flip a checkbox and your desktop silently changes"
    /// surprise. If product decides the feature isn't worth the intrusion, see
    /// docs/settings-audit.md for the removal recipe.
    private func applyWallpaper() {
        if settings.coverArtAsWallpaper {
            guard confirmWallpaperTakeoverIfNeeded() else {
                // User declined: revert the toggle. Setting it to false re-enters
                // this method on the next runloop tick and hits the restore branch
                // (a no-op, since nothing was captured/applied yet).
                if settings.coverArtAsWallpaper { settings.coverArtAsWallpaper = false }
                return
            }
            captureWallpapersIfNeeded()
            applyArtworkToWallpaper()
        } else {
            wallpaperConfirmed = false
            restoreWallpapers()
        }
    }

    /// Show a modal confirmation the first time the wallpaper takeover is applied
    /// in an enable session. Returns `true` if we may proceed (already confirmed,
    /// or the user just approved), `false` if the user declined.
    private func confirmWallpaperTakeoverIfNeeded() -> Bool {
        if wallpaperConfirmed { return true }
        let alert = NSAlert()
        alert.messageText = "Use album art as your desktop wallpaper?"
        alert.informativeText = """
        VinylPod will replace your desktop wallpaper on every display with the \
        current album's cover art, and keep changing it as tracks change. Your \
        original wallpaper is saved and restored automatically when you turn this \
        off.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Use Album Art")
        alert.addButton(withTitle: "Cancel")
        let approved = alert.runModal() == .alertFirstButtonReturn
        wallpaperConfirmed = approved
        return approved
    }

    /// Capture each screen's current wallpaper exactly once per enable, so we can
    /// restore the user's original desktop later.
    private func captureWallpapersIfNeeded() {
        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            let key = screen.localizedName
            guard savedWallpapers[key] == nil else { continue }
            if let url = workspace.desktopImageURL(for: screen) {
                savedWallpapers[key] = url
            }
        }
    }

    /// Render the current artwork to a temp PNG and set it on every screen.
    /// No-op if there is no artwork to apply.
    private func applyArtworkToWallpaper() {
        guard let artwork = nowPlaying.track.artwork,
              let url = writeArtworkPNG(artwork) else { return }
        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            try? workspace.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    /// Restore each screen's saved wallpaper, then clear the saved set so a future
    /// enable re-captures a fresh baseline.
    private func restoreWallpapers() {
        guard !savedWallpapers.isEmpty else { return }
        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            if let url = savedWallpapers[screen.localizedName] {
                try? workspace.setDesktopImageURL(url, for: screen, options: [:])
            }
        }
        savedWallpapers.removeAll()
    }

    /// Encode an `NSImage` to a PNG file in the temporary directory.
    private func writeArtworkPNG(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vinylpod-wallpaper-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
