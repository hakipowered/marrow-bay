// RaGoon City co-op relay: a Cloudflare Worker + Durable Object.
// One Durable Object per room code. The first socket (role=host) becomes
// peer 1, the joiner becomes peer 2. Binary frames are forwarded with the
// sender id swapped in; JSON text frames carry welcome / peer_joined / peer_left.
//
// Client -> relay: [u32 target][u8 channel][u8 mode] payload  (target 0 = all others)
// Relay -> client: [u32 from  ][u8 channel][u8 mode] payload

const MAX_PLAYERS = 2;
const CODE_RE = /^[A-Z0-9]{6}$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const m = url.pathname.match(/^\/room\/([A-Za-z0-9]{6})$/);
    if (!m) return new Response("RaGoon City relay", { status: 200 });
    if (request.headers.get("Upgrade") !== "websocket") return new Response("expected websocket", { status: 426 });
    const code = m[1].toUpperCase();
    if (!CODE_RE.test(code)) return new Response("bad code", { status: 400 });
    const id = env.ROOMS.idFromName(code);
    return env.ROOMS.get(id).fetch(request);
  },
};

export class Room {
  constructor(state) {
    this.state = state;
    this.peers = new Map(); // id -> WebSocket
  }

  async fetch(request) {
    const role = new URL(request.url).searchParams.get("role") === "host" ? "host" : "join";
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    server.accept();

    const fail = (msg) => {
      server.send(JSON.stringify({ type: "error", message: msg }));
      server.close(1008, msg);
      return new Response(null, { status: 101, webSocket: client });
    };
    if (role === "host" && this.peers.has(1)) return fail("Room code already in use");
    if (role === "join" && !this.peers.has(1)) return fail("No game with that code");
    if (this.peers.size >= MAX_PLAYERS) return fail("Room is full");

    let id = role === "host" ? 1 : 2;
    while (this.peers.has(id)) id++;
    const others = [...this.peers.keys()];
    this.peers.set(id, server);
    server.send(JSON.stringify({ type: "welcome", id, peers: others }));
    for (const [pid, ws] of this.peers) if (pid !== id) ws.send(JSON.stringify({ type: "peer_joined", id }));

    server.addEventListener("message", (ev) => {
      if (typeof ev.data === "string") return; // clients send no control text
      const buf = new Uint8Array(ev.data);
      if (buf.length < 6) return;
      const target = new DataView(buf.buffer, buf.byteOffset).getUint32(0, true);
      new DataView(buf.buffer, buf.byteOffset).setUint32(0, id, true);
      for (const [pid, ws] of this.peers) {
        if (pid === id) continue;
        if (target === 0 || target === pid) {
          try { ws.send(buf); } catch (_) {}
        }
      }
    });
    const leave = () => {
      if (this.peers.get(id) !== server) return;
      this.peers.delete(id);
      for (const ws of this.peers.values()) {
        try { ws.send(JSON.stringify({ type: "peer_left", id })); } catch (_) {}
        if (id === 1) try { ws.close(1000, "Host left"); } catch (_) {}
      }
      if (id === 1) this.peers.clear();
    };
    server.addEventListener("close", leave);
    server.addEventListener("error", leave);
    return new Response(null, { status: 101, webSocket: client });
  }
}
