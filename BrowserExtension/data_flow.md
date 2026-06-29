# VinylPod Extension — Data Flow (Manifest V3, backend only)

## Components
- **Per-site content scripts** (ISOLATED world): `sites/spotify.js`, `sites/apple-music.js`,
  `sites/youtube.js`, `sites/youtube-music.js`. Each defines an *adapter* and calls
  `VinylPodRun(adapter)` from `cs-common.js`. They scrape the DOM (metadata + exact
  `currentTime`/`duration`) and perform control by clicking real buttons / using the
  media element.
- **Universal fallback**: `mediasession-main.js` (MAIN world — can read
  `navigator.mediaSession.metadata`, which the page sets and the isolated world cannot
  see) + `universal-relay.js` (ISOLATED — relays MAIN messages to the service worker
  and handles control via the page's `<video>`/`<audio>` element). Runs on every site
  EXCEPT the four with dedicated scrapers (`exclude_matches`).
- **`cs-common.js`** (ISOLATED): the shared bridge runner — polling, change-diffing,
  reporting, and the control-message listener.
- **`service-worker.js`**: central per-tab state store, message router, control relay,
  and a best-effort `localhost` WebSocket push so the native macOS app can consume data.

## Outbound (capture): page → service worker → consumers
```
[web page DOM / navigator.mediaSession]
        │  (poll every pollIntervalMs, default 1000ms; only emit on change)
        ▼
content script (adapter.readState)            MAIN: mediasession-main.js
        │  chrome.runtime.sendMessage          │  window.postMessage({__vinylpod})
        │   {type:"vinylpod:nowplaying",        ▼
        │    payload:{source,title,artist,    universal-relay.js (ISOLATED)
        │    album,artwork,isPlaying,           │  chrome.runtime.sendMessage(...)
        │    currentTime,duration}}             │
        └───────────────┬──────────────────────┘
                        ▼
              service-worker.js
              • stores state[tabId] = {payload, ts}
              • tracks most-recently-updated tab as "active now playing"
              • chrome.storage.session.set({nowPlaying})   (readable by anything)
              • WS.send(JSON)  → ws://127.0.0.1:8787       (native app, best-effort)
```

## Inbound (control): consumer → service worker → page
```
consumer (native app via WS  OR  chrome.runtime.sendMessage)
   {type:"vinylpod:control", action:"playpause"|"next"|"prev"|"seek", value?}
        ▼
service-worker.js  → picks the active now-playing tab
        │  chrome.tabs.sendMessage(tabId, {type:"vinylpod:control", action, value})
        ▼
content script (cs-common listener) → adapter.controls[action](value)
        ▼
   real DOM button click / mediaElement.play()/pause()/currentTime=
```

## Message contract (frozen — all scrapers code to this)
- Report:  `chrome.runtime.sendMessage({ type: "vinylpod:nowplaying", payload })`
  - `payload = { source, title, artist, album, artwork, isPlaying, currentTime, duration }`
  - `source ∈ {"spotify","appleMusic","youtube","youtubeMusic","mediaSession"}`
  - times in **seconds** (numbers); `artwork` is an https URL string (or "").
- Gone:    `chrome.runtime.sendMessage({ type: "vinylpod:gone" })` when nothing is playing.
- Control: content scripts receive `{ type: "vinylpod:control", action, value? }` and
  `sendResponse({ ok: true|false })`.
- Read:    any context may `chrome.runtime.sendMessage({type:"vinylpod:get"})` →
  responds with the latest aggregated `payload` (or null).

## Memory-leak guards
- Single shared `setInterval` per content script (cleared on `pagehide`).
- Diff before send: never emit identical consecutive payloads (currentTime rounded to
  whole seconds so a steadily-advancing clock doesn't spam, but still updates ~1/s).
- Service worker keeps only one record per tabId and deletes it on `tabs.onRemoved`.
- WebSocket auto-reconnects with backoff; never queues unboundedly.
