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
    // Spotify: size is encoded in the image id (4851=64px, 1e02=300px) -> b273=640px.
    if (url.indexOf("i.scdn.co") !== -1) {
      return url.replace(/ab67616d[0-9a-f]{8}/, "ab67616d0000b273");
    }
    // Apple Music / mzstatic: rewrite the WxH segment (and {w}x{h} template) -> 1000px.
    if (url.indexOf("mzstatic.com") !== -1) {
      return url
        .replace(/\{w\}x\{h\}/i, "1000x1000")
        .replace(/\/\d+x\d+((?:bb|cc|sr|fn|bf|[a-z]{1,2})?)\.(jpe?g|png|webp)/i,
                 "/1000x1000$1.$2");
    }
    // Google image CDN (YouTube Music, etc.): "=wW-hH" / "=sN" -> 544px.
    if (url.indexOf("googleusercontent.com") !== -1 || url.indexOf("ggpht.com") !== -1) {
      return url.replace(/=w\d+-h\d+/, "=w544-h544").replace(/=s\d+/, "=s544");
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
let wsRetry = 0;
let wsTimer = null;

function hasDeliverableTrack() {
  for (const rec of tabState.values()) if (rec && rec.payload) return true;
  return false;
}

// Connect only if we have data AND aren't already connected/connecting/scheduled.
function wsEnsure() {
  if (ws && (ws.readyState === 0 || ws.readyState === 1)) return;
  if (wsTimer) return;
  if (!hasDeliverableTrack()) return;
  wsConnect();
}

function wsConnect() {
  try {
    ws = new WebSocket(WS_URL);
  } catch (e) {
    ws = null;
    scheduleReconnect();
    return;
  }
  ws.onopen = () => {
    wsRetry = 0;
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
  ws.onclose = () => { ws = null; scheduleReconnect(); };
  ws.onerror = () => { try { ws.close(); } catch (_) {} };
}

function wsSend(obj) {
  if (ws && ws.readyState === 1) {
    try { ws.send(JSON.stringify(obj)); } catch (_) {}
  }
}

function scheduleReconnect() {
  ws = null;
  if (wsTimer) return;
  // Stop retrying when there's nothing to deliver — this is what makes the
  // console go quiet once playback stops or the tab closes.
  if (!hasDeliverableTrack()) { wsRetry = 0; return; }
  // Slow backoff: 5s, 10s, 20s, 40s, capped 60s.
  const delay = Math.min(60000, 5000 * Math.pow(2, Math.min(wsRetry++, 4)));
  wsTimer = setTimeout(() => { wsTimer = null; wsEnsure(); }, delay);
}
