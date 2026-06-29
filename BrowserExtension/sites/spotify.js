/*
 * sites/spotify.js — VinylPod content script for open.spotify.com (ISOLATED world).
 *
 * Scrapes the now-playing widget DOM (this script CANNOT read the page's
 * navigator.mediaSession). Defines an adapter and hands it to VinylPodRun()
 * from cs-common.js, which owns polling, diffing, reporting and control.
 *
 * Manifest V3 compliant: read-only DOM scraping + real button clicks only.
 * No eval, no new Function, no remote code, no innerHTML writes.
 *
 * ----------------------------------------------------------------------------
 * Selectors used (Spotify ships A/B variants — these may need updating as the
 * site changes; each has a sensible fallback):
 *   widget root  : [data-testid="now-playing-widget"]
 *   title        : [data-testid="context-item-info-title"]
 *                  fallback: a[data-testid="context-item-link"] in the widget
 *   artist       : [data-testid="context-item-info-artist"]
 *                  fallback: first a[href^="/artist/"] in the widget
 *   artwork      : [data-testid="now-playing-widget"] img -> .src / .currentSrc
 *   current time : [data-testid="playback-position"]   (text "m:ss")
 *   duration     : [data-testid="playback-duration"]   (text "m:ss")
 *   play/pause   : [data-testid="control-button-playpause"] (aria-label "Pause" => playing)
 *   next         : [data-testid="control-button-skip-forward"]
 *   prev         : [data-testid="control-button-skip-back"]
 *   seek bar     : [data-testid="progress-bar"] input[type="range"]
 * ----------------------------------------------------------------------------
 */
(function () {
  "use strict";

  // --- small DOM helpers (every lookup is null-guarded) ---------------------
  function q(sel, root) {
    try {
      return (root || document).querySelector(sel);
    } catch (e) {
      return null;
    }
  }
  function txt(el) {
    return el && typeof el.textContent === "string" ? el.textContent.trim() : "";
  }

  // Parse "m:ss" / "h:mm:ss" (and bare "ss") into whole seconds. Returns 0 on
  // anything unparseable. Tolerates a leading "-" (treated as magnitude).
  function parseTime(str) {
    if (!str) return 0;
    var s = String(str).trim();
    if (!s) return 0;
    var neg = s.charAt(0) === "-";
    if (neg) s = s.slice(1);
    var parts = s.split(":");
    var total = 0;
    for (var i = 0; i < parts.length; i++) {
      var n = parseInt(parts[i], 10);
      if (!isFinite(n)) return 0;
      total = total * 60 + n;
    }
    return total;
  }

  function widget() {
    return q('[data-testid="now-playing-widget"]');
  }

  function readState() {
    try {
      var w = widget();
      if (!w) return null;

      // Title
      var titleEl =
        q('[data-testid="context-item-info-title"]', w) ||
        q('a[data-testid="context-item-link"]', w);
      var title = txt(titleEl);
      if (!title) return null; // nothing meaningful playing

      // Artist
      var artistEl =
        q('[data-testid="context-item-info-artist"]', w) ||
        q('a[href^="/artist/"]', w);
      var artist = txt(artistEl);

      // Album — Spotify's compact bar rarely exposes album; leave blank.
      var album = "";

      // Artwork
      var imgEl = q("img", w);
      var artwork = "";
      if (imgEl) artwork = imgEl.currentSrc || imgEl.src || "";
      // Quality: Spotify encodes size in the image id — the now-playing thumb is
      // ...00004851 (64px). Rewrite to ...0000b273 (640px) for a sharp cover.
      // (4851 = 64px, 1e02 = 300px, b273 = 640px.)
      if (artwork) artwork = artwork.replace(/ab67616d[0-9a-f]{8}/, "ab67616d0000b273");

      // Times (these live outside the widget root, query from document)
      var currentTime = parseTime(txt(q('[data-testid="playback-position"]')));
      var duration = parseTime(txt(q('[data-testid="playback-duration"]')));

      // isPlaying — aria-label of the play/pause button says "Pause" while playing.
      var ppBtn = q('[data-testid="control-button-playpause"]');
      var label = ppBtn ? (ppBtn.getAttribute("aria-label") || "") : "";
      var isPlaying = /pause/i.test(label);

      return {
        title: title,
        artist: artist,
        album: album,
        artwork: artwork,
        isPlaying: isPlaying,
        currentTime: currentTime,
        duration: duration
      };
    } catch (e) {
      return null; // readState must never throw
    }
  }

  // --- controls: real DOM button clicks -------------------------------------
  function click(sel) {
    var el = q(sel);
    if (el && typeof el.click === "function") el.click();
  }

  function seek(seconds) {
    try {
      var range = q('[data-testid="progress-bar"] input[type="range"]');
      if (!range) return; // no-op if absent
      var secs = Number(seconds);
      if (!isFinite(secs) || secs < 0) return;

      // Spotify's range is typically 0..duration (or 0..1). Clamp to its bounds.
      var min = parseFloat(range.min);
      var max = parseFloat(range.max);
      if (!isFinite(min)) min = 0;
      if (!isFinite(max)) max = 0;

      var value;
      if (max > 0 && max <= 1.0001) {
        // Normalized 0..1 range: convert seconds -> fraction of duration.
        var dur = parseTime(txt(q('[data-testid="playback-duration"]')));
        value = dur > 0 ? Math.min(1, secs / dur) : 0;
      } else if (max > 0) {
        value = Math.min(max, Math.max(min, secs));
      } else {
        value = secs;
      }

      // Set the value through the native setter so React's controlled input
      // notices the change, then dispatch input + change.
      var proto = Object.getPrototypeOf(range);
      var desc =
        proto &&
        Object.getOwnPropertyDescriptor(proto, "value");
      if (desc && typeof desc.set === "function") {
        desc.set.call(range, String(value));
      } else {
        range.value = String(value);
      }
      range.dispatchEvent(new Event("input", { bubbles: true }));
      range.dispatchEvent(new Event("change", { bubbles: true }));
    } catch (e) {
      // best-effort; swallow
    }
  }

  var adapter = {
    source: "spotify",
    readState: readState,
    controls: {
      playpause: function () {
        click('[data-testid="control-button-playpause"]');
      },
      next: function () {
        click('[data-testid="control-button-skip-forward"]');
      },
      prev: function () {
        click('[data-testid="control-button-skip-back"]');
      },
      seek: seek
    }
  };

  if (typeof window.VinylPodRun === "function") {
    window.VinylPodRun(adapter);
  }
})();
