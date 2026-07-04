# VinylPod — Pre-Publish Security Audit (2026-07-03)

Audit run before a **public** GitHub publish. Two parallel specialist agents (bridge/network, SwiftUI/concurrency/memory) + a gating secret sweep. Repo: `~/Desktop/VinylPodMac`, ~9,300 LOC Swift + MV3 extension.

## Gate result

| Gate | Result |
|------|--------|
| **Secret leak (BLOCKS public push)** | ✅ **PASS** — `LASTFM_API_KEY`/`SECRET` are empty `""` placeholders (`LastFmClient.swift:16-17`); no certs/keys/profiles/env files; no tokens in tracked source; **62 commits of history carry no real key**; no team IDs / user paths leaked. |
| **Repo hygiene** | ✅ PASS — `.claude/` worktrees, `dist/` bundle, `node_modules` all untracked; 151 tracked files, no junk. |
| **Local service hardening** | ⚠️ PARTIAL — loopback bind holds, but the bridge is **unauthenticated** and the SSRF guard is bypassable (see HIGH-1/2). |
| **State/concurrency/memory** | ⚠️ SHIP-WITH-FIXES — one crash-class lifetime bug + a shared-state race + two inert-feature wiring gaps. |
| **RCE / remote exposure / file-read** | ✅ None — loopback-only, `file://`/`data:` correctly blocked, no exec surface. |

**Overall: safe to open-source (no leak, no remote, no RCE) — but NOT a clean security bill of health. Real hardening backlog below.**

---

## Bridge / loopback / network (verdict: PUBLISH-WITH-FIXES)

Reachability: remote = **NO** (genuine `127.0.0.1:8787` bind, `BrowserBridge.swift:42`). Other local processes/users = **YES** (loopback isn't user-namespaced). Malicious `http://` page can connect directly and **bypass the extension entirely**.

- **HIGH-1 — Bridge has zero authentication / no Origin validation.** `BrowserBridge.swift:33-74,102-135`. Any local process or `http://evil` page can `new WebSocket("ws://127.0.0.1:8787")` and inject `nowplaying` frames → spoof track, trigger attacker-URL fetches (→ SSRF), and **scrobble fake tracks to the user's Last.fm** if configured. Not CRITICAL (loopback-only, no exec, browsers block `ws://` from `https://`). Fix: per-install token handshake (`{type:"hello",token}`), drop unauthenticated sockets.
- **HIGH-2 — SSRF guard (`isPublicHost`) bypassable.** `BrowserBridge.swift:150-209`; no `URLSessionDelegate` → redirects followed unchecked. Bypasses: (1) HTTP 302 → private IP, (2) DNS rebinding, (3) numeric IP encodings (`http://2130706433/`, `0x7f000001`, octal), (4) IPv6 gaps (`fe80::`, `fc00::`, `::ffff:127.0.0.1`). Blind SSRF (response only decoded as image, no exfil), but docs **falsely claim** SSRF mitigated. Fix: validate the *resolved* IP against loopback/private/link-local/ULA/IPv4-mapped ranges + re-check on every redirect (`willPerformHTTPRedirection`).
- **MEDIUM-1 — Image decompression bomb.** 8 MB cap is on *encoded* bytes; `normalizedImage` (`BrowserBridge.swift:213-218`) has no pixel/dimension clamp; the `data:` path has no byte cap at all. A tiny 30000×30000 image → multi-GB alloc → crash. Fix: reject `NSBitmapImageRep` dims above ~4096×4096 / ~16 MP on both paths.
- **MEDIUM-2 — No rate limiting.** `receive` re-arms with no throttle; single-slot URL cache lets each new-URL frame trigger a fresh fetch → outbound-fetch amplification / internal port scan (with HIGH-2). Fix: per-connection frame token-bucket + outbound-fetch dedup/cap.
- **LOW-1 — Connection-cap evicts the OLDEST (legit extension), not the new one.** `BrowserBridge.swift:63`. Fix: reject new at cap.
- **LOW-2 — Injected track reaches Last.fm scrobbles + (opt-in, confirm-gated) wallpaper.** Rolls up under HIGH-1.

**Confirmed-holding mitigations:** loopback bind, 256 KB frame cap (×2), 6-conn cap, `file://` blocked, `data:` string-decoded (no `contentsOf:`), non-http scheme rejected, title ≤2048 guard, 10 s fetch timeout, artwork-cache serialized. The strongest control (`file://`/`data:` local-file read blocked) is real.

---

## SwiftUI state / concurrency / memory (verdict: SHIP-WITH-FIXES)

Headline: **the documented ~100% render-loop landmine is genuinely fixed** (`VinylPodApp.swift:32-42` compare-before-assign binding; `position` is the only unconditional `@Published`; no off-main `@Published` mutation anywhere; no `try!`/`as!`/`fatalError`/attacker-reachable `!`).

- **HIGH (H1) — NSPanels `.close()`d without `isReleasedWhenClosed = false`.** `WindowManager.swift:262,306,516`. Default `true` + ARC ownership → unbalanced over-release → EXC_BAD_ACCESS on the Desktop-Widget switch / notch-toggle paths, likeliest on min-OS macOS 13. (Settings/Shortcuts windows already set it `false` — panels are the outlier.) 2-line fix. **Must-fix before MAS.**
- **MEDIUM (M1) — Out-of-order async metadata race.** `Services.swift:82-97 (playCurrent)`. Fast Next→Next: older AVAsset load finishes last and clobbers `track`/`onTrackChanged` with the stale track → UI shows wrong song. Fix: generation-token / still-current guard after the `await`.
- **MEDIUM (M2) — Glass widgets observe `NowPlayingService` at the shell** → whole `body` re-evaluates at the 10 Hz local-playback tick (`SmallGlassWidget.swift:14`, `Regular/Large`, `DesktopWidgetCanvas.swift:13`). GPU redraw is coalesced (not the old loop), but it's per-tick struct allocation and a deviation from the equatable-leaf discipline. Fix: shell observes only `settings`; read track/isPlaying in an equatable snapshot leaf (mirror `DynamicIslandWidget`).
- **MEDIUM (M3/M4) — Two features are inert.** `attachNativeCapture` is called only from the settings toggle, never at launch (`Services.swift:130`) → persisted `nativeCaptureEnabled=true` not honored on relaunch. `LastFmScrobbler.attach(to:)` has **no caller anywhere** → scrobbler never observes playback (independent of the empty keys). Fix: wire both in `applicationDidFinishLaunching`.
- **LOW:** `DesktopWidgetCanvas` 10 Hz TimelineView runs even with no track / in `.time` mode (breaks ~0.0% idle in that mode); dead `WidgetCanvas`/`ProgressBarView` reads raw `position` (latent Rule-3 landmine); `HotKeyManager` Carbon handler has no teardown; `NativeMediaRemoteCapture` main-actor hop is convention-safe only.

---

## Recommendation

1. **Publishing is safe re: leaks** — proceed whenever ready; nothing sensitive is exposed by source or history.
2. **Do NOT rush HIGH-1/HIGH-2 into the frozen bridge before the push** — bridge auth is a cross-component design change (Swift + browser ext + Safari native messaging) that risks breaking the working app; it belongs in a **planned, tested `/gsd-secure-phase`**, not a publish-flow hot-patch.
3. **Before a public push:** correct the security docs that overstate SSRF protection (or ship an honest `SECURITY.md`), and optionally apply the two low-risk fixes (NSPanel `isReleasedWhenClosed=false`, image dimension clamp).
4. **Track HIGH-1, HIGH-2, MEDIUM-1, and H1 as the security backlog** for the secure-phase.
