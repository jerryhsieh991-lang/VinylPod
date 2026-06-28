import SwiftUI
import AppKit

/// Where the currently-displayed track is coming from. The app unifies three
/// real input sources behind one "Now Playing" layer.
enum PlaybackSource: String, Codable, CaseIterable {
    case localFile
    case browser
    case spotify
    case appleMusic
    case none

    var displayName: String {
        switch self {
        case .localFile:  return "Local"
        case .browser:    return "Browser"
        case .spotify:    return "Spotify"
        case .appleMusic: return "Apple Music"
        case .none:       return "VinylPod"
        }
    }

    var sfSymbol: String {
        switch self {
        case .localFile:  return "music.note"
        case .browser:    return "globe"
        case .spotify:    return "waveform"
        case .appleMusic: return "applelogo"
        case .none:       return "opticaldisc"
        }
    }
}

/// Immutable snapshot of what is playing right now.
struct Track: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artwork: NSImage? = nil
    var duration: TimeInterval = 0
    var source: PlaybackSource = .none
    var url: URL? = nil

    static let empty = Track()
    var isEmpty: Bool { title.isEmpty && artist.isEmpty && url == nil }

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist &&
        lhs.album == rhs.album && lhs.url == rhs.url && lhs.source == rhs.source
    }
}

/// The four runtime-selectable window sizes. Same visual language, different
/// scale and control density.
enum WindowMode: String, Codable, CaseIterable, Identifiable {
    case small
    case normal
    case large
    case desktopWidget

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small:         return "Small"
        case .normal:        return "Normal"
        case .large:         return "Large"
        case .desktopWidget: return "Desktop Widget"
        }
    }

    /// Default content size (the desktop widget is sized to the screen at runtime
    /// by the WindowManager, so this is just a sensible fallback).
    var defaultSize: CGSize {
        switch self {
        case .small:         return CGSize(width: 180, height: 180)
        case .normal:        return CGSize(width: 360, height: 200)
        case .large:         return CGSize(width: 420, height: 540)
        case .desktopWidget: return CGSize(width: 1280, height: 800)
        }
    }

    /// Keyboard shortcut digit (⌘1…⌘4).
    var shortcutKey: Character {
        switch self {
        case .small: return "1"
        case .normal: return "2"
        case .large: return "3"
        case .desktopWidget: return "4"
        }
    }
}

/// Desktop-widget stacking: in front of every window, or behind everything
/// (below the desktop icons), per the PRD.
enum DesktopLayer: String, Codable, CaseIterable {
    case front
    case back

    var displayName: String { self == .front ? "In Front" : "Behind" }
}
