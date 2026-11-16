// Same protocol as worker.js, for testing on a PC: `npm i ws && node local_relay.js`
// Then set the relay URL in the game to ws://<pc-ip>:8787
//
// To try the game over a bad connection, the relay can hold frames back the
// way a phone's link does. All in milliseconds, all off by default:
//   LAG_MS          added on the way to each player (so the ping goes up by 2x)
//   JITTER_MS       plus a random 0..JITTER_MS more per frame
//   STALL_EVERY_MS  every so often (randomly, about this far apart) ...
//   STALL_MS        ... nothing gets through for this long, then it all
//                   arrives at once (what a lost packet does to a TCP link)
// Frames to one player never overtake each other, as on a real WebSocket.
const { WebSocketServer } = require("ws");
const LAG = Number(process.env.LAG_MS || 0);
const JITTER = Number(process.env.JITTER_MS || 0);
const STALL_EVERY = Number(process.env.STALL_EVERY_MS || 0);
const STALL = Number(process.env.STALL_MS || 0);
const SHAPED = LAG > 0 || JITTER > 0 || (STALL_EVERY > 0 && STALL > 0);
// RELAY_STATS=1: every 5 s, log what each player sent (frames and bytes per second).
const traffic = new Map();
if (process.env.RELAY_STATS) setInterval(() => {
  for (const [id, t] of traffic) console.log(`peer ${id} sent ${(t.frames / 5).toFixed(0)} frames/s, ${(t.bytes / 5 / 1024).toFixed(1)} KB/s`);
  traffic.clear();
}, 5000);

// Per receiving socket: when its last frame goes out, and its next stall.
function shaper(ws) {
  let last = 0;
  let stallAt = STALL_EVERY > 0 ? Date.now() + Math.random() * 2 * STALL_EVERY : Infinity;
  return (data, opts) => {
    if (!SHAPED) return ws.send(data, opts);
    const now = Date.now();
    let at = now + LAG + Math.random() * JITTER;
    if (now >= stallAt) {
      at = Math.max(at, stallAt + STALL);
      if (now >= stallAt + STALL) stallAt = now + Math.random() * 2 * STALL_EVERY;
    }
    at = Math.max(at, last);
    last = at;
    const copy = Buffer.isBuffer(data) ? Buffer.from(data) : data;
    setTimeout(() => { try { ws.send(copy, opts); } catch (_) {} }, at - now);
  };
}

const rooms = new Map();
const wss = new WebSocketServer({ port: Number(process.env.PORT || 8787) });
wss.on("connection", (ws, req) => {
  const url = new URL(req.url, "http://x");
  const m = url.pathname.match(/^\/room\/([A-Za-z0-9]{6})$/);
  if (!m) return ws.close();
  const code = m[1].toUpperCase();
  const role = url.searchParams.get("role") === "host" ? "host" : "join";
  const peers = rooms.get(code) || new Map();
  const fail = (msg) => { ws.send(JSON.stringify({ type: "error", message: msg })); ws.close(); };
  if (role === "host" && peers.has(1)) return fail("Room code already in use");
  if (role === "join" && !peers.has(1)) return fail("No game with that code");
  if (peers.size >= 2) return fail("Room is full");
  rooms.set(code, peers);
  let id = role === "host" ? 1 : 2;
  while (peers.has(id)) id++;
  ws.sendShaped = shaper(ws);
  ws.send(JSON.stringify({ type: "welcome", id, peers: [...peers.keys()] }));
  for (const o of peers.values()) o.send(JSON.stringify({ type: "peer_joined", id }));
  peers.set(id, ws);
  ws.on("message", (data, isBinary) => {
    if (!isBinary || data.length < 6) return;
    const t = traffic.get(id) || { frames: 0, bytes: 0 };
    t.frames++; t.bytes += data.length; traffic.set(id, t);
    const target = data.readUInt32LE(0);
    data.writeUInt32LE(id, 0);
    for (const [pid, o] of peers) if (pid !== id && (target === 0 || target === pid)) o.sendShaped(data, { binary: true });
  });
  ws.on("close", () => {
    peers.delete(id);
    for (const o of peers.values()) { o.send(JSON.stringify({ type: "peer_left", id })); if (id === 1) o.close(); }
    if (id === 1 || peers.size === 0) rooms.delete(code);
  });
});
console.log("relay listening on", wss.options.port, SHAPED ? `(lag ${LAG} ms + jitter ${JITTER} ms, stall ${STALL} ms every ~${STALL_EVERY} ms)` : "");
