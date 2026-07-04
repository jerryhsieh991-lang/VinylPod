# Stack Research

**Domain:** Native macOS menu-bar app (SwiftUI + AppKit via SwiftPM) → Mac App Store distribution
**Researched:** 2026-07-03
**Confidence:** MEDIUM-HIGH (core Apple-toolchain facts verified against Apple Developer docs, TN3147, and Swift Forums; some App Store review specifics are policy-dependent)

> Scope note: This is a SUBSEQUENT-milestone stack delta. The existing stack (Swift 5.9, SwiftUI/AppKit, `Network`, AVFoundation, CryptoKit, Carbon, ServiceManagement, zero third-party deps, MV3 extension, loopback WebSocket bridge) is already documented in `.planning/codebase/STACK.md` and is NOT re-litigated here. This document covers ONLY the tooling needed to (1) go from a CLT-only `swift build` to a Mac-App-Store-distributable app, (2) resolve the `@VPState`/`@State` macro workaround, (3) wire App Sandbox + signing + submission around the loopback bridge, (4) package the Safari extension, and (5) add a test target.

---

## TL;DR Recommendations

1. **Install full Xcode 26** (year-versioned, ships with macOS 26 "Tahoe" SDK). This single change resolves the `@State` macro problem and is a hard prerequisite for App Store submission.
2. **Do NOT use `swift package generate-xcodeproj`** — deprecated and removed. Keep `Package.swift` as the source of truth for code + tests; add a **thin Xcode app project** that references the package as a **local Swift package**.
3. **Manage that thin Xcode project with a native `.xcodeproj`** for now (single app + one Safari appex is small). Consider **XcodeGen** if `.pbxproj` merge pain appears; **Tuist** only if the project grows to many targets.
4. **App Sandbox is mandatory.** The loopback bridge is feasible under sandbox with `com.apple.security.network.server` (listen) + `com.apple.security.network.client` (outbound). **This is the key feasibility answer: the 127.0.0.1 WebSocket server survives sandboxing.**
5. **Mac App Store path ≠ notarytool path.** App Store apps upload to App Store Connect and are auto-ticketed by Apple; `notarytool` is only for a parallel Developer-ID direct-download build.
6. **Add a SwiftPM test target using Swift Testing** (bundled with Xcode 16+/26) for pure-function unit tests; keep XCTest available for any performance/measurement tests.
7. **Remove/guard the private `MediaRemote` framework** in the shipping path — private frameworks are an automatic App Store rejection.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Xcode | 26.x (macOS 26 Tahoe SDK) | Build toolchain, signing, App Store archive/upload | Mandatory for App Store; ships the `SwiftUIMacros` plugin that fixes `@State`; provides Organizer archive→validate→upload flow. Year-based versioning aligns Xcode 26 ↔ macOS 26. |
| Swift Package Manager | swift-tools 5.9+ (keep) | Source of truth for code + tests | `swift build` under the Xcode toolchain keeps the fast dev loop and unit tests; no need to migrate all code into `.pbxproj`. |
| Native `.xcodeproj` app target | Xcode 26 | App bundle: Info.plist, entitlements, App Sandbox, signing, Safari appex, App Store packaging | SPM alone cannot produce a signed, sandboxed, App-Store-submittable `.app`. A thin Xcode app target referencing the local package is the standard 2026 pattern. |
| App Sandbox | macOS 26 | Required MAS runtime container | Non-negotiable for Mac App Store. Loopback bridge works with the two network entitlements below. |
| Safari Web Extension (appex) | via `xcrun safari-web-extension-converter` | Ship a browser-capture path through the App Store inside the app bundle | Only browser-extension form Apple will host in the MAS; Chrome/Firefox variants stay in their own stores. |
| Swift Testing | bundled Xcode 16+/26 | Pure-function unit tests (bridge security helpers, change-gating, perf-invariant logic) | Apple's modern first-party test framework; `@Test`/`#expect` macros, parameterized cases, parallel-by-default. Ideal for the pure helpers targeted in the Active requirements. |

### Supporting Libraries / Tools

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `xcodebuild` | Xcode 26 | CI/scripted archive + test | Replace/augment `make_app.sh` for signed builds; `xcodebuild archive` → `-exportArchive`. |
| `xcrun safari-web-extension-converter` | Xcode 26 CLT | Convert the MV3 `BrowserExtension/` into a Safari appex + Xcode project | One-time scaffold; then maintain the appex in-tree. |
| `notarytool` | Xcode 14+/standalone | Notarize a **Developer ID** direct-download build (optional, parallel channel) | ONLY if you also ship outside the MAS. Not part of the MAS submission itself. |
| `codesign` / `stapler` | Xcode 26 CLT | Signing + (for Developer ID) stapling the notarization ticket | MAS build is signed by Xcode's archive/export; `stapler` only for the Developer-ID channel. |
| XcodeGen | 2.x (latest) | Generate `.xcodeproj` from a text `project.yml` | Adopt only if `.pbxproj` merge conflicts become a problem. No runtime dependency. |
| Tuist | 4.x (latest) | Swift-based project generation | Reserve for later growth (many targets, modular packages). Overkill for app + one appex today. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Xcode Organizer | Archive → Validate → Distribute to App Store Connect | The primary MAS upload UI; alternative is `xcrun altool`-successor / Transporter. |
| Transporter.app | Alternative MAS upload | Mac App Store app from Apple; upload `.pkg`/`.app` archives to App Store Connect. |
| App Store Connect | Listing, TestFlight (macOS), review submission | Where the MAS build is reviewed; TestFlight for macOS allows beta distribution. |

---

## The Five Migration Concerns (prescriptive answers)

### 1. Introducing an Xcode project over the existing `Package.swift`

**Verdict: keep `Package.swift`, add a thin Xcode app target that references it as a local package. Do NOT generate a project from SPM.**

- `swift package generate-xcodeproj` is **deprecated (Swift Forums RFC) and removed** since ~Swift 5.9.x (`Unknown subcommand or plugin name 'generate-xcodeproj'`). Do not use it. *(Confidence: HIGH — Swift Forums + issue trackers.)*
- Since Xcode 11, Xcode **opens `Package.swift` directly**. But an SPM executable target cannot itself be a signed/sandboxed MAS `.app` — you need a real app target that owns Info.plist, entitlements, and the appex.
- **Recommended structure:**
  1. Refactor the SPM `VinylPod` **executable** target into a **library** target (e.g. `VinylPodKit`) plus a minimal `@main` app-entry file. All ~9,300 LOC stay in the library so `swift build` + tests keep working.
  2. Create a native **Xcode app target** whose only job is the app shell + `import VinylPodKit`, added via *File → Add Package Dependencies → Add Local…* pointing at the repo package.
  3. The Xcode app target owns: `Info.plist` (`LSUIElement`), entitlements (App Sandbox + network), code-signing, the Safari appex, and the App Store archive config.
- **Tooling choice for that project file:**
  - **Native `.xcodeproj`, committed (recommended now):** simplest, zero extra tooling, fine for 2 targets. Risk: `.pbxproj` merge conflicts (mitigated by rare structural changes for a solo/small team).
  - **XcodeGen (fallback):** `project.yml` → generated `.xcodeproj`, kept out of git; eliminates `.pbxproj` merge conflicts. Adopt if conflicts bite.
  - **Tuist (future):** most powerful/actively-developed, Swift-defined projects, great SPM integration — but overkill for app + one appex today.
- **Preserve the dev path:** `swift build` and `make_app.sh` keep working for local dev **because the code lives in the SPM library**; the Xcode project is additive, used for signed/App-Store builds. This satisfies the PROJECT.md constraint that Xcode adoption "must not break the `swift build` / `make_app.sh` path."

*Confidence: MEDIUM-HIGH.*

### 2. Resolving the `@State`-as-macro / `@VPState` workaround

**Verdict: installing the full Xcode 26 toolchain resolves it; real `@State` then compiles. The `VPState` alias becomes unnecessary but harmless.**

- Root cause (confirmed): the macOS 26 SDK declares SwiftUI `@State` as an **attached macro**; its implementation ships in the **`SwiftUIMacros` compiler plugin bundled only with full Xcode**, not standalone Command Line Tools. Under CLT `swift build` the compiler cannot locate the external macro implementation → build failure. `typealias VPState = SwiftUI.State` references the property-wrapper **type**, dodging macro-name resolution.
- **Resolution:** build with the **Xcode 26 toolchain** — via the Xcode app, `xcodebuild`, or `xcrun swift build` — which makes the `SwiftUIMacros` plugin available, so real `@State` (and `#Preview`, other SwiftUI macros) compile normally.
- **Recommendation:**
  - Once Xcode 26 is the build toolchain for the App Store target, `@VPState` is **no longer required**. You may mechanically migrate `@VPState` → `@State`, OR keep `typealias VPState = State` as a **harmless compatibility shim** so contributors on CLT-only machines can still `swift build`. Lowest-risk path: keep the alias, stop mandating it; new code may use `@State` freely once Xcode is standard.
  - Do NOT ship third-party `SwiftUIMacros` packages (e.g. community `SwiftUI-Macros`) — they are unrelated to Apple's plugin and add a dependency against the project's zero-dep principle.

*Confidence: MEDIUM (root cause matches Swift Forums reports of "external macro implementation type could not be found" from CLI vs Xcode; the fix is the standard "use the Xcode toolchain" resolution).*

### 3. Code signing + entitlements + App Sandbox — and the loopback-bridge feasibility

**Verdict: FEASIBLE. The 127.0.0.1 WebSocket server runs under App Sandbox with the network server + client entitlements.**

- **App Sandbox (`com.apple.security.app-sandbox = true`) is mandatory** for the Mac App Store.
- **Entitlements the bridge needs:**
  - `com.apple.security.network.server = true` — allows the app to **listen** for incoming connections; required to bind `NWListener` on `127.0.0.1:8787`.
  - `com.apple.security.network.client = true` — required for **outbound** connections: Last.fm HTTPS (`ws.audioscrobbler.com`), artwork downloads, and any outbound loopback.
- **Loopback is subject to the sandbox network entitlements** (it is not exempt), so BOTH entitlements are needed. With them, a sandboxed app can run a local loopback WebSocket server. A separate browser process (Chrome/Safari/Firefox) connecting **inbound** to `127.0.0.1:8787` is fine — the browser has its own network capability. Apple DTS guidance indicates loopback failures are typically **firewall / code-signing** issues, not sandbox restrictions.
- **Additional entitlements likely required:**
  - `com.apple.security.files.user-selected.read-only` (or read-write) — for local audio drag-and-drop (AVFoundation). Drag-drop grants a temporary sandbox extension; user-selected file access covers it.
- **Signing for MAS:** Apple Distribution certificate + a Mac App Store provisioning profile (managed by Xcode "Automatically manage signing"). The archive is signed by Xcode's export step — **not** ad-hoc `codesign --sign -` as `make_app.sh` does today (ad-hoc is dev-only).
- **Hardened Runtime:** required for Developer-ID/notarized builds; for MAS the sandbox + Apple Distribution signing govern. Keep the app free of private frameworks either way.

*Confidence: MEDIUM-HIGH on entitlements (Apple docs); MEDIUM on the exact App-Review reception of a bundled local server — document the justification in review notes.*

### 4. Notarization (notarytool) — important clarification

**Verdict: `notarytool` is for a Developer-ID direct-download build, NOT the Mac App Store submission. Don't conflate them.**

- `altool` notarization was deprecated; the notary service **rejects `altool`/Xcode ≤13 uploads since 2023-11-01** (Apple TN3147). `notarytool` (Xcode 14+, runs standalone on macOS 10.15.7+, zero external deps, has `--wait`) is the current tool for the **Developer ID** channel.
- **Mac App Store apps are NOT notarized via `notarytool`.** They are uploaded to **App Store Connect** (Xcode Organizer → Distribute App → App Store Connect, or Transporter), go through **App Review**, and Apple performs its own signing/ticketing automatically.
- **Recommendation:** for the primary MAS goal, skip `notarytool` entirely. Only if VinylPod also offers a **direct `.dmg`/`.zip` download** (a common "free app, also downloadable" hedge) do you run: `codesign` (Developer ID + Hardened Runtime) → `notarytool submit --wait` → `stapler staple`.

*Confidence: HIGH (Apple TN3147 + App Store distribution docs).*

### 5. Safari Web Extension packaging inside the app bundle

**Verdict: convert the MV3 extension once with `safari-web-extension-converter`, ship the resulting appex inside the `.app`. Chrome/Firefox stay in their own stores.**

- `xcrun safari-web-extension-converter BrowserExtension/ --project-location <dir> --app-name VinylPod --bundle-identifier <id>` scaffolds an Xcode project with the **app + a Safari Web Extension appex**; the appex is packaged **inside the `.app` bundle** and submitted together to the MAS.
- **Caveats to plan for:**
  - The converter emits **one icon**; the appex needs a full icon set for distribution.
  - It does **not** copy the version from `manifest.json` — set it manually.
  - **MV3 conversion has rough edges** — expect to reconcile background service-worker vs Safari's model, host-permission prompts, and any Chrome-only APIs.
- **Architecture note:** the Chrome/Firefox MV3 builds are distributed via **their own web stores**, not inside the `.app`. App Review only inspects the **Safari appex**. The app's loopback server still serves all browsers, so the multi-browser capture story is intact even though only Safari ships through the MAS.
- **Safari appex is itself sandboxed** — verify its network use and messaging stay within Safari extension constraints; it talks to web pages via content scripts, and the *native app* (not the appex) owns the loopback server.

*Confidence: MEDIUM (Apple packaging docs + multiple conversion write-ups; MV3→Safari specifics are project-dependent).*

---

## Test Target (concern 5 of the Active list)

| Choice | Recommendation | Rationale |
|--------|----------------|-----------|
| Framework | **Swift Testing** for new pure-function unit tests | Bundled Xcode 16+/26; `@Test`/`#expect`, parameterized tests, parallel execution. Perfect for `isPublicHost`, `decodeDataURI`, `updateFromExternal` change-gating, perf-invariant logic. |
| Keep XCTest? | Yes, for performance/measurement | Swift Testing has **no performance-measurement API**; XCTest's `measure {}`/`XCTMetric` remains the way to guard the "0.0% idle CPU" invariants if you assert them in tests. Both coexist in one test target under Xcode 16+. |
| SPM wiring | Add a `.testTarget` in `Package.swift` depending on the `VinylPodKit` library | Keeps tests runnable via `swift test` (Xcode toolchain) AND in Xcode; no app bundle needed for pure-function tests. |

`Package.swift` sketch:
```swift
.testTarget(
    name: "VinylPodKitTests",
    dependencies: ["VinylPodKit"]
)
```
Pure-function tests need only the library, so they run fast headlessly. UI/window tests requiring `NSApplication` belong in an Xcode-hosted test target, not SPM.

*Confidence: MEDIUM-HIGH.*

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Thin `.xcodeproj` + local SPM package | Full migration of all code into `.xcodeproj` | Never recommended — loses `swift build`/`swift test` and the zero-config SPM dev loop. |
| Native `.xcodeproj` (committed) | XcodeGen (`project.yml`) | When `.pbxproj` merge conflicts become frequent/painful. |
| Native `.xcodeproj` | Tuist (`Project.swift`) | When the project grows to many targets/modules and needs reproducible, cache-accelerated generation. |
| Swift Testing | XCTest | For performance/`measure` tests and any legacy `NSApplication`-hosted UI tests. |
| Ship Safari appex via MAS + Chrome/Firefox via web stores | Ship only Safari | If you want a single distribution channel; but this drops the cross-browser advantage that is VinylPod's differentiator. |
| Keep `@VPState` alias as harmless shim | Full `@State` migration | Migrate fully only once every dev machine has Xcode 26 and CLT-only builds are no longer supported. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `swift package generate-xcodeproj` | Deprecated and removed (Swift 5.9.x); errors out | Open `Package.swift` in Xcode + a thin app target referencing the local package |
| Private `MediaRemote.framework` in the shipping path | Automatic App Store rejection (private API); already entitlement-gated/no-op on macOS 15.4+ | Compile it out (or hard-guard behind a non-shipping flag) for the MAS build; rely on the browser bridge |
| Ad-hoc `codesign --sign -` (current `make_app.sh`) for release | Not acceptable for MAS or Developer-ID distribution | Apple Distribution cert + MAS provisioning profile (Xcode-managed) for MAS; Developer ID + notarytool for direct download |
| `altool` for notarization | Notary service rejects it since 2023-11-01 | `notarytool` (Developer-ID channel only) |
| Third-party `SwiftUIMacros`/`@State` replacement packages | Adds a dependency, violates zero-dep principle, unrelated to Apple's plugin | Install full Xcode 26 (ships Apple's `SwiftUIMacros` plugin) |
| Relying on `notarytool` for the MAS submission | MAS uses App Store Connect review + Apple's own ticketing, not notarytool | Xcode Organizer / Transporter → App Store Connect |

---

## Feasibility Flags for the Roadmap

- 🟢 **Loopback WebSocket server under App Sandbox: FEASIBLE** with `network.server` + `network.client`. This was the flagged "real feasibility question" in PROJECT.md — it resolves in favor of proceeding. Add clear review notes justifying the local server (browser now-playing capture, loopback-only, no external network exposure).
- 🟡 **App Review reception of a bundled local server + broad browser capture** is policy-dependent; keep the loopback-only hardening (already implemented: 256 KB frame cap, 6-conn cap, SSRF guard) and document it. Consider a shared-secret/nonce handshake (already an Active requirement) to strengthen the review narrative.
- 🟡 **MV3 → Safari appex conversion** will need hands-on reconciliation (service-worker model, icons, versioning). Budget a dedicated phase; don't assume a clean one-shot convert.
- 🔴 **`MediaRemote` MUST be removed/guarded** from the shipping MAS binary before submission — hard blocker if present.
- 🟡 **`make_app.sh` ad-hoc signing** cannot be the release pipeline; a parallel signed/archive pipeline (Xcode/`xcodebuild`) is required. Keep `make_app.sh` for local dev only.

---

## Version Compatibility

| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| Xcode 26 | macOS 26 Tahoe SDK, Swift 6/5.x language modes | Provides `SwiftUIMacros` plugin → fixes `@State`; keep `swift-tools-version:5.9` unless a Swift 6 migration is separately scoped |
| Swift Testing | Xcode 16+ (thus 26) | Bundled; coexists with XCTest in one target |
| `notarytool` | Xcode 14+ or standalone on macOS 10.15.7+ | Developer-ID channel only |
| App Sandbox network entitlements | All supported macOS | `server` (listen) + `client` (outbound) both required for the loopback bridge |
| Deployment target `macOS 13.0` | Must still build against macOS 26 SDK | Building with a newer SDK while targeting 13.0 is standard; verify Liquid-Glass APIs are availability-gated (`if #available`) |

---

## Sources

- Swift Forums — "RFC: Deprecating generate-xcodeproj" / "generate-xcodeproj is no longer needed" — confirms deprecation + Xcode-opens-Package.swift. (curated, HIGH)
- swiftlang/swift-package-manager issues (#6640 / removal) — `generate-xcodeproj` removed in Swift 5.9.x. (curated, HIGH)
- Swift Forums — "external macro implementation type could not be found" threads — CLI-vs-Xcode macro plugin behavior underpinning the `@VPState` root cause. (web, MEDIUM)
- Apple Developer Documentation — `com.apple.security.network.server` entitlement — listen for incoming connections; MAS-allowed. (curated, HIGH)
- Apple Developer Documentation — App Sandbox / `com.apple.security.app-sandbox` — MAS sandbox requirement. (curated, HIGH)
- Apple Developer Forums thread 743191 (Apple DTS/Quinn) — loopback issues are firewall/code-signing, not sandbox. (web, MEDIUM)
- Apple TN3147 "Migrating to the latest notarization tool" + Apple news 2023-11-01 requirement — `altool` deprecated, `notarytool` current. (curated, HIGH)
- Apple Developer Documentation — "Packaging a web extension for Safari" + `safari-web-extension-converter` usage write-ups — appex-inside-app packaging for MAS. (curated + web, MEDIUM)
- Swift Testing (Apple, bundled Xcode 16+) — modern first-party test framework recommendation. (curated, MEDIUM-HIGH)

> External search providers (Exa, Tavily) were unavailable during this run (401/unauthorized); findings were gathered via built-in WebSearch/WebFetch against official Apple docs, Apple TN3147, and Swift Forums. Confidence is set by SOURCE authority (Apple official = HIGH) rather than the generic web-provider tier. Re-verify Xcode 26 exact minor version and current MAS review guidance at submission time.

---
*Stack research for: SPM SwiftUI+AppKit macOS menu-bar app → Mac App Store*
*Researched: 2026-07-03*
