# 00 — Product Vision & Target User

> **Slice:** Product intent, not implementation. Read this before 01–05 if you're
> new to the repo — it explains *why* the architecture makes the tradeoffs it does.
> **Sources:** `PRD.md`, `CONTRACTS.md`, `README.md`, `Sources/VinylPod/Core/Models.swift`,
> `BrowserExtension/manifest.json`, `Sources/VinylPod/Views/Widget/SettingsMenu.swift`,
> `Sources/VinylPod/Views/Settings/*.swift`, `docs/system-design/01–05`, git history.

---

## 1. What VinylPod Is

VinylPod is a free, unsandboxed **macOS menu-bar app** that shows what's currently
playing — pulled from a **browser tab** (Spotify Web, Apple Music Web, YouTube,
YouTube Music, or literally any site that implements the W3C MediaSession API) or
from a **local audio file** the user drags in — and renders it as a
**liquid-glass "now playing" widget** in one of five selectable sizes, from a
162×162 corner card up to a full-screen desktop widget, plus an optional
Dynamic-Island-style notch companion. It has no server, no account system, and
(as of this pass) no paywall in the running code — `SettingsMenu.swift`'s "You're
a Pro" row is a static, non-interactive label, not a gate. Capture happens
through a companion browser extension (**VinylPod Connect**, `BrowserExtension/`)
that relays now-playing state over a loopback WebSocket
(`ws://127.0.0.1:8787`) to the native app; there is no cloud round-trip and no
telemetry in the current architecture (`docs/system-design/01-core-architecture.md`,
`03-capture-and-bridge.md`).

The one-line pitch, in the PRD's own words: *"capture and beautifully display
the currently-playing music"* so the app "feels less like software and more
like a quiet, living piece of desktop decor" (`PRD.md` §1). That framing —
decor first, control panel second — is the thread that runs through every
downstream decision: static (not track-reactive) landscape backgrounds, silent
default error states, hover-to-reveal controls on the larger widgets, and a
deliberate progression from a single play/pause glyph (Small) up to a
full desktop scene (Desktop Widget).

---

## 2. The Core Problem It Solves

**The gap:** macOS has no first-class, persistently visible, good-looking
"what's playing" surface for **browser-based** listening. Concretely:

- **Apple's own Now Playing** (Control Center widget, Touch Bar, media keys)
  is built around native apps (Music.app) and MediaRemote-aware apps. It does
  not reliably see a Spotify Web Player tab, a YouTube Music tab, or an
  arbitrary site's `<audio>` element — because those are just web content to
  the OS, not a registered "now playing" client.
- **Native menu-bar now-playing utilities** (Sleeve, Tuneful, NepTunes,
  Vinyls, Silicio, Jukebox) solve this for the *native* Spotify.app / Music.app
  by reading Apple's private `MediaRemote.framework`. That framework was
  restricted by Apple starting **macOS 15.4**, and it never covered browser
  tabs in the first place — someone who lives inside Chrome or Safari and
  streams via the web player gets nothing from these tools.
- **The notch-app tier** (NotchNook, DynamicLake, BoringNotch, Alcove,
  MediaMate) mostly repackages the same MediaRemote-sourced now-playing data
  inside a bigger, more ambitious multi-purpose notch shell (file tray,
  calendar, HUDs). Good if you want a Swiss-army notch; overkill and still
  browser-blind if all you want is "show me the album art from the Spotify tab
  I have open."
- **Paid tiers.** Most of the above charge for the polish (adaptive theming,
  bigger widgets, extra sources). A user who just wants a free, good-looking
  now-playing corner widget for browser playback has no clean free option.

VinylPod's answer is architectural, not cosmetic: instead of asking the OS
"what's playing," it asks the **browser** directly, via a real extension that
reads `navigator.mediaSession` (or site-specific DOM scraping for Spotify/Apple
Music/YouTube/YouTube Music) and relays it over a local socket. This sidesteps
the MediaRemote restriction entirely and is the one piece of capture
infrastructure in this whole competitive set that is *strategically resilient*
to Apple's 15.4 lockdown — because it was never built on the thing Apple
locked down. See `docs/system-design/03-capture-and-bridge.md` and the "Key
design decisions" section of the system-design README for the full rationale.

---

## 3. Target User Profile(s)

The PRD is explicit that the app is designed around two personas balanced
against each other (`PRD.md` §2):

| Persona | PRD label | Signal in the feature set |
|---|---|---|
| **A — Visual / aesthetic listener** | "音乐发烧友 / 视觉控" — music enthusiasts / visual lovers | 5 widget sizes up to a full desktop scene, liquid-glass adaptive theming, vinyl-vs-image style choice, custom background upload, cover-art-as-wallpaper, artwork-as-Dock-icon |
| **D — General / low-friction listener** | "大众普通听众" — general listeners, "simpler the better" | Small mode is play/pause only, empty state is silent (no popups), sensible persisted defaults, one-click size switching from the menu bar |

Beyond the PRD's two headline personas, the actual shipped feature set narrows
the realistic audience further. To get real value out of VinylPod today, someone
needs to be:

- **A browser-first (or at least browser-inclusive) listener.** The primary,
  fully-wired capture path is the browser extension
  (`BrowserExtension/manifest.json` targets `open.spotify.com`,
  `music.apple.com`, `www.youtube.com`, `music.youtube.com`, plus a universal
  MediaSession content script matching `http(s)://*/*`). Someone who exclusively
  uses the native Spotify.app or Music.app desktop apps and never opens a
  browser tab for music gets comparatively little out of the box — native
  desktop-app capture exists only behind an **experimental, off-by-default**
  toggle (`Sources/VinylPod/Views/Settings/CaptureSettingsSection.swift`,
  `Sources/VinylPod/Capture/`), and its own settings copy warns it may return
  nothing on macOS 15.4+.
- **Willing to install a browser extension.** This is a real, non-trivial ask
  compared to a pure native app — VinylPod trades a slightly higher setup cost
  for capture breadth and App-Store-safety. The "Connect a Browser…" row in
  the settings menu (`SettingsMenu.swift`) and the honest, three-state
  "Now Playing From" indicator (playing / connected-but-idle / not-connected)
  exist specifically to manage this onboarding moment.
  point.
- **Someone who keeps a Mac desktop visible and cares how it looks.** The
  Desktop Widget mode is not a toy — it is sized to the full screen at
  runtime, supports front/behind-desktop-icons layering
  (`DesktopLayer.front`/`.back`), and drives a full vinyl-deck animation
  (`DesktopWidgetCanvas`). This is a feature for people who treat their Mac's
  desktop as a surface worth curating (a wallpaper/aesthetics audience), not
  people who live in full-screen apps and never see the desktop.
- **Comfortable with an early-stage, unsandboxed, unsigned-for-distribution
  app.** There's no App Store listing yet, no notarization pipeline in
  `make_app.sh` beyond ad-hoc `codesign --sign -`, and known rough edges (§7
  below). This currently suits an early-adopter / tinkerer audience more than
  a zero-tolerance mainstream user, notwithstanding the "General listener"
  persona's aspirational simplicity goal.
- **Scrobblers and stats-driven listeners** are a secondary but real audience
  now that Last.fm scrobbling exists (`Sources/VinylPod/Scrobbling/`,
  `LastFmSettingsSection.swift`) — someone who already has a Last.fm habit and
  was previously locked out of scrobbling from browser playback specifically
  (Last.fm's own web integrations lean on official Spotify/Apple APIs, not
  arbitrary sites) gets something new here.

**Who this is *not* for (yet):** someone who wants zero setup and only ever
plays music through the native macOS Music app with no aesthetic interest in
their desktop — Apple's Control Center Now Playing already serves that user
better and with no install step at all.

---

## 4. Core Value Proposition

**Stated plainly:** VinylPod turns "what's playing in some browser tab
somewhere" into an always-available, good-looking, customizable-sized desktop
object — for free — without depending on the private OS hook that every other
now-playing utility relies on and that Apple is actively closing off.

Unpacked into three claims, each traceable to a concrete decision in the code:

1. **Breadth of capture at zero cost.** Five real sources unified behind one
   `Track` model and one `NowPlayingService` (`Core/Models.swift`'s
   `PlaybackSource`: `.localFile`, `.browser`, `.spotify`, `.appleMusic`,
   `.none`; the browser extension itself further covers YouTube and YouTube
   Music, and — via the universal MediaSession content script — effectively
   any site with a working `navigator.mediaSession`). No competitor combines
   this breadth with a $0 price tag (`docs/system-design/README.md` §
   "Competitive context & roadmap signals").
2. **A widget that scales to how much attention you want to give it**, not a
   fixed menu-bar text label. Five discrete sizes (`WindowMode`: small /
   normal / regular / large / desktopWidget) share one visual language but
   trade control density for footprint, switchable instantly via menu bar,
   ⌘1–⌘5, or global hotkeys, without interrupting playback
   (`docs/system-design/02-windowing-and-ui.md` §2–3).
3. **Visual craftsmanship that reacts to the music without being distracting.**
   The liquid-glass surfaces (`AdaptiveWidgetGlassBackground`'s six-layer
   stack) tint themselves from the current album art's extracted palette in
   real time, while the landscape background behind everything is
   deliberately static — "visual stability is a hard rule" (`PRD.md` §8) — so
   the app never becomes visually noisy or attention-grabbing by accident.

---

## 5. Feature Set at a Product Level

### Capture breadth
- Browser extension (VinylPod Connect) capturing Spotify Web, Apple Music Web,
  YouTube, YouTube Music via named site-scrapers, plus a **universal**
  MediaSession-API fallback that works on any site with standards-compliant
  media metadata — Chrome (MV3) and Safari (wrapped) both supported.
- Local audio file playback via drag-and-drop, with embedded ID3/AVAsset
  metadata and artwork extraction (`Audio/MetadataReader.swift`).
- **Native desktop-app capture (new, experimental, opt-in)** — reads
  Spotify.app/Music.app directly via the private MediaRemote path as a
  best-effort *addition* to the browser extension, not a replacement; openly
  documented as possibly returning nothing on macOS 15.4+
  (`CaptureSettingsSection.swift`).
- One unified "Now Playing" state (`NowPlayingService`) regardless of which
  source is active, with an honest, live "Now Playing From" indicator instead
  of a static/inert source picker (this replaced an earlier radio-button
  design that changed nothing — see commits `32c3338`, `44dbdc7`).

### Five widget sizes + Dynamic Island
- **Small** (162×162) — artwork + play/pause + minimal glass strip.
- **Medium/Normal** (344×132) — + title/artist + progress + transport.
- **Regular** (300×360) — full-bleed artwork, hover-revealed transport.
- **Large** (320×432) — centered artwork card, full metadata, hover-revealed
  chrome.
- **Desktop Widget** (full screen) — vinyl-deck animation (spinning record +
  swinging tonearm), big clock, front/behind-desktop-icons stacking toggle,
  hover-revealed control row.
- Optional **Dynamic Island**: a pinned top-center notch companion,
  independent of the main widget's position, with its own collapsed
  (pill/equalizer) and expanded (full transport) states.
- All switching is instant, non-destructive to playback, and persisted across
  launches.

### Liquid-glass adaptive theming
- Album artwork drives a four-token color palette (dominant / vibrant / muted
  / shadow) extracted off-main via CoreImage, animated in with a 1.05s cinematic
  cross-fade, and consumed by every glass surface, the landscape overlay, and
  even the settings dropdown tint.
- User-adjustable glass intensity (Subtle / Balanced / Vivid) and a manual
  accent-color override for anyone who prefers a fixed palette over
  album-adaptive color.

### Vinyl/image style choice
- `VinylStyle.vinyl` — spinning-record rendering with art on the label
  (matches the "decor" framing from the PRD).
- `VinylStyle.image` — flat album-art card, for a cleaner/more literal look.

### Last.fm scrobbling (new)
- Full OAuth-style connect flow (`LastFmClient`/`LastFmScrobbler`,
  `LastFmSettingsSection.swift`) — browser-based authorization, "Complete
  connection" handshake, live connected-as-`username` status, disconnect.
- Directly closes the single most commonly cited feature gap versus Sleeve,
  Tuneful, NepTunes, and Silicio, and is now a genuine differentiator working
  with a source (browser playback) those competitors don't uniformly cover
  either.

### Settings depth
- A proper multi-tab Settings window (⌘,) — General / Appearance / Sources /
  Shortcuts / About — replacing an earlier single crowded dropdown.
- Fully user-recordable global keyboard shortcuts (Carbon hotkeys, no
  Accessibility-permission prompt required) for play/pause, next/previous,
  open player, cycle widget size, jump to fullscreen, toggle desktop layer,
  toggle notch, toggle menu bar.
- System-integration toggles: launch at login, hide Dock icon, show album art
  as the Dock icon, set album art as desktop wallpaper (with reversible
  restore), hide notch in fullscreen, keep-window-in-front stacking.
- Custom background image upload (replaces the default ice-mountain landscape)
  with PNG/JPEG/HEIC support via a native file picker.

---

## 6. Competitive Positioning

From the session's live research against Sleeve, Tuneful, NepTunes, Vinyls,
Silicio, Jukebox, and the notch tier (NotchNook, DynamicLake, BoringNotch,
Alcove, MediaMate) — summarized here as background, not re-verified in this
pass (see `docs/system-design/README.md` § "Competitive context & roadmap
signals" for the same conclusions in architecture-doc form):

| Dimension | VinylPod | The field |
|---|---|---|
| Price | Free, no tiers enforced in code | Mostly paid or freemium-gated |
| Browser/web capture | Primary path — Spotify Web, Apple Music Web, YouTube, YouTube Music, universal MediaSession (any site) | Not covered, or covered only incidentally |
| Native desktop-app capture | Experimental, opt-in, best-effort (macOS 15.4+ may block it) | Primary path for most competitors (via MediaRemote) |
| Resilience to macOS 15.4 MediaRemote lockdown | High — browser path is architecturally independent of it | Low — the whole tier's core capture mechanism is what got restricted |
| Widget size options | 5 (162×162 up to full-screen) | Typically 1 fixed menu-bar/notch presentation |
| Full desktop-spanning mode | Yes (Desktop Widget, front/behind-icons toggle) | Not offered |
| Optional Dynamic-Island-style surface | Yes, now-playing-only | The notch tier (NotchNook etc.) offers this but as one of many notch functions — more mature and more crowded there |
| Adaptive liquid-glass theming | Yes, real-time album-palette extraction across all surfaces | Varies; several competitors have simpler static theming |
| Last.fm scrobbling | Yes (new) | Present in Sleeve, Tuneful, NepTunes, Silicio — was the biggest gap, now closed |
| App Store distribution safety | Yes by architecture (no private-API dependency in the default path) | Several competitors' MediaRemote dependency is a live App Store risk |

**What VinylPod still lacks vs. the field:**
- **Maturity of the notch surface.** The Dynamic Island here is
  now-playing-only; NotchNook/BoringNotch/DynamicLake bundle file trays,
  calendar, HUD volume/brightness, and more. Not a differentiator, just
  parity-minus.
- **No App Store presence yet** — `VinylPodLinks.appStoreURL` is a placeholder
  URL (`https://apps.apple.com/app/vinylpod`), and `make_app.sh` produces an
  ad-hoc-signed local build, not a notarized/distributable one.
- **No account system, sync, or cross-device state** — single-machine only,
  by design so far.
- **Native capture is second-class, not a peer path.** Competitors built
  entirely around MediaRemote get one consistent experience with native apps;
  VinylPod's native path is explicitly labeled experimental and may silently
  return nothing.

---

## 7. Known Rough Edges / Early-Stage Caveats

Being upfront about where this stands today (per `docs/system-design/01`, `02`,
`05` "Known Risks" sections, git history, and the current working tree):

- **A widget size-switch CPU regression is actively being tracked down in this
  session.** The repo has prior, *fixed and verified* history of a severe
  98%-CPU idle render-loop bug (`bed0c39`, `8a4383f`, documented in detail in
  `docs/system-design/05-security-performance-build.md` §3) caused by an
  always-on parent view observing `NowPlayingService.position` directly. The
  current uncommitted working tree (branch `claude/security-crash-fixes`)
  touches `WindowManager.swift` and several widget files as part of an
  in-progress follow-up pass, and a new instance of a runaway CPU spin
  triggered specifically by switching widget sizes has been observed and is
  still being isolated as of this writing. Treat size-switching as an area
  that needs a fresh Instruments pass before considering the render-loop
  discipline in doc 05 fully re-verified.
- **No App Store listing, no notarization.** `make_app.sh` ad-hoc-signs
  locally (`codesign --sign -`); Gatekeeper will flag a build shared outside
  this machine. "Rate us" and the App Store URL are placeholders.
- **`BrowserBridge` has no authentication.** Any local process that knows
  `127.0.0.1:8787` can push arbitrary track metadata or receive transport
  commands. Acceptable for a loopback-only bridge on a single-user machine,
  but explicitly called out as unmitigated in `docs/system-design/05` §2.3.
- **Native (MediaRemote) capture is best-effort and may go dark on macOS
  15.4+.** This is disclosed directly in the Settings UI copy, not hidden.
- **Local-file queue has no shuffle/repeat/persistence** — a plain `[URL]`
  array with an index (`docs/system-design/01-core-architecture.md` §7).
- **Wallpaper-restore-on-crash gap.** If the app crashes while "Cover art as
  wallpaper" is enabled, the user's original wallpaper is not restored,
  because the saved URL lives only in memory, not `UserDefaults`.
- **Single-screen assumption for the Dynamic Island** on multi-monitor setups
  — it always pins to the primary screen's top-center even if the main widget
  lives on a secondary display.
- **No automated test suite.** `AppEnvironment.shared` is a singleton with no
  DI seam for tests; correctness currently rests on manual verification and
  the invariant documentation in `docs/system-design/05`.
- **Persona-D ("simplest possible") aspiration is not fully realized yet.**
  The five-tab Settings window, capture/experimental toggles, and Last.fm
  auth handshake represent real settings depth that a zero-friction general
  listener would likely never need to open — the app currently serves
  Persona A (visual/aesthetic) more completely than Persona D.

---

## 8. Summary

VinylPod's bet is narrow and specific: don't try to be the one now-playing app
that does everything (that's the crowded notch tier); be the one that
**actually sees browser playback**, **costs nothing**, and **looks like it was
designed rather than defaulted**. The architecture (browser extension +
loopback bridge, one `NowPlayingService` state core, five-mode window system,
album-adaptive liquid glass) is built entirely in service of that bet, and the
two newest features — Last.fm scrobbling and experimental native capture —
are direct responses to the two gaps that same bet left open. The product is
early-stage and still has real rough edges (most acutely, an unresolved
size-switch CPU regression currently under investigation), but the core
differentiation — capture breadth immune to Apple's MediaRemote lockdown,
free, five-size adaptive widget, liquid-glass theming — is real and already
built, not aspirational.
