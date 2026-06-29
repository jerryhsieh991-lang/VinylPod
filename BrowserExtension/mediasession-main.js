// =============================================================================
// VinylPod — Universal fallback (PART 1 of 2): MAIN-world script
// =============================================================================
// WORLD: MAIN (runs in the page's own JS context).
//   - CAN read `navigator.mediaSession.metadata` / `.playbackState` (the page
//     sets these; the ISOLATED world cannot see them).
//   - CAN reach the page's real <video>/<audio> elements for control.
//   - CANNOT use chrome.* APIs. Talks to the ISOLATED relay ONLY via
//     window.postMessage. The relay (universal-relay.js) bridges to the SW.
//
// MV3-safe: no eval / no new Function / no remote code / no innerHTML.
// Read-only inspection + media-element control only.
// =============================================================================
(function () {
  "use strict";

  // ---- de-dupe: don't install twice if injected more than once -------------
  if (window.__vinylpodMainInstalled) return;
  window.__vinylpodMainInstalled = true;

  var POLL_MS = 1000;

  var lastKey = null;        // serialized signature of the last posted payload
  var lastWasGone = false;   // whether we last posted a "gone" message
  var pollTimer = null;
  var chosenEl = null;       // media element kept for control requests

  // ---------------------------------------------------------------------------
  // Pick the "primary" media element on the page.
  //   1) Prefer one that is actively playing (not paused, currentTime > 0),
  //      choosing the longest duration among those.
  //   2) Fallback to the first element with a finite duration > 0.
  // ---------------------------------------------------------------------------
  function pickMediaElement() {
    var nodes = [];
    var v = document.getElementsByTagName("video");
    var a = document.getElementsByTagName("audio");
    var i;
    for (i = 0; i < v.length; i++) nodes.push(v[i]);
    for (i = 0; i < a.length; i++) nodes.push(a[i]);

    var bestPlaying = null;
    var firstWithDuration = null;

    for (i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var dur = (typeof el.duration === "number" && isFinite(el.duration)) ? el.duration : 0;

      if (dur > 0 && firstWithDuration === null) {
        firstWithDuration = el;
      }

      var isActive = !el.paused && (el.currentTime > 0);
      if (isActive) {
        if (bestPlaying === null) {
          bestPlaying = el;
        } else {
          var bestDur = (typeof bestPlaying.duration === "number" && isFinite(bestPlaying.duration))
            ? bestPlaying.duration : 0;
          if (dur > bestDur) bestPlaying = el;
        }
      }
    }

    return bestPlaying || firstWithDuration || null;
  }

  // ---------------------------------------------------------------------------
  // Largest artwork URL from mediaSession.metadata.artwork[].
  // "Largest" = largest pixel area parsed from the "WxH" sizes string; entries
  // without a parseable size sort last. Returns the .src, or "".
  // ---------------------------------------------------------------------------
  function pickArtwork(meta) {
    if (!meta || !meta.artwork || !meta.artwork.length) return "";
    var best = null;
    var bestArea = -1;
    for (var i = 0; i < meta.artwork.length; i++) {
      var art = meta.artwork[i];
      if (!art || !art.src) continue;
      var area = 0;
      if (art.sizes && typeof art.sizes === "string") {
        // sizes can be like "512x512" or "96x96 128x128"; take the max token.
        var tokens = art.sizes.split(/\s+/);
        for (var t = 0; t < tokens.length; t++) {
          var m = /^(\d+)x(\d+)$/i.exec(tokens[t]);
          if (m) {
            var thisArea = parseInt(m[1], 10) * parseInt(m[2], 10);
            if (thisArea > area) area = thisArea;
          }
        }
      }
      if (best === null || area > bestArea) {
        best = art.src;
        bestArea = area;
      }
    }
    return best || "";
  }

  // ---------------------------------------------------------------------------
  // Build the now-playing payload, or null when nothing is playing.
  // ---------------------------------------------------------------------------
  function buildPayload() {
    var ms = (typeof navigator !== "undefined") ? navigator.mediaSession : null;
    var meta = (ms && ms.metadata) ? ms.metadata : null;

    var title = (meta && meta.title) ? String(meta.title) : "";
    var artist = (meta && meta.artist) ? String(meta.artist) : "";
    var album = (meta && meta.album) ? String(meta.album) : "";
    var artwork = pickArtwork(meta);

    var el = pickMediaElement();
    chosenEl = el; // keep for control even if we end up reporting "gone"

    var hasTitle = title.length > 0;
    var hasPlayingEl = false;
    if (el) {
      hasPlayingEl = !el.paused && (el.currentTime > 0);
    }

    // Nothing playing: no metadata title AND no actively-playing media element.
    if (!hasTitle && !hasPlayingEl) {
      return null;
    }

    var playbackState = (ms && ms.playbackState) ? ms.playbackState : "none";
    var isPlaying;
    if (playbackState === "playing") {
      isPlaying = true;
    } else if (el) {
      isPlaying = !el.paused;
    } else {
      isPlaying = false;
    }

    var currentTime = 0;
    var duration = 0;
    if (el) {
      if (typeof el.currentTime === "number" && isFinite(el.currentTime)) {
        currentTime = el.currentTime;
      }
      if (typeof el.duration === "number" && isFinite(el.duration)) {
        duration = el.duration;
      }
    }

    return {
      title: title,
      artist: artist,
      album: album,
      artwork: artwork,
      isPlaying: isPlaying,
      currentTime: currentTime,
      duration: duration
    };
  }

  // ---------------------------------------------------------------------------
  // Diff signature: round times to whole seconds so a steadily-advancing clock
  // doesn't spam, while still updating roughly once per second.
  // ---------------------------------------------------------------------------
  function signature(p) {
    if (!p) return "GONE";
    return [
      p.title,
      p.artist,
      p.album,
      p.artwork,
      p.isPlaying ? "1" : "0",
      Math.round(p.currentTime),
      Math.round(p.duration)
    ].join("");
  }

  function postNowPlaying(payload) {
    window.postMessage({ __vinylpod: true, kind: "nowplaying", payload: payload }, "*");
  }

  function postGone() {
    window.postMessage({ __vinylpod: true, kind: "gone" }, "*");
  }

  function tick() {
    var payload = buildPayload();
    var key = signature(payload);

    if (payload === null) {
      // Only emit "gone" once per transition into the not-playing state.
      if (!lastWasGone) {
        postGone();
        lastWasGone = true;
        lastKey = "GONE";
      }
      return;
    }

    if (key !== lastKey) {
      postNowPlaying(payload);
      lastKey = key;
      lastWasGone = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Control requests coming back from the ISOLATED relay.
  //   { __vinylpod:true, kind:"control", action, value }
  // ---------------------------------------------------------------------------
  function onMessage(e) {
    if (e.source !== window) return;
    var m = e.data;
    if (!m || !m.__vinylpod || m.kind !== "control") return;

    var el = chosenEl;
    if (!el) return;

    try {
      switch (m.action) {
        case "playpause":
          if (el.paused) {
            var pr = el.play();
            if (pr && typeof pr.catch === "function") pr.catch(function () {});
          } else {
            el.pause();
          }
          break;
        case "seek":
          if (typeof m.value === "number" && isFinite(m.value)) {
            el.currentTime = m.value;
          }
          break;
        case "next":
        case "prev":
          // No-op in the universal fallback. Track skipping on an arbitrary page
          // is driven by mediaSession action handlers that the PAGE registered;
          // there is no standard API for another script to *trigger* those
          // handlers, and a generic <video>/<audio> element has no concept of a
          // playlist. Per-site adapters handle next/prev by clicking real
          // buttons; here we deliberately do nothing.
          break;
        default:
          break;
      }
    } catch (err) {
      // Swallow — control is best-effort and must never throw into the page.
    }
  }

  window.addEventListener("message", onMessage, false);

  // ---------------------------------------------------------------------------
  // Single shared interval; cleared on pagehide to avoid leaks.
  // ---------------------------------------------------------------------------
  function start() {
    if (pollTimer !== null) return;
    pollTimer = setInterval(tick, POLL_MS);
    tick(); // emit immediately on install
  }

  function stop() {
    if (pollTimer !== null) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  window.addEventListener("pagehide", stop, false);

  start();
})();
