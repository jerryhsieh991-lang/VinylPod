import Foundation
import CryptoKit
import AppKit

// ============================================================================
// MARK: - USER CONFIGURATION
// ============================================================================
//
// >>> PASTE YOUR LAST.FM API CREDENTIALS HERE <<<
//
// Create an API account at https://www.last.fm/api/account/create to obtain
// these two values, then replace the empty strings below. Until BOTH are set,
// the entire scrobbling subsystem no-ops gracefully (no network calls, no
// crashes) and the settings panel shows a "not configured" note.
//
private let LASTFM_API_KEY    = ""   // e.g. "0123456789abcdef0123456789abcdef"
private let LASTFM_API_SECRET = ""   // e.g. "fedcba9876543210fedcba9876543210"
//
// ============================================================================

/// Thin async Last.fm 2.0 API client: desktop auth-token flow, request signing
/// (MD5 `api_sig`), and the two write methods the scrobbler needs
/// (`track.updateNowPlaying`, `track.scrobble`).
///
/// Networking is `URLSession` async/await off the main thread. This type is an
/// `actor` so its pending-token state is serialized without touching MainActor.
actor LastFmClient {

    /// Shared instance the scrobbler and settings UI both use.
    static let shared = LastFmClient()

    private let apiRoot = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    private let session: URLSession

    /// The auth token fetched by `beginAuthorization()`, awaiting the user to
    /// authorize it in the browser and then call `completeAuthorization()`.
    private var pendingAuthToken: String?

    // Persistence keys.
    private static let sessionKeyDefault = "lastfm.sessionKey"
    private static let usernameDefault   = "lastfm.username"

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Configuration / persisted session

    /// True only when BOTH credential constants are filled in.
    nonisolated var isConfigured: Bool {
        !LASTFM_API_KEY.isEmpty && !LASTFM_API_SECRET.isEmpty
    }

    /// The persisted session key, if the user has connected. `nonisolated` so
    /// the UI can read it synchronously without awaiting the actor.
    nonisolated var sessionKey: String? {
        let k = UserDefaults.standard.string(forKey: Self.sessionKeyDefault)
        return (k?.isEmpty ?? true) ? nil : k
    }

    /// The persisted Last.fm username, if connected.
    nonisolated var username: String? {
        let u = UserDefaults.standard.string(forKey: Self.usernameDefault)
        return (u?.isEmpty ?? true) ? nil : u
    }

    /// Coarse state for the settings UI.
    nonisolated var connectionState: LastFmConnectionState {
        guard isConfigured else { return .notConfigured }
        if let u = username, sessionKey != nil { return .connected(username: u) }
        return .disconnected
    }

    /// Forget the persisted session (Disconnect button).
    nonisolated func clearSession() {
        UserDefaults.standard.removeObject(forKey: Self.sessionKeyDefault)
        UserDefaults.standard.removeObject(forKey: Self.usernameDefault)
    }

    private func persist(session: LastFmSession) {
        UserDefaults.standard.set(session.sessionKey, forKey: Self.sessionKeyDefault)
        UserDefaults.standard.set(session.username, forKey: Self.usernameDefault)
    }

    // MARK: - Request signing (MD5 api_sig)

    /// Last.fm signature: MD5 over the params sorted by key name, concatenated
    /// as `key+value` (no separators), with the shared secret appended, all
    /// UTF-8. `format`/`callback` params are excluded from the signature.
    private func apiSignature(for params: [String: String]) -> String {
        let joined = params
            .filter { $0.key != "format" && $0.key != "callback" }
            .sorted { $0.key < $1.key }
            .map { $0.key + $0.value }
            .joined()
        let digest = Insecure.MD5.hash(data: Data((joined + LASTFM_API_SECRET).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Build a signed, JSON-formatted request. `httpMethod` is "GET" or "POST".
    private func signedRequest(params rawParams: [String: String],
                               httpMethod: String) -> URLRequest {
        var params = rawParams
        params["api_key"] = LASTFM_API_KEY
        params["api_sig"] = apiSignature(for: params)
        params["format"]  = "json"

        if httpMethod == "POST" {
            var req = URLRequest(url: apiRoot)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded; charset=utf-8",
                         forHTTPHeaderField: "Content-Type")
            req.httpBody = Self.formEncode(params).data(using: .utf8)
            return req
        } else {
            var comps = URLComponents(url: apiRoot, resolvingAgainstBaseURL: false)!
            comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
            var req = URLRequest(url: comps.url!)
            req.httpMethod = "GET"
            return req
        }
    }

    /// x-www-form-urlencoded body encoder (spaces as %20, not '+').
    private static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params
            .sorted { $0.key < $1.key }
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }

    // MARK: - Transport

    private func perform(_ request: URLRequest) async throws -> [String: Any] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LastFmError.network(error.localizedDescription)
        }

        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LastFmError.decoding("invalid JSON")
        }
        guard let dict = json as? [String: Any] else {
            throw LastFmError.decoding("unexpected shape")
        }
        // Last.fm returns HTTP 200 even for API errors, with an "error" code.
        if let code = dict["error"] as? Int {
            let msg = dict["message"] as? String ?? "unknown"
            throw LastFmError.api(code: code, message: msg)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LastFmError.network("HTTP \(http.statusCode)")
        }
        return dict
    }

    // MARK: - Desktop auth flow (getToken → authorize → getSession)

    /// Step 1: fetch an auth token and return the browser URL the user must
    /// visit to authorize this API key. Caller opens the URL, the user clicks
    /// "Yes, allow access", then calls `completeAuthorization()`.
    func beginAuthorization() async throws -> URL {
        guard isConfigured else { throw LastFmError.notConfigured }
        let req = signedRequest(params: ["method": "auth.getToken"], httpMethod: "GET")
        let dict = try await perform(req)
        guard let token = dict["token"] as? String, !token.isEmpty else {
            throw LastFmError.decoding("no token in response")
        }
        pendingAuthToken = token
        let authURL = URL(string:
            "https://www.last.fm/api/auth/?api_key=\(LASTFM_API_KEY)&token=\(token)")!
        return authURL
    }

    /// Step 2: exchange the previously-authorized token for a session key and
    /// persist it. Returns the connected session on success.
    @discardableResult
    func completeAuthorization() async throws -> LastFmSession {
        guard isConfigured else { throw LastFmError.notConfigured }
        guard let token = pendingAuthToken else { throw LastFmError.noPendingToken }
        let req = signedRequest(
            params: ["method": "auth.getSession", "token": token],
            httpMethod: "GET")
        let dict = try await perform(req)
        guard let sess = dict["session"] as? [String: Any],
              let key = sess["key"] as? String,
              let name = sess["name"] as? String,
              !key.isEmpty else {
            throw LastFmError.decoding("no session in response")
        }
        let session = LastFmSession(username: name, sessionKey: key)
        persist(session: session)
        pendingAuthToken = nil
        return session
    }

    // MARK: - Scrobbling write methods

    /// `track.updateNowPlaying` — a transient "now playing" push on track change.
    /// No-ops gracefully when unconfigured or unauthenticated.
    func updateNowPlaying(_ item: LastFmScrobbleItem) async {
        guard isConfigured, let sk = sessionKey, item.isSubmittable else { return }
        var params: [String: String] = [
            "method": "track.updateNowPlaying",
            "artist": item.artist,
            "track":  item.track,
            "sk":     sk
        ]
        if !item.album.isEmpty { params["album"] = item.album }
        if item.duration > 0 { params["duration"] = String(Int(item.duration.rounded())) }

        do {
            _ = try await perform(signedRequest(params: params, httpMethod: "POST"))
        } catch {
            NSLog("[Last.fm] updateNowPlaying failed: \(error.localizedDescription)")
        }
    }

    /// `track.scrobble` — permanently record a completed listen.
    /// No-ops gracefully when unconfigured or unauthenticated.
    func scrobble(_ item: LastFmScrobbleItem) async {
        guard isConfigured, let sk = sessionKey, item.isSubmittable else { return }
        var params: [String: String] = [
            "method":    "track.scrobble",
            "artist":    item.artist,
            "track":     item.track,
            "timestamp": String(Int(item.startedAt.timeIntervalSince1970)),
            "sk":        sk
        ]
        if !item.album.isEmpty { params["album"] = item.album }
        if item.duration > 0 { params["duration"] = String(Int(item.duration.rounded())) }

        do {
            _ = try await perform(signedRequest(params: params, httpMethod: "POST"))
        } catch {
            NSLog("[Last.fm] scrobble failed: \(error.localizedDescription)")
        }
    }
}
