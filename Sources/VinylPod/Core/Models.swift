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

/// The runtime-selectable window sizes. Same visual language, different
/// scale and control density.
enum WindowMode: String, Codable, CaseIterable, Identifiable {
    case small
    case normal
    case regular
    case large
    case desktopWidget

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small:         return "Small"
        case .normal:        return "Medium"
        case .regular:       return "Regular"
        case .large:         return "Large"
        case .desktopWidget: return "Desktop"
        }
    }

    /// Default content size (the desktop widget is sized to the screen at runtime
    /// by the WindowManager, so this is just a sensible fallback).
    var defaultSize: CGSize {
        switch self {
        case .small:         return CGSize(width: 162, height: 162)
        case .normal:        return CGSize(width: 344, height: 132)
        case .regular:       return CGSize(width: 300, height: 360)
        case .large:         return CGSize(width: 320, height: 432)
        case .desktopWidget: return CGSize(width: 1280, height: 800)
        }
    }

    /// Keyboard shortcut digit (⌘1…⌘5).
    var shortcutKey: Character {
        switch self {
        case .small: return "1"
        case .normal: return "2"
        case .regular: return "3"
        case .large: return "4"
        case .desktopWidget: return "5"
        }
    }
}

/// Desktop-widget stacking: in front of every window, or behind everything
/// (below the desktop icons), per the PRD. Also used by the in-art
/// "Window behavior" popover (Above all windows / Below all windows).
enum DesktopLayer: String, Codable, CaseIterable {
    case front
    case back

    var displayName: String { self == .front ? "In Front" : "Behind" }
    /// Label as shown in the in-art Window-behavior popover.
    var behaviorLabel: String { self == .front ? "Above all windows" : "Below all windows" }
}

/// How the center label / artwork is rendered (from the settings "Vinyl Style").
/// Raw values are persisted in UserDefaults — never rename existing cases.
enum VinylStyle: String, Codable, CaseIterable, Identifiable {
    case vinyl      // spinning record with art on the label
    case image      // flat album-art card
    case cassette   // retro tape deck with twin synced gear hubs
    case liquidDisc // boundary-less ambient disc tinted by the album palette

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vinyl:      return "Vinyl"
        case .image:      return "Image"
        case .cassette:   return "Cassette"
        case .liquidDisc: return "Liquid Disc"
        }
    }

    /// Styles that draw their own (round / soft) edge. Call sites skip the
    /// rectangular card chrome — bevel strokes, corner clipping, card shadows —
    /// for these, exactly as they previously did for `.vinyl` only.
    var rendersOwnEdge: Bool {
        switch self {
        case .vinyl, .liquidDisc: return true
        case .image, .cassette:   return false
        }
    }
}

/// User-facing intensity for the album-reactive liquid glass.
enum GlassTintStrength: String, Codable, CaseIterable, Identifiable {
    case subtle
    case balanced
    case vivid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .subtle: return "Subtle"
        case .balanced: return "Balanced"
        case .vivid: return "Vivid"
        }
    }

    var multiplier: Double {
        switch self {
        case .subtle: return 0.72
        case .balanced: return 1.0
        case .vivid: return 1.28
        }
    }
}

/// A transport command routed to an external player (browser tab via the
/// BrowserBridge) when the current track isn't a local file.
enum ExternalControlAction {
    case playpause
    case next
    case previous
    case seek(TimeInterval)
}
