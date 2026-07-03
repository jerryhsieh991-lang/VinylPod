# Feature Research

**Domain:** macOS menu-bar / desktop now-playing widget (VinylPod)
**Researched:** 2026-07-03
**Confidence:** HIGH (Last.fm spec) / MEDIUM (multi-source precedence, Liquid-Glass UI patterns)

> **Scope note (SUBSEQUENT milestone).** Already-shipping features are intentionally NOT re-catalogued here (five window sizes + Dynamic Island, liquid-glass adaptive theming, local-file playback, MV3 browser capture, empty/loading/error states). This file covers ONLY the three features being added/refined this cycle:
> 1. **Multi-source capture selection & precedence** (Spotify / Apple Music / browser wired end-to-end)
> 2. **Last.fm scrobbling done right** (real keys + correct behavior)
> 3. **UI BLEND** (glass architecture kept; fold in ~40 fresh "VinyIpod UI" mockup refinements)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist in a 2026 now-playing widget. Missing these = product feels broken or half-finished.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Auto-detect the active source** ("last active wins") | System `MediaRemote` and every competitor (SpotMenu, NepTunes, Sleeve) follow whichever player most recently started playing. Users expect the widget to "just follow" what they hit play on. | MEDIUM | Precedence rule keyed on most-recent-playing timestamp per source. VinylPod already funnels all producers through one `updateFromExternal` gate — precedence is a selection policy *in front of* that gate, not a new ingestion path. |
| **Graceful hand-off when a source pauses/ends** | If Spotify pauses and Apple Music is still playing, the widget should switch to the still-playing source, not freeze on stale metadata. | MEDIUM | Needs a per-source `isPlaying` + last-update clock so a paused/dead source yields. Watch the perf invariant: only real changes may fire `onTrackChanged`. |
| **Last.fm: `track.updateNowPlaying` on play start** | Scrobbler users expect their Last.fm profile to show the live track within seconds of pressing play. | LOW | Official API: send immediately on play start; does NOT affect charts; **failures must not be retried**. Already scaffolded in `LastFmScrobbler`; needs real keys + wiring. |
| **Last.fm: scrobble at 50% or 4 min (whichever first), min 30s track** | This is THE canonical scrobble rule; users who scrobble will notice if it fires early, late, or double. | LOW | Official spec: track must be >30s; scrobble once played ≥50% of duration OR ≥4:00, whichever is earlier. Existing threshold logic matches — validate against wall-clock start, not accumulated position, and handle seek/scrub. |
| **Last.fm: correct desktop auth flow** | Users won't paste API secrets; they expect "click, authorize in browser, done." | MEDIUM | Auth-token desktop flow already in `LastFmClient` (`beginAuthorization` → browser → `completeAuthorization`, MD5 `api_sig`, session key in UserDefaults). Needs real `LASTFM_API_KEY`/`SECRET` and a Settings UI to trigger + show connected state/username. |
| **Last.fm: persistent offline scrobble queue** | Network drops mid-listen are common; a scrobbler that silently loses plays feels broken. | MEDIUM | Official spec: maintain a local cache that **survives app restart**, send cached scrobbles **before** new ones (chronological order), batch up to **50** per request. Current placeholder has no durable queue — this is the biggest correctness gap. |
| **Manual source override** | When auto-detect guesses wrong (browser tab steals Now Playing from desktop Spotify), users expect to force a preferred source. | LOW–MEDIUM | Every serious competitor (SpotMenu auto/manual, Mac Media Key Forwarder) offers this. A simple picker: Auto / Browser / Spotify / Apple Music. |
| **Legible now-playing text over glass** | Liquid Glass's own biggest complaint (TidBITS) is contrast; title/artist must stay readable over any album-art tint. | LOW | Already partly solved via `AlbumColorPalette`; the BLEND pass must not sacrifice legibility for translucency. Respect `Reduce Transparency`. |

### Differentiators (Competitive Advantage)

Features that set VinylPod apart. Should reinforce Core Value ("browser playback every competitor misses, beautifully displayed").

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Unified browser + desktop + local precedence in one widget** | Competitors are usually Spotify-and-Apple-Music-only (desktop apps). VinylPod already captures *any browser tab* via MediaSession AND local files AND (opt-in) desktop — folding all into one precedence policy is genuinely differentiated. | MEDIUM | This is the moat. Precedence must rank across heterogeneous producers (browser bridge, local player, native capture) not just two desktop apps. |
| **Source badge / provenance indicator** | Show a small glyph for where the track is coming from (browser / Spotify / Apple Music / local). Users with multiple sources want to know which one is showing. | LOW | Cheap, high-clarity. `Track.source` (`PlaybackSource` enum) already exists — surface it in the UI. Fits the mockup-refinement BLEND work. |
| **Liquid-Glass micro-interactions on track change** | A subtle refract/settle animation when the track changes (Dynamic Island philosophy: responsiveness, fluidity, depth) makes it feel like a 2026 Tahoe-native app, not a utility. | MEDIUM | ~12ms Core Animation micro-interactions are imperceptible in cost but "delightful." Must respect existing perf invariants — animate on `onTrackChanged` (real changes only), never per-tick. |
| **Scrobble state visible on the widget/menu** | A tiny "scrobbled ✓" / "now playing on Last.fm" indicator closes the loop competitors hide in preferences. | LOW | Reads scrobbler state; keep it a leaf view so it doesn't re-render the shell (perf invariant #1). |
| **Reduce-Transparency-aware glass fallback** | Ship a solid/high-contrast variant of every glass surface. Turns Liquid Glass's #1 accessibility criticism into a selling point ("beautiful AND readable"). | MEDIUM | TidBITS documents users actively disabling glass. A `VPTheme` solid-token variant gated on the system accessibility flag. |
| **Cross-fade source switching** | When precedence hands off between sources, reuse the existing opacity cross-fade instead of a hard cut. | LOW | Reuses the proven `.transition(.opacity)` pattern already mandated by perf invariant #5 for size switches. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create disproportionate cost, risk, or App-Store/perf problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Simultaneous multi-source display** (show two players at once) | "I have Spotify and a YouTube tab, show both." | Breaks the single-source-of-truth model (`NowPlayingService` holds exactly one track), doubles render cost, confuses the "what's playing" answer. Not what any competitor does. | Single active source + fast, obvious hand-off + a source badge. One truth. |
| **Relying on native `MediaRemote` for desktop Spotify/Apple Music as the precedence winner** | "Just read the system Now Playing like other apps." | Entitlement-gated on macOS 15.4+; returns empty dict to unsigned/third-party apps; **blocks Mac App Store** (private framework). Making it the *default* precedence source would make the app dead-on-arrival on modern macOS. | Keep native capture opt-in/experimental. Browser bridge + local are the durable precedence sources; native only supplements when it happens to work. |
| **Manual per-track "scrobble now" / edit-before-scrobble** | Power scrobblers on other apps love tweaking metadata. | Adds UI surface, correctness traps (timestamp filtering rejects edited-past plays), and audit complexity for near-zero mainstream value. | Automatic, spec-correct scrobbling only. Let users disconnect/reconnect Last.fm; no manual editing. |
| **Scrobbling non-music / short clips / browser noise** | "Scrobble everything my browser plays." | MediaSession fires for YouTube ads, podcasts, 10s clips → junk scrobbles that pollute the user's Last.fm history. The 30s/50%/4-min rule exists precisely to prevent this. | Enforce the 30s-minimum + threshold strictly; consider a per-source scrobble toggle (e.g., off for generic browser tabs by default). |
| **Retrying failed `updateNowPlaying` calls / aggressive polling** | "Make sure Last.fm always shows the right track." | Official spec explicitly says do NOT retry now-playing failures; retry loops waste battery and risk rate-limiting. Also a perf-invariant hazard if it touches state on a timer. | Fire-and-forget now-playing; only *scrobbles* get the durable retry queue. |
| **Full "liquid glass everywhere" maximalism** | Tahoe looks cool; more glass = more premium. | Documented legibility/accessibility backlash (TidBITS "turn Liquid Glass into a solid interface"); risks the calm-desktop-decor value and the perf budget. | Purposeful glass on now-playing surfaces only; solid fallback; keep BLEND *selective* per the project decision. |
| **User-configurable precedence priority lists / rules engine** | "Let me rank all my sources with custom rules." | Over-engineered for a free glanceable widget; most users want Auto or one manual pick. | Auto (last-active-playing) + a single manual override picker. Nothing more. |

---

## Feature Dependencies

```
Multi-source precedence policy
    └──requires──> per-source (isPlaying, lastUpdatedAt) tracking in front of updateFromExternal
                       └──requires──> Phase-2 capture wiring (Spotify/Apple Music/browser end-to-end)

Manual source override ──enhances──> Multi-source precedence policy
Source badge (provenance) ──enhances──> Multi-source precedence policy   (reads Track.source)

Last.fm scrobbling (correct)
    └──requires──> real LASTFM_API_KEY / SECRET
    └──requires──> desktop auth flow surfaced in Settings UI
    └──requires──> persistent offline scrobble queue (survives restart, chronological, batch≤50)
    └──depends-on──> reliable per-source play start/stop signals (from precedence layer)

Scrobble-state indicator ──requires──> Last.fm scrobbling wired + leaf-view observation

Liquid-Glass micro-interactions ──requires──> onTrackChanged (real-change) hook   (NOT per-tick)
Reduce-Transparency fallback ──enhances──> all glass surfaces (BLEND)
Cross-fade source switching ──reuses──> existing .transition(.opacity) pattern

[Simultaneous multi-source display] ──conflicts──> single-source-of-truth NowPlayingService
[Native MediaRemote as default winner] ──conflicts──> Mac App Store sandbox / no-private-frameworks
```

### Dependency Notes

- **Precedence requires per-source liveness tracking:** VinylPod's `updateFromExternal` is a single guarded setter with no notion of "which of several sources is winning." Precedence must sit *in front of* it, choosing which producer's update reaches the gate — without adding a second ingestion path (preserve the architecture).
- **Scrobbling correctness depends on the precedence layer:** Accurate scrobble timing (wall-clock start, 50%/4-min) needs clean play-start / track-change / stop signals. If precedence hand-off is sloppy, scrobbles double-fire or drop. Wire precedence first, scrobbling on top.
- **Offline queue is the load-bearing scrobbling gap:** Current subsystem no-ops (empty keys) and has no durable cache. This is the single highest-value correctness item — without it, any network blip loses plays silently.
- **Micro-interactions must hook real track changes only:** Perf invariants forbid animating on the ~1–10 Hz position tick. Bind glass micro-interactions to `onTrackChanged` (fires only on genuine change) and coarsen any position-driven motion to whole seconds.
- **Native-capture conflict is a hard boundary:** Making native `MediaRemote` a relied-upon precedence source conflicts directly with the App Store goal. Keep it opt-in and never the default winner.

---

## MVP Definition (this milestone)

### Launch With (v1 of this cycle)

- [ ] **Multi-source precedence: auto "last-active-playing" wins** — the core promise of Phase-2 capture; unifies browser/local/(opt-in native).
- [ ] **Manual source override picker** (Auto / Browser / Spotify / Apple Music) — escape hatch when auto guesses wrong; low cost, high trust.
- [ ] **Last.fm real keys + desktop auth flow in Settings** — turns the no-op subsystem on.
- [ ] **Spec-correct scrobble timing** (30s min, 50%/4-min, wall-clock start, seek-safe) — validate existing logic.
- [ ] **`track.updateNowPlaying` on play start, no retry** — live profile update.
- [ ] **Persistent offline scrobble queue** (survives restart, chronological, batch ≤50) — correctness-critical.
- [ ] **BLEND UI refinements** from mockups onto existing five sizes + Dynamic Island, keeping glass tokens/perf invariants.
- [ ] **Reduce-Transparency legibility fallback** — accessibility + the calm-decor value.

### Add After Validation (v1.x)

- [ ] **Source provenance badge** — trigger: once precedence ships and users have multiple live sources.
- [ ] **Scrobble-state indicator on widget/menu** — trigger: once scrobbling is trusted end-to-end.
- [ ] **Per-source scrobble toggle** (e.g., default-off for generic browser tabs) — trigger: if junk-scrobble complaints appear.
- [ ] **Liquid-Glass track-change micro-interactions** — trigger: after BLEND baseline lands and perf is re-profiled at 0.0% idle.

### Future Consideration (v2+)

- [ ] **Cross-fade source switching polish** — defer: nice-to-have motion once hand-off correctness is proven.
- [ ] **Love/unlove track to Last.fm** (`track.love`) — defer: adds write scope + UI; not core to now-playing display.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Auto precedence (last-active-playing) | HIGH | MEDIUM | P1 |
| Manual source override picker | HIGH | LOW | P1 |
| Last.fm real keys + auth flow UI | HIGH | MEDIUM | P1 |
| Spec-correct scrobble timing (30s/50%/4min) | HIGH | LOW | P1 |
| `updateNowPlaying` on play start (no retry) | MEDIUM | LOW | P1 |
| Persistent offline scrobble queue | HIGH | MEDIUM | P1 |
| BLEND UI refinements (glass, 5 sizes + Island) | HIGH | MEDIUM | P1 |
| Reduce-Transparency fallback | MEDIUM | MEDIUM | P2 |
| Source provenance badge | MEDIUM | LOW | P2 |
| Scrobble-state indicator | MEDIUM | LOW | P2 |
| Per-source scrobble toggle | MEDIUM | LOW | P2 |
| Liquid-Glass micro-interactions | MEDIUM | MEDIUM | P2 |
| Cross-fade source switching | LOW | LOW | P3 |
| Love/unlove track (`track.love`) | LOW | MEDIUM | P3 |

---

## Competitor Feature Analysis

| Feature | NepTunes | SpotMenu | Sleeve | Our Approach (VinylPod) |
|---------|----------|----------|--------|-------------------------|
| Sources | Apple Music + Spotify (desktop) | Spotify + Apple Music (desktop) | Apple Music + Spotify + Doppler (desktop) | **Browser (any MediaSession tab) + local files + opt-in desktop** — broader capture is the moat |
| Multi-source handling | Follows active player | Auto-detect **or manual** select | Follows active player | Auto last-active-playing **+ manual override + source badge** |
| Last.fm scrobbling | Yes (its main purpose) | Via integrations | No (display/control focus) | Spec-correct scrobbling **+ durable offline queue** (many rivals lack persistence) |
| UI style | Menu-bar text, minimal | Menu-bar mini-player | Desktop floating art widget | **Liquid-glass, 5 sizes + Dynamic Island**, Tahoe-native micro-interactions |
| Price | Free | Free/OSS | Paid | **Free, App-Store-safe (no private frameworks in shipping path)** |
| App-Store safe | — | — | — | **Yes — browser bridge avoids `MediaRemote` lockdown** |

---

## Sources

- Last.fm official Scrobbling 2.0 API docs — https://www.last.fm/api/scrobbling (HIGH: 30s min, 50%/4-min threshold, no-retry now-playing, batch ≤50, persistent cache survives restart, chronological cached-before-new)
- "5 Best Mac Music Controller & Now Playing Apps" — https://getseam.app/blog/best-mac-music-controller-now-playing-apps
- NepTunes / AlternativeTo — https://alternativeto.net/software/neptunes/
- SpotMenu (auto-detect + manual multi-player) — https://github.com/kmikiy/SpotMenu
- "Make app take precedence in Now Playing" (system last-active behavior, browser stealing Now Playing) — https://discussions.apple.com/thread/253618480
- Apple Newsroom — Liquid Glass design language — https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/
- "How to Turn Liquid Glass into a Solid Interface" (legibility/accessibility caveat) — https://tidbits.com/2025/10/09/how-to-turn-liquid-glass-into-a-solid-interface/
- macOS Tahoe 26 Liquid Glass review (micro-interactions, adaptive tint) — https://www.xugj520.cn/en/archives/macos-tahoe-26-review.html
- Project canonical docs: `.planning/PROJECT.md`, `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/INTEGRATIONS.md`

---
*Feature research for: macOS menu-bar now-playing widget (VinylPod) — multi-source capture, Last.fm scrobbling, Liquid-Glass UI BLEND*
*Researched: 2026-07-03*
