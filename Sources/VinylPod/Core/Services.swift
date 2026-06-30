import SwiftUI
import AppKit
import Combine

// MARK: - Seams implemented by the Audio module (Agent A)

/// Anything that can actually decode and play an audio file.
/// Implemented by `LocalAudioPlayer` in the Audio module.
@MainActor
protocol AudioPlaying: AnyObject {
    func load(_ url: URL)
    func play()
    func pause()
    func stop()
    func seek(to seconds: TimeInterval)
    /// Called ~10×/sec with (currentPosition, duration).
    var onTick: ((TimeInterval, TimeInterval) -> Void)? { get set }
    /// Called when the current item finishes.
    var onFinish: (() -> Void)? { get set }
}

/// Reads title/artist/album/artwork/duration from a local audio file.
/// Implemented by `MetadataReader` in the Audio module.
@MainActor
protocol MetadataReading {
    func read(_ url: URL) async -> Track
}

/// Extracts album-reactive liquid-glass colors from album art.
/// Implemented by `ArtworkColorExtractor` in the Audio module.
@MainActor
protocol ArtworkColorExtracting {
    func palette(from image: NSImage) -> AlbumColorPalette?
    func dominantColor(from image: NSImage) -> Color?
}

// MARK: - Central observable playback state (Core owns this; everyone reads it)

/// The single source of truth for "what's playing". Views observe it; the
/// Audio module drives it; the menu bar and shortcuts command it.
@MainActor
final class NowPlayingService: ObservableObject {

    @Published private(set) var track: Track = .empty
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    /// Whether the browser extension currently has an open WebSocket to the
    /// local bridge. Set by BrowserBridge on connect/disconnect — it changes
    /// rarely (never per tick), so the settings UI can observe it cheaply.
    @Published private(set) var bridgeConnected: Bool = false

    /// Injected by the Audio module at startup.
    var player: AudioPlaying?
    var metadata: MetadataReading?
    /// Called whenever a new track's artwork is ready, so settings can refresh
    /// the adaptive accent color.
    var onTrackChanged: ((Track) -> Void)?
    /// Set by the BrowserBridge: routes transport commands to the active web
    /// tab when the current track isn't a local file.
    var externalControl: ((ExternalControlAction) -> Void)?

    private var queue: [URL] = []
    private var index: Int = 0

    init() {}

    /// Load a list of local files and start playing the first.
    func load(urls: [URL]) {
        let audio = urls.filter { Self.isAudio($0) }
        guard !audio.isEmpty else { return }
        queue = audio
        index = 0
        playCurrent()
    }

    private func playCurrent() {
        guard queue.indices.contains(index) else { return }
        let url = queue[index]
        player?.load(url)
        Task { [weak self] in
            guard let self else { return }
            var t = await metadata?.read(url) ?? Track(title: url.deletingPathExtension().lastPathComponent, source: .localFile, url: url)
            t.source = .localFile
            t.url = url
            self.track = t
            self.duration = t.duration
            self.onTrackChanged?(t)
        }
        player?.play()
        isPlaying = true
    }

    /// Push state coming from an external source (browser / Spotify / Apple Music).
    func updateFromExternal(_ t: Track, isPlaying playing: Bool, position pos: TimeInterval, duration dur: TimeInterval) {
        // The browser bridge pushes ~1×/sec (on every currentTime tick). React
        // to a REAL track change ONLY: re-assigning `track` and firing
        // onTrackChanged every second re-ran dominant-color extraction and
        // re-triggered the glass/landscape liquid animation at 60fps — a
        // self-sustaining 98%-CPU render loop. Position is the one field that
        // legitimately updates each tick.
        let trackChanged = (t != track)
        if trackChanged { track = t }
        if isPlaying != playing { isPlaying = playing }
        position = pos
        if duration != dur { duration = dur }
        if trackChanged { onTrackChanged?(t) }
    }

    /// Called by BrowserBridge when an extension client connects/disconnects.
    func setBridgeConnected(_ connected: Bool) {
        if bridgeConnected != connected { bridgeConnected = connected }
    }

    func playPause() {
        if track.isEmpty { return }
        isPlaying.toggle()
        if track.source == .localFile {
            isPlaying ? player?.play() : player?.pause()
        } else {
            externalControl?(.playpause)
        }
    }

    func next() {
        if track.source == .localFile {
            guard !queue.isEmpty else { return }
            index = (index + 1) % queue.count
            playCurrent()
        } else {
            externalControl?(.next)
        }
    }

    func previous() {
        if track.source == .localFile {
            guard !queue.isEmpty else { return }
            // Restart current track if >3s in, else go to previous.
            if position > 3 { seek(to: 0); return }
            index = (index - 1 + queue.count) % queue.count
            playCurrent()
        } else {
            externalControl?(.previous)
        }
    }

    func seek(to seconds: TimeInterval) {
        position = seconds
        if track.source == .localFile {
            player?.seek(to: seconds)
        } else {
            externalControl?(.seek(seconds))
        }
    }

    /// Wired by the Audio module's player tick.
    func reportTick(position pos: TimeInterval, duration dur: TimeInterval) {
        position = pos
        if dur > 0 { duration = dur }
    }

    func reportFinished() {
        next()
    }

    static func isAudio(_ url: URL) -> Bool {
        ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "alac", "caf"]
            .contains(url.pathExtension.lowercased())
    }
}

// MARK: - User settings / window state

@MainActor
final class AppSettings: ObservableObject {

    @Published var windowMode: WindowMode = .small {
        didSet { UserDefaults.standard.set(windowMode.rawValue, forKey: "windowMode") }
    }
    @Published var desktopLayer: DesktopLayer = .front {
        didSet { UserDefaults.standard.set(desktopLayer.rawValue, forKey: "desktopLayer") }
    }

    /// Adaptive palette extracted from album art. The whole liquid-glass surface
    /// uses this palette; `accentColor` remains as a convenience for controls.
    @Published var albumPalette: AlbumColorPalette = .iceMountain
    @Published var accentColor: Color = VPTheme.accentFallback
    @Published var useAdaptiveAccent: Bool = true {
        didSet { UserDefaults.standard.set(useAdaptiveAccent, forKey: "useAdaptiveAccent") }
    }

    /// nil → procedural built-in "ice mountain" background. Non-nil → user image.
    @Published var customBackgroundURL: URL? {
        didSet { UserDefaults.standard.set(customBackgroundURL, forKey: "customBackgroundURL") }
    }

    // MARK: - Settings-menu backed state (reference "three-dots" dropdown)

    /// "Music Player Source" radio group.
    @Published var musicSource: PlaybackSource = .spotify {
        didSet { UserDefaults.standard.set(musicSource.rawValue, forKey: "musicSource") }
    }
    /// "Vinyl Style" radio group.
    @Published var vinylStyle: VinylStyle = .image {
        didSet { UserDefaults.standard.set(vinylStyle.rawValue, forKey: "vinylStyle") }
    }
    /// How strongly album colors tint the liquid glass membranes.
    @Published var glassTintStrength: GlassTintStrength = .balanced {
        didSet { UserDefaults.standard.set(glassTintStrength.rawValue, forKey: "glassTintStrength") }
    }

    /// Simple boolean toggles from the dropdown. Persisted by key = property name.
    @Published var showProgress      = true  { didSet { persist("showProgress", showProgress) } }
    @Published var keepWindowInFront = true  { didSet { persist("keepWindowInFront", keepWindowInFront) } }
    @Published var dynamicNotch      = true  {
        didSet {
            persist("dynamicNotch", dynamicNotch)
            WindowCoordinator.shared.manager?.syncDynamicIsland()
        }
    }
    @Published var showInMenuBar     = true  { didSet { persist("showInMenuBar", showInMenuBar) } }
    @Published var launchAtLogin     = false { didSet { persist("launchAtLogin", launchAtLogin) } }
    @Published var showArtworkInDock = false { didSet { persist("showArtworkInDock", showArtworkInDock) } }
    @Published var hideDockIcon      = true  { didSet { persist("hideDockIcon", hideDockIcon) } }
    @Published var coverArtAsWallpaper = false { didSet { persist("coverArtAsWallpaper", coverArtAsWallpaper) } }
    @Published var hideNotchInFullscreen = false { didSet { persist("hideNotchInFullscreen", hideNotchInFullscreen) } }

    private func persist(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
    private static func bool(_ key: String, default def: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? def
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: "windowMode"),
           let m = WindowMode(rawValue: raw) { windowMode = m }
        if let raw = UserDefaults.standard.string(forKey: "desktopLayer"),
           let l = DesktopLayer(rawValue: raw) { desktopLayer = l }
        useAdaptiveAccent = UserDefaults.standard.object(forKey: "useAdaptiveAccent") as? Bool ?? true
        customBackgroundURL = UserDefaults.standard.url(forKey: "customBackgroundURL")
        if let raw = UserDefaults.standard.string(forKey: "musicSource"),
           let s = PlaybackSource(rawValue: raw) { musicSource = s }
        if let raw = UserDefaults.standard.string(forKey: "vinylStyle"),
           let v = VinylStyle(rawValue: raw) { vinylStyle = v }
        if let raw = UserDefaults.standard.string(forKey: "glassTintStrength"),
           let strength = GlassTintStrength(rawValue: raw) { glassTintStrength = strength }
        showProgress      = Self.bool("showProgress", default: true)
        keepWindowInFront = Self.bool("keepWindowInFront", default: true)
        dynamicNotch      = Self.bool("dynamicNotch", default: true)
        showInMenuBar     = Self.bool("showInMenuBar", default: true)
        launchAtLogin     = Self.bool("launchAtLogin", default: false)
        showArtworkInDock = Self.bool("showArtworkInDock", default: false)
        hideDockIcon      = Self.bool("hideDockIcon", default: true)
        coverArtAsWallpaper = Self.bool("coverArtAsWallpaper", default: false)
        hideNotchInFullscreen = Self.bool("hideNotchInFullscreen", default: false)
    }

    func setAccent(from color: Color?) {
        guard useAdaptiveAccent, let color else {
            accentColor = VPTheme.accentFallback
            return
        }
        withAnimation(VPTheme.fade) { accentColor = color }
    }

    func setAlbumPalette(from palette: AlbumColorPalette?) {
        guard useAdaptiveAccent, let palette else {
            guard albumPalette != .iceMountain else { return }   // no-op: skip
            withAnimation(VPTheme.liquid) {
                albumPalette = .iceMountain
                accentColor = VPTheme.accentFallback
            }
            return
        }

        // Defense-in-depth: never re-assign an EQUAL palette. Otherwise the
        // `.animation(value: albumPalette)` on the glass + landscape re-fires and
        // re-renders those expensive views at 60fps for an unchanged cover.
        guard palette != albumPalette else { return }
        withAnimation(VPTheme.liquid) {
            albumPalette = palette
            accentColor = palette.vibrant.color
        }
    }
}

// MARK: - Shared environment

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()
    let nowPlaying = NowPlayingService()
    let settings = AppSettings()
    let shortcuts = ShortcutStore()
    private init() {}
}
