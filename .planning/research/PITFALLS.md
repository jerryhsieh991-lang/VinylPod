# Pitfalls Research

**Domain:** Native macOS menu-bar now-playing app → Mac App Store distribution (sandbox + notarization), Safari Web Extension, private-framework removal, perf-sensitive SwiftUI UI refresh, Last.fm scrobbling
**Researched:** 2026-07-03
**Confidence:** MEDIUM (web + official Apple docs cross-checked; MAS/Safari review behavior is opaque and version-sensitive, so treat exact rejection wording as indicative, not guaranteed)

> Scope note: This file deliberately covers **external / common** mistakes for the NEW work in this milestone. The already-catalogued internal concerns (WIP drift, 6 perf invariants, bridge threat model residual gaps, `@VPState`/CLT toolchain, `MediaRemote` no-op, doc sprawl, zero tests) live in `.planning/codebase/CONCERNS.md` and are referenced, not repeated.

---

## Critical Pitfalls

### Pitfall 1: Assuming the loopback WebSocket bridge survives the App Sandbox — and works for Safari

**What goes wrong:**
The whole capture architecture rests on `BrowserBridge` listening on `ws://127.0.0.1:8787`. Under App Sandbox two independent things break silently: (a) the server socket fails to bind unless the app carries `com.apple.security.network.server`, and every outbound artwork fetch fails unless it *also* carries `com.apple.security.network.client`; (b) far more serious — a **Safari Web Extension can only communicate with its own container app via native messaging (an XPC channel through `SafariWebExtensionHandler`)**, not by opening an arbitrary loopback WebSocket the way Chrome/Firefox content scripts do. Safari extension JS is heavily sandboxed and is not a reliable/idiomatic path for a raw `ws://127.0.0.1` connection. So the exact ingestion mechanism that works for Chrome/Firefox is the wrong mechanism for the Safari build.

**Why it happens:**
The bridge works today because the app is **unsandboxed** and the extension is loaded in Chromium-family browsers. Teams carry the "one loopback WS for all browsers" mental model into the MAS + Safari world and only discover the mismatch after signing, sandboxing, and submitting.

**How to avoid:**
- Treat "does the sandboxed app still bind `127.0.0.1:8787`?" as a **spike/feasibility gate at the very start** of the MAS workstream, before any UI or scrobbling work. Add both `com.apple.security.network.server` and `com.apple.security.network.client`; verify bind + outbound fetch under a real sandboxed build (Console.app `sandboxd` denials, not just "it launched").
- Design the Safari path around **native messaging** (`browser.runtime.sendNativeMessage` / `connectNative` + `nativeMessaging` permission + `SafariWebExtensionHandler`), feeding the *same* `NowPlayingService.updateFromExternal` ingestion point. Keep the loopback WS for Chrome/Firefox; add a native-messaging producer for Safari. Do not assume one transport covers all three browsers.
- Decide explicitly whether Safari is in-scope for v1 of the MAS listing. If the loopback WS is retained as the only transport, Safari capture is effectively unsupported and should be stated as such.

**Warning signs:**
`sandboxd` deny logs for `network-bind`/`network-outbound`; the extension "connects" in Chrome but the Safari extension's `sendNativeMessage` returns undefined; artwork stops loading only in the sandboxed build.

**Phase to address:** MAS Readiness — earliest spike (blocks everything downstream). Safari transport belongs to the Safari Web Extension workstream.

---

### Pitfall 2: Private `MediaRemote` symbols/strings remain in the shipped binary and trip static analysis

**What goes wrong:**
`NativeMediaRemoteCapture.swift` `dlopen`/`dlsym`s `/System/Library/PrivateFrameworks/MediaRemote.framework` and resolves `MRMediaRemoteGetNowPlayingInfo` et al. Even though it is a runtime no-op on macOS 15.4+, Apple's App Review runs **static analysis** over the binary: `strings`/`otool`/`nm`-style scans surface the private symbol names, selectors, and the framework path **even when they are only referenced via string literals for `dlsym`**. A runtime guard (`if enabled { … }`) does not remove the strings. Result: automated "use of non-public API" rejection that is slow and opaque to appeal.

**Why it happens:**
Developers assume "it never runs, so it's fine" or "it's `dlsym`, so it's invisible." Neither is true — the literal `"MRMediaRemoteGetNowPlayingInfo"` and the private framework path are compiled into the binary as data.

**How to avoid:**
- **Fully exclude** the native-capture code from the MAS build, not just guard it. Use a compilation condition (e.g. `#if VINYLPOD_MAS` strips the file) or a separate SPM target / build configuration so the strings never enter the shipped binary.
- Add a **pre-submit grep gate**: `nm`/`strings`/`otool -L` the final `.app` binary for `MediaRemote`, `MRMediaRemote`, and any private-framework path; fail the build if found. Cheap, deterministic, catches regressions.
- Keep native capture available only in the dev/`swift build` path, matching the existing "experimental, off by default" posture.

**Warning signs:**
`strings VinylPod.app/Contents/MacOS/VinylPod | grep -i mediaremote` returns hits; ITMS/Review email citing Guideline 2.5.1 / non-public API.

**Phase to address:** MAS Readiness — private-framework removal must land and be grep-verified before the first upload.

---

### Pitfall 3: Entitlement / provisioning-profile / hardened-runtime mismatch blocks notarization

**What goes wrong:**
The upload or notarization fails (or the app is rejected) because: Hardened Runtime is not enabled; the embedded provisioning profile's App ID (Team ID + bundle identifier) does not match the signing certificate or the requested entitlements; entitlements requested exceed what the profile authorizes; or nested binaries/helpers/the extension are not signed with the same identity and hardened runtime. For MAS specifically the app must be signed with an **Apple Distribution** cert + a Mac App Store provisioning profile and carry `com.apple.security.app-sandbox` — different from the Developer ID + notarization path used for direct distribution.

**Why it happens:**
This project has **no Xcode project, no signing pipeline today** (CLT-only, `make_app.sh` bundling). Introducing signing/entitlements/sandbox from scratch is exactly where profile/cert/entitlement triads get misaligned. The MAS path and the Developer-ID-notarized path are easy to conflate.

**How to avoid:**
- Stand up the Xcode target and get a **trivial signed+sandboxed "hello" build through the full MAS pipeline early** (an empty shell that just launches), before wiring real features into it. Validate with `codesign --verify --deep --strict`, `spctl -a -vv`, and an actual App Store Connect upload/notarization round-trip.
- Keep the entitlements set **minimal and exact**: `app-sandbox`, `network.server`, `network.client`, plus only what artwork/file-drop truly needs. Every extra entitlement is a review-surface and a possible profile mismatch.
- Ensure the Xcode target does not break the existing `swift build` + `make_app.sh` dev path (a stated project constraint) — treat them as two build systems over one source tree, and pin the `@VPState` workaround so raw `@State` never leaks in.
- Sign the Safari extension appex and any helpers with the same team/hardened runtime; verify nested-code signing.

**Warning signs:**
`errSecInternalComponent`, "provisioning profile doesn't include signing certificate", "The executable does not have the hardened runtime enabled", notarization log `The signature of the binary is invalid`.

**Phase to address:** MAS Readiness — signing/entitlements/sandbox pipeline spike, ahead of feature wiring.

---

### Pitfall 4: Re-introducing the ~98% idle-CPU render loop during the BLEND UI refresh

**What goes wrong:**
The UI overhaul folds mockup ideas into the five sizes + Dynamic Island and, in doing so, violates one of the 6 documented perf invariants — most likely by (a) observing `NowPlayingService` in a newly-restructured always-on parent view, (b) adding a new `@Published` field written every tick (a progress ring, animated waveform, live ms timer), or (c) rendering raw `position` instead of `Int(position)`. Any of these resurrects the self-sustaining 60 fps idle loop the project already paid to fix.

**Why it happens:**
UI refreshes reorganize the view tree and add "live" flourishes (scrubbers, animated art, VU meters) — precisely the patterns that re-couple always-on shells to the 10 Hz `position` publisher. The invariants are convention-enforced, not compiler-enforced, so refactors slip past silently.

**How to avoid:**
- Before touching `Services.swift`, `WindowManager.swift`, or any always-on view, re-read `docs/system-design/05-security-performance-build.md` §3 and keep observation at leaf views (`IslandTimeRow`, `NowPlayingMenuSection`).
- Any new animation must be driven by `TimelineView(minimumInterval:paused:)` gated on active playback (as `EqualizerBars` already is), **never** by a new high-frequency `@Published` field. `position` stays the only unconditionally-written field.
- **Add an automated idle-CPU regression check** to the new test target's manual/CI checklist: launch, idle 60s with a track "playing," assert ~0.0% CPU via `sample`/`powermetrics`. Cross-fade (`.transition(.opacity)`), not `.id(mode)`, for size switches.

**Warning signs:**
Fans spin at idle; `sample` shows `GraphHost.updatePreferences`/`MainMenuItemHost.requestUpdate` hot; Instruments Time Profiler busy while paused.

**Phase to address:** UI BLEND phase — profile after every batch of view changes; gate the phase's "done" on the idle-CPU check.

---

### Pitfall 5: Last.fm scrobble threshold, dedup, and auth handled wrong

**What goes wrong:**
Common failure modes: scrobbling immediately on track start (should be on threshold), scrobbling the same track repeatedly on pause/resume or on `position` jitter, scrobbling tracks < 30s, hammering the API (error 29 rate-limit / ban), storing the shared secret in the client where it can leak, or building `api_sig` wrong so every call is auth-rejected. The threshold rule is specific: a track is eligible only after **half its duration OR 4 minutes played, whichever comes first**, and only for tracks longer than 30s. `track.updateNowPlaying` is fire-on-start and must **not** be treated as a scrobble.

**Why it happens:**
The scrobbling subsystem is currently a no-op (empty-string API key/secret placeholders), so none of the edge-case logic has ever run against real credentials. VinylPod's `position` is also *extrapolated/coarsened* for perf and, for external sources, updates at ~1 Hz — so naive "played ≥ 50%" math off a jittery/extrapolated clock will mis-fire.

**How to avoid:**
- Implement a per-track scrobble state machine keyed on a **stable track identity** (source + artist + title + album), independent of the `position` publisher: mark `nowPlaying` on real track change; arm a threshold timer (`min(duration/2, 240s)`); fire `track.scrobble` **once** when reached; reset on real track change. Ignore pause/seek for eligibility (track elapsed listening, not raw position).
- Respect limits: batch up to 50 scrobbles, keep ≥ 30s between scrobbles, back off on error 29, do not poll in a tight loop. Queue scrobbles offline and flush in batches so a network blip does not drop plays.
- Build `api_sig` correctly: sort all params alphabetically by name, concatenate `name+value`, append the shared secret, MD5. Do the signing/session-key exchange, store only the **session key** (not the password) in the Keychain, and keep the API secret out of any client-visible surface. Never scrobble tracks < 30s or with missing artist/title.
- Note the sandbox interaction: scrobbling needs `com.apple.security.network.client`; confirm it works under the sandboxed build, not just dev.

**Warning signs:**
Duplicate scrobbles in the Last.fm history; plays appear at 0:00 instead of at threshold; error 29 in logs; "Invalid method signature supplied" (error 13); short jingles/ads scrobbled.

**Phase to address:** Last.fm scrobbling phase; the network-client entitlement portion overlaps MAS Readiness.

---

### Pitfall 6: Safari Web Extension review rejections unrelated to code

**What goes wrong:**
The extension is functionally fine but App Review rejects the listing for metadata reasons: **naming competing browsers** (Chrome/Firefox/Edge/Opera) in the description or UI, emoji in the App Store description, donation/tip content (for a non-nonprofit), calling any feature "beta," or over-promising capabilities not visibly demonstrable. Separately, `safari-web-extension-converter` only cleanly converts ~70–80% of an MV3 extension; Chrome-specific APIs (notably `webRequest` under MV3) are **unsupported in Safari and fail silently** rather than erroring.

**Why it happens:**
The current extension and its store copy were written for the Chrome/Firefox world where cross-browser mentions and casual copy are normal. Converter output looks like it "just works" until a Safari-unsupported API silently no-ops.

**How to avoid:**
- Scrub all store metadata and in-extension strings: no competitor browser names, no emoji in the description, no donation asks, no "beta" language. Describe only what a reviewer can see working in Safari.
- Audit the MV3 code against Safari's supported-API surface before converting; explicitly test each capture path (Spotify Web, Apple Music Web, YouTube/YT Music, generic MediaSession) **inside Safari**, not just Chrome. Confirm no reliance on `webRequest`/other unsupported MV3 APIs.
- Package the extension as an appex inside the same signed/sandboxed container app; sign with the same team + hardened runtime.
- Remember the WIP-drift note: the three `BrowserExtension/*.js` files are uncommitted — land and re-review them before converting, so Safari conversion targets the real code.

**Warning signs:**
Rejection email quoting Guideline 4.x/2.x metadata; a browser source that captures in Chrome but shows nothing in Safari; converter warnings about unsupported keys.

**Phase to address:** Safari Web Extension workstream (packaging + review), with a metadata-scrub checklist gate.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Runtime-guard `MediaRemote` instead of compile-excluding it | Less refactoring | Private strings stay in binary → automated MAS rejection; recurs on every build | Never for the MAS binary |
| Ship one loopback-WS transport for all browsers incl. Safari | Reuse existing bridge | Safari capture silently unsupported; user-visible "nothing plays" | Only if Safari is explicitly out of v1 scope and documented |
| Reuse Developer-ID/notarization setup for MAS | Familiar path | Wrong cert/profile type; late rejection | Never — MAS needs Apple Distribution + MAS profile + sandbox |
| Derive scrobble eligibility directly from `position` | Simple | Mis-fires on extrapolated/1 Hz/jittery clock; dup scrobbles | Never — use an independent elapsed-listen timer |
| Add a "live" animated UI element via a new `@Published` field | Easy binding | Re-arms the 98% idle-CPU loop | Never — use gated `TimelineView` |
| Broad entitlements ("just add them all") to make sandbox errors go away | Fast unblock | Larger review surface, profile mismatch, privacy prompts | Never — request the minimal exact set |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Safari Web Extension IPC | Opening `ws://127.0.0.1` from Safari extension JS | `nativeMessaging` → `SafariWebExtensionHandler` (XPC) into the same `updateFromExternal` seam |
| App Sandbox networking | Only adding `network.server` | Add **both** `network.server` (bind) and `network.client` (artwork fetch + Last.fm) |
| Last.fm auth | Storing username/password or the API secret client-side | Web-auth flow → store **session key** in Keychain; secret never shipped in a leakable surface |
| Last.fm scrobble | Treating `updateNowPlaying` as a scrobble; scrobbling on start | `updateNowPlaying` on track start; `track.scrobble` once at `min(dur/2, 240s)` |
| Last.fm rate limits | Tight polling / per-track immediate POST | Batch ≤ 50, ≥ 30s spacing, back off on error 29, offline queue |
| `safari-web-extension-converter` | Trusting 100% conversion | Assume ~70–80%; hand-audit Chrome-only MV3 APIs; test in Safari |
| Notarization | Unsigned nested extension/helpers | Sign every nested binary with same team + hardened runtime |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Always-on view observing `NowPlayingService` after UI restructure | Fans at idle; 60 fps redraw while paused | Keep observation at leaves; parents observe `AppSettings` only | Immediately at idle with a track loaded |
| New high-freq `@Published` field for a UI flourish | CPU busy while paused | Only `position` unconditional; others equality-gated; animate via gated `TimelineView` | As soon as the flourish is on screen |
| Rendering raw `position` (`TimeInterval`) in a leaf | Excess body diffs | Coarsen to `Int(position)` at display sites | Continuous during playback |
| Size-switch via `.id(mode)` | Glass/blur subtree rebuild, flash/stretch, CPU spike | `.transition(.opacity)` cross-fade on stable `.id` | Every size switch |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Shipping the private `MediaRemote` path in MAS binary | Automatic rejection; breakage on macOS updates | Compile-exclude + grep gate |
| Last.fm API secret embedded in a readable/client surface | Secret theft, key ban | Keep secret server/build-side; store only session key in Keychain |
| Relying on the loopback bridge as trust boundary under sandbox without re-review | Any local process on :8787 injects payloads (documented residual gap) | Address extension auth (shared secret/nonce) + Origin/rate-limit gaps during the bridge-hardening + Safari-transport work |
| Over-broad entitlements | Larger attack/review surface | Minimal exact entitlement set |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Silent Safari capture failure (unsupported API / wrong transport) | "It shows nothing" — looks broken vs. competitors | Native-messaging Safari path + explicit per-browser capture test |
| Scrobble dupes / wrong-time plays | Users notice polluted Last.fm history and distrust the app | Independent elapsed-listen state machine; `updateNowPlaying` vs `scrobble` split |
| UI refresh that regresses idle CPU | Fan noise / battery drain on a "calm desktop decor" app | Idle-CPU gate on the BLEND phase |
| Sandbox prompts / broken artwork after MAS switch | App feels degraded vs. the unsandboxed dev build | Validate sandboxed build behavior (network, file-drop) before shipping |

## "Looks Done But Isn't" Checklist

- [ ] **MAS build:** launches unsandboxed in dev but never verified under sandbox — check `sandboxd` denials, loopback bind, artwork fetch, file-drop in a signed sandboxed build.
- [ ] **Private-framework removal:** code path guarded but `strings`/`nm` still show `MRMediaRemote*` — verify the symbols/strings are gone from the shipped binary.
- [ ] **Safari extension:** converts and loads, but capture sources untested in Safari — verify each source actually updates now-playing in Safari, not just Chrome.
- [ ] **Signing:** app signed but nested extension/helpers not — `codesign --verify --deep --strict` + notarization round-trip.
- [ ] **Scrobbling:** posts to Last.fm but threshold/dedup/rate-limit untested — verify one clean scrobble at threshold, no dupes on pause/seek, ≥30s spacing.
- [ ] **UI BLEND:** looks refreshed but idle CPU not re-profiled — `sample` at idle-with-track shows ~0.0%.
- [ ] **Entitlements:** app runs but requests more than needed — audit for the minimal exact set.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| MAS rejection for private API (`MediaRemote`) | LOW–MEDIUM | Compile-exclude the file, add grep gate, re-sign, re-upload |
| Sandbox blocks loopback bind | LOW | Add `network.server` + `network.client`; re-verify via `sandboxd` logs |
| Safari capture doesn't work | MEDIUM–HIGH | Add native-messaging producer into `updateFromExternal`; audit MV3 API use |
| Idle-CPU loop reintroduced | LOW | `sample` to find the observing view; move observation to leaf; drop the offending `@Published` field |
| Scrobble dupes / bad auth | LOW | Fix state machine + `api_sig`; delete bad scrobbles from Last.fm; back off on error 29 |
| Metadata rejection (Safari listing) | LOW | Scrub competitor names/emoji/donation/beta copy; resubmit |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase / Workstream | Verification |
|---------|-------------------------------|--------------|
| Sandbox breaks loopback + Safari transport mismatch (1) | MAS Readiness (earliest spike) + Safari Web Extension | Sandboxed build binds :8787, fetches artwork; Safari uses native messaging into `updateFromExternal` |
| Private `MediaRemote` strings in binary (2) | MAS Readiness (private-framework removal) | `strings`/`nm` of shipped binary clean; no Guideline 2.5.1 flag |
| Entitlement/profile/hardened-runtime mismatch (3) | MAS Readiness (signing pipeline spike) | Trivial signed+sandboxed shell passes notarization + App Store Connect upload |
| Idle-CPU loop during UI BLEND (4) | UI BLEND phase | `sample`/`powermetrics` ~0.0% CPU idle-with-track after each change batch |
| Last.fm threshold/dedup/auth/rate-limit (5) | Last.fm scrobbling phase (+ network.client from MAS) | One scrobble at threshold, zero dupes on pause/seek, valid `api_sig`, ≥30s spacing |
| Safari review metadata + unsupported MV3 APIs (6) | Safari Web Extension workstream | Metadata scrub checklist passes; every capture source verified in Safari |
| Test foundation must lock the perf + bridge invariants | Test-foundation phase (first) | Unit tests for `isPublicHost`/`decodeDataURI`/`updateFromExternal` gating + idle-CPU check exist |

**Ordering implication for the roadmap:** the MAS-readiness spikes (sandbox+loopback feasibility, signing pipeline, private-framework removal) are *upstream gates* — they can invalidate the transport architecture and should precede the UI BLEND and scrobbling feature work. The test-foundation phase should come first so the perf invariants and bridge guards are locked before the UI and capture changes churn them.

## Sources

- Apple Developer Documentation — `com.apple.security.network.server` entitlement (listen on loopback requires it) — MEDIUM
- Apple Developer Documentation — Messaging a Web Extension's Native App (Safari extension talks only to its container app via native messaging / XPC) — MEDIUM
- Apple Developer Documentation — Resolving common notarization issues; Hardened Runtime (required for notarization) — MEDIUM
- Apple Developer Forums / Electron #20027, Apple Community threads — private/non-public API rejection detected via static binary analysis (`strings`/`otool`/`nm`) — MEDIUM
- Tauri docs issue #3171 — sandboxed macOS apps require `com.apple.security.network.client` — MEDIUM
- Last.fm API docs — `track.scrobble`, `track.updateNowPlaying`, scrobbling threshold (half or 4 min), signature construction; navidrome/headphones issues — error 29 rate limiting — MEDIUM
- stefanvd.net "3 Common Browser Extension Store Mistakes"; Apple forums / conversion gists — Safari review metadata rules + `safari-web-extension-converter` coverage (~70–80%, `webRequest` MV3 unsupported) — MEDIUM
- Project inputs: `.planning/PROJECT.md`, `.planning/codebase/CONCERNS.md`, `.planning/codebase/ARCHITECTURE.md` (perf invariants, bridge threat model, toolchain) — HIGH

---
*Pitfalls research for: macOS now-playing widget → Mac App Store (sandbox/notarization), Safari extension, private-framework removal, SwiftUI perf, Last.fm scrobbling*
*Researched: 2026-07-03*
