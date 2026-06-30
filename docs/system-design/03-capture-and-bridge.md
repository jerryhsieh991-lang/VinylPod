# 03 — Now-Playing Capture & the Browser Bridge

## Overview

VinylPod captures now-playing metadata from web music players (Spotify, Apple Music, YouTube, YouTube Music, and any page that implements the W3C MediaSession API) via a browser extension called **VinylPod Connect**. Because browser sandboxing prevents a native macOS app from reading a web page's media state directly, the extension runs inside the browser, reads whatever it can from the page, and relays the data over a localhost WebSocket to the native app.

The pipeline has four distinct layers:

1. **Page capture** — reads metadata and playback state out of the live web page.
2. **Extension messaging** — shuttles the data from page context into the extension service worker.
3. **WebSocket transport** — the service worker pushes aggregated "active track" state over `ws://127.0.0.1:8787` to the native app.
4. **Native bridge** — `BrowserBridge` receives frames, validates them, downloads artwork, and calls `NowPlayingService.updateFromExternal` on the main actor.

Control commands flow in the opposite direction: native UI → `BrowserBridge.send` → WebSocket → service worker → active tab's content script → DOM button clicks or media-element API calls.

---

## Capture Strategies: Named-Site vs Universal Fallback

The extension uses two parallel capture strategies, selected per origin at install time.

### Named-site DOM scrapers (ISOLATED world)

Four sites get hand-written adapters injected as ISOLATED-world content scripts (they share a DOM read-only view but have full `chrome.*` access):

| Origin | Files | Source tag |
|---|---|---|
| `open.spotify.com` | `cs-common.js` + `sites/spotify.js` | `"spotify"` |
| `music.apple.com` | `cs-common.js` + `sites/apple-music.js` | `"appleMusic"` |
| `www.youtube.com` | `cs-common.js` + `sites/youtube.js` | `"youtube"` |
| `music.youtube.com` | `cs-common.js` + `sites/youtube-music.js` | `"youtubeMusic"` |

Each adapter implements a single `readState()` function that returns a normalized payload or `null` if nothing is playing. The adapter is handed to `VinylPodRun()` in `cs-common.js`, which owns:

- A **1-second polling interval** (`setInterval(tick, 1000)`).
- **Change diffing** via a signature string (title + artist + album + artwork + isPlaying + `Math.round(currentTime)` + `Math.round(duration)`) — only changed payloads are sent, so the service worker is not flooded by the advancing clock.
- Normalization (coerce all fields to proper types, trim strings, guard `NaN`).
- Routing to the service worker via `chrome.runtime.sendMessage({ type: "vinylpod:nowplaying", payload })`.
- Listening for `{ type: "vinylpod:control" }` from the service worker and delegating to `adapter.controls`.

Each adapter also does **inline artwork URL rewriting** to request higher-resolution art before the payload ever leaves the page. For example, Spotify's now-playing bar serves a 64 px thumbnail (`ab67616d00004851`); `spotify.js` rewrites the hash fragment to `ab67616d0000b273` (640 px) in `readState()`. The service worker has a second pass in `boostArtworkURL()` so any URL that slipped through (e.g. from the universal path) is also upgraded.

### Universal MediaSession fallback (MAIN + ISOLATED world pair)

All other origins (i.e., everything that is not one of the four named sites) receive two co-injected scripts:

| Script | World | Role |
|---|---|---|
| `mediasession-main.js` | MAIN | Reads `navigator.mediaSession` (metadata + playbackState) and live `<video>`/`<audio>` elements; polls every 1 second; posts `window.postMessage` frames tagged `{ __vinylpod: true }`. |
| `universal-relay.js` | ISOLATED | Listens for those `postMessage` frames, stamps `source: "mediaSession"`, and calls `chrome.runtime.sendMessage` to the service worker. Also forwards SW control messages back into the page via `postMessage`. |

The split is forced by the MV3 privilege boundary: `navigator.mediaSession` is a MAIN-world object that ISOLATED scripts cannot access. Injecting into MAIN gives read access to metadata; injecting the relay into ISOLATED gives access to `chrome.runtime` APIs.

**Safari compatibility shim.** Safari recognises `world: "MAIN"` in manifest `content_scripts` as a no-op on some versions, so `mediasession-main.js` would never run from the manifest declaration alone. `universal-relay.js` works around this by dynamically appending a `<script src="...">` tag via `chrome.runtime.getURL()`, which forces execution in the page's own context on both browsers. A guard variable (`window.__vinylpodMainInstalled`) prevents double-initialisation on Chrome where the manifest already ran it.

---

## Service Worker Aggregation

`service-worker.js` is the central aggregation and relay point. It is an MV3 event-driven service worker (no persistent background page; can be suspended by the browser at any time).

### Per-tab state

```
tabState: Map<tabId, { payload, ts: Date.now() }>
```

Every `vinylpod:nowplaying` message from any content script updates this map for the sender's tab. `vinylpod:gone` deletes the tab's entry. Tab removal (`chrome.tabs.onRemoved`) also deletes it.

### Active-tab selection

`recomputeActive()` walks the map and picks:

1. The most-recently-updated tab whose `payload.isPlaying === true` (playing-preferred).
2. Falling back to the most-recently-updated tab overall.

This means if Spotify is paused and YouTube is playing, YouTube wins. If nothing is playing, the most-recently-active tab's metadata is kept visible (so the UI doesn't go blank just because the user hit pause).

### Artwork boosting

Before any payload is stored in `tabState` or forwarded anywhere, `boostArtworkURL()` rewrites thumbnail URLs for four CDNs:

- **Spotify** (`i.scdn.co`): hash fragment → `ab67616d0000b273` (640 px).
- **Apple Music / mzstatic**: `{w}x{h}` template or `WxH` segment → 1200 px.
- **Google CDN** (`googleusercontent.com`, `ggpht.com`): `=wW-hH` / `=sN` → 1200 px.
- **YouTube thumbnails** (`ytimg.com`): low-quality variants → `sddefault.jpg` (640×480, always present — `maxresdefault` would 404 on non-HD videos).

### Injection into already-open tabs

Declarative `content_scripts` only auto-inject on navigation, so a music tab that was open _before_ the extension was installed or updated would never receive any scripts. On `chrome.runtime.onInstalled`, the service worker calls `injectOpenTabs()`, which queries all open HTTP/HTTPS tabs and programmatically injects the correct script set via `chrome.scripting.executeScript`, mirroring the manifest mapping exactly.

---

## WebSocket Transport

### Connection lifecycle (lazy + quiet)

The WebSocket to `ws://127.0.0.1:8787` is managed with an explicit quiet-window mechanism to avoid console noise when the native app is not running.

Every refused WebSocket attempt logs an uncatchable `net::ERR_CONNECTION_REFUSED` in DevTools that cannot be swallowed in `onerror`. The only way to stay quiet is to not attempt at all. The logic:

- **Never connect at startup.** `wsEnsure()` is only called from `publish()` (when a content script reports a track) and from the heartbeat alarm.
- **Skip if nothing is playing** (`hasDeliverableTrack()` checks `tabState` for any non-null payload).
- **Honor the quiet window** (`wsQuietUntil` epoch-ms). The window is stored in `chrome.storage.session` so it survives service-worker restarts (the worker can be torn down between checks).
- **On connection failure / close**: set a quiet window. If the app was seen at least once this session (`wsAppSeen = true`), use 15 seconds (likely a transient drop); otherwise use 2 minutes (app is probably not running).
- **On successful open**: clear the quiet window; immediately send the current active payload.
- **Heartbeat alarm**: `chrome.alarms` fires every 30 seconds (`periodInMinutes: 0.5`), calling `wsEnsure()`. This is the wake-from-suspension mechanism — Safari's MV3 runtime aggressively suspends service workers during idle, which would silently kill the WebSocket. The alarm keeps re-establishing the bridge while music is playing.

Net effect with the app closed and nothing playing: zero connection attempts, zero console errors. With music playing and the app closed: one attempt every 2 minutes.

---

## Native App Bridge: `BrowserBridge`

`BrowserBridge` is a Swift class that wraps Apple's `Network.framework` (`NWListener` + `NWProtocolWebSocket`) to run a loopback-only WebSocket server. No third-party dependencies.

### Binding

```swift
params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
```

Bound explicitly to loopback. The server is never reachable from the network.

### Connection cap

```swift
if connections.count >= 6, let oldest = connections.first { remove(oldest) }
```

At most 6 concurrent connections are kept. An open-flood would evict the oldest connection rather than growing unbounded.

### Inbound frame handling (`handle(_ data: Data)`)

1. Reject frames larger than 256 KB.
2. Decode `{ type: "nowplaying", payload: { … } }` via `JSONDecoder`.
3. Require `type == "nowplaying"` and a non-empty `title` (≤ 2048 chars). Null or empty payloads are silently ignored — this preserves any local-file track that is currently playing in the native player.
4. Map `payload.source` to `PlaybackSource` (see Wire Format below).
5. Download cover art via `loadArtwork()` (cached by URL).
6. Hop to `@MainActor` via `Task { @MainActor in … }` and call `nowPlaying.updateFromExternal(track, isPlaying:, position:, duration:)`.

### Artwork loading

`loadArtwork()` handles two cases:

- **`data:` URI**: decoded entirely from the string (split on the comma, base64-decode the payload). The `data:` scheme is handled without ever calling `URL.load` or `Data(contentsOf:)`, which would dereference `file://` URLs and constitute a local-file read.
- **`http://` or `https://` URL**: validated against an allowlist that blocks loopback (`127.*`, `::1`, `localhost`), link-local (`169.254.*`), and RFC-1918 private ranges (`10.*`, `192.168.*`, `172.16–31.*`). Fetch is capped at 10 seconds timeout and 8 MB response. This guards against SSRF where a malicious page could craft an artwork URL pointing at a local service.

The downloaded image is normalized: `NSBitmapImageRep` is extracted and the `NSImage.size` is set to the bitmap's pixel dimensions so SwiftUI renders it at true resolution rather than scaling from a small logical point size.

Artwork is cached by URL — if the same URL arrives in the next tick (which happens every second), the previously downloaded image is returned immediately without a network fetch.

### `updateFromExternal` — change guard

`NowPlayingService.updateFromExternal` applies a critical optimization: only changes that represent a genuine track change trigger `onTrackChanged`. Position ticks every second but is written directly. Without this guard, every 1-second tick would re-trigger dominant-color extraction and the liquid-glass animation at 60 fps — a self-sustaining ~98% CPU render loop.

### Outbound control frames

```swift
func send(_ action: ExternalControlAction)
```

Serializes a `{ type: "vinylpod:control", action, value? }` object and sends it as a text WebSocket frame to **all** open connections. The service worker's `ws.onmessage` handler receives it and calls `dispatchControl(action, value)`, which routes the command to the active tab via `chrome.tabs.sendMessage`.

---

## Sequence Diagram

```mermaid
sequenceDiagram
    participant Page as Web Page (MAIN world)
    participant Main as mediasession-main.js
    participant Relay as universal-relay.js (ISOLATED)
    participant Adapter as sites/*.js + cs-common.js (ISOLATED)
    participant SW as service-worker.js
    participant WS_S as ws://127.0.0.1:8787 (server)
    participant BB as BrowserBridge (Swift)
    participant NPS as NowPlayingService

    Note over Page,Adapter: Two parallel capture paths (only one runs per tab)

    alt Named site (Spotify / Apple Music / YouTube / YT Music)
        loop Every 1 second
            Adapter->>Page: readState() — DOM scrape
            Page-->>Adapter: { title, artist, artwork, isPlaying, currentTime, duration }
            Adapter->>Adapter: diff signature; skip if unchanged
            Adapter->>SW: chrome.runtime.sendMessage({type:"vinylpod:nowplaying", payload})
        end
    else Universal fallback (any other origin)
        loop Every 1 second
            Main->>Page: read navigator.mediaSession.metadata + <video>/<audio>
            Page-->>Main: metadata + playback state
            Main->>Main: diff signature; skip if unchanged
            Main->>Relay: window.postMessage({__vinylpod:true, kind:"nowplaying", payload})
            Relay->>Relay: stamp source:"mediaSession"
            Relay->>SW: chrome.runtime.sendMessage({type:"vinylpod:nowplaying", payload})
        end
    end

    SW->>SW: boostArtworkURL(payload.artwork)
    SW->>SW: tabState.set(tabId, {payload, ts})
    SW->>SW: recomputeActive() → pick playing tab or most-recent tab
    SW->>SW: chrome.storage.session.set({nowPlaying})
    SW->>SW: wsEnsure() — lazy connect if quiet window elapsed

    alt WebSocket not open
        SW->>WS_S: new WebSocket("ws://127.0.0.1:8787")
        WS_S-->>SW: onopen
        SW->>SW: wsAppSeen=true; clearQuietWindow
    end

    SW->>WS_S: ws.send({type:"nowplaying", payload})
    WS_S->>BB: NWConnection.receiveMessage(data)
    BB->>BB: decode InMessage; validate type + title length
    BB->>BB: mapSource(payload.source) → PlaybackSource
    BB->>BB: loadArtwork(payload.artwork) — cache / SSRF-check / fetch
    BB->>NPS: @MainActor: updateFromExternal(track, isPlaying, position, duration)
    NPS->>NPS: diff track; set position; fire onTrackChanged only if track changed

    Note over BB,SW: Reverse path — control commands

    NPS->>BB: externalControl?(.playpause / .next / .prev / .seek(s))
    BB->>WS_S: ws.send({type:"vinylpod:control", action, value?})
    WS_S->>SW: ws.onmessage → dispatchControl(action, value)
    SW->>Adapter: chrome.tabs.sendMessage(activeTabId, {type:"vinylpod:control", action, value})
    Adapter->>Page: adapter.controls.playpause() / .next() / .prev() / .seek(s)
    Page->>Page: button.click() or videoEl.currentTime = s

    Note over SW: Heartbeat alarm fires every 30s
    SW->>SW: wsEnsure() — re-establish if suspended
```

---

## Wire Format Contract

### Extension → Native App (inbound to `BrowserBridge`)

**Frame type**: WebSocket text frame, UTF-8 JSON.

```json
{
  "type": "nowplaying",
  "payload": {
    "source":      "spotify" | "appleMusic" | "youtube" | "youtubeMusic" | "mediaSession",
    "title":       "string (non-empty, ≤ 2048 chars)",
    "artist":      "string (may be empty)",
    "album":       "string (may be empty)",
    "artwork":     "https://… | data:image/…;base64,… | \"\"",
    "isPlaying":   true | false,
    "currentTime": 42.0,
    "duration":    213.0
  }
}
```

**Null/absent payloads** (when no tab has active media) are sent as `{ "type": "nowplaying", "payload": null }` and are silently dropped by `BrowserBridge.handle` — a null payload is not a reason to clear a locally-playing track.

**Source mapping** (performed in `BrowserBridge.mapSource`):

| `payload.source` | `PlaybackSource` |
|---|---|
| `"spotify"` | `.spotify` |
| `"appleMusic"` | `.appleMusic` |
| `"youtube"`, `"youtubeMusic"`, `"mediaSession"`, anything else | `.browser` |

### Native App → Extension (outbound from `BrowserBridge.send`)

**Frame type**: WebSocket text frame, UTF-8 JSON.

```json
{ "type": "vinylpod:control", "action": "playpause" }
{ "type": "vinylpod:control", "action": "next" }
{ "type": "vinylpod:control", "action": "prev" }
{ "type": "vinylpod:control", "action": "seek", "value": 42.0 }
```

`value` is a `Double` (seconds) and is only present for `"seek"`. The service worker forwards this to `activeTabId` via `chrome.tabs.sendMessage`; the content script's `onMessage` handler dispatches to `adapter.controls`.

### Internal extension messaging (content script → service worker)

```json
{ "type": "vinylpod:nowplaying", "payload": { … } }
{ "type": "vinylpod:gone" }
{ "type": "vinylpod:get" }   // response: { payload: … | null }
{ "type": "vinylpod:control", "action": "…", "value": … }
```

### Internal extension messaging (MAIN ↔ ISOLATED via `window.postMessage`)

```json
{ "__vinylpod": true, "kind": "nowplaying", "payload": { … } }
{ "__vinylpod": true, "kind": "gone" }
{ "__vinylpod": true, "kind": "control", "action": "…", "value": … }
```

The `__vinylpod` sentinel and `e.source !== window` guard prevent foreign pages from injecting spoofed messages.

---

## Design Decisions and Trade-offs

### Why a browser extension instead of a private/native API?

Spotify, Apple Music, and YouTube do not expose their web-player state over any public macOS API. The native Spotify app exposes AppleScript / Apple Events for track info, but the _web_ player (which many users prefer, especially on the free tier) does not. The MediaSession W3C API lives in the browser's MAIN JavaScript world — inaccessible from a sandboxed native app or a Node/Swift process. A browser extension is the only standards-compliant way to read it without reverse-engineering a private protocol or scraping TLS-decrypted traffic.

**Trade-off**: the user must install a browser extension and grant permissions. The extension cannot be distributed on the Chrome Web Store or Safari App Extensions Gallery without a developer account. For a personal/open-source tool this is acceptable; for a commercial product it would be a distribution bottleneck.

### Why DOM scraping instead of relying purely on MediaSession?

Spotify, Apple Music, and YouTube all set `navigator.mediaSession` metadata in their web players — but the ISOLATED world cannot read it, so the only way to access it is from MAIN. The named-site adapters run in ISOLATED, which means they would need the MAIN→ISOLATED bridge (the universal path) to get MediaSession data. That bridge is asynchronous and adds a round-trip. Direct DOM scraping in ISOLATED is synchronous, more reliable (sites also expose richer fields like album in the DOM than in MediaSession), and lets each adapter implement precise per-site controls.

**Trade-off**: DOM scraping is fragile. A site's CSS class or `data-testid` attribute can change in a deploy with no notice. Each named-site adapter carries comments about which selectors are in use and which are fallbacks. This is the primary ongoing maintenance burden.

### Why a localhost WebSocket instead of native messaging?

Chrome's native messaging host protocol requires a registered helper process and an explicit browser-policy entry that is OS-specific, harder to debug, and ties the extension to a specific app path. A localhost WebSocket:

- Works identically in Chrome, Arc, Brave, Firefox, and Safari (with the Safari App Extension wrapper).
- The native app can start and stop independently of the browser.
- Easy to debug with `wscat` or any WebSocket client.
- Requires no OS-level registration.

**Trade-off**: any local process that knows port 8787 can connect to `BrowserBridge` and receive now-playing data or send control commands. Mitigated by: binding to loopback only (network-unreachable), the connection cap, the 256 KB frame cap, the SSRF guard on artwork URLs, and the title-length validation. There is no authentication token on the socket — a concern for multi-user machines (see Known Risks below).

### Why `NWProtocolWebSocket` (Network.framework) instead of a third-party library?

No dependencies to manage, no SPM resolution conflicts, and first-class OS integration (the listener participates in Network.framework's power-management and privacy APIs automatically). `autoReplyPing = true` handles WebSocket keep-alive at the framework level.

### Active-tab selection strategy

The "playing-preferred, most-recent fallback" strategy in `recomputeActive()` handles the common case where the user has Spotify open in one tab and a paused YouTube video in another. As long as one player is playing, it wins. The fallback to most-recent means the now-playing display doesn't go blank just because the user hit pause — it shows the last-active track, which is the expected behavior.

**Trade-off**: if two tabs are simultaneously playing (e.g., a Spotify song and a YouTube autoplay), the tie is broken by the most-recently-updated timestamp, which is effectively "whichever sent a message last." This can flicker between two sources if both update at the same time. In practice this rarely causes visible problems because users typically only play one thing at a time.

---

## Known Risks and Limitations

### 1. DOM scraper brittleness

Named-site adapters depend on CSS selectors and `data-testid` attributes that web teams change without notice. A single deploy on open.spotify.com or music.apple.com can silently break capture for that source. The universal MediaSession fallback covers the case where the named adapter stops returning a title (it returns `null` and the universal path takes over if the site sets `navigator.mediaSession`), but Spotify does not reliably set MediaSession in its web player, so a broken scraper means no capture at all for that site.

**Mitigation**: the adapter is small and isolated; the selectors section in each file's header lists exactly what to update. A site-change only requires updating one file.

### 2. No WebSocket authentication

`BrowserBridge` accepts any WebSocket connection from `127.0.0.1:8787` without a token or challenge. A malicious local process could:
- Read now-playing metadata (low sensitivity — it's already displayed in the UI).
- Send control commands (play, pause, seek, skip) to whatever tab is active.

On a single-user personal machine this is acceptable. On a shared or multi-user machine (e.g., a Mac with multiple accounts or remote login), it is a real risk.

**Mitigation paths**: a shared secret written to `chrome.storage.local` by the extension and read by the native app; or OS-level validation of the connecting process (Network.framework does not expose this easily).

### 3. Service worker lifecycle gaps

MV3 service workers can be suspended by the browser at any time during idle. Safari is particularly aggressive. If the worker is suspended while music is playing:
- The `tabState` map is lost (it is in-memory).
- The WebSocket to the native app drops.
- The heartbeat alarm wakes the worker every 30 seconds, but there is a gap between suspension and the next alarm firing.

`chrome.storage.session` persists the last `nowPlaying` payload and the `wsQuietUntil` value across restarts, but `tabState` is not persisted. After a restart, the worker will re-populate `tabState` from the next message from each content script (which continue running — they are not affected by service worker suspension), so the gap is typically at most one 1-second poll cycle per content script. In practice this is invisible to the user. The native app will see a 15–30 second gap where the WebSocket is down.

### 4. Artwork SSRF residual risk

The artwork URL is attacker-controlled (crafted by the web page's JavaScript). The `isPublicHost` guard in `BrowserBridge` blocks loopback and RFC-1918 ranges. However, it does not perform DNS resolution, so a public-DNS hostname that resolves to a private IP (DNS rebinding) would pass the check. A full mitigation requires an OS-level DNS-resolution step before the URL fetch, which is not currently implemented.

### 5. Safari App Extension wrapper not covered here

The extension ships a `SafariExtensionWrapper/` Xcode target that generates a Safari App Extension from the same JS source. The `manifest.json` `world: "MAIN"` content script is a no-op in Safari, which is why `universal-relay.js` dynamically injects `mediasession-main.js` as a `<script>` tag. Named-site adapters run normally in Safari's ISOLATED world. The Safari wrapper must be distributed as part of the macOS app bundle (App Store or notarised direct download), not as a standalone browser extension, which is a separate packaging concern.

---

## File Map

| File | Layer | Role |
|---|---|---|
| `BrowserExtension/manifest.json` | Config | Declares permissions, host permissions, content script injection rules |
| `BrowserExtension/service-worker.js` | SW | Aggregation, active-tab selection, WebSocket management, heartbeat |
| `BrowserExtension/cs-common.js` | ISOLATED | Shared polling/diffing/reporting harness; dispatched by each named-site adapter |
| `BrowserExtension/sites/spotify.js` | ISOLATED | Spotify DOM adapter + controls |
| `BrowserExtension/sites/apple-music.js` | ISOLATED | Apple Music DOM adapter + controls |
| `BrowserExtension/sites/youtube.js` | ISOLATED | YouTube DOM adapter + controls |
| `BrowserExtension/sites/youtube-music.js` | ISOLATED | YouTube Music DOM adapter + controls |
| `BrowserExtension/mediasession-main.js` | MAIN | Universal `navigator.mediaSession` + `<video>`/`<audio>` reader |
| `BrowserExtension/universal-relay.js` | ISOLATED | MAIN→SW bridge; Safari MAIN injection shim; SW→MAIN control relay |
| `Sources/VinylPod/Bridge/BrowserBridge.swift` | Native | NWListener WebSocket server; artwork fetch + SSRF guard; `NowPlayingService` integration |
| `Sources/VinylPod/Core/Services.swift` | Native | `NowPlayingService.updateFromExternal`; `ExternalControlAction`; `PlaybackSource` enum |
