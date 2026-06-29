/*
 * sites/apple-music.js — VinylPod content script for music.apple.com (ISOLATED world).
 *
 * Scrapes Apple Music web's web-chrome playback component tree (this script
 * CANNOT read the page's navigator.mediaSession). Defines an adapter and hands
 * it to VinylPodRun() from cs-common.js, which owns polling, diffing, reporting
 * and control.
 *
 * Manifest V3 compliant: read-only DOM scraping + real button clicks only.
 * No eval, no new Function, no remote code, no innerHTML writes.
 *
 * ----------------------------------------------------------------------------
 * Selectors used (Apple Music web uses an amp-/web-chrome component tree;
 * these may need updating as the site changes; each has a fallback):
 *   title        : .web-chrome-playback-lcd__song-name-scrubber
 *                  fallback: .web-chrome-playback-lcd__song-name
 *   artist       : .web-chrome-playback-lcd__sub-copy-scrubber
 *                  fallback: .web-chrome-playback-lcd__sub-copy a
 *   artwork      : .web-chrome-playback-lcd artwork-component img
 *                  fallback: .web-chrome-playback-lcd img  (-> .src / .currentSrc)
 *   current time : .web-chrome-playback-lcd__time--current
 *   duration     : .web-chrome-playback-lcd__time--duration
 *                  (if text starts with "-", it's remaining => duration = current + |remaining|)
 *   play/pause   : .web-chrome-playback-controls__playback-btn (aria-label "Pause" => playing)
 *                  fallback: button[aria-label="Pause"] exists
 *   next         : .web-chrome-playback-controls__next  | button[aria-label*="Next"]
 *   prev         : .web-chrome-playback-controls__previous | button[aria-label*="Previous"]
 *   seek bar     : input.web-chrome-playback-lcd__scrubber
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
  // anything unparseable. Strips a leading "-" (caller handles sign meaning).
  function parseTime(str) {
    if (!str) return 0;
    var s = String(str).trim();
    if (!s) return 0;
    if (s.charAt(0) === "-") s = s.slice(1);
    var parts = s.split(":");
    var total = 0;
    for (var i = 0; i < parts.length; i++) {
      var n = parseInt(parts[i], 10);
      if (!isFinite(n)) return 0;
      total = total * 60 + n;
    }
    return total;
  }

  function readState() {
    try {
      // Title
      var titleEl =
        q(".web-chrome-playback-lcd__song-name-scrubber") ||
        q(".web-chrome-playback-lcd__song-name");
      var title = txt(titleEl);
      if (!title) return null;

      // Artist
      var artistEl =
        q(".web-chrome-playback-lcd__sub-copy-scrubber") ||
        q(".web-chrome-playback-lcd__sub-copy a") ||
        q(".web-chrome-playback-lcd__sub-copy");
      var artist = txt(artistEl);

      // Album — Apple's compact LCD bundles "Artist — Album" in sub-copy and
      // doesn't reliably expose album separately; leave blank.
      var album = "";

      // Artwork (Apple uses srcset; prefer currentSrc, fall back to src)
      var imgEl =
        q(".web-chrome-playback-lcd artwork-component img") ||
        q(".web-chrome-playback-lcd img");
      var artwork = "";
      if (imgEl) artwork = imgEl.currentSrc || imgEl.src || "";
      // Quality: Apple/mzstatic art URLs carry a WxH segment (the LCD thumb is
      // ~100px). Rewrite it — and the {w}x{h} template form — to 1000px.
      if (artwork) {
        artwork = artwork
          .replace(/\{w\}x\{h\}/i, "1000x1000")
          .replace(/\/\d+x\d+((?:bb|cc|sr|fn|bf|[a-z]{1,2})?)\.(jpe?g|png|webp)/i,
                   "/1000x1000$1.$2");
      }

      // Times
      var currentTime = parseTime(
        txt(q(".web-chrome-playback-lcd__time--current"))
      );

      var durEl = q(".web-chrome-playback-lcd__time--duration");
      var durRaw = txt(durEl);
      var duration;
      if (durRaw && durRaw.charAt(0) === "-") {
        // Remaining time: total = current + |remaining|
        duration = currentTime + parseTime(durRaw);
      } else {
        duration = parseTime(durRaw);
      }

      // isPlaying — play/pause button labelled "Pause" while playing.
      var ppBtn = q(".web-chrome-playback-controls__playback-btn");
      var label = ppBtn ? (ppBtn.getAttribute("aria-label") || "") : "";
      var isPlaying = /pause/i.test(label);
      if (!isPlaying && q('button[aria-label="Pause"]')) isPlaying = true;

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
  function clickFirst(selectors) {
    for (var i = 0; i < selectors.length; i++) {
      var el = q(selectors[i]);
      if (el && typeof el.click === "function") {
        el.click();
        return;
      }
    }
  }

  function seek(seconds) {
    try {
      var range = q("input.web-chrome-playback-lcd__scrubber");
      if (!range) return; // no-op if absent
      var secs = Number(seconds);
      if (!isFinite(secs) || secs < 0) return;

      var min = parseFloat(range.min);
      var max = parseFloat(range.max);
      if (!isFinite(min)) min = 0;
      if (!isFinite(max)) max = 0;

      var value;
      if (max > 0 && max <= 1.0001) {
        // Normalized 0..1 scrubber: convert seconds -> fraction of duration.
        var durRaw = txt(q(".web-chrome-playback-lcd__time--duration"));
        var curr = parseTime(txt(q(".web-chrome-playback-lcd__time--current")));
        var dur =
          durRaw && durRaw.charAt(0) === "-"
            ? curr + parseTime(durRaw)
            : parseTime(durRaw);
        value = dur > 0 ? Math.min(1, secs / dur) : 0;
      } else if (max > 0) {
        value = Math.min(max, Math.max(min, secs));
      } else {
        value = secs;
      }

      var proto = Object.getPrototypeOf(range);
      var desc = proto && Object.getOwnPropertyDescriptor(proto, "value");
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
    source: "appleMusic",
    readState: readState,
    controls: {
      playpause: function () {
        clickFirst([".web-chrome-playback-controls__playback-btn"]);
      },
      next: function () {
        clickFirst([
          ".web-chrome-playback-controls__next",
          'button[aria-label*="Next"]'
        ]);
      },
      prev: function () {
        clickFirst([
          ".web-chrome-playback-controls__previous",
          'button[aria-label*="Previous"]'
        ]);
      },
      seek: seek
    }
  };

  if (typeof window.VinylPodRun === "function") {
    window.VinylPodRun(adapter);
  }
})();
