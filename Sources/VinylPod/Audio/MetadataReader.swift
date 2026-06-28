import Foundation
import AVFoundation
import AppKit

/// Reads track metadata (title / artist / album / artwork / duration) from a
/// local audio file using the modern async `AVAsset` loading API.
///
/// Everything is best-effort: any missing field falls back to a sensible
/// default (notably title → filename), and an unreadable file never throws out
/// of `read(_:)` — it returns a minimally-populated `Track` so the player UI
/// still has something to show.
@MainActor
final class MetadataReader: MetadataReading {

    init() {}

    func read(_ url: URL) async -> Track {
        // Base track: even if everything below fails, we always return a Track
        // with a usable title (the filename) and the correct source/url.
        var track = Track(
            title: url.deletingPathExtension().lastPathComponent,
            source: .localFile,
            url: url
        )

        let asset = AVURLAsset(url: url)

        // Duration — load independently so a metadata failure doesn't cost us
        // the duration, and vice-versa.
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite && seconds > 0 {
                track.duration = seconds
            }
        } catch {
            // Leave duration at 0; AVAudioPlayer will report it at playback time.
        }

        // Common metadata (title/artist/album/artwork). Wrapped in do/catch so a
        // corrupt or DRM'd file can't crash the read.
        do {
            let items = try await asset.load(.commonMetadata)

            if let title = try await stringValue(for: .commonIdentifierTitle, in: items),
               !title.isEmpty {
                track.title = title
            }
            if let artist = try await stringValue(for: .commonIdentifierArtist, in: items) {
                track.artist = artist
            }
            if let album = try await stringValue(for: .commonIdentifierAlbumName, in: items) {
                track.album = album
            }
            if let artwork = try await artworkImage(from: items) {
                track.artwork = artwork
            }
        } catch {
            // Keep the filename-derived fallback track.
        }

        return track
    }

    // MARK: - Helpers

    /// Pull the first metadata item matching `identifier` and load its string.
    private func stringValue(
        for identifier: AVMetadataIdentifier,
        in items: [AVMetadataItem]
    ) async throws -> String? {
        guard let item = AVMetadataItem.metadataItems(
            from: items,
            filteredByIdentifier: identifier
        ).first else { return nil }
        // `.stringValue` is async-loadable on macOS 13+.
        let value = try await item.load(.stringValue)
        return value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Find the common artwork item and decode its data into an `NSImage`.
    private func artworkImage(from items: [AVMetadataItem]) async throws -> NSImage? {
        guard let item = AVMetadataItem.metadataItems(
            from: items,
            filteredByIdentifier: .commonIdentifierArtwork
        ).first else { return nil }
        // Artwork is delivered as raw image data (JPEG/PNG inside the container).
        guard let data = try await item.load(.dataValue) else { return nil }
        return NSImage(data: data)
    }
}
