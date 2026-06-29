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
  return payload;
}

// ---- Inbound messages from content scripts / consumers ---------------------
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || typeof msg.type !== "string") return;

  switch (msg.type) {
    case "vinylpod:nowplaying": {
      const tabId = sender.tab && sender.tab.id;
      if (tabId != null) {
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

// ---- Native-app WebSocket bridge (best effort, auto-reconnect) -------------
let ws = null;
let wsRetry = 0;
let wsTimer = null;

function wsConnect() {
  if (ws && (ws.readyState === 0 || ws.readyState === 1)) return;
  try {
    ws = new WebSocket(WS_URL);
  } catch (e) {
    scheduleReconnect();
    return;
  }
  ws.onopen = () => {
    wsRetry = 0;
    // Send the current state immediately on connect.
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
  ws.onclose = () => scheduleReconnect();
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
  // Exponential backoff capped at 30s; the native app may not be running.
  const delay = Math.min(30000, 1000 * Math.pow(2, Math.min(wsRetry++, 5)));
  wsTimer = setTimeout(() => { wsTimer = null; wsConnect(); }, delay);
}

// Kick off the bridge. Harmless if nothing is listening on the port.
wsConnect();
