/*
 * sites/youtube.js — VinylPod adapter for www.youtube.com (NOT music.youtube.com).
 *
 * Runs in the ISOLATED world. Reads the page DOM + the real <video> element for
 * exact time/state, and reports through the shared VinylPodRun runner in
 * cs-common.js. Manifest V3 safe: read-only DOM scraping + media-element control
 * and real-button clicks only. No eval, no innerHTML, no remote code.
 *
 * Source: "youtube". Only reports when a watch <video> with duration>0 is active.
 */
(function () {
  "use strict";

  // ---- tiny null-safe DOM helpers ----------------------------------------
  // querySelector that never throws on a bad/empty selector and tolerates a
  // missing document.
  function qs(sel) {
    try {
      return document.querySelector(sel);
    } catch (e) {
      return null;
    }
  }
  // Trimmed text content of the first match, or "" if absent.
  function text(sel) {
    const el = qs(sel);
    return el && el.textContent ? el.textContent.trim() : "";
  }
  // Safe click: only clicks if the element exists and exposes .click().
  function click(sel) {
    const el = qs(sel);
    if (el && typeof el.click === "function") el.click();
  }
  // The single <video> element YouTube uses for the current watch page.
  function videoEl() {
    return qs("video");
  }

  // ---- metadata parse helpers --------------------------------------------
  // Title: primary watch-metadata heading, then <meta name="title">, then the
  // document title with the trailing " - YouTube" suffix stripped.
  function parseTitle() {
    let t = text("ytd-watch-metadata #title h1 yt-formatted-string");
    if (t) return t;

    const meta = qs('meta[name="title"]');
    if (meta && meta.content) {
      t = String(meta.content).trim();
      if (t) return t;
    }

    t = (document.title || "").trim();
    // YouTube appends " - YouTube" to the tab title.
    if (t.endsWith(" - YouTube")) t = t.slice(0, -" - YouTube".length).trim();
    return t;
  }

  // Artist == channel/owner name. Several DOM shapes across YT versions.
  function parseArtist() {
    return (
      text("ytd-watch-metadata #owner #channel-name a") ||
      text("#owner-name a") ||
      text("ytd-channel-name a") ||
      ""
    );
  }

  // Artwork: prefer the page's og:image (the official high-res thumbnail, often
  // maxres) for a sharp cover; fall back to the guaranteed hqdefault built from
  // the ?v= id. (We avoid blindly using maxresdefault.jpg because it 404s for
  // videos without an HD thumbnail, which would leave the art blank.)
  function parseArtwork() {
    try {
      const og = document.querySelector('meta[property="og:image"]');
      if (og && og.content) return og.content;
      const id = new URLSearchParams(location.search).get("v");
      return id ? "https://i.ytimg.com/vi/" + id + "/hqdefault.jpg" : "";
    } catch (e) {
      return "";
    }
  }

  // ---- adapter ------------------------------------------------------------
  const adapter = {
    source: "youtube",

    readState: function () {
      const v = videoEl();
      // Require an active watch video with a real duration; otherwise the page
      // is a feed/search/etc. and there's nothing to report.
      const duration = v && Number.isFinite(v.duration) ? v.duration : 0;
      if (!v || !(duration > 0)) return null;

      const title = parseTitle();
      if (!title) return null; // cs-common also treats empty title as "gone".

      return {
        title: title,
        artist: parseArtist(),
        album: "", // N/A for YouTube
        artwork: parseArtwork(),
        isPlaying: !v.paused,
        currentTime: Number.isFinite(v.currentTime) ? v.currentTime : 0,
        duration: duration
      };
    },

    controls: {
      // Toggle the media element directly; fall back to the player UI button.
      playpause: function () {
        const v = videoEl();
        if (v) {
          if (v.paused) {
            const p = v.play();
            if (p && typeof p.catch === "function") p.catch(function () {});
          } else {
            v.pause();
          }
          return;
        }
        click(".ytp-play-button");
      },
      // No media API for "next"; click the real player button.
      next: function () {
        click(".ytp-next-button");
      },
      // Prefer the player's prev button; if absent, restart current video.
      prev: function () {
        const btn = qs(".ytp-prev-button");
        if (btn && typeof btn.click === "function") {
          btn.click();
          return;
        }
        const v = videoEl();
        if (v) v.currentTime = 0;
      },
      // Seek by setting the media element clock (seconds).
      seek: function (seconds) {
        const v = videoEl();
        const s = Number(seconds);
        if (v && Number.isFinite(s)) v.currentTime = s;
      }
    }
  };

  if (typeof window.VinylPodRun === "function") {
    window.VinylPodRun(adapter);
  }
})();
