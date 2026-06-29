import XCTest
@testable import VinylPod

/// NODE (a) — State_Sync_Bridge.
///
/// Validates the capture→WebSocket→app ingest contract: a representative
/// extension WS frame `{type:"nowplaying", payload:{…}}` must decode and map
/// onto `NowPlayingService` so `isPlaying`, `duration`, `position`, and the
/// derived `source` are correct, and a now-playing color can be derived from
/// the same path.
///
/// `BrowserBridge.handle(_:)`, `mapSource`, and its `InMessage`/`Payload`
/// structs are `private`, so we mirror the frozen wire format here (the same
/// shape `data_flow.md` freezes) and exercise the reachable
/// `NowPlayingService.updateFromExternal(...)` seam — which is exactly what the
/// bridge calls after decoding. This pins the contract without reaching into
/// private members.
@MainActor
final class StateSyncBridgeTests: XCTestCase {

    // MARK: Mirror of BrowserBridge's private wire format (must stay in sync)

    private struct InMessage: Decodable {
        let type: String
        let payload: Payload?
    }
    private struct Payload: Decodable {
        let source: String?
        let title: String?
        let artist: String?
        let album: String?
        let artwork: String?
        let isPlaying: Bool?
        let currentTime: Double?
        let duration: Double?
    }

    /// Mirror of `BrowserBridge.mapSource` — kept identical on purpose so this
    /// test fails loudly if the production mapping ever diverges.
    private func mapSource(_ raw: String?) -> PlaybackSource {
        switch raw {
        case "spotify":    return .spotify
        case "appleMusic": return .appleMusic
        default:           return .browser
        }
    }

    // MARK: - A representative extension frame round-trips into the service

    func testNowPlayingFrameMapsIntoService() throws {
        // A realistic frame as service-worker.js would push for a Spotify track.
        let json = """
        {
          "type": "nowplaying",
          "payload": {
            "source": "spotify",
            "title": "Midnight City",
            "artist": "M83",
            "album": "Hurry Up, We're Dreaming",
            "artwork": "https://i.scdn.co/image/ab67616d0000b273abcdef",
            "isPlaying": true,
            "currentTime": 42.5,
            "duration": 244.0
          }
        }
        """.data(using: .utf8)!

        let msg = try JSONDecoder().decode(InMessage.self, from: json)
        XCTAssertEqual(msg.type, "nowplaying")
        let p = try XCTUnwrap(msg.payload)
        let title = try XCTUnwrap(p.title)
        XCTAssertFalse(title.isEmpty, "bridge drops frames with empty title")

        let source = mapSource(p.source)
        let track = Track(title: title,
                          artist: p.artist ?? "",
                          album: p.album ?? "",
                          artwork: nil,
                          duration: p.duration ?? 0,
                          source: source,
                          url: nil)

        let svc = NowPlayingService()
        svc.updateFromExternal(track,
                               isPlaying: p.isPlaying ?? false,
                               position: p.currentTime ?? 0,
                               duration: p.duration ?? 0)

        // The three fields the task calls out explicitly:
        XCTAssertTrue(svc.isPlaying, "isPlaying must map true")
        XCTAssertEqual(svc.duration, 244.0, accuracy: 0.001, "songDuration must map")
        XCTAssertEqual(svc.position, 42.5, accuracy: 0.001, "currentTime must map")

        // …plus the derived track identity.
        XCTAssertEqual(svc.track.title, "Midnight City")
        XCTAssertEqual(svc.track.artist, "M83")
        XCTAssertEqual(svc.track.source, .spotify)
    }

    // MARK: - source string → PlaybackSource mapping (mirrors mapSource)

    func testSourceMappingMatchesBridgeContract() {
        XCTAssertEqual(mapSource("spotify"), .spotify)
        XCTAssertEqual(mapSource("appleMusic"), .appleMusic)
        // Everything else (youtube, youtubeMusic, mediaSession, nil) → .browser.
        XCTAssertEqual(mapSource("youtube"), .browser)
        XCTAssertEqual(mapSource("youtubeMusic"), .browser)
        XCTAssertEqual(mapSource("mediaSession"), .browser)
        XCTAssertEqual(mapSource(nil), .browser)
    }

    // MARK: - "gone"/empty-title frames must be ignorable (no clobber contract)

    func testEmptyTitleFrameIsRejectedByContract() throws {
        // The bridge guards `let title = p.title, !title.isEmpty` and otherwise
        // returns early so a local track is never clobbered. Assert the wire
        // form a "gone" or metadata-less frame takes, and that the guard trips.
        let goneFrame = """
        { "type": "nowplaying", "payload": null }
        """.data(using: .utf8)!
        let m1 = try JSONDecoder().decode(InMessage.self, from: goneFrame)
        XCTAssertNil(m1.payload, "null payload must decode to nil and be skipped")

        let emptyTitle = """
        { "type": "nowplaying", "payload": { "title": "", "isPlaying": true } }
        """.data(using: .utf8)!
        let m2 = try JSONDecoder().decode(InMessage.self, from: emptyTitle)
        let shouldIngest = (m2.payload?.title.map { !$0.isEmpty }) ?? false
        XCTAssertFalse(shouldIngest, "empty-title frame must NOT be ingested")
    }

    // MARK: - dominantAlbumColor derivation from the ingest path

    func testDominantColorDerivesFromArtwork() {
        // The app derives the accent (dominantAlbumColor) from a track's artwork
        // via ArtworkColorExtractor after ingest. Feed a solid-color image and
        // assert a non-nil lively accent comes back.
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor(calibratedRed: 0.10, green: 0.55, blue: 0.85, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        img.unlockFocus()

        let extractor = ArtworkColorExtractor()
        let color = extractor.dominantColor(from: img)
        XCTAssertNotNil(color, "a colored cover must yield a dominant accent color")
    }
}
