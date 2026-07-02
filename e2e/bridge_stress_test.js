#!/usr/bin/env node
// VinylPod WebSocket bridge stress test.
// Hammers ws://127.0.0.1:8787 with concurrent connections + high-frequency
// nowplaying messages, churns connections, samples the app's RSS/CPU via ps,
// and prints a FINAL STAT block. Requires Node >= 22 (global WebSocket).
//
// Usage: node bridge_stress_test.js --duration-ms 30000 --process-name VinylPod
const { execSync } = require('child_process');

function arg(name, dflt) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : dflt;
}
const DURATION_MS = parseInt(arg('--duration-ms', '30000'), 10);
const PROC_NAME = arg('--process-name', 'VinylPod');
const PORT = parseInt(arg('--port', '8787'), 10);
const STEADY_CONNS = 8;      // persistent connections
const MSG_INTERVAL_MS = 5;   // per-connection send interval (~200 msg/s/conn)
const CHURN_INTERVAL_MS = 250; // open+close a short-lived connection this often

const stats = {
  connectAttempts: 0, connectOk: 0, connectFail: 0,
  msgsSent: 0, sendErrors: 0, unexpectedClose: 0, churnCycles: 0,
  rssSamples: [], cpuSamples: [],
};

function pidOf(name) {
  try {
    return execSync(`pgrep -x ${name} | head -1`).toString().trim() || null;
  } catch { return null; }
}

function sampleProc(pid) {
  try {
    const out = execSync(`ps -o rss=,%cpu= -p ${pid}`).toString().trim().split(/\s+/);
    stats.rssSamples.push(parseInt(out[0], 10)); // KB
    stats.cpuSamples.push(parseFloat(out[1]));
  } catch { /* app gone */ }
}

function makePayload(i) {
  return JSON.stringify({
    type: 'nowplaying',
    payload: {
      title: `Stress Track ${i}`,
      artist: 'Bridge Stress Bot',
      album: `Load Album ${i % 50}`,
      source: 'spotify',
      isPlaying: true,
      currentTime: (i % 300),
      duration: 300,
      artwork: null,
    },
  });
}

function openConn(tag, senders) {
  stats.connectAttempts++;
  return new Promise((resolve) => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}`);
    ws.onopen = () => { stats.connectOk++; resolve(ws); };
    ws.onerror = () => { stats.connectFail++; resolve(null); };
    ws.onclose = (ev) => {
      if (senders.has(ws)) { stats.unexpectedClose++; clearInterval(senders.get(ws)); senders.delete(ws); }
    };
  });
}

(async () => {
  const pid = pidOf(PROC_NAME);
  if (!pid) { console.error(`FATAL: process "${PROC_NAME}" not running`); process.exit(1); }
  console.log(`Target: ${PROC_NAME} (pid ${pid}), ws://127.0.0.1:${PORT}, duration ${DURATION_MS}ms`);
  sampleProc(pid);
  const rssStart = stats.rssSamples[0];

  const senders = new Map();
  let seq = 0;

  // Steady pool
  for (let c = 0; c < STEADY_CONNS; c++) {
    const ws = await openConn(`steady-${c}`, senders);
    if (!ws) continue;
    const t = setInterval(() => {
      try { ws.send(makePayload(seq++)); stats.msgsSent++; }
      catch { stats.sendErrors++; }
    }, MSG_INTERVAL_MS);
    senders.set(ws, t);
  }
  if (stats.connectOk === 0) { console.error('FATAL: no connection could be established'); process.exit(1); }

  // Connection churn: open, blast 20 messages, close.
  const churn = setInterval(async () => {
    const ws = await openConn('churn', new Map());
    if (!ws) return;
    stats.churnCycles++;
    for (let i = 0; i < 20; i++) {
      try { ws.send(makePayload(seq++)); stats.msgsSent++; } catch { stats.sendErrors++; }
    }
    setTimeout(() => ws.close(), 50);
  }, CHURN_INTERVAL_MS);

  // Sample RSS/CPU every second
  const sampler = setInterval(() => sampleProc(pid), 1000);

  const t0 = Date.now();
  await new Promise(r => setTimeout(r, DURATION_MS));
  clearInterval(churn); clearInterval(sampler);
  for (const [ws, t] of senders) { clearInterval(t); senders.delete(ws); ws.close(); }
  const elapsed = Date.now() - t0;

  await new Promise(r => setTimeout(r, 500));
  sampleProc(pid);

  const rss = stats.rssSamples, cpu = stats.cpuSamples;
  const rssEnd = rss[rss.length - 1];
  const mb = kb => (kb / 1024).toFixed(1);
  console.log('\n================ FINAL STAT ================');
  console.log(`duration_ms         : ${elapsed}`);
  console.log(`connections_ok      : ${stats.connectOk}/${stats.connectAttempts} (failed: ${stats.connectFail})`);
  console.log(`steady_conns        : ${STEADY_CONNS}, churn_cycles: ${stats.churnCycles}`);
  console.log(`messages_sent       : ${stats.msgsSent} (~${Math.round(stats.msgsSent / (elapsed / 1000))}/s)`);
  console.log(`send_errors         : ${stats.sendErrors}`);
  console.log(`unexpected_closes   : ${stats.unexpectedClose}`);
  console.log(`rss_start_mb        : ${mb(rssStart)}`);
  console.log(`rss_end_mb          : ${mb(rssEnd)}`);
  console.log(`rss_peak_mb         : ${mb(Math.max(...rss))}`);
  console.log(`rss_delta_mb        : ${mb(rssEnd - rssStart)}`);
  console.log(`cpu_avg_pct         : ${(cpu.reduce((a, b) => a + b, 0) / cpu.length).toFixed(1)}`);
  console.log(`cpu_peak_pct        : ${Math.max(...cpu).toFixed(1)}`);
  console.log(`app_alive_at_end    : ${pidOf(PROC_NAME) === pid}`);
  console.log('============================================');
  process.exit(0);
})();
