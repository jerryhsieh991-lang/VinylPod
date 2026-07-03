/*
 * cs-common.js — shared ISOLATED-world bridge runner for every site adapter.
 *
 * A site script (sites/spotify.js, etc.) defines an adapter and calls
 * VinylPodRun(adapter). This file owns the polling loop, change-diffing,
 * reporting to the service worker, and the control-message listener — so each
 * adapter stays tiny and they all behave identically.
 *
 * Adapter shape:
 *   {
 *     source: "spotify" | "appleMusic" | "youtube" | "youtubeMusic",
 *     readState(): { title, artist, album, artwork, isPlaying,
 *                    currentTime, duration } | null,   // null = nothing playing
 *     controls: {
 *       playpause(): void,
 *       next(): void,
 *       prev(): void,
 *       seek(seconds): void
 *     }
 *   }
 *
 * Manifest V3 compliant: no eval, no remote code. Runs in the isolated world,
 * so it can use chrome.runtime and read the DOM (incl. <video>/<audio> time),
 * but NOT page-context navigator.mediaSession (that's the universal MAIN path).
 */
(function () {
  "use strict";

  const POLL_MS = 1000; // keep in sync with extension_backend_features.json config

  // Hard caps on untrusted DOM-scraped strings. A malicious/broken page could
  // put arbitrarily long text into a title node; clamp BEFORE it ever crosses
  // the messaging boundary so the SW and native app never see unbounded input.
  const MAX_TEXT = 512;    // title / artist / album
  const MAX_URL = 2048;    // artwork URL
  const clampText = (s) => (s.length > MAX_TEXT ? s.slice(0, MAX_TEXT) : s);
  const clampURL = (s) => (s.length > MAX_URL ? "" : s); // drop absurd URLs entirely

  window.VinylPodRun = function VinylPodRun(adapter) {
    if (!adapter || typeof adapter.readState !== "function") return;

    let lastSerialized = null;
    let timer = null;

    // --- normalize a raw state object into the frozen payload contract -------
    function normalize(raw) {
      if (!raw) return null;
      // Clamp numeric fields to a sane, finite, non-negative range so a bogus
      // duration/time can't propagate NaN/Infinity or a huge value downstream.
      const num = (v) => {
        const n = +v;
        if (!Number.isFinite(n) || n < 0) return 0;
        return n > 1e7 ? 0 : n; // >~115 days ⇒ clearly bogus
      };
      return {
        source: adapter.source,
        title: clampText(String(raw.title || "").trim()),
        artist: clampText(String(raw.artist || "").trim()),
        album: clampText(String(raw.album || "").trim()),
        artwork: clampURL(String(raw.artwork || "")),
        isPlaying: !!raw.isPlaying,
        currentTime: num(raw.currentTime),
        duration: num(raw.duration)
      };
    }

    // Round currentTime so a steadily-advancing clock doesn't make every poll
    // look "changed" beyond ~1/sec, while still updating once per second.
    function signature(p) {
      if (!p) return "gone";
      return [
        p.source, p.title, p.artist, p.album, p.artwork,
        p.isPlaying, Math.round(p.currentTime), Math.round(p.duration)
      ].join("|");
    }

    function tick() {
      let payload = null;
      try {
        payload = normalize(adapter.readState());
      } catch (e) {
        payload = null;
      }
      // Treat empty title as nothing playing.
      if (payload && !payload.title) payload = null;

      const sig = signature(payload);
      if (sig === lastSerialized) return;
      lastSerialized = sig;

      try {
        if (payload) {
          chrome.runtime.sendMessage({ type: "vinylpod:nowplaying", payload });
        } else {
          chrome.runtime.sendMessage({ type: "vinylpod:gone" });
        }
      } catch (e) {
        // Service worker may be asleep / context invalidated; ignore.
      }
    }

    // --- control listener: SW -> here -> adapter.controls -------------------
    chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
      if (!msg || msg.type !== "vinylpod:control") return; // not ours
      const fn = adapter.controls && adapter.controls[msg.action];
      let ok = false;
      try {
        if (typeof fn === "function") { fn(msg.value); ok = true; }
      } catch (e) { ok = false; }
      // Push a fresh reading right after acting so consumers update promptly.
      setTimeout(tick, 150);
      sendResponse({ ok });
      return true; // keep the channel open for the async sendResponse
    });

    // --- lifecycle: single interval, cleared on navigation away -------------
    function start() {
      if (timer) return;
      tick();
      timer = setInterval(tick, POLL_MS);
    }
    function stop() {
      if (timer) { clearInterval(timer); timer = null; }
    }
    window.addEventListener("pagehide", stop, { once: true });
    document.addEventListener("visibilitychange", () => {
      // Slow down nothing here; just ensure we keep reporting. Kept simple.
      if (document.visibilityState === "visible") tick();
    });

    start();
  };
})();
