import Foundation
import AppKit
import Network

/// Local WebSocket server that receives now-playing data from the "VinylPod
/// Connect" browser extension and pushes transport commands back to it.
///
/// The extension's service worker connects to `ws://127.0.0.1:8787`, streams
/// `{type:"nowplaying", payload:{…}}` messages, and accepts
/// `{type:"vinylpod:control", action, value?}` in return. We bind to loopback
/// only, use Apple's native `NWProtocolWebSocket` (no dependencies), and hop to
/// the main actor before touching `NowPlayingService`.
final class BrowserBridge {

    private let nowPlaying: NowPlayingService
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "com.vinylpod.browserbridge")

    private var listener: NWListener?
    private var connections: [NWConnection] = []

    // Artwork cache so we don't re-download the same cover every second.
    private var lastArtworkURL: String?
    private var lastArtworkImage: NSImage?

    init(nowPlaying: NowPlayingService, port: UInt16 = 8787) {
        self.nowPlaying = nowPlaying
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    // MARK: - Lifecycle

    func start() {
        do {
            let params = NWParameters.tcp
            let ws = NWProtocolWebSocket.Options()
            ws.autoReplyPing = true
            params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
            params.allowLocalEndpointReuse = true
            // Loopback only — never expose the bridge on the network.
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)

            let listener = try NWListener(using: params)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener.stateUpdateHandler = { state in
                if case .failed(let err) = state {
                    NSLog("BrowserBridge listener failed: \(err)")
                }
            }
            listener.start(queue: queue)
            NSLog("BrowserBridge listening on ws://127.0.0.1:\(port)")
        } catch {
            NSLog("BrowserBridge failed to start: \(error)")
        }
    }

    // MARK: - Connections

    private func accept(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.remove(conn)
            default: break
            }
        }
        connections.append(conn)
        conn.start(queue: queue)
        receive(on: conn)
    }

    private func remove(_ conn: NWConnection) {
        conn.cancel()
        connections.removeAll { $0 === conn }
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.handle(data) }
            if error != nil { self.remove(conn); return }
            self.receive(on: conn)   // re-arm for the next frame
        }
    }

    // MARK: - Inbound: now-playing → NowPlayingService

    private func handle(_ data: Data) {
        guard let msg = try? JSONDecoder().decode(InMessage.self, from: data),
              msg.type == "nowplaying",
              let p = msg.payload,
              let title = p.title, !title.isEmpty
        else { return }   // ignore null/"gone" so we never clobber a local track

        let source = Self.mapSource(p.source)
        let artist = p.artist ?? ""
        let album = p.album ?? ""
        let isPlaying = p.isPlaying ?? false
        let currentTime = p.currentTime ?? 0
        let duration = p.duration ?? 0

        loadArtwork(p.artwork) { [weak self] image in
            guard let self else { return }
            Task { @MainActor in
                // "Music Player Source" filter: only surface the source the user
                // selected in settings (Apple Music / Spotify / Safari Music=browser).
                // A locally-played file is never affected (it doesn't come through here).
                guard source == AppEnvironment.shared.settings.musicSource else { return }
                let track = Track(title: title, artist: artist, album: album,
                                  artwork: image, duration: duration,
                                  source: source, url: nil)
                self.nowPlaying.updateFromExternal(track, isPlaying: isPlaying,
                                                   position: currentTime,
                                                   duration: duration)
            }
        }
    }

    private static func mapSource(_ raw: String?) -> PlaybackSource {
        switch raw {
        case "spotify":    return .spotify
        case "appleMusic": return .appleMusic
        default:           return .browser   // youtube, youtubeMusic, mediaSession
        }
    }

    /// Download cover art (cached by URL). Calls back on a background queue.
    /// Handles http(s) URLs and inline `data:` URLs (some players expose art that
    /// way). The decoded image is normalized to its true PIXEL size so SwiftUI
    /// renders it at full resolution — a low CFBundle/DPI point-size on the rep
    /// would otherwise make a high-res image render soft.
    private func loadArtwork(_ urlString: String?, completion: @escaping (NSImage?) -> Void) {
        guard let s = urlString, !s.isEmpty, let url = URL(string: s) else {
            completion(nil); return
        }
        if s == lastArtworkURL { completion(lastArtworkImage); return }

        // Inline data: URL — decode synchronously, no network.
        if s.hasPrefix("data:"), let data = try? Data(contentsOf: url) {
            let image = Self.normalizedImage(from: data)
            lastArtworkURL = s; lastArtworkImage = image
            completion(image); return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap { Self.normalizedImage(from: $0) }
            self?.lastArtworkURL = s
            self?.lastArtworkImage = image
            completion(image)
        }.resume()
    }

    /// Build an NSImage whose `size` (points) equals its bitmap PIXEL size, so
    /// SwiftUI never upscales a high-res cover from a small logical size.
    private static func normalizedImage(from data: Data) -> NSImage? {
        guard let rep = NSBitmapImageRep(data: data) else { return NSImage(data: data) }
        let image = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Outbound: transport commands → extension

    /// Send a control command to every connected extension client.
    func send(_ action: ExternalControlAction) {
        let obj: [String: Any]
        switch action {
        case .playpause:    obj = ["type": "vinylpod:control", "action": "playpause"]
        case .next:         obj = ["type": "vinylpod:control", "action": "next"]
        case .previous:     obj = ["type": "vinylpod:control", "action": "prev"]
        case .seek(let s):  obj = ["type": "vinylpod:control", "action": "seek", "value": s]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }

        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "control", metadata: [meta])
        queue.async {
            for conn in self.connections {
                conn.send(content: data, contentContext: ctx, isComplete: true,
                          completion: .contentProcessed { _ in })
            }
        }
    }

    // MARK: - Wire format

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
}
