/*
 * sites/youtube-music.js — VinylPod adapter for music.youtube.com.
 *
 * Runs in the ISOLATED world. Prefers the real <video> element for exact
 * time/state, scrapes the player bar for metadata, and controls playback via
 * the real player-bar buttons / the media element. Reports through the shared
 * VinylPodRun runner in cs-common.js. Manifest V3 safe: read-only DOM scraping
 * + media-element control and real-button clicks only. No eval / innerHTML /
 * remote code.
 *
 * Source: "youtubeMusic".
 */
(function () {
  "use strict";

  // ---- tiny null-safe DOM helpers ----------------------------------------
  function qs(sel) {
    try {
      return document.querySelector(sel);
    } catch (e) {
      return null;
    }
  }
  function text(sel) {
    const el = qs(sel);
    return el && el.textContent ? el.textContent.trim() : "";
  }
  function click(sel) {
    const el = qs(sel);
    if (el && typeof el.click === "function") el.click();
  }
  function videoEl() {
    return qs("video");
  }

  // ---- parse helpers ------------------------------------------------------
  // Title: the player-bar title element.
  function parseTitle() {
    return (
      text(".ytmusic-player-bar .title") ||
      text("ytmusic-player-bar .title.ytmusic-player-bar") ||
      ""
    );
  }

  // The byline holds "Artist • Album • Views" (segments vary). We split on the
  // bullet and use [0] as artist, [1] as album when present.
  function bylineParts() {
    const raw = text(".ytmusic-player-bar .byline");
    if (!raw) return [];
    return raw
      .split("•")
      .map(function (s) {
        return s.trim();
      })
      .filter(function (s) {
        return s.length > 0;
      });
  }
  function parseArtist() {
    const parts = bylineParts();
    return parts.length ? parts[0] : "";
  }
  function parseAlbum() {
    const parts = bylineParts();
    return parts.length > 1 ? parts[1] : "";
  }

  // Artwork: the player-bar thumbnail (~60px). Google's image CDN resizes via
  // the "=wW-hH" / "=sN" URL token, so rewrite it to 544px for a sharp cover.
  function parseArtwork() {
    const img =
      qs(".ytmusic-player-bar img.ytmusic-player-bar") ||
      qs(".ytmusic-player-bar img");
    if (!img || !img.src) return "";
    return img.src
      .replace(/=w\d+-h\d+/, "=w544-h544")
      .replace(/=s\d+/, "=s544");
  }

  // Parse "m:ss" / "h:mm:ss" into seconds; NaN-safe → 0.
  function clockToSeconds(str) {
    if (!str) return 0;
    const parts = String(str).trim().split(":");
    let secs = 0;
    for (let i = 0; i < parts.length; i++) {
      const n = parseInt(parts[i], 10);
      if (!Number.isFinite(n)) return 0;
      secs = secs * 60 + n;
    }
    return secs;
  }

  // Fallback time when no <video> is available: ".time-info" reads "m:ss / m:ss".
  function timeInfoFallback() {
    const raw = text(".ytmusic-player-bar .time-info");
    const out = { currentTime: 0, duration: 0 };
    if (!raw) return out;
    const halves = raw.split("/");
    if (halves[0]) out.currentTime = clockToSeconds(halves[0]);
    if (halves[1]) out.duration = clockToSeconds(halves[1]);
    return out;
  }

  // ---- adapter ------------------------------------------------------------
  const adapter = {
    source: "youtubeMusic",

    readState: function () {
      const title = parseTitle();
      if (!title) return null; // nothing loaded in the player bar.

      const v = videoEl();
      let currentTime = 0;
      let duration = 0;
      let isPlaying = false;

      if (v) {
        // Prefer exact values from the media element.
        currentTime = Number.isFinite(v.currentTime) ? v.currentTime : 0;
        duration = Number.isFinite(v.duration) ? v.duration : 0;
        isPlaying = !v.paused;
      }
      // If the video element gave no usable times, fall back to the text clock.
      if (!(duration > 0)) {
        const t = timeInfoFallback();
        currentTime = t.currentTime;
        duration = t.duration;
      }

      return {
        title: title,
        artist: parseArtist(),
        album: parseAlbum(),
        artwork: parseArtwork(),
        isPlaying: isPlaying,
        currentTime: currentTime,
        duration: duration
      };
    },

    controls: {
      // Click the real play/pause control; fall back to toggling the media el.
      playpause: function () {
        const btn = qs("#play-pause-button");
        if (btn && typeof btn.click === "function") {
          btn.click();
          return;
        }
        const v = videoEl();
        if (v) {
          if (v.paused) {
            const p = v.play();
            if (p && typeof p.catch === "function") p.catch(function () {});
          } else {
            v.pause();
          }
        }
      },
      next: function () {
        // Player-bar "next" button (class or tagged paper-icon-button form).
        const btn =
          qs(".next-button") || qs("tp-yt-paper-icon-button.next-button");
        if (btn && typeof btn.click === "function") btn.click();
      },
      prev: function () {
        const btn =
          qs(".previous-button") ||
          qs("tp-yt-paper-icon-button.previous-button");
        if (btn && typeof btn.click === "function") btn.click();
      },
      // Seek via the media element clock (seconds).
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
