# codex.md — VinylPod Living Project Map
<!-- Source of truth for WHAT this project is right now. Update at the end of every landed feature. -->
<!-- Last-verified: 2026-07-03 · Pairs with CLAUDE.md (HOW to work). Points to deep SSOTs; does not duplicate them. -->

> **How to use this file:** `CLAUDE.md` tells the AI *how to behave*; this file tells it *what exists*.
> When code and this file disagree, **code wins** — fix this file in the same change.

---

## 1. Vision & Goals

**VinylPod** is a free, native **macOS menu-bar (accessory / `LSUIElement`) app** that captures and
beautifully displays the currently-playing track as a **liquid-glass "now-playing" widget** floating
over a calm, static landscape backdrop.

- **Who it's for:** (A) music/visual lovers who want desktop decor, and (D) general listeners who want
  zero learning curve. Every decision is balanced against those two.
- **Core value:** *"The landscape is the soul; the UI is a whisper of glass on top of it."* Visually
  striking yet dead-simple.
- **Three input sources, one display layer:** local audio files (drag-drop), any **browser tab**
  (via the bundled extension), and native desktop players (Spotify / Apple Music, opt-in & OS-gated).
- **Distinguishing bet:** capture via a **browser extension + loopback WebSocket** instead of Apple's
  private `MediaRemote.framework` (restricted in macOS 15.4, blocks Mac App Store) — App-Store-safe and
  cross-browser. Trade-off: an extension install is required; only *browser* playback is seen on 15.4+.

Deeper: `PRD.md` (product intent), `docs/system-design/00-product-vision.md`.

---

## 2. System Architecture (data flow)

```
Browser tab ─content script─► MV3 service worker ─ws://127.0.0.1:8787─┐
Local file  ─────────────────► LocalAudioPlayer ─────────────────────┐│
Native app  ─────────────────► NativeMediaRemoteCapture (opt-in) ───┐││
                                                                     ▼▼▼
                    NowPlayingService  ◄── updateFromExternal() / reportTick()
                    (@MainActor · single source of truth · @Published track/isPlaying/position/duration)
          ┌──────────────┬──────────────────┬───────────────────┬──────────────┐
          ▼              ▼                  ▼                   ▼              ▼
   ArtworkColorExtractor  SwiftUI Views    AppSettings       externalControl()  LastFmScrobbler
   → AlbumColorPalette    (glass widgets)  (UserDefaults)    → transport out    (on $track only)
   {dominant,vibrant,
    muted,shadow}
```

- **One state core, many inputs.** Every source funnels through the *same* `NowPlayingService`
  ingress; `track.source` (`PlaybackSource{localFile,browser,spotify,appleMusic,none}`) is the
  discriminator. Transport routes on it: `localFile` → `LocalAudioPlayer`; else → `externalControl`
  relay back through the WebSocket.
- **Bridge** (`Bridge/BrowserBridge.swift`): `NWListener`+`NWProtocolWebSocket`, **loopback-only**
  bind `127.0.0.1:8787` (default port `8787`), 256 KB frame cap, 6-connection cap, SSRF guard on
  artwork URLs (blocks `file://`/loopback/RFC-1918), 8 MB / 10 s image fetch cap. Flood-guarded
  (coalescing + adaptive 10 Hz→2 Hz flush; commit `630f629`).
- **Palette** (`Audio/ArtworkColorExtractor.swift`): `paletteOffMain` (nonisolated CoreImage) →
  Sendable `AlbumColorPalette` → liquid-glass membrane tint scaled by `GlassTintStrength`.
- **Composition root:** `AppEnvironment.shared` (`Core/Services.swift`) holds `nowPlaying` + `settings`.

Deeper: `architecture.md` (six pillars), `docs/system-design/01…03`.

---

## 3. Directory & File Map

All paths below are confirmed present in `~/Projects/VinylPodMac`.

```
Sources/VinylPod/
  Core/        Models.swift · Services.swift · Theme.swift · Shortcuts.swift   ← FROZEN (see CONTRACTS.md)
  Audio/       LocalAudioPlayer · MetadataReader · ArtworkColorExtractor       (AVFoundation / CoreImage)
  Bridge/      BrowserBridge.swift                                             (loopback WebSocket server)
  Capture/     NativeMediaRemoteCapture.swift                                  (private MediaRemote, dlopen'd, opt-in)
  Scrobbling/  LastFmClient · LastFmModels · LastFmScrobbler                   (Last.fm, off by default)
  Windowing/   WindowManager.swift                                            (NSPanel reuse, levels, AX exposure)
  MenuBar/     MenuBarContentView.swift                                        (mode picker popover)
  Hotkeys/     HotKeyManager.swift                                             (Carbon global hotkeys)
  App/         VinylPodApp.swift · WindowCoordinator.swift · SettingsEffects.swift
  Views/       ModeContentView · GlassPanel · VisualEffectBlur · LandscapeBackground · ProgressBarView · TransportControls
  Views/Settings/  SettingsWindow + {General,Appearance,Capture,LastFm,About}SettingsSection.swift
  Views/Widget/    Small/Regular/Large glass widgets · DesktopWidgetCanvas · DynamicIslandWidget ·
                   VinylDiskView · MusicVisualizerContainerView · GroovePulse · SettingsMenu · AlbumArtCloseButton · …
  Resources/   default landscape artwork (bundled via Package.swift .process("Resources"))

BrowserExtension/     MV3 extension: manifest.json · service-worker.js · cs-common.js ·
                      mediasession-main.js · universal-relay.js · sites/{spotify,apple-music,youtube,youtube-music}.js · icons/
SafariExtension/      VinylPodConnect/ — Xcode Safari Web Extension wrapper (needs Xcode to build)
e2e/                  bridge_stress_test.js · bridge_stress_test_codex.js · e2e_size_switching.spec.js (JXA/AX harness)
docs/system-design/   00…07 canonical product+architecture slices · settings-audit.md
Tests/                present but NOT wired into Package.swift (no testTarget yet)
dist/                 make_app.sh output → VinylPod.app (git-ignored)
```

**Root docs (SSOT index):**
| Topic | Read |
|---|---|
| AI behavior / red lines | `CLAUDE.md` |
| This map / current state | `codex.md` (this file) |
| Architecture (six pillars) | `architecture.md` |
| Frozen module interfaces | `CONTRACTS.md` |
| Design tokens / visual spec | `design_system.md` |
| Product requirements | `PRD.md` |
| Swarm / agent operating rules | `agents.md` |
| Restart point / session log | `progress.txt` (newest on top) |
| Feature task graph | `features.json` (+ 8 per-surface `*_features.json`) |

---

## 4. Active Progress & Roadmap

> Sync this section from `progress.txt` (newest entry on top) whenever a slice lands.
> **Working branch:** `claude/security-crash-fixes` · **tree is currently dirty** (6 uncommitted files:
> `AlbumArtCloseButton`, `SettingsMenu`, `WindowManager`, `e2e_size_switching.spec.js`, `features.json`,
> `progress.txt`) — do **not** commit without asking.

**✅ Done & verified**
- 0-warning `swift build`; app compiles, launches, renders.
- Local-file drag-drop playback; ID3 metadata + artwork; adaptive album-art accent palette.
- **5 window modes** — Small 162² · Medium(`normal`) 344×132 · Regular 300×360 · Large 320×432 ·
  Desktop 1280×800/full — plus a separate **Dynamic Island** panel. Menu-bar picker + ⌘1–⌘5.
- Empty / loading / error states; procedural ice-mountain + custom-image background.
- Browser-extension MediaSession capture → loopback bridge; flood-optimized
  (avg ~20 % / peak ~25 % under 8-conn flood, settles to ~7 % = 30fps vinyl baseline; was permanent 100 %).
- Creative layer slice 1 — **GroovePulse** beat *simulation* (no system-audio tap): CRE-001..003 done
  (groove/vinyl/liquid-disc share one tempo per song, no new render clock).
- E2E: `bridge_stress_test.js`; `e2e_size_switching.spec.js` **GREEN** 2026-07-02 (5/5 modes, 0 failures)
  after AX-exposure fixes (`WindowManager.exposeToAccessibility`, `PinnablePanel`, JXA `el[key]()`).

**🚧 In progress / uncommitted**
- Security/crash-fix branch edits to `WindowManager` / `SettingsMenu` / `AlbumArtCloseButton`.
- Creative backlog: CRE-004 ambient color-temperature; optional cassette-hub micro-wobble.

**🔜 Next**
- Land & commit the dirty security-crash-fix tree (after review).
- Real streaming wiring (Spotify/Apple Music) — seams exist (`updateFromExternal`), needs OAuth/entitlements.
- Spec-correct Last.fm (real API keys, Keychain storage, offline scrobble queue).

Deeper: `progress.txt`, `docs/system-design/07-feature-inventory.md`.

---

## 5. Known Issues & Technical Debt

- **`make_app.sh` does not abort on build failure.** The `swift build … | grep … | tail` pipe masks
  `swift build`'s exit code (no `pipefail`); the script only hard-fails if the binary is *entirely
  absent*. A failed *rebuild* over a stale binary **silently ships the previous build.** Watch the
  build log, not just the "✓ Built" line.
- **Native MediaRemote capture no-ops on macOS 15.4+.** `MRMediaRemoteGetNowPlayingInfo` is
  entitlement-gated and returns an empty dict to unsigned apps; handled gracefully (no crash), but the
  Capture settings toggle appears to do nothing on 15.4+. Off by default.
- **Last.fm is scaffold-only.** `LASTFM_API_KEY`/`_SECRET` are empty placeholders; session key is stored
  in **UserDefaults, not Keychain**; **no scrobble retry/queue** (a failed scrobble is lost).
- **Hardware hotkey firing is unverified in CI.** Synthetic key events need TCC/Accessibility, which
  headless runs lack — requires a ~10 s manual check. Shortcut *persistence* format is verified:
  flat-array JSON `["action",{combo}]` under UserDefaults key `keyboardShortcuts`.
- **Dynamic Island Settings popover is orphaned from AX** — never appears in the accessibility tree, so
  it is not drivable headlessly; only the main widget-window popover is automatable.
- **Docs reconciled 2026-07-03:** `README.md` / `CONTRACTS.md` / `architecture.md` synced to **5 modes / ⌘1–⌘5**
  (was the old "4 / ⌘1–4" drift; `regular` had been added in code). A `.git/hooks/post-commit` hook now warns
  when a `Sources/`-only commit leaves docs untouched. See `progress.txt`.
- **Two diverged working copies exist.** `~/Projects/VinylPodMac` (this repo — eng/e2e/AX/creative work)
  and `~/Desktop/VinylPodMac` (a `.planning/` GSD docs branch, newer git timestamp). They have diverged;
  reconcile before assuming either is fully authoritative. **Never build under `~/Desktop`** (iCloud
  quarantine xattrs break `codesign`).
- **Disk pressure:** this machine sits ~97 % full; builds have hit 100 % mid-run. `df -h /` before long
  builds; suspect a full disk on any I/O error.
- **`Tests/` is not wired** into `Package.swift` (no `testTarget`) — verification is via `swift build`
  gate + `e2e/` scripts, not `swift test`.
