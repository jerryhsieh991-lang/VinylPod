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
        self.port = NWEndpoint.Port(rawValue: port) ?? 8787
    }

    // MARK: - Lifecycle

    func start() {
        do {
            let params = NWParameters.tcp
            let ws = NWProtocolWebSocket.Options()
            ws.autoReplyPing = true
            ws.maximumMessageSize = 256 * 1024   // H1: cap inbound frame size (DoS guard)
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
        // H1: cap concurrent connections so an open-flood can't pile up unbounded.
        if connections.count >= 6, let oldest = connections.first { remove(oldest) }
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
        guard data.count <= 256 * 1024 else { return }   // H1: reject oversized frames
        guard let msg = try? JSONDecoder().decode(InMessage.self, from: data),
              msg.type == "nowplaying",
              let p = msg.payload,
              let title = p.title, !title.isEmpty, title.count <= 2048
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
        guard let s = urlString, !s.isEmpty,
              let url = URL(string: s), let scheme = url.scheme?.lowercased()
        else { completion(nil); return }

        // Cache read — `handle` hops onto `queue` before calling us, so this is
        // safe to read here.
        if s == lastArtworkURL { completion(lastArtworkImage); return }

        // C2: inline data: URI — decode the payload FROM THE STRING. Never use
        // `Data(contentsOf:)`, which would dereference `file://`/other schemes
        // (a payload-controlled local-file read on this unsandboxed app).
        if scheme == "data" {
            let image = Self.decodeDataURI(s).flatMap { Self.normalizedImage(from: $0) }
            lastArtworkURL = s; lastArtworkImage = image     // on `queue`
            completion(image); return
        }

        // C2 (SSRF): only fetch over http(s), and never to loopback / link-local
        // / RFC-1918 hosts — the URL is attacker-controllable via the WS payload.
        guard scheme == "http" || scheme == "https", Self.isPublicHost(url.host) else {
            completion(nil); return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10                              // H1: no hung fetch
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            // H1: cap the in-memory image so a huge response can't blow up RAM.
            let ok = (data?.count ?? 0) <= 8 * 1024 * 1024
            let image = ok ? data.flatMap { Self.normalizedImage(from: $0) } : nil
            guard let self else { completion(image); return }
            self.queue.async {                                // race fix: write on `queue`
                self.lastArtworkURL = s
                self.lastArtworkImage = image
                completion(image)
            }
        }.resume()
    }

    /// Decode a `data:[<mediatype>][;base64],<payload>` URI from the string
    /// itself — string-split, never URL-load (so no `file://` dereference).
    private static func decodeDataURI(_ s: String) -> Data? {
        guard s.hasPrefix("data:"), let comma = s.firstIndex(of: ",") else { return nil }
        let header = s[s.startIndex..<comma].lowercased()
        let payload = String(s[s.index(after: comma)...])
        if header.contains("base64") { return Data(base64Encoded: payload) }
        return payload.removingPercentEncoding?.data(using: .utf8)
    }

    /// Blocks SSRF to loopback / link-local / private ranges before any fetch.
    private static func isPublicHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased(), !h.isEmpty else { return false }
        if h == "localhost" || h == "0.0.0.0" || h == "::1"
            || h.hasSuffix(".local") || h.hasSuffix(".localhost") { return false }
        if h.hasPrefix("127.") || h.hasPrefix("169.254.")
            || h.hasPrefix("10.") || h.hasPrefix("192.168.") { return false }
        if h.range(of: #"^172\.(1[6-9]|2\d|3[01])\."#, options: .regularExpression) != nil { return false }
        return true
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
