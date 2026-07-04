# Architecture Research

**Domain:** Native macOS menu-bar now-playing widget — subsequent-milestone architectural deltas (Mac App Store readiness, UI blend, Phase 2 capture, tests)
**Researched:** 2026-07-03
**Confidence:** HIGH (sandbox loopback-server feasibility, Safari-extension WebSocket limitation, and Xcode-wraps-SPM pattern are all confirmed against Apple docs / developer forums)

> Scope note: The existing architecture is **frozen and working** (single-source-of-truth `NowPlayingService` @MainActor; producers → `updateFromExternal` → observers; one reused `NSPanel`; six perf invariants; `CONTRACTS.md` public names). This document does **not** redesign it. It specifies only the *additive* changes this cycle needs, the component boundaries they introduce, the data-flow deltas, and a build order that keeps the four workstreams from blocking each other.

---

## Q1 — App Sandbox vs. loopback WebSocket server (the critical feasibility gate)

### Verdict: FEASIBLE. A sandboxed Mac App Store app CAN run the `127.0.0.1:8787` `NWListener` WebSocket **server**. Confidence: HIGH.

**Entitlements required (both):**

| Entitlement | Value | Why VinylPod needs it |
|-------------|-------|------------------------|
| `com.apple.security.app-sandbox` | `true` | Mandatory for any Mac App Store binary. |
| `com.apple.security.network.server` | `true` | "May listen for incoming network connections." This is exactly what `NWListener` binding `127.0.0.1:8787` does. Loopback is **not** carved out — the entitlement grants listening on any interface, and `params.requiredLocalEndpoint` already pins the bind to `127.0.0.1`. |
| `com.apple.security.network.client` | `true` | Required separately for the **outbound** artwork fetch (`BrowserBridge.loadArtwork()` `URLSession` GET) and any Last.fm HTTPS calls. Server and client are independent booleans; the bridge needs both. |

**Why the server binding is not the risk.** Many shipping Mac App Store apps run local loopback servers under exactly this entitlement (dev-tool companions, sync helpers, hardware bridges). The App Sandbox restricts *filesystem* and *device* reach, not the ability to `listen()` once `network.server` is declared. The existing loopback-only bind, 6-connection cap, and 256 KB frame cap all remain valid inside the sandbox unchanged.

**Where the real constraint lives: the browser side, not the app side.** The feasibility question flips from "can the app listen?" (yes) to "can each browser's extension *connect* to `ws://127.0.0.1:8787`?":

| Browser | Can its extension open `ws://127.0.0.1:8787`? | Path |
|---------|-----------------------------------------------|------|
| Chrome / Edge / Brave (MV3) | **Yes** — extension service worker / content script opens the WebSocket to loopback directly. | Existing WebSocket path, unchanged. |
| Firefox (MV3) | **Yes** — same as Chrome. | Existing WebSocket path, unchanged. |
| **Safari Web Extension** | **No.** Safari Web Extensions **cannot open a WebSocket to `ws://localhost`** — Apple blocks insecure `ws://` from the extension context, and `network.client` does not apply to the WebExtension sandbox. Apple's explicit recommendation is to use **native messaging** to reach a local app. | **New path required** (see Q3). |

**Second-order sandbox implication for the WebSocket server.** Loopback `ws://` (not `wss://`) is fine for Chrome/Firefox extensions connecting to `127.0.0.1` (loopback is a secure context by CSP rules). No TLS/cert work is needed for those two. The `ws://localhost` insecure-content block is **Safari-specific**, which is why Safari must fork to native messaging rather than "fix the scheme."

**Alternatives if a future macOS tightened the loopback server (not currently needed, ranked):**
1. **Native messaging host** (already mandatory for Safari) — a stdin/stdout `NSExtension`/helper the browser launches; no listening socket at all. Most sandbox-durable.
2. **Unix domain socket in an App Group container** — sandbox-legal IPC, but browser extensions (Chrome/Firefox) cannot reach a UDS, so this only helps a bundled helper, not the cross-browser extensions. Not a drop-in.
3. **XPC service** — same limitation: reachable by same-team bundled processes, not by third-party browser extensions.

Conclusion: keep the loopback WebSocket server for Chrome/Firefox; add native messaging only for Safari. Do **not** rip out the WebSocket bridge — it remains the durable cross-browser path and is fully sandbox-legal.

---

## Q2 — Removing / guarding the private `MediaRemote.framework` capture path

**Current state.** `Capture/NativeMediaRemoteCapture.swift` reaches `MediaRemote.framework` via `dlopen`/`dlsym` — there is **no link-time dependency**, so `otool -L` on the binary is clean. It is already off by default and a graceful no-op on macOS 15.4+.

**Why `dlopen` alone is not App-Store-safe.** App Store static analysis flags **private-framework symbol strings** (`MRMediaRemoteGetNowPlayingInfo`, the `/System/Library/PrivateFrameworks/MediaRemote.framework` path literal) even when resolved dynamically. Shipping those strings risks rejection.

**Recommended boundary: compile the module *out* of the App Store build, don't just gate it at runtime.**

- Introduce a compilation condition (e.g. `#if VINYLPOD_PRIVATE_CAPTURE`) wrapping the entire body of `NativeMediaRemoteCapture.swift`, leaving a no-op stub conforming to the same seam when the flag is absent.
- The **App Store target defines the flag OFF** → the private symbol strings never enter the shipping binary. The **dev `swift build` target may leave it ON** for local experimentation.
- The `updateFromExternal` ingestion contract is unchanged: `attachNativeCapture(settings:)` still exists as a seam; under the App Store flag it binds to the no-op stub. No consumer, no `NowPlayingService` change, no perf-invariant impact.
- Component-boundary delta: `Capture/` moves from "runtime-gated producer" to "**conditionally-compiled** producer." The CaptureSettings UI toggle should be hidden/absent when the module is stubbed so the App Store build shows no dead control.

This satisfies "shipping build is private-API-free" without deleting the experimental path from the repo.

---

## Q3 — Packaging the cross-browser MV3 extension for distribution

There is **no single package** that ships to all browsers. Three distribution channels, two code paths:

| Channel | Vehicle | Bridge path to the app | Where it's built |
|---------|---------|------------------------|------------------|
| **Safari** | **Safari Web Extension target** bundled *inside* the `.app` (an app-extension `.appex`), shipped in the same App Store submission. | **Native messaging** (`browser.runtime.sendNativeMessage` / port) → the app's `SafariWebExtensionHandler` → forward into `NowPlayingService.updateFromExternal`. **Not** the WebSocket. | Xcode "Safari Web Extension" target (already scaffolded at `SafariExtension/`). |
| **Chrome / Edge / Brave** | Same MV3 source, zipped and submitted to the **Chrome Web Store** separately. | Existing `ws://127.0.0.1:8787` WebSocket → `BrowserBridge`. | `BrowserExtension/` (already exists, not part of SPM). |
| **Firefox** | Same MV3 source, submitted to **AMO** separately. | Existing WebSocket → `BrowserBridge`. | `BrowserExtension/`. |

**Key architectural delta — a second ingestion transport for Safari only.** Safari's native-messaging handler becomes a **new producer** that funnels through the *same* `updateFromExternal` entry point (identical to how `NativeMediaRemoteCapture` reuses it). This preserves the single-ingestion-point invariant: no new consumer path, no new `@Published` field.

```
Chrome / Firefox ext ──ws://127.0.0.1:8787──► BrowserBridge ──┐
                                                              ├─► NowPlayingService.updateFromExternal(...)
Safari Web Extension ──native message──► SafariWebExtHandler ─┘        (single ingestion, unchanged contract)
```

**Shared-core recommendation.** Keep one MV3 source tree (content scripts + MediaSession reader) and abstract only the *transport tail*: Chrome/Firefox emit over WebSocket; the Safari build emits over `runtime.sendNativeMessage`. A build/flag switch on the transport avoids maintaining two MediaSession readers. The threat-model hardening (frame cap, title cap, `data:` decode, SSRF guard) must be **re-applied on the native-messaging boundary too** — native messages are still untrusted extension input.

**Store metadata note.** The Safari extension ships automatically with the app (one App Store review). Chrome/Firefox are independent review pipelines with their own listing assets and their own release cadence — treat them as a separate, decoupled workstream that does **not** block the App Store submission.

---

## Q4 — Where the Xcode target sits relative to the SwiftPM package

**Pattern: an Xcode app project that consumes the existing SwiftPM package as a *local package dependency*.** Confidence: HIGH — this is the standard, Apple-documented modularization pattern.

- Convert (or expose) `Sources/VinylPod` as a **library product** in `Package.swift` (in addition to, or instead of, the current single `executableTarget`). The Xcode app target links that library product via `.package(path: "..")` / "Add Local Package."
- The **Xcode app target** owns everything the SPM build cannot: `Info.plist` (`LSUIElement=true`), entitlements (`app-sandbox`, `network.server`, `network.client`), code signing, the Safari Web Extension `.appex`, asset catalog, and the App Store archive. It contains a thin `@main` shim (or hosts the existing `VinylPodApp`) and depends on the library for all logic.
- **Dev path stays intact.** `swift build` + `make_app.sh` continue to work against the library/executable for fast local iteration. The Xcode project is **additive**, used for the signed/sandboxed/entitled archive only. This directly honors the constraint "introducing Xcode must not break the `swift build` / `make_app.sh` path."
- **`@VPState` resolution.** The Xcode toolchain ships the `SwiftUIMacros` plugin, so under Xcode `@State` compiles natively. Keep the `typealias VPState = SwiftUI.State` — it is a no-op alias under Xcode and preserves CLT builds. Do **not** mass-rewrite `@VPState` back to `@State`; that would break the CLT dev path for no benefit.

```
Package.swift  ──(library product: VinylPodKit)──┐
   Sources/VinylPod/**  (frozen Core/…, all logic)│
                                                  ▼
VinylPod.xcodeproj
 ├─ App target ────────► links VinylPodKit (local SPM dep)
 │    Info.plist, entitlements, signing, App Store archive
 ├─ Safari Web Extension target (.appex, embedded)
 └─ (dev unchanged: swift build + make_app.sh still target the package)
```

**Notarization note (build-order relevant).** Mac **App Store** submissions are *not* separately notarized — App Store review performs equivalent checks; notarization is only for Developer-ID distribution outside the store. So the "notarization pipeline" line item collapses into **App Store archive + signing + entitlements**, unless a parallel direct-download (Developer ID) build is also wanted. Confirm which distribution is intended before building a standalone notarization step.

---

## Q5 — Build order / dependency graph across the four workstreams

```
                 ┌─────────────────────────────────────────────┐
   W0  LAND WIP  │ commit 19-file drift, re-verify perf invariants (blocks all)
                 └───────────────┬─────────────────────────────┘
                                 │
        ┌────────────────────────┼───────────────────────────────┐
        ▼                        ▼                                ▼
  W1 TESTS (foundation)   W2a SANDBOX SPIKE            W4 UI BLEND (independent)
  SPM test target;        prove loopback NWListener     Views/ + Widget/ only;
  isPublicHost,           runs under app-sandbox +      must respect 6 perf
  decodeDataURI,          network.server on a signed    invariants (W1 guards it)
  updateFromExternal      throwaway build (feasibility  ── runs parallel to W2/W3
  change-gating           gate, ~1 day)
        │                        │
        │                        ▼
        │                 W2b MAS SCAFFOLD
        │                 Xcode app target wraps SPM lib;
        │                 entitlements; #if-strip MediaRemote (Q2);
        │                 Safari Web Ext target (Q3)
        │                        │
        └───────────┬────────────┘
                    ▼
             W3 PHASE 2 CAPTURE
             source-precedence rules; wire Safari native-messaging
             producer + keep Chrome/FF WebSocket; Last.fm creds
                    │
                    ▼
             W5 STORE SUBMISSION (App Store archive; Chrome/FF stores decoupled)
```

**Ordering rationale / non-blocking cuts:**

1. **W0 (land WIP) is a hard prerequisite.** The 19-file uncommitted drift sits in perf/security-critical files (`Services.swift +78`, `WindowManager.swift`, the three extension JS files). Everything downstream must build on committed, invariant-verified code or the whole plan floats on sand.
2. **W1 (tests) first and parallel-safe.** No dependency on the others; it *de-risks* every later refactor (especially W2b's `#if` strip and W3's new producer, which touch `Services.swift`/ingestion). Start it immediately after W0.
3. **W2a (sandbox spike) is the feasibility gate — isolate it early and small.** Although Q1 resolves to FEASIBLE with HIGH confidence, prove it on a signed throwaway build *before* committing to the full Xcode migration, because a negative result would force the native-messaging-only architecture and reorder everything. Cheap insurance (~1 day). It gates only W2b, not W1/W4.
4. **W2b (MAS scaffold) and W4 (UI blend) run in parallel** — disjoint files. UI blend touches `Views/`/`Widget/`; MAS scaffold touches project structure, `Package.swift` product, entitlements, and the conditionally-compiled `Capture/`. Their only shared risk is perf invariants, which W1 now guards.
5. **W3 (Phase 2 capture) depends on W2b** only for the Safari native-messaging producer (it needs the Safari extension target to exist). The Chrome/Firefox source-precedence work does **not** depend on MAS and could start earlier against the existing WebSocket bridge; sequence it after W2b only if you want the Safari fork landed in the same pass.
6. **Chrome/Firefox store submissions are fully decoupled** from the App Store submission — different review pipelines, no shared blocking. Treat as a trailing, independent task.

**Critical-path summary:** `W0 → W2a → W2b → W3 → W5`, with `W1` and `W4` hanging off `W0` in parallel. The only true serialization is the sandbox gate before the Xcode migration, and the Safari extension target before the Safari capture producer.

---

## Component / boundary deltas (net-new this cycle)

| New/changed component | Boundary | Feeds / touches | Invariant preserved |
|-----------------------|----------|-----------------|---------------------|
| `SafariWebExtensionHandler` (native-messaging producer) | Producer, App/Extension layer | → `updateFromExternal` (same single ingestion) | No new consumer path; no new `@Published` field |
| `NativeMediaRemoteCapture` → `#if`-stubbed | Conditionally-compiled producer | Same seam, no-op stub in MAS build | Private-API-free shipping binary |
| Xcode app target | Wiring/packaging layer | Links SPM library product; owns entitlements/signing | `swift build`/`make_app.sh` dev path intact |
| Entitlements file | Packaging | `app-sandbox` + `network.server` + `network.client` | Loopback bridge unchanged |
| SPM test target | Test layer | Exercises `isPublicHost`, `decodeDataURI`, `updateFromExternal` gating | Locks perf + threat-model invariants |

**Unchanged and must stay unchanged:** `NowPlayingService` public contract, the single `updateFromExternal` ingestion point, the one reused `NSPanel`, the six performance invariants, and all `CONTRACTS.md` frozen names. Every delta above is additive and routes through existing seams.

---

## Confidence Assessment

| Question | Verdict | Confidence | Basis |
|----------|---------|------------|-------|
| Q1 Sandbox loopback server | Feasible with `network.server`+`network.client` | HIGH | Apple App Sandbox docs; entitlement is "listen for incoming connections," loopback not carved out; widely shipped pattern |
| Q1 Safari extension caveat | Safari can't `ws://localhost`; use native messaging | HIGH | Apple dev forums + Apple "Messaging a Web Extension's Native App" docs |
| Q2 MediaRemote strip | Compile out via `#if`, not just runtime-gate | HIGH | `dlsym` string flagging by App Store static analysis is well-established |
| Q3 Extension packaging | Safari `.appex` in-app + separate Chrome/FF stores; transport fork | HIGH | Safari Web Extension model; native-messaging requirement from Q1 |
| Q4 Xcode wraps SPM | App target consumes local package product | HIGH | Apple "Adding package dependencies" docs; standard modularization pattern |
| Q5 Build order | W0→(W1‖W4)→W2a→W2b→W3→W5 | MEDIUM-HIGH | Derived from dependency graph; sandbox spike is the one gating unknown |

## Sources

- [App Sandbox — Apple Developer Documentation](https://developer.apple.com/documentation/security/app-sandbox)
- [Enabling App Sandbox / Entitlement Key Reference — Apple](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)
- [Configuring the macOS App Sandbox — Apple](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Safari Web Extension background cannot open WebSocket — Apple Developer Forums](https://developer.apple.com/forums/thread/657900)
- [Messaging a Web Extension's Native App — Apple Developer Documentation](https://developer.apple.com/documentation/safariservices/messaging-a-web-extension-s-native-app)
- [Adding package dependencies to your app — Apple Developer Documentation](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)
- [Sandboxing on macOS — Mark Rowe](https://bdash.net.nz/posts/sandboxing-on-macos/)

---

*Architecture research: 2026-07-03. Deltas only — the frozen VinylPod architecture is not redesigned here.*
