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
        // 1. Launch at Login.
        settings.$launchAtLogin
            .sink { [weak self] _ in self?.applyLaunchAtLogin() }
            .store(in: &cancellables)

        // 2 + 3. Dock policy depends on hideDockIcon + showInMenuBar; whenever the
        // policy may change we must also re-evaluate the Dock artwork (artwork is
        // only shown while the Dock icon is actually visible).
        settings.$hideDockIcon
            .sink { [weak self] _ in
                self?.applyDockPolicy()
                self?.applyDockArtwork()
            }
            .store(in: &cancellables)

        settings.$showInMenuBar
            .sink { [weak self] _ in
                self?.applyDockPolicy()
                self?.applyDockArtwork()
            }
            .store(in: &cancellables)

        // 3. Show Artwork in Dock.
        settings.$showArtworkInDock
            .sink { [weak self] _ in self?.applyDockArtwork() }
            .store(in: &cancellables)

        // 4. Cover art as wallpaper.
        settings.$coverArtAsWallpaper
            .sink { [weak self] _ in self?.applyWallpaper() }
            .store(in: &cancellables)

        // 3 + 4. A new track refreshes both the Dock artwork and (if enabled) the
        // wallpaper.
        nowPlaying.$track
            .sink { [weak self] _ in
                self?.applyDockArtwork()
                self?.applyWallpaper()
            }
            .store(in: &cancellables)

        // 5. `dynamicNotch` and `hideNotchInFullscreen` are intentionally no-ops:
        // there is no notch HUD feature in this app yet, so nothing is observed.
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

    private func applyDockArtwork() {
        // Only paint artwork onto the Dock when both the toggle is on and the
        // Dock icon is actually visible; otherwise clear back to the default icon.
        if settings.showArtworkInDock, dockIconVisible {
            NSApp.applicationIconImage = nowPlaying.track.artwork // nil → default icon
        } else {
            NSApp.applicationIconImage = nil
        }
    }

    // MARK: - 4. Cover art as wallpaper (reversible)

    private func applyWallpaper() {
        if settings.coverArtAsWallpaper {
            captureWallpapersIfNeeded()
            applyArtworkToWallpaper()
        } else {
            restoreWallpapers()
        }
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
