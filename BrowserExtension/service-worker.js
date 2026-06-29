/*
 * service-worker.js — VinylPod Connect background (Manifest V3 service worker).
 *
 * Responsibilities:
 *   1. Aggregate now-playing reports from all content scripts (one record/tab).
 *   2. Expose the current track to any consumer (chrome.storage.session +
 *      chrome.runtime "vinylpod:get").
 *   3. Relay control commands to the active now-playing tab.
 *   4. Best-effort push to the native macOS app over a localhost WebSocket.
 *
 * MV3 compliant: this is an event service worker (not a background page), uses
 * no eval / no remote code, and tolerates being terminated and restarted.
 */
"use strict";

const WS_URL = "ws://127.0.0.1:8787"; // native VinylPod app's local bridge (optional)

// ---- State (best-effort; service workers can be torn down at any time) ------
// Persist the latest aggregate in chrome.storage.session so a restarted worker
// (or any consumer) can recover it. Per-tab live records are kept in memory.
const tabState = new Map(); // tabId -> { payload, ts }
let activeTabId = null;     // the tab whose track we currently surface

// ---- Aggregation -----------------------------------------------------------
function recomputeActive() {
  // The active track = the most-recently-updated tab that is actually playing,
  // falling back to the most-recently-updated tab overall.
  let bestPlaying = null, bestAny = null;
  for (const [tabId, rec] of tabState) {
    if (!bestAny || rec.ts > bestAny.ts) bestAny = { tabId, ...rec };
    if (rec.payload && rec.payload.isPlaying) {
      if (!bestPlaying || rec.ts > bestPlaying.ts) bestPlaying = { tabId, ...rec };
    }
  }
  const winner = bestPlaying || bestAny;
  activeTabId = winner ? winner.tabId : null;
  return winner ? winner.payload : null;
}

function publish() {
  const payload = recomputeActive();
  try {
    chrome.storage.session.set({ nowPlaying: payload || null });
  } catch (e) { /* storage.session may be unavailable in some channels */ }
  wsSend({ type: "nowplaying", payload: payload || null });
  // Lazily bring up the native-app bridge only when there's something to deliver.
  wsEnsure();
  return payload;
}

// ---- Artwork quality: upgrade CDN thumbnail URLs to high-res variants -------
// A single chokepoint so EVERY source benefits (named-site scrapers AND the
// universal MediaSession path, which often yields a small cover). These CDNs
// support lossless on-the-fly resizing via their URL, so the app downloads a
// crisp image at no extra payload cost. Unknown hosts pass through untouched.
function boostArtworkURL(url) {
  if (!url || typeof url !== "string") return url;
  try {
    // Spotify: size encoded in the image id -> b273 = 640px (the CDN's max).
    if (url.indexOf("i.scdn.co") !== -1) {
      return url.replace(/ab67616d[0-9a-f]{8}/, "ab67616d0000b273");
    }
    // Apple Music / mzstatic: rewrite the WxH segment (and {w}x{h} template) -> 1200px.
    if (url.indexOf("mzstatic.com") !== -1) {
      return url
        .replace(/\{w\}x\{h\}/i, "1200x1200")
        .replace(/\/\d+x\d+((?:bb|cc|sr|fn|bf|[a-z]{1,2})?)\.(jpe?g|png|webp)/i,
                 "/1200x1200$1.$2");
    }
    // Google image CDN (YouTube Music, etc.): "=wW-hH" / "=sN" -> 1200px.
    if (url.indexOf("googleusercontent.com") !== -1 || url.indexOf("ggpht.com") !== -1) {
      return url.replace(/=w\d+-h\d+/, "=w1200-h1200").replace(/=s\d+/, "=s1200");
    }
    // YouTube thumbnails (i.ytimg.com): bump low variants to sddefault (640×480,
    // always present — maxresdefault 404s on non-HD videos, so don't risk it).
    if (url.indexOf("ytimg.com") !== -1) {
      return url.replace(/\/(?:hq|mq|sd)?default\.jpg/, "/sddefault.jpg");
    }
  } catch (e) { /* fall through to original */ }
  return url;
}

// ---- Inbound messages from content scripts / consumers ---------------------
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || typeof msg.type !== "string") return;

  switch (msg.type) {
    case "vinylpod:nowplaying": {
      const tabId = sender.tab && sender.tab.id;
      if (tabId != null) {
        if (msg.payload) msg.payload.artwork = boostArtworkURL(msg.payload.artwork);
        tabState.set(tabId, { payload: msg.payload, ts: Date.now() });
        publish();
      }
      break;
    }
    case "vinylpod:gone": {
      const tabId = sender.tab && sender.tab.id;
      if (tabId != null) { tabState.delete(tabId); publish(); }
      break;
    }
    case "vinylpod:get": {
      sendResponse({ payload: recomputeActive() });
      return true; // async response
    }
    case "vinylpod:control": {
      // A consumer (not a content script) asked us to control playback.
      dispatchControl(msg.action, msg.value).then((ok) => sendResponse({ ok }));
      return true; // async response
    }
    default:
      break;
  }
});

// ---- Control relay: SW -> active tab's content script ----------------------
async function dispatchControl(action, value) {
  if (activeTabId == null) recomputeActive();
  if (activeTabId == null) return false;
  try {
    const res = await chrome.tabs.sendMessage(activeTabId, {
      type: "vinylpod:control", action, value
    });
    return !!(res && res.ok);
  } catch (e) {
    return false;
  }
}

// ---- Tab cleanup -----------------------------------------------------------
chrome.tabs.onRemoved.addListener((tabId) => {
  if (tabState.delete(tabId)) publish();
});

// ---- Inject into ALREADY-OPEN tabs on install/update -----------------------
// Declarative content_scripts only auto-inject on navigation, so any music tab
// that was already open when the extension loads captures nothing until it's
// reloaded. On install we inject the right scripts into existing tabs so it
// "just works" without the user reloading anything. Mirrors manifest mapping.
const NAMED_SITES = [
  { host: "open.spotify.com",  js: ["cs-common.js", "sites/spotify.js"] },
  { host: "music.apple.com",   js: ["cs-common.js", "sites/apple-music.js"] },
  { host: "music.youtube.com", js: ["cs-common.js", "sites/youtube-music.js"] },
  { host: "www.youtube.com",   js: ["cs-common.js", "sites/youtube.js"] },
];

async function injectOpenTabs() {
  let tabs = [];
  try { tabs = await chrome.tabs.query({ url: ["http://*/*", "https://*/*"] }); }
  catch (_) { return; }
  for (const tab of tabs) {
    if (tab.id == null || !tab.url) continue;
    let host = "";
    try { host = new URL(tab.url).hostname; } catch (_) { continue; }
    const named = NAMED_SITES.find((s) => s.host === host);
    try {
      if (named) {
        await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: named.js });
      } else {
        // Universal capture: ISOLATED relay + MAIN-world MediaSession reader.
        await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["universal-relay.js"] });
        await chrome.scripting.executeScript({ target: { tabId: tab.id }, world: "MAIN", files: ["mediasession-main.js"] });
      }
    } catch (_) { /* chrome://, web store, or other restricted tab — skip */ }
  }
}

chrome.runtime.onInstalled.addListener(injectOpenTabs);

// ---- Native-app WebSocket bridge (LAZY + quiet when the app is closed) ------
//
// The VinylPod app's bridge (ws://127.0.0.1:8787) is OPTIONAL — it only exists
// while the app is running. A browser logs an uncatchable "connection failed"
// error for every refused WebSocket attempt, so to keep the console quiet we:
//   • never connect at startup,
//   • only attempt when there's actually a now-playing track to deliver,
//   • stop retrying entirely once nothing is playing,
//   • back off slowly (5s → 60s) instead of hammering.
// Net effect: with the app closed and nothing playing, ZERO connection errors;
// while music plays with the app closed, at most an occasional line.
let ws = null;
let wsAppSeen = false;       // app accepted a connection at least once this session
let wsQuietUntil = 0;        // do not attempt before this epoch-ms (silence window)
const WS_QUIET_DOWN = 120000; // app never answered → stay quiet 2 min between probes
const WS_QUIET_DROP = 15000;  // app was up and dropped → re-probe sooner (15s)

function hasDeliverableTrack() {
  for (const rec of tabState.values()) if (rec && rec.payload) return true;
  return false;
}

// Attempt a connection ONLY when it can plausibly succeed. A refused WebSocket
// logs an UNCATCHABLE `net::ERR_CONNECTION_REFUSED` in DevTools — it cannot be
// swallowed in onerror — so the only way to stay quiet while the app is closed
// is to STOP attempting. After a refusal we go silent for a window and only
// re-probe afterwards (driven by the heartbeat / next track update). A closed
// app therefore costs ~1 line every couple of minutes, not one per cycle; an
// open app connects on the first try and logs nothing.
async function wsEnsure() {
  if (ws && (ws.readyState === 0 || ws.readyState === 1)) return; // up / connecting
  if (!hasDeliverableTrack()) return;                              // nothing to send
  // Honor the quiet window, persisted so it survives service-worker restarts.
  try {
    const r = await chrome.storage.session.get("wsQuietUntil");
    if (typeof r.wsQuietUntil === "number") wsQuietUntil = Math.max(wsQuietUntil, r.wsQuietUntil);
  } catch (_) { /* storage.session may be unavailable in some channels */ }
  if (Date.now() < wsQuietUntil) return;                           // still quiet → NO attempt, NO error
  wsConnect();
}

function wsConnect() {
  try {
    ws = new WebSocket(WS_URL);
  } catch (e) {
    onWsDown();
    return;
  }
  ws.onopen = () => {
    wsAppSeen = true;
    setQuietUntil(0);          // app is up — clear any silence window
    wsSend({ type: "nowplaying", payload: recomputeActive() });
  };
  ws.onmessage = (ev) => {
    // The native app can drive playback back through the same socket.
    let data = null;
    try { data = JSON.parse(ev.data); } catch (_) { return; }
    if (data && data.type === "vinylpod:control") {
      dispatchControl(data.action, data.value);
    }
  };
  ws.onclose = () => { onWsDown(); };
  ws.onerror = () => { try { ws.close(); } catch (_) {} }; // → onclose → onWsDown
}

function onWsDown() {
  ws = null;
  // Open a silence window so we stop re-logging refused attempts. Shorter when
  // the app was up this session (likely a transient drop), longer when it has
  // never answered (probably not running). The heartbeat re-probes afterward.
  setQuietUntil(Date.now() + (wsAppSeen ? WS_QUIET_DROP : WS_QUIET_DOWN));
}

function setQuietUntil(ts) {
  wsQuietUntil = ts;
  try { chrome.storage.session.set({ wsQuietUntil: ts }); } catch (_) {}
}

function wsSend(obj) {
  if (ws && ws.readyState === 1) {
    try { ws.send(JSON.stringify(obj)); } catch (_) {}
  }
}

// ---- Heartbeat: survive service-worker suspension (esp. Safari) -------------
// MV3 service workers get suspended when idle — Safari especially aggressively —
// silently dropping the WebSocket to the app. A periodic alarm wakes the worker
// and re-ensures the connection whenever there's still a track to deliver, so
// the bridge re-establishes itself instead of staying dead until the next
// now-playing message. No effect when nothing is playing (keeps app-closed
// state error-free).
try {
  chrome.alarms.create("vinylpod:heartbeat", { periodInMinutes: 0.5 });
  chrome.alarms.onAlarm.addListener((a) => {
    if (a.name === "vinylpod:heartbeat") wsEnsure();
  });
} catch (e) { /* chrome.alarms unavailable in this channel */ }
