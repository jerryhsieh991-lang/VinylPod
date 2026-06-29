# VinylPod Connect — Chrome Extension (backend capture engine)

Manifest V3 extension that captures now-playing data (title, artist, album,
**artwork**, isPlaying, currentTime, duration) from web players and exposes
bidirectional playback control. **No popup / no UI** — it is a data engine.

## Supported sources
- Spotify Web · Apple Music Web · YouTube · YouTube Music (dedicated DOM scrapers)
- Everything else → universal `navigator.mediaSession` + media-element fallback

## How to load (developer mode)
1. Open `chrome://extensions`
2. Toggle **Developer mode** (top-right)
3. **Load unpacked** → select this `BrowserExtension/` folder
4. Open a supported site and play something.

## How to read the captured data
- From any extension context: `chrome.runtime.sendMessage({type:"vinylpod:get"})`
  → `{ payload: { source,title,artist,album,artwork,isPlaying,currentTime,duration } }`
- Also mirrored to `chrome.storage.session` under key `nowPlaying`.
- **Native macOS app**: the service worker pushes every update as JSON to
  `ws://127.0.0.1:8787` (best-effort, auto-reconnect). Run a tiny WebSocket
  server in the VinylPod app on that port to receive it, and send
  `{type:"vinylpod:control", action:"playpause"|"next"|"prev"|"seek", value?}`
  back over the same socket to control the active tab.

See `data_flow.md` for the full message map and `extension_backend_features.json`
for the build checklist.
