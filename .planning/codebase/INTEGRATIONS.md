# External Integrations

**Analysis Date:** 2026-07-03

## APIs & External Services

**Now-Playing Capture (primary path — Browser Bridge):**
- The "VinylPod Connect" MV3 browser extension captures now-playing data from web players and streams it to the native app over a loopback WebSocket.
  - Native server: `NWListener` + `NWProtocolWebSocket` bound to `ws://127.0.0.1:8787`, loopback-only, in `Sources/VinylPod/Bridge/BrowserBridge.swift`
  - Extension client: `service-worker.js` connects to `WS_URL = "ws://127.0.0.1:8787"`
  - Message protocol: extension -> app `{type:"nowplaying", payload:{…}}`; app -> extension `{type:"vinylpod:control", action, value?}`
  - Auth: none — trust is established by loopback binding only (never exposed on the network)
  - Hardening: max inbound frame 256 KB, max 6 concurrent connections (DoS guards in `BrowserBridge.accept`)

**Web-player sources (extension content scripts, `BrowserExtension/`):**
- Spotify Web — `sites/spotify.js` (DOM-scrape of `[data-testid="now-playing-widget"]`, ISOLATED world, real button clicks for control)
- Apple Music Web — `sites/apple-music.js`
- YouTube Music — `sites/youtube-music.js`
- YouTube — `sites/youtube.js`
- Universal fallback — `universal-relay.js` (ISOLATED) + `mediasession-main.js` (MAIN world, reads `navigator.mediaSession`) for any other site
- Shared adapter/polling/diff/control engine: `cs-common.js` (`VinylPodRun()`)
- Extension host permissions: `open.spotify.com`, `music.apple.com`, `www.youtube.com`, `music.youtube.com`, plus `http://*/*` + `https://*/*` for the universal relay
- Extension permissions: `tabs`, `storage`, `scripting`, `alarms`

**Native desktop capture (optional, opt-in supplement):**
- MediaRemote private framework, runtime-resolved in `Sources/VinylPod/Capture/NativeMediaRemoteCapture.swift`
  - Captures now-playing from Spotify.app / Music.app desktop apps
  - Symbols resolved via `dlopen`/`dlsym` of `/System/Library/PrivateFrameworks/MediaRemote.framework` (nothing links against it)
  - Entitlement-gated on macOS 15.4+ — typically returns an EMPTY dict to unsigned third-party apps, in which case it silently no-ops
  - Enabled only via `AppSettings.nativeCaptureEnabled`; updates pushed to main queue at <=1 Hz
  - The browser bridge remains the DEFAULT; this only supplements it

**Scrobbling — Last.fm API 2.0:**
- Client: `Sources/VinylPod/Scrobbling/LastFmClient.swift` (`actor LastFmClient`)
  - Endpoint: `https://ws.audioscrobbler.com/2.0/`
  - Transport: `URLSession` async/await (15s request timeout)
  - Auth: desktop auth-token flow (`beginAuthorization()` fetches token -> user authorizes in browser -> `completeAuthorization()` exchanges for a session key)
  - Request signing: MD5 `api_sig` via CryptoKit
  - Write methods: `track.updateNowPlaying`, `track.scrobble`
  - Credentials: hardcoded constants `LASTFM_API_KEY` / `LASTFM_API_SECRET` (empty by default; subsystem no-ops until both are set)
- Scrobble driver: `Sources/VinylPod/Scrobbling/LastFmScrobbler.swift` — scrobbles once threshold (50% of length OR 4 minutes) is met, timed off a wall-clock start timestamp

**Spotify / Apple Music "Connect" (scaffolded):**
- Spotify.app / Music.app are reached indirectly via the MediaRemote native capture path and via web content scripts. No direct Spotify Web API / Apple MusicKit OAuth client is wired — `NowPlayingService` (`Sources/VinylPod/Core/Services.swift`) accepts state "coming from an external source (browser / Spotify / Apple Music)" but there is no dedicated OAuth service module for these providers.

## Data Storage

**Databases:**
- None. No database engine, no ORM.

**File Storage:**
- Local filesystem only — bundled artwork resource `Sources/VinylPod/Resources/majestic-ice-mountain-stockcake.jpg`; local audio files read via AVFoundation

**Caching:**
- In-memory artwork cache in `BrowserBridge` (`lastArtworkURL` / `lastArtworkImage`) to avoid re-downloading covers each tick
- `chrome.storage.session` in the extension service worker holds the latest aggregate now-playing record

## Authentication & Identity

**Auth Provider:**
- Last.fm desktop auth-token flow only (see above). Session key persisted in `UserDefaults` (`lastfm.sessionKey`, `lastfm.username`).
- No app-level user accounts, no SSO, no OAuth2 for Spotify/Apple.

## Monitoring & Observability

**Error Tracking:**
- None. Diagnostics via `NSLog` (e.g. BrowserBridge listener failures, MediaRemote single-line diagnostic).

**Logs:**
- `NSLog` to the system log in the native app; `console` in the browser extension.

## CI/CD & Deployment

**Hosting:**
- Not applicable — locally-built, ad-hoc-signed macOS `.app` distributed via `dist/VinylPod.app`

**CI Pipeline:**
- None detected (no `.github/workflows`, no CI config)

## Environment Configuration

**Required config for full functionality:**
- `LASTFM_API_KEY` and `LASTFM_API_SECRET` constants in `LastFmClient.swift` (optional; scrobbling off until set)
- Browser extension installed and pointed at `ws://127.0.0.1:8787` (optional; native MediaRemote capture is an alternative)

**Secrets location:**
- Last.fm API credentials hardcoded in source (empty by default). No `.env` file present. No secret manager.

## Webhooks & Callbacks

**Incoming:**
- Loopback WebSocket frames from the browser extension (`{type:"nowplaying"}`) received by `BrowserBridge` on `ws://127.0.0.1:8787`

**Outgoing:**
- Control commands to the extension (`{type:"vinylpod:control", action, value?}`) over the same WebSocket
- Last.fm `track.updateNowPlaying` / `track.scrobble` HTTPS POSTs

---

*Integration audit: 2026-07-03*
