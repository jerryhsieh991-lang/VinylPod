// =============================================================================
// VinylPod — Universal fallback (PART 2 of 2): ISOLATED-world relay
// =============================================================================
// WORLD: ISOLATED (a normal content script).
//   - HAS chrome.* APIs (chrome.runtime) but CANNOT see the page's
//     navigator.mediaSession.metadata — that lives in the MAIN world.
//   - The MAIN-world script (mediasession-main.js) reads mediaSession + the
//     media element and emits window.postMessage; this relay forwards those to
//     the service worker, and forwards SW control messages back to MAIN.
//
//   MAIN  --window.postMessage-->  ISOLATED (this)  --chrome.runtime-->  SW
//   SW  --chrome.runtime.onMessage-->  ISOLATED (this)  --window.postMessage--> MAIN
//
// MV3-safe: no eval / no new Function / no remote code / no innerHTML.
// =============================================================================
(function () {
  "use strict";

  if (window.__vinylpodRelayInstalled) return;
  window.__vinylpodRelayInstalled = true;

  // ---------------------------------------------------------------------------
  // MAIN -> SW : page postMessage events bridged to the service worker.
  // chrome.runtime.sendMessage is wrapped in try/catch because the worker may
  // be asleep or the context may have been invalidated (extension reload).
  // ---------------------------------------------------------------------------
  function safeSend(message) {
    try {
      chrome.runtime.sendMessage(message, function () {
        // Touch lastError so Chrome doesn't log "Unchecked runtime.lastError"
        // when the worker is asleep / there is no receiver.
        void chrome.runtime.lastError;
      });
    } catch (err) {
      // Context invalidated or messaging unavailable — drop silently.
    }
  }

  function onWindowMessage(e) {
    // Only trust messages from this same window object, tagged __vinylpod.
    if (e.source !== window) return;
    var m = e.data;
    if (!m || !m.__vinylpod) return;

    if (m.kind === "nowplaying") {
      // Force source:"mediaSession" — the relay owns this field per the contract.
      var payload = {};
      var src = m.payload || {};
      for (var k in src) {
        if (Object.prototype.hasOwnProperty.call(src, k)) payload[k] = src[k];
      }
      payload.source = "mediaSession";

      safeSend({ type: "vinylpod:nowplaying", payload: payload });
    } else if (m.kind === "gone") {
      safeSend({ type: "vinylpod:gone" });
    }
    // "control" messages are MAIN-bound; ignore them here.
  }

  window.addEventListener("message", onWindowMessage, false);

  // ---------------------------------------------------------------------------
  // SW -> MAIN : control messages forwarded into the page world.
  // We return true to keep the sendResponse channel open (sync response here,
  // but returning true is harmless and future-proof).
  // ---------------------------------------------------------------------------
  function onRuntimeMessage(msg, sender, sendResponse) {
    if (!msg || msg.type !== "vinylpod:control") return;

    try {
      window.postMessage({
        __vinylpod: true,
        kind: "control",
        action: msg.action,
        value: msg.value
      }, "*");
      sendResponse({ ok: true });
    } catch (err) {
      try { sendResponse({ ok: false }); } catch (e2) {}
    }
    return true;
  }

  try {
    chrome.runtime.onMessage.addListener(onRuntimeMessage);
  } catch (err) {
    // chrome.runtime unavailable — nothing to relay.
  }

  // ---------------------------------------------------------------------------
  // Inject the MAIN-world reader as a page <script>. The manifest registers
  // mediasession-main.js with world:"MAIN", but SAFARI ignores that key, so on
  // Safari the reader never runs and universal capture is dead. Injecting it
  // here runs it in the page's own context on BOTH browsers. It self-guards
  // against double-init (window.__vinylpodMainInstalled), so on Chrome — where
  // world:"MAIN" already ran it — this injection is a harmless no-op.
  // ---------------------------------------------------------------------------
  try {
    var s = document.createElement("script");
    s.src = chrome.runtime.getURL("mediasession-main.js");
    s.async = false;
    s.onload = function () { s.remove(); };
    (document.head || document.documentElement).appendChild(s);
  } catch (err) {
    // getURL/CSP blocked — named-site scrapers (and world:MAIN on Chrome) still cover capture.
  }
})();
