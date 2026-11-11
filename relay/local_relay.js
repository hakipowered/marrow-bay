// Same protocol as worker.js, for testing on a PC: `npm i ws && node local_relay.js`
// Then set the relay URL in the game to ws://<pc-ip>:8787
const { WebSocketServer } = require("ws");
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
  ws.send(JSON.stringify({ type: "welcome", id, peers: [...peers.keys()] }));
  for (const o of peers.values()) o.send(JSON.stringify({ type: "peer_joined", id }));
  peers.set(id, ws);
  ws.on("message", (data, isBinary) => {
    if (!isBinary || data.length < 6) return;
    const target = data.readUInt32LE(0);
    data.writeUInt32LE(id, 0);
    for (const [pid, o] of peers) if (pid !== id && (target === 0 || target === pid)) o.send(data);
  });
  ws.on("close", () => {
    peers.delete(id);
    for (const o of peers.values()) { o.send(JSON.stringify({ type: "peer_left", id })); if (id === 1) o.close(); }
    if (id === 1 || peers.size === 0) rooms.delete(code);
  });
});
console.log("relay listening on", wss.options.port);
