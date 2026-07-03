# Phase 2: Sandbox/Loopback + Signing Spike - Research

**Researched:** 2026-07-03
**Domain:** macOS App Sandbox networking + Mac App Store signing/upload pipeline (Xcode 26, NWListener, App Store Connect)
**Confidence:** MEDIUM-HIGH (Apple-docs-grounded; ASC upload behavior is version/policy-sensitive — the spike itself is the verification step for the LOW/MEDIUM items)

## Summary

Phase 2 is a ~1-day throwaway spike with two deliverables: (MAS-01) a signed + sandboxed shell app that binds `127.0.0.1:8787` with `NWListener` and completes an outbound HTTPS artwork fetch on a real sandboxed build, verified via sandbox-violation logs rather than "it launched"; and (MAS-02) that same shell clearing an App Store Connect upload, validating the Apple Distribution cert + MAS provisioning profile + app-sandbox pipeline end-to-end. Project research already resolved feasibility FEASIBLE/HIGH — this phase's job is a trustworthy empirical verdict plus a working pipeline.

Environment probing on this machine surfaced **two facts that reshape the plan**: (1) the Mac runs **macOS 27.0 beta with Xcode 27.0 beta** (27A5209h) installed and `xcode-select` pointing at CLT — there is **no release Xcode 26.x** installed. App Store Connect can reject uploads built with beta Xcode/SDKs ("Unsupported Xcode or SDK Version"), which would produce a **false-negative on MAS-02** — so the spike must install release Xcode 26.x (≥26.1.1) for the upload leg. (2) `security find-identity` shows **zero codesigning identities** — Apple Developer Program enrollment + Xcode account sign-in is a hard human prerequisite before any signed build exists.

The spike should be built as a 4-variant entitlement test matrix (sandbox × {server,client} combinations) so it empirically answers the open question "does outbound *loopback* need `network.client`?" while simultaneously producing a reference table of failure signatures (sandbox denial vs. signing/config error) — which is exactly the go/no-go discrimination the phase exists to deliver.

**Primary recommendation:** Build one tiny Xcode app target (`spike/` directory, never touching `Package.swift`) with a single Swift file (NWListener WS echo + URLSession HTTPS fetch + outbound-loopback probe), run it through the entitlement matrix under `log stream` sandbox predicates, then archive with release Xcode 26.x and upload via Xcode Organizer to a pre-created ASC app record. Record the verdict in a go/no-go doc.

## Phase Requirements

<phase_requirements>

| ID | Description | Research Support |
|----|-------------|------------------|
| MAS-01 | Signed + sandboxed throwaway shell binds `127.0.0.1:8787` (NWListener) and fetches artwork on a real sandboxed build, verified via Console `sandboxd` | Entitlement triad + test-matrix design (§Architecture Patterns), sandbox-denial observation commands (§Code Examples), failure-mode playbook (§Failure-Mode Playbook), bind-pattern reuse from `BrowserBridge.swift` |
| MAS-02 | Shell passes App Store Connect upload — full MAS signing pipeline validated end-to-end | Toolchain findings (release Xcode 26.x required, not the installed 27 beta), ASC app-record prerequisites, Organizer vs `xcodebuild -exportArchive` vs Transporter paths, upload-acceptance confirmation steps, Info.plist keys that trip validation (`LSApplicationCategoryType`, icon) |

</phase_requirements>

## Project Constraints (from repo docs, no CONTEXT.md exists for this phase)

- The spike must **NOT touch the existing SPM package** (`Package.swift`, `Sources/`, `make_app.sh`) — throwaway shell in its own directory. [CITED: .planning/ROADMAP.md Phase 2]
- Locked milestone decisions: PURSUE MAC APP STORE; the loopback WebSocket bridge stays for Chrome/Firefox; Safari uses native messaging (later phases). [CITED: .planning/REQUIREMENTS.md]
- `notarytool` is explicitly NOT part of the MAS path (ENH-04 defers Developer-ID). [CITED: .planning/research/STACK.md §4]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Loopback WS server bind (`127.0.0.1:8787`) | Spike app (Network.framework, in-process) | — | Same tier that owns it in production (`BrowserBridge`); sandbox verdict must be measured where production runs it |
| Outbound HTTPS artwork fetch | Spike app (URLSession) | — | Mirrors `BrowserBridge.loadArtwork()`; exercises `network.client` |
| Outbound *loopback* probe | Spike app (URLSession → 127.0.0.1) | — | Answers open question (a); production browsers connect inbound, but the answer informs test clients/health checks |
| Inbound connect exercise | External test client (CLT `swift` script) | — | Sandbox restricts the *listener's* bind, not the (unsandboxed) client; a second process proves real cross-process inbound traffic |
| Sandbox verdict observation | macOS unified log (`log stream`) | Console.app | `sandboxd`/`Sandbox` sender is the authoritative denial channel — not app-side error codes alone |
| Signing/provisioning | Xcode 26 (automatic signing) + Apple Developer portal | `codesign`/`spctl` verification | Certs/profiles are account-level state, not code |
| Upload validation | App Store Connect (server-side) | Xcode Organizer / `xcodebuild` / Transporter | Only ASC's acceptance is the MAS-02 pass signal |

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Xcode | **26.x release (≥26.1.1; install latest 26.x)** | Build, sign, archive, upload the spike | ASC rejects beta-toolchain uploads for submission and may reject at upload ("Unsupported Xcode or SDK Version"); the installed Xcode 27.0 beta risks a false-negative on MAS-02 [VERIFIED: developer.apple.com forums + georgegarside.com; version via xcodereleases.com] |
| Network.framework (`NWListener` + `NWProtocolWebSocket`) | macOS SDK (built-in) | Loopback WS echo server | Identical API production uses in `Sources/VinylPod/Bridge/BrowserBridge.swift:44` — the spike must exercise the same bind pattern (`requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 8787)`) [VERIFIED: codebase grep] |
| URLSession | Foundation (built-in) | Outbound HTTPS artwork fetch + loopback probe | Mirrors `BrowserBridge.loadArtwork()`; respects sandbox `network.client` (unlike some Apple out-of-process frameworks) [CITED: developer.apple.com/forums/thread/744961 — Quinn: URLSession respects the sandbox restriction] |
| App Sandbox + entitlements | `com.apple.security.app-sandbox`, `.network.server`, `.network.client` | The triad under test | MAS-mandatory; `server` = "listen for incoming connections", `client` = "open outgoing connections" [CITED: developer.apple.com/documentation/bundleresources/entitlements] |
| Xcode Organizer | Xcode 26 | Primary upload path (Archive → Distribute App → App Store Connect → Upload) | Simplest path with automatic signing; creates Apple Distribution cert + MAS profile on demand once signed into the account [CITED: STACK.md; Apple distribution docs] |
| `log` CLI / Console.app | macOS built-in | Observe sandbox denials | `sandboxd` + `com.apple.sandbox.reporting` subsystem is the violation channel [VERIFIED: fullmetalmac.com + n8henrie.com cross-checked] |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `xcodebuild archive` / `-exportArchive` | Xcode 26 | Scriptable alternative upload (`method: app-store-connect`, `destination: upload`) | If Organizer flow fails or repeatability is wanted; requires ASC API key or signed-in account |
| Transporter.app | Mac App Store (free) | Third upload option (takes the exported `.pkg`) | Fallback if Xcode upload auth misbehaves |
| `codesign -d --entitlements :-` | CLT | Verify entitlements actually embedded in the built binary | ALWAYS before interpreting any failure — top false-negative source |
| `swift <file>.swift` (CLT) | existing CLT | Run the unsandboxed WS test client (URLSessionWebSocketTask) | Inbound cross-process connect proof; no browser/extension needed |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Release Xcode 26.x for upload | Installed Xcode 27.0 beta | Beta may build/run the sandbox test fine (MAS-01 leg), but upload rejection for beta SDK is indistinguishable-in-cost from a real pipeline failure — unacceptable for a feasibility gate. Use the beta at most for a first local sandbox smoke while 26.x downloads |
| Xcode Organizer upload | `xcodebuild -exportArchive destination=upload` | CLI is repeatable but needs ASC API-key setup (extra prerequisite); Organizer is faster for a one-shot spike |
| Real final bundle ID for the spike | Throwaway bundle ID | Real ID + real app name creates the ASC app record you'll reuse in Phase 6 (name reserved — an asset); throwaway ID litters the account (deletable only pre-approval). **Recommend the real bundle ID** — spike uploads build `0.1 (1)`, later real builds just increment |
| SwiftUI app template | AppKit `NSApplication` shell | Either works; SwiftUI template is fewer files under Xcode 26 (macros work there). Keep it to one content view that shows pass/fail status text |

**Installation:**
```bash
# No package managers involved — Apple toolchain only.
# Download latest Xcode 26.x release (Apple ID required):
#   https://developer.apple.com/download/applications/  (or check xcodereleases.com for the newest 26.x)
xip --expand Xcode_26.x.xip && sudo mv Xcode.app /Applications/Xcode.app
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch          # installs macOS platform bits; no extra platform downloads needed for macOS-only
xcodebuild -version                  # expect: Xcode 26.x
```

**Version verification:** No npm/pip/cargo packages are used in this phase. Toolchain verification is `xcodebuild -version` (must report 26.x release, not a beta build suffix) and `xcrun --show-sdk-version --sdk macosx` (release SDK).

## Package Legitimacy Audit

No external packages are installed in this phase (Apple first-party toolchain + system frameworks only; project has a zero-dependency principle).

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
                        ┌────────────────────────── macOS host ──────────────────────────┐
                        │                                                                 │
 CLT swift script       │   ┌─────────────── SandboxSpike.app (signed, sandboxed) ─────┐ │
 (unsandboxed WS client)│   │                                                           │ │
 URLSessionWebSocketTask┼──►│  NWListener ws://127.0.0.1:8787  ──echo──►  reply frame   │ │
        INBOUND         │   │        │ (requiredLocalEndpoint pins loopback)            │ │
                        │   │        ▼                                                  │ │
                        │   │  Probe 1: URLSession GET https://<artwork-URL>  ──────────┼─┼──► Internet (needs network.client)
                        │   │  Probe 2: URLSession/NWConnection → 127.0.0.1:8787 ───────┼─┘    OUTBOUND LOOPBACK (test-matrix question)
                        │   │  os.Logger: PASS/FAIL per probe                           │
                        │   └───────────────────────────────────────────────────────────┘
                        │                       │ denials logged by kernel/sandboxd
                        │                       ▼
                        │   log stream --predicate '…sandbox…violation…'   (Terminal 2)
                        └─────────────────────────────────────────────────────────────────┘

 Upload leg (MAS-02):  Xcode 26 Archive ──► Organizer "Distribute App → App Store Connect → Upload"
                        └─► ASC app record (pre-created: bundle ID + name + SKU) ──► processing email / build appears in ASC
```

### Recommended Project Structure

```
spike/                          # NEW, sibling of Sources/ — never touches Package.swift
├── SandboxSpike/               # Xcode project dir (macOS App template)
│   ├── SandboxSpike.xcodeproj
│   ├── SandboxSpike/
│   │   ├── SpikeApp.swift      # @main + single status view + all probe logic (~150 lines)
│   │   ├── SandboxSpike.entitlements   # the triad (varied per test-matrix run)
│   │   ├── Info.plist keys via build settings (LSUIElement, LSApplicationCategoryType)
│   │   └── Assets.xcassets     # AppIcon filled (at least 512pt/1024pt) — upload validation
├── wsclient.swift              # CLT-runnable inbound test client (URLSessionWebSocketTask)
├── watch-sandbox.sh            # log stream wrapper (predicates below)
└── VERDICT.md                  # go/no-go record (success criterion 4)
```

### Pattern 1: Minimal spike shell — exact required settings

**What:** Smallest Xcode 26 macOS app that exercises bind + outbound under sandbox.
**When to use:** This phase only; throwaway.

Required target settings (Xcode → target):
1. **Signing & Capabilities:** Team set; "Automatically manage signing"; **App Sandbox** capability ON; under App Sandbox → Network: check **Incoming Connections (Server)** and **Outgoing Connections (Client)** (writes `com.apple.security.network.server`/`.client` into the `.entitlements` file). [CITED: developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox]
2. **Info tab / build settings:**
   - `Application is agent (UIElement)` = YES (`LSUIElement`) — accessory app, no Dock icon (matches production).
   - `LSApplicationCategoryType` = `public.app-category.music` — **required for Mac App Store upload; missing/invalid ⇒ ITMS-90242** [VERIFIED: developer.apple.com/forums/thread/737134 + Apple archive "Submitting to the Mac App Store"].
   - Bundle ID: the real intended production ID (recommended — see Alternatives).
   - App Category can also be set in General → Identity (writes the same key).
3. **AppIcon:** fill the macOS AppIcon set (a single 1024px source in Xcode 26's single-size mode is fine). Missing icons are a classic upload-validation trip. [ASSUMED — cheap to do; Organizer "Validate App" will confirm]
4. **Hardened Runtime:** NOT required for MAS (sandbox + Apple Distribution govern); leave whatever the template sets. [CITED: STACK.md §3]

**Example — the probe core:**
```swift
// Source: pattern lifted from Sources/VinylPod/Bridge/BrowserBridge.swift:33-57 (verified in-repo)
import Network
import Foundation
import os

let log = Logger(subsystem: "com.vinylpod.spike", category: "probe")

func startListener() {
    let params = NWParameters.tcp
    let ws = NWProtocolWebSocket.Options()
    ws.autoReplyPing = true
    params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
    params.allowLocalEndpointReuse = true
    params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 8787)  // loopback-only, as production
    do {
        let listener = try NWListener(using: params)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:            log.info("BIND PASS: listening on 127.0.0.1:8787")
            case .failed(let err):  log.error("BIND FAIL: \(err.localizedDescription) — \(String(describing: err))")
            default: break
            }
        }
        listener.newConnectionHandler = { conn in
            conn.start(queue: .global())
            // echo one frame back, log INBOUND PASS
        }
        listener.start(queue: .global())
    } catch { log.error("BIND THROW: \(error)") }   // sync throw = config-shaped failure, not a denial
}

func fetchArtwork() {   // Probe 1 — public HTTPS (needs network.client)
    let url = URL(string: "https://itunes.apple.com/search?term=daft+punk&entity=album&limit=1")!
    URLSession.shared.dataTask(with: url) { data, _, err in
        if let err { log.error("HTTPS FETCH FAIL: \(err.localizedDescription)") }
        else       { log.info("HTTPS FETCH PASS: \(data?.count ?? 0) bytes") }
    }.resume()
}

func probeOutboundLoopback() {   // Probe 2 — answers open question (a)
    let conn = NWConnection(host: "127.0.0.1", port: 8787, using: .tcp)
    conn.stateUpdateHandler = { state in
        switch state {
        case .ready:           log.info("OUTBOUND-LOOPBACK PASS")
        case .failed(let e):   log.error("OUTBOUND-LOOPBACK FAIL: \(String(describing: e))")
        default: break
        }
    }
    conn.start(queue: .global())
}
```

### Pattern 2: The entitlement test matrix (answers open question (a) empirically)

Run the same binary through 4 entitlement variants (edit `.entitlements`, rebuild, run, capture logs). Each run: start `watch-sandbox.sh` first, then launch the app, then run `swift wsclient.swift` from Terminal 3.

| Variant | app-sandbox | network.server | network.client | Expected (hypothesis) | What it proves |
|---------|-------------|----------------|----------------|----------------------|----------------|
| A (ship config) | ✓ | ✓ | ✓ | bind PASS, inbound PASS, HTTPS PASS, outbound-loopback PASS, **zero denials** | MAS-01 pass condition |
| B | ✓ | ✓ | ✗ | bind PASS, inbound PASS, HTTPS **FAIL + `deny network-outbound`**, outbound-loopback = **THE ANSWER** — hypothesis: also denied (`deny network-outbound 127.0.0.1:8787`) | Whether outbound loopback needs `network.client` |
| C | ✓ | ✗ | ✓ | bind **FAIL + `deny network-bind`** (listener `.failed` or `.waiting`) | The denial signature for a blocked bind — calibrates the playbook |
| D | ✓ | ✗ | ✗ | everything denied | Full-deny baseline log signatures |

Hypothesis basis for B: sandbox profiles log `deny network-outbound 127.0.0.1:PORT` — loopback is not carved out of the sandbox network checks, and Apple's `network.client` doc has no loopback exception. [VERIFIED: lucaswiman.github.io sandbox logs + developer.apple.com entitlement doc — but tagged MEDIUM; the matrix run is the authoritative answer]

Note: macOS 15+ **Local Network privacy** prompts do NOT apply to loopback traffic — no TCC prompt should appear for 127.0.0.1; if one appears, the listener/client is touching a non-loopback interface (bug in the spike). [CITED: developer.apple.com/forums/thread/663858 Local Network Privacy FAQ + WICG explainer]

### Pattern 3: MAS upload path (2026, validation-only)

**Prerequisites (human, one-time — plan as `checkpoint:human-verify` tasks):**
1. Apple Developer Program membership active (paid). **This machine has 0 codesigning identities — enrollment/sign-in is not yet done.** [VERIFIED: `security find-identity -v -p codesigning` → "0 valid identities found"]
2. Xcode → Settings → Accounts → add Apple ID; Xcode creates Apple Development cert; the Distribution flow creates the Apple Distribution cert + Mac App Store profile on demand.
3. **App ID** registered (explicit bundle ID) at developer.apple.com → Certificates, Identifiers & Profiles (automatic signing usually registers it for you).
4. **ASC app record MUST exist before upload** or Xcode/Transporter fails with "No suitable application records were found". Create at App Store Connect → Apps → "+" → New App: platform **macOS**, app **name** (unique across the store — gets reserved), primary language, **bundle ID** (picked from registered App IDs), **SKU** (any internal string). Requires Admin/App Manager role. No screenshots/description needed to *upload* a build — full metadata is only needed to *submit for review* (Phase 6). [VERIFIED: developer.apple.com/forums/thread/72023 + appuploader tutorial cross-check]

**Upload (primary — Organizer):** Product → Archive (scheme: Any Mac / My Mac, Release) → Organizer → **Validate App** (catches ITMS errors locally-ish first) → **Distribute App → App Store Connect → Upload**. Automatic signing re-signs with Apple Distribution + MAS profile during export.

**Upload (scriptable alternative):**
```bash
xcodebuild -project spike/SandboxSpike/SandboxSpike.xcodeproj -scheme SandboxSpike \
  -configuration Release archive -archivePath build/SandboxSpike.xcarchive

xcodebuild -exportArchive -archivePath build/SandboxSpike.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates
```
```xml
<!-- ExportOptions.plist — method "app-store" is DEPRECATED; use "app-store-connect" (Xcode 15.3+) -->
<!-- Source: xcodebuild -help "Available keys for -exportOptionsPlist"; deprecation verified via flutter/flutter#149369 -->
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>   <!-- or "export" to get a .pkg for Transporter -->
  <key>teamID</key><string>YOUR_TEAM_ID</string>
</dict></plist>
```
CLI upload auth needs either a signed-in Xcode account or an ASC API key (`-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID`). `altool` is dead — do not use. [CITED: Apple TN3147 lineage; STACK.md]

**Confirming acceptance (the MAS-02 pass signal):** the upload completing is NOT the signal — server-side processing can still reject. Pass = the build appears under the app record (App Store Connect → Apps → <app> → TestFlight or the build picker) with state past "Processing", and/or the "has completed processing" email arrives. A rejection email (ITMS-xxxxx) = fix and re-upload. **Do NOT click "Add for Review"** — MAS-02 is upload-only.

### Anti-Patterns to Avoid

- **Validating the sandbox with `swift build` / `make_app.sh` ad-hoc signing:** ad-hoc (`codesign --sign -`) builds do not carry the MAS provisioning context; sandbox behavior must be measured on the Xcode-signed build. A quick dev-signed sandbox smoke is fine for iteration, but the recorded verdict must come from a real Apple-Development-or-better signed build.
- **Interpreting app-side error codes without the log stream open:** a bind failure can be EADDRINUSE (port 48 — another VinylPod instance running!), firewall, or a denial. Only the sandbox violation log disambiguates.
- **Uploading with the installed Xcode 27 beta:** an "Unsupported Xcode or SDK Version" rejection would read as a pipeline failure. Use release 26.x for the archive/upload leg.
- **Skipping `codesign -d --entitlements :-` verification:** if the entitlements file wasn't actually applied (wrong target, stale build), variant A behaves like variant D and you record a catastrophically wrong NO-GO.
- **Submitting for review:** upload only. Review submission is Phase 6 with the real app.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| WebSocket framing | Custom TCP framing / third-party WS lib | `NWProtocolWebSocket` (as production already does) | Zero-dep principle; identical to the code path being validated |
| Inbound test client | Browser extension harness | 30-line `swift wsclient.swift` with `URLSessionWebSocketTask` run under CLT | No browser needed to prove cross-process inbound connect |
| Sandbox introspection | dtrace/custom instrumentation | `log stream` with sandbox predicates + Console.app | The unified log IS the authoritative denial channel |
| Cert/profile management | Manual cert requests, manual profile downloads | Xcode automatic signing (`-allowProvisioningUpdates` for CLI) | Manual signing is the #1 source of the Pitfall-3 triad mismatch |
| Upload transport | Custom ASC API upload code | Organizer / `xcodebuild destination=upload` / Transporter | Three supported paths already exist |

**Key insight:** every hand-rolled piece here would add a variable to a spike whose entire value is attributing failures to exactly one cause.

## Failure-Mode Playbook (the go/no-go decision table)

The spike's product is a trustworthy verdict. Interpret results ONLY after confirming, on the exact binary that ran: `codesign -d --entitlements :- SandboxSpike.app` shows the intended triad, and `codesign --verify --deep --strict` passes.

| Observed pattern | Meaning | Verdict class |
|------------------|---------|---------------|
| Variant A: listener `.ready`, inbound echo works, HTTPS 200, zero `Sandbox`/`sandboxd` violations | Entitlement triad sufficient | **GO — MAS-01 pass** |
| Variant C: listener `.failed`/`.waiting` + log shows `deny(1) network-bind` for the spike process | Sandbox denial signature (expected when server entitlement absent) | Calibration — proves your observation rig works |
| Variant A: bind fails, log shows `network-bind` denial, entitlements verified on binary, firewall off, reboot-persistent | Sandbox genuinely blocks an entitled loopback bind | **Potential NO-GO** — before declaring: re-test on a non-beta macOS (this host runs macOS 27 BETA — an OS-beta sandbox regression is more likely than a policy change; test on a macOS 26 machine/VM before rearchitecting) |
| Bind fails with POSIX 48 `EADDRINUSE`, no denial logged | Production VinylPod (or a prior spike run) already holds :8787 | Config — kill it, rerun |
| Bind fails/`.waiting`, no denial logged, macOS firewall on | Application Firewall interference (per Apple DTS, loopback issues are typically firewall/code-signing, not sandbox) | Config — toggle firewall, re-sign, rerun |
| HTTPS fetch fails only in variant B with `deny network-outbound` | `network.client` correctly gates outbound | Expected — record loopback sub-result |
| Outbound-loopback probe denied in B but passes in A | Answer to open question (a): outbound loopback **does** require `network.client` | Record in VERDICT.md — informs MAS-05 doc |
| Upload fails: "No suitable application records were found" | ASC app record missing / bundle-ID mismatch | Config — create/fix record |
| Upload fails: ITMS-90242 | `LSApplicationCategoryType` missing/invalid | Config — set `public.app-category.music` |
| Upload fails: "Unsupported Xcode or SDK Version" | Built with beta toolchain | Config — use release Xcode 26.x |
| Upload fails: profile/cert errors (`provisioning profile doesn't include signing certificate`, etc.) | Pitfall-3 triad mismatch | Config — let automatic signing regenerate; check Apple Distribution cert exists |
| Build stuck "Processing" >24h or processing rejection email | Server-side validation issue | Read the ITMS code in the email; almost always config |

**Only one pattern forces the native-messaging-only rearchitecture:** a reproducible, entitlement-verified, firewall-excluded, non-beta-OS-confirmed sandbox denial of the loopback bind (row 3). Everything else is signing/config and does not invalidate the Phase 3→4 plan.

## Common Pitfalls

### Pitfall 1: Beta toolchain poisons the upload verdict
**What goes wrong:** Archive built with the installed Xcode 27.0 beta (27A5209h) is rejected by ASC for beta SDK, misread as a pipeline failure.
**Why it happens:** This Mac has only CLT + Xcode-beta; `xcode-select` points at CLT.
**How to avoid:** Install release Xcode 26.x for the archive/upload leg; verify `xcodebuild -version` before archiving.
**Warning signs:** "Unsupported Xcode or SDK Version" in Organizer/ASC email. [VERIFIED: developer.apple.com/forums/thread/120616 + georgegarside.com/blog/ios/submit-apps-built-beta-xcode]

### Pitfall 2: Host OS is macOS 27 beta
**What goes wrong:** A sandbox denial on a beta OS gets recorded as a permanent NO-GO; or Xcode 26 release misbehaves on the beta OS.
**Why it happens:** `sw_vers` → ProductVersion 27.0 beta (build 26A5368g).
**How to avoid:** Building with release Xcode 26 SDK on a newer host OS is normally fine [ASSUMED]; if any anomalous sandbox result appears, cross-check on a macOS 26 release machine/VM before recording the verdict.
**Warning signs:** behavior that contradicts variant expectations only on this host.

### Pitfall 3: Entitlements not actually on the binary
**What goes wrong:** Test matrix results are garbage because the `.entitlements` edit didn't apply (wrong target, cached build).
**How to avoid:** After every rebuild: `codesign -d --entitlements :- <app>` and diff against the intended variant. Clean build folder between variants.
**Warning signs:** variant B/C/D behaving identically to A (or vice versa).

### Pitfall 4: Zero signing identities on this machine
**What goes wrong:** Nothing signs; spike stalls on day 1.
**How to avoid:** Human prerequisite first: Apple Developer Program enrollment + Xcode account sign-in (plan as a blocking checkpoint task before any build task). [VERIFIED: `security find-identity` probe]

### Pitfall 5: "It launched" ≠ verified
**What goes wrong:** App runs, UI shows, but the listener silently sits in `.waiting` or artwork silently falls back to cache — MAS-01 recorded as pass without evidence.
**How to avoid:** Success is defined as log-verified: probe PASS lines in the app's os_log AND zero sandbox violations in the `log stream` window covering the run. Persist both outputs into `spike/VERDICT.md`.

### Pitfall 6: Disk space for Xcode 26
**What goes wrong:** xip (~4 GB) + expanded Xcode (~15+ GB) exceeds the **28 GiB free** on this machine mid-expand.
**How to avoid:** Delete the xip immediately after expansion; if still tight, remove `/Applications/Xcode-beta.app` (needs user consent — checkpoint). [VERIFIED: `df -h` probe]

## Code Examples

### Observing sandbox denials (Terminal 2, start BEFORE launching the app)
```bash
# Source: cross-verified fullmetalmac.com log-predicates + n8henrie.com darwin sandbox debugging
# Primary — violation channel:
log stream --info --debug --predicate \
  '(process == "sandboxd") && (subsystem == "com.apple.sandbox.reporting") && (category == "violation")'

# Belt-and-suspenders — kernel-logged denials use sender "Sandbox":
log stream --style compact --predicate \
  'sender == "Sandbox" AND eventMessage CONTAINS "SandboxSpike"'

# Retrospective (after a run you forgot to watch):
log show --last 10m --predicate 'process == "sandboxd" AND eventMessage CONTAINS "deny"'

# App-side probe results:
log stream --predicate 'subsystem == "com.vinylpod.spike"' --level info
```
Console.app equivalent: start streaming, filter `sandboxd` (process) or `Sandbox` (sender), keep "Info/Debug messages" enabled via Action menu. A **silent bind failure** (listener `.waiting`/`.failed`, nothing in these streams) points at firewall/port-in-use/signing — a **denial** always produces a `deny … network-bind` / `network-outbound` line naming the process.

### Inbound test client (unsandboxed, CLT-runnable — `spike/wsclient.swift`)
```swift
// Run: swift spike/wsclient.swift   (works under existing CLT; no Xcode needed)
import Foundation
let task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:8787")!)
task.resume()
task.send(.string("ping-from-outside")) { err in
    if let err { print("SEND FAIL:", err); exit(1) }
    task.receive { result in
        print("ECHO:", result)      // any reply == INBOUND PASS
        exit(0)
    }
}
RunLoop.main.run(until: .now + 10)
print("TIMEOUT — no echo"); exit(2)
```

### Signing verification (before interpreting ANY result)
```bash
codesign -d --entitlements :- /path/to/SandboxSpike.app     # must show the intended variant triad
codesign --verify --deep --strict --verbose=2 /path/to/SandboxSpike.app
spctl -a -vv /path/to/SandboxSpike.app                       # informational for MAS builds
security find-identity -v -p codesigning                     # expect Apple Development + Apple Distribution after account setup
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `altool` upload/notarization | Organizer / `xcodebuild destination=upload` / Transporter; `notarytool` (Dev-ID only, NOT MAS) | altool rejected since 2023-11 (TN3147) | Never script `altool` |
| `method: app-store` in ExportOptions | `method: app-store-connect` | Xcode 15.3+ deprecation | Old name warns/deprecated; use new |
| `swift package generate-xcodeproj` | Thin `.xcodeproj` + local package (Phase 3 concern) | Removed ~Swift 5.9 | Spike uses a plain Xcode app project, no SPM involvement at all |
| Xcode betas uploadable to ASC | Release/RC required for submission; uploads may bounce | ongoing policy | Release Xcode 26.x for MAS-02 |
| Pre-macOS-15 free local networking | Local Network privacy (macOS 15+) — loopback exempt | macOS 15 Sequoia | No TCC prompt expected for 127.0.0.1; a prompt = spike bug |

**Deprecated/outdated:**
- `altool`: dead for upload/notarization.
- `app-store` method string: deprecated alias.
- Chrome note for later phases: Chromium ~142+ ships Local Network Access permission gating page/extension → `127.0.0.1` connections — re-verify the Chrome extension's loopback connect UX in Phase 4/6 [ASSUMED from Chrome dev blog; out of this phase's scope].

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Outbound loopback requires `network.client` under sandbox | Test matrix hypothesis (B) | None — matrix answers it either way; that's the point |
| A2 | Release Xcode 26.x runs correctly on this macOS 27 beta host | Toolchain | Spike must move to a macOS 26 machine/VM; add fallback note in plan |
| A3 | App icon required for macOS ASC upload validation | Spike settings §3 | Organizer "Validate App" catches it; 15-min fix |
| A4 | ASC accepts upload with only name/bundle-ID/SKU (no full metadata) for a build upload | Upload path | Add minimal metadata at upload time; does not invalidate pipeline |
| A5 | Xcode 26.x is still the current release major (not superseded in a way that changes upload policy) by execution date | Toolchain | Check xcodereleases.com at execution; use latest release major that ships a release macOS SDK |
| A6 | An ASC app record that has never been submitted for review can be deleted (if throwaway bundle ID were used) | Alternatives | Moot if real bundle ID used (recommended) |
| A7 | Uploaded spike build can be expired/ignored in ASC without affecting the future real submission (build numbers must simply increase) | Upload path | Real app starts at a higher build number — trivial |

## Open Questions

1. **Does outbound loopback need `network.client`?** (carried from project research)
   - What we know: sandbox logs show `deny network-outbound 127.0.0.1:PORT` in profile-land; no loopback carve-out documented.
   - What's unclear: current-macOS behavior for an entitled app minus `client`.
   - Recommendation: variant B of the test matrix answers it; record in VERDICT.md and feed MAS-05.
2. **Safari `ws://localhost` behavior** (note-only for later phases)
   - Resolved enough: Safari still blocks insecure `ws://` from extension/HTTPS contexts (macOS 15 tightened WKWebView similarly); native messaging remains the Safari path. [VERIFIED: developer.apple.com/forums/thread/657900 + discussions.apple.com 2025 threads] No spike work needed — do NOT spend spike time here.
3. **Will ASC processing accept an LSUIElement accessory app with near-empty UI as an uploaded build?**
   - What we know: upload validation checks structure (plist keys, signing, icons), not app quality; review (which judges quality) is not part of MAS-02.
   - Recommendation: proceed; if a processing rejection cites something unexpected, it's config-class per the playbook.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 26.x release | MAS-01 signed build + MAS-02 upload | ✗ | — (only Xcode-beta 27.0 27A5209h + CLT; `xcode-select` → CLT) | Download from developer.apple.com/download (~4 GB xip); no other fallback |
| Codesigning identities (Apple Development/Distribution) | Both requirements | ✗ | 0 valid identities | Human: enroll in Apple Developer Program + sign into Xcode — **blocking checkpoint** |
| Apple Developer Program membership | Certs + ASC | unknown (no identities present suggests not set up on this machine) | — | Human action; $99/yr; enrollment can take 24–48h — start first |
| ASC app record | MAS-02 | ✗ (to be created) | — | Create during phase (needs Admin/App Manager role) |
| Disk space | Xcode 26 install | ⚠ 28 GiB free | — | Delete xip post-expand; remove Xcode-beta.app with user consent |
| macOS host | Runtime for sandbox test | ✓ but **beta** (27.0, 26A5368g) | — | Cross-check anomalies on macOS 26 release machine/VM |
| `log` CLI / Console.app | MAS-01 verification | ✓ | built-in | — |
| CLT `swift` (test client) | Inbound probe | ✓ | /Library/Developer/CommandLineTools | — |
| Internet + Apple ID | Downloads, ASC | ✓ (assumed) | — | — |

**Missing dependencies with no fallback:**
- Apple Developer Program membership + signing identities (human enrollment — plan as the FIRST task, since approval latency can exceed the 1-day spike budget)
- Release Xcode 26.x (download ~4 GB + `-runFirstLaunch`)

**Missing dependencies with fallback:**
- Disk headroom (delete xip / Xcode-beta.app)

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | none (observational spike — unified log + ASC server-side validation are the oracles) |
| Config file | none — see `spike/watch-sandbox.sh` + `spike/wsclient.swift` |
| Quick run command | `swift spike/wsclient.swift` (after launching the app with `spike/watch-sandbox.sh` running) |
| Full suite command | run all 4 entitlement variants + capture logs into `spike/VERDICT.md` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MAS-01 | Bind + inbound echo + HTTPS fetch under sandbox, zero denials | scripted-manual (log-verified) | `spike/watch-sandbox.sh` + `swift spike/wsclient.swift`; PASS lines via `log stream --predicate 'subsystem == "com.vinylpod.spike"'` | ❌ Wave 0 (spike scripts are the deliverable) |
| MAS-02 | ASC upload accepted, build appears post-processing | manual-only — **justification:** the oracle is Apple's server-side pipeline; not automatable in-repo | Organizer upload; confirm build visible in ASC / processing email | manual |

### Sampling Rate
- **Per task commit:** re-run variant A probes + log check (`wsclient.swift` echo + zero-denial window)
- **Per wave merge:** n/a (2 sequential plans)
- **Phase gate:** `spike/VERDICT.md` records: 4-variant matrix results, entitlement dumps (`codesign -d --entitlements`), upload evidence (ASC build screenshot/ID), go/no-go — before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `spike/watch-sandbox.sh` — sandbox-denial observation wrapper (MAS-01)
- [ ] `spike/wsclient.swift` — inbound WS probe (MAS-01)
- [ ] `spike/VERDICT.md` — go/no-go record template (success criterion 4)
- Framework install: none

Note: the existing SPM test suite (Phase 1) is untouched by this phase — the spike lives entirely in `spike/` and does not run `swift test`.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no (throwaway echo server; bridge auth is SEC-01, Phase 4) | — |
| V3 Session Management | no | — |
| V4 Access Control | yes (network exposure) | Pin bind to `127.0.0.1` via `requiredLocalEndpoint` — never `0.0.0.0`; verify with `lsof -iTCP:8787 -sTCP:LISTEN` showing `127.0.0.1:8787` |
| V5 Input Validation | minimal | Echo server caps frame size (`maximumMessageSize = 256*1024`, same as production) — copy the cap so the spike can't be a local DoS toy |
| V6 Cryptography | no custom crypto | HTTPS via URLSession/ATS defaults; no hand-rolled TLS |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Accidental LAN exposure of the spike listener | Information Disclosure | `requiredLocalEndpoint` loopback pin + `lsof` check in verification |
| Any local process connecting to :8787 | Spoofing | Accepted for the spike (documented residual gap — closed by SEC-01 in Phase 4); spike echoes non-sensitive data only |
| Leaking signing assets | Info Disclosure | Certs/profiles stay in Keychain/Xcode; never commit `.p12`/API keys; ASC API key (if used for CLI) stored outside repo |

## Sources

### Primary (HIGH confidence)
- Codebase: `Sources/VinylPod/Bridge/BrowserBridge.swift` — production NWListener bind pattern (read this session)
- Machine probes (this session): `xcode-select -p`, Xcode-beta version 27.0 (27A5209h), `sw_vers` 27.0 beta, `security find-identity` → 0 identities, `df -h` → 28 GiB free
- Project research: `.planning/research/STACK.md`, `ARCHITECTURE.md`, `PITFALLS.md` (Apple-doc-grounded; carried forward, not re-litigated)
- developer.apple.com — `com.apple.security.network.client` / `network.server` entitlement docs; Configuring the macOS App Sandbox

### Secondary (MEDIUM confidence — web, cross-checked)
- developer.apple.com/forums/thread/744961 — Quinn (DTS): URLSession respects `network.client`; out-of-process Apple frameworks may not (fetched this session)
- developer.apple.com/forums/thread/120616 + georgegarside.com — beta Xcode upload rejection ("Unsupported Xcode or SDK Version"); RC/release required for submission
- flutter/flutter#149369 — `app-store` → `app-store-connect` method deprecation
- developer.apple.com/forums/thread/72023 — "No suitable application records were found" ⇒ ASC app record prerequisite
- developer.apple.com/forums/thread/737134 + Apple archive "Submitting to the Mac App Store" — ITMS-90242 / `LSApplicationCategoryType`
- fullmetalmac.com + n8henrie.com (2025-12) — `log stream` sandbox-violation predicates
- developer.apple.com/forums/thread/663858 (Local Network Privacy FAQ) + WICG local-network-access explainer — loopback exempt from Local Network prompts
- developer.apple.com/forums/thread/657900 + discussions.apple.com (2025) — Safari blocks `ws://localhost`; native messaging path unchanged
- xcodereleases.com / Xcode 26 release notes — Xcode 26.1.1+ as current release line (re-verify latest 26.x at execution)

### Tertiary (LOW confidence, marked)
- Chrome Local Network Access permission affecting extension → loopback (Chrome dev blog) — later-phase note only

## Metadata

**Confidence breakdown:**
- Sandbox/entitlement behavior: MEDIUM-HIGH — Apple docs + forum evidence; the spike's matrix is itself the HIGH-confidence verifier
- Spike shell construction: HIGH — standard Xcode template + settings verified against production code patterns
- MAS upload pipeline: MEDIUM — path names verified; ASC server-side behavior is policy/version-sensitive; playbook classifies every known rejection as config-class
- Environment: HIGH — directly probed this session (beta Xcode/OS, zero identities, disk)

**Research date:** 2026-07-03
**Valid until:** 2026-08-03 (30 days) — EXCEPT: re-check latest Xcode 26.x release version and ASC "what's new" upload requirements at execution time
