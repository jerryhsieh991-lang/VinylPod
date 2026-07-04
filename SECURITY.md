# Security Policy

VinylPod is a free macOS menu-bar "now playing" app. It runs a **loopback-only**
local WebSocket bridge (`127.0.0.1:8787`) that browser extensions use to report
what's playing. This document states the security model honestly, including known
limitations that are on the hardening backlog.

## Security model

- **No secrets in the source.** Last.fm API key/secret are empty placeholders you
  supply locally; nothing sensitive is committed. Verified across full history.
- **Loopback-only.** The bridge binds `127.0.0.1` (never `0.0.0.0`) — it is not
  reachable from other machines.
- **Bridge input is treated as hostile.** Frame size cap (256 KB), connection cap
  (6), 10 s fetch timeout, title-length guard, and — importantly — `file://` and
  arbitrary schemes are rejected, and `data:` URIs are string-decoded (never
  `Data(contentsOf:)`), so local-file read via the bridge is blocked.
- **No remote network surface, no code execution surface** via the bridge.

## Known limitations (hardening backlog)

These are tracked for a dedicated security-hardening pass. They are **loopback-only**
(no remote, no RCE, no secret exposure), but they are real:

1. **The bridge is unauthenticated.** Any local process — or a malicious `http://`
   page you visit while the app runs — can connect to `127.0.0.1:8787` and inject
   `nowplaying` frames (spoofing the displayed track, and, if Last.fm is configured,
   scrobbling a fake track). Planned fix: a per-install token handshake.
2. **SSRF hardening is incomplete.** The artwork-URL host check validates the
   *literal* host string; it does not re-validate the resolved IP, HTTP redirect
   targets, or numeric/IPv6 IP encodings. Impact is *blind* SSRF (the response is
   only decoded as an image, never returned), loopback-only. Planned fix: validate
   the resolved IP against private/loopback/link-local/ULA ranges and re-check on
   every redirect.
3. **No decoded-image dimension clamp.** The 8 MB cap bounds encoded bytes, not
   decoded pixels; a decompression-bomb image could exhaust memory. Planned fix:
   reject oversized pixel dimensions before decode.

## Reporting a vulnerability

Please open a private security advisory on this repository, or contact the
maintainer directly. Do not file public issues for security reports.
