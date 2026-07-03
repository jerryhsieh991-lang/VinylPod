#!/usr/bin/env node
"use strict";
const net = require("node:net");
const crypto = require("node:crypto");
const { execFile } = require("node:child_process");
const { performance, monitorEventLoopDelay } = require("node:perf_hooks");

const DEFAULTS = {
  host: "127.0.0.1",
  port: 8787,
  durationMs: 30_000,
  reportMs: 1_000,
  seekHz: 250,
  binaryHz: 500,
  binarySize: 16 * 1024,
  churnConnections: 250,
  churnBatch: 10,
  stableConnections: 4,
  maxBufferedBytes: 8 * 1024 * 1024,
  processName: "VinylPod",
  pid: null,
  failOnDropRate: 0.05,
  failOnRssGrowthMb: 150
};

const cfg = parseArgs(process.argv.slice(2), DEFAULTS);
const deadline = Date.now() + cfg.durationMs;
const clients = new Set();
const loopDelay = monitorEventLoopDelay({ resolution: 20 });

const metrics = {
  startedAt: new Date().toISOString(),
  connectionsAttempted: 0,
  connectionsOpened: 0,
  handshakeFailed: 0,
  connectionErrors: 0,
  unexpectedDrops: 0,
  normalCloses: 0,
  textFramesSent: 0,
  binaryFramesSent: 0,
  bytesSent: 0,
  sendFailures: 0,
  clientBackpressureDrops: 0,
  serverFramesReceived: 0,
  serverCloseFrames: 0,
  rssSamples: []
};

class RawWebSocketClient {
  constructor(label) {
    this.label = label;
    this.socket = null;
    this.open = false;
    this.closedByTest = false;
    this.readBuffer = Buffer.alloc(0);
  }

  connect() {
    metrics.connectionsAttempted += 1;
    return new Promise((resolve, reject) => {
      const key = crypto.randomBytes(16).toString("base64");
      const socket = net.createConnection({ host: cfg.host, port: cfg.port });
      let handshakeBuffer = Buffer.alloc(0);
      let settled = false;

      const fail = (err) => {
        if (settled) return;
        settled = true;
        metrics.handshakeFailed += 1;
        socket.destroy();
        reject(err);
      };

      socket.setNoDelay(true);
      socket.setTimeout(5_000, () => fail(new Error(`${this.label}: handshake timeout`)));

      socket.once("connect", () => {
        socket.write([
          "GET / HTTP/1.1",
          `Host: ${cfg.host}:${cfg.port}`,
          "Upgrade: websocket",
          "Connection: Upgrade",
          `Sec-WebSocket-Key: ${key}`,
          "Sec-WebSocket-Version: 13",
          "",
          ""
        ].join("\r\n"));
      });

      socket.on("data", (chunk) => {
        if (!this.open) {
          handshakeBuffer = Buffer.concat([handshakeBuffer, chunk]);
          const marker = handshakeBuffer.indexOf("\r\n\r\n");
          if (marker === -1) return;

          const header = handshakeBuffer.subarray(0, marker).toString("latin1");
          const rest = handshakeBuffer.subarray(marker + 4);
          const accept = crypto
            .createHash("sha1")
            .update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
            .digest("base64");

          if (!/^HTTP\/1\.1 101\b/.test(header) || !header.includes(`Sec-WebSocket-Accept: ${accept}`)) {
            fail(new Error(`${this.label}: bad handshake response`));
            return;
          }

          settled = true;
          this.socket = socket;
          this.open = true;
          socket.setTimeout(0);
          metrics.connectionsOpened += 1;
          if (rest.length) this.consumeFrames(rest);
          resolve(this);
          return;
        }
        this.consumeFrames(chunk);
      });

      socket.on("error", () => {
        metrics.connectionErrors += 1;
        if (!settled) fail(new Error(`${this.label}: socket error`));
      });

      socket.on("close", () => {
        const wasOpen = this.open;
        this.open = false;
        clients.delete(this);
        if (wasOpen && this.closedByTest) metrics.normalCloses += 1;
        if (wasOpen && !this.closedByTest) metrics.unexpectedDrops += 1;
      });
    });
  }

  consumeFrames(chunk) {
    this.readBuffer = Buffer.concat([this.readBuffer, chunk]);
    while (this.readBuffer.length >= 2) {
      const first = this.readBuffer[0];
      const second = this.readBuffer[1];
      let length = second & 0x7f;
      let offset = 2;

      if (length === 126) {
        if (this.readBuffer.length < offset + 2) return;
        length = this.readBuffer.readUInt16BE(offset);
        offset += 2;
      } else if (length === 127) {
        if (this.readBuffer.length < offset + 8) return;
        const high = this.readBuffer.readUInt32BE(offset);
        const low = this.readBuffer.readUInt32BE(offset + 4);
        length = high * 2 ** 32 + low;
        offset += 8;
      }

      if (second & 0x80) offset += 4;
      if (this.readBuffer.length < offset + length) return;

      const opcode = first & 0x0f;
      metrics.serverFramesReceived += 1;
      if (opcode === 0x8) metrics.serverCloseFrames += 1;
      this.readBuffer = this.readBuffer.subarray(offset + length);
    }
  }

  sendText(obj) {
    this.sendFrame(0x1, Buffer.from(JSON.stringify(obj), "utf8"));
  }

  sendBinary(size, salt) {
    const payload = Buffer.allocUnsafe(size);
    for (let i = 0; i < payload.length; i += 1) payload[i] = (i + salt) & 0xff;
    this.sendFrame(0x2, payload);
  }

  sendFrame(opcode, payload) {
    if (!this.open || !this.socket || this.socket.destroyed) {
      metrics.sendFailures += 1;
      return;
    }
    if (this.socket.writableLength > cfg.maxBufferedBytes) {
      metrics.clientBackpressureDrops += 1;
      return;
    }

    const frame = encodeClientFrame(opcode, payload);
    const ok = this.socket.write(frame);
    metrics.bytesSent += frame.length;
    if (opcode === 0x1) metrics.textFramesSent += 1;
    if (opcode === 0x2) metrics.binaryFramesSent += 1;
    if (!ok) metrics.clientBackpressureDrops += 1;
  }

  close() {
    this.closedByTest = true;
    if (!this.socket || this.socket.destroyed) return;
    try {
      this.socket.write(encodeClientFrame(0x8, Buffer.alloc(0)));
      this.socket.end();
    } catch (_) {
      this.socket.destroy();
    }
  }
}

function encodeClientFrame(opcode, payload) {
  const length = payload.length;
  const extra = length < 126 ? 0 : length <= 0xffff ? 2 : 8;
  const header = Buffer.allocUnsafe(2 + extra + 4);
  let offset = 0;

  header[offset++] = 0x80 | opcode;
  if (length < 126) {
    header[offset++] = 0x80 | length;
  } else if (length <= 0xffff) {
    header[offset++] = 0x80 | 126;
    header.writeUInt16BE(length, offset);
    offset += 2;
  } else {
    header[offset++] = 0x80 | 127;
    header.writeUInt32BE(Math.floor(length / 2 ** 32), offset);
    header.writeUInt32BE(length >>> 0, offset + 4);
    offset += 8;
  }

  const mask = crypto.randomBytes(4);
  mask.copy(header, offset);
  const masked = Buffer.allocUnsafe(length);
  for (let i = 0; i < length; i += 1) masked[i] = payload[i] ^ mask[i & 3];
  return Buffer.concat([header, masked]);
}

function nowPlayingPayload(sequence) {
  return {
    type: "nowplaying",
    payload: {
      source: sequence % 3 === 0 ? "spotify" : sequence % 3 === 1 ? "appleMusic" : "browser",
      title: `Bridge Stress Track ${Math.floor(sequence / 100)}`,
      artist: "Local QA",
      album: "Socket Boundary Suite",
      artwork: "",
      isPlaying: true,
      currentTime: (sequence * 0.137) % 240,
      duration: 240
    }
  };
}

async function createClient(label) {
  const client = new RawWebSocketClient(label);
  try {
    await client.connect();
    clients.add(client);
    return client;
  } catch (err) {
    return null;
  }
}

async function runStableSeekStorm() {
  const stable = [];
  for (let i = 0; i < cfg.stableConnections; i += 1) {
    const client = await createClient(`stable-${i}`);
    if (client) stable.push(client);
  }
  let sequence = 0;
  const intervalMs = Math.max(1, Math.floor(1000 / cfg.seekHz));
  const timer = setInterval(() => {
    for (const client of stable) client.sendText(nowPlayingPayload(sequence++));
    if (Date.now() >= deadline) clearInterval(timer);
  }, intervalMs);
  return stable;
}

async function runBinaryBombardment() {
  const client = await createClient("binary-bombardment");
  if (!client) return null;
  let salt = 0;
  const intervalMs = Math.max(1, Math.floor(1000 / cfg.binaryHz));
  const timer = setInterval(() => {
    client.sendBinary(cfg.binarySize, salt++);
    if (Date.now() >= deadline) clearInterval(timer);
  }, intervalMs);
  return client;
}

async function runConnectionChurn() {
  let created = 0;
  const timer = setInterval(async () => {
    if (Date.now() >= deadline || created >= cfg.churnConnections) {
      clearInterval(timer);
      return;
    }
    const batch = [];
    for (let i = 0; i < cfg.churnBatch && created < cfg.churnConnections; i += 1) {
      created += 1;
      batch.push(createClient(`churn-${created}`));
    }
    const opened = (await Promise.all(batch)).filter(Boolean);
    for (const client of opened) {
      client.sendText(nowPlayingPayload(created));
      setTimeout(() => client.close(), 5 + (created % 40));
    }
  }, 50);
}

function sampleReceiverRss() {
  resolveReceiverPid((pid) => {
    if (!pid) return;
    execFile("ps", ["-o", "rss=", "-p", String(pid)], (err, stdout) => {
      if (err) return;
      const rssKb = Number.parseInt(stdout.trim(), 10);
      if (!Number.isFinite(rssKb)) return;
      metrics.rssSamples.push({ atMs: elapsedMs(), pid, rssMb: rssKb / 1024 });
    });
  });
}

let cachedPid = cfg.pid ? Number(cfg.pid) : null;
function resolveReceiverPid(callback) {
  if (cachedPid) { callback(cachedPid); return; }
  execFile("pgrep", ["-n", "-x", cfg.processName], (err, stdout) => {
    if (err) { callback(null); return; }
    const pid = Number.parseInt(stdout.trim(), 10);
    cachedPid = Number.isFinite(pid) ? pid : null;
    callback(cachedPid);
  });
}

function printReport(final = false) {
  const rss = metrics.rssSamples.at(-1);
  const opened = Math.max(metrics.connectionsOpened, 1);
  const dropRate = metrics.unexpectedDrops / opened;
  const rssText = rss ? ` receiverRss=${rss.rssMb.toFixed(1)}MB(pid=${rss.pid})` : " receiverRss=n/a";

  console.log([
    final ? "FINAL" : "STAT",
    `t=${elapsedMs()}ms`,
    `opened=${metrics.connectionsOpened}/${metrics.connectionsAttempted}`,
    `unexpectedDrops=${metrics.unexpectedDrops}`,
    `dropRate=${(dropRate * 100).toFixed(2)}%`,
    `text=${metrics.textFramesSent}`,
    `binary=${metrics.binaryFramesSent}`,
    `sentMB=${(metrics.bytesSent / 1024 / 1024).toFixed(1)}`,
    rssText
  ].join(" "));
}

function summarizeAndExit() {
  for (const client of Array.from(clients)) client.close();
  loopDelay.disable();
  printReport(true);
  const opened = Math.max(metrics.connectionsOpened, 1);
  const dropRate = metrics.unexpectedDrops / opened;
  const firstRss = metrics.rssSamples[0]?.rssMb;
  const lastRss = metrics.rssSamples.at(-1)?.rssMb;
  const rssGrowth = Number.isFinite(firstRss) && Number.isFinite(lastRss) ? lastRss - firstRss : 0;

  console.log(JSON.stringify({ durationMs: elapsedMs(), dropRate, receiverRssGrowthMb: rssGrowth }, null, 2));
  process.exit(0);
}

function elapsedMs() { return Math.round(performance.now() - startedAt); }

function parseArgs(args, defaults) {
  const out = { ...defaults };
  for (let i = 0; i < args.length; i += 1) {
    if (!args[i].startsWith("--")) continue;
    const key = args[i].slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    if (key in out) { out[key] = Number(args[i + 1]) || args[i + 1]; i += 1; }
  }
  return out;
}

const startedAt = performance.now();
loopDelay.enable();
sampleReceiverRss();
const rssTimer = setInterval(sampleReceiverRss, cfg.reportMs);
const reportTimer = setInterval(() => printReport(false), cfg.reportMs);

Promise.all([runStableSeekStorm(), runBinaryBombardment(), runConnectionChurn()]).catch(console.error);

setTimeout(() => {
  clearInterval(rssTimer); clearInterval(reportTimer);
  sampleReceiverRss(); setTimeout(summarizeAndExit, 250);
}, cfg.durationMs);
