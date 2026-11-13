// RaGoon City download page: serves the latest Android build from Workers KV.
// KV values are capped at 25 MiB, so the APK is stored as numbered chunks
// (apk:0, apk:1, ...) plus apk:manifest, and streamed back in order.
//
// The APK is a thin base; the game itself is content packs the app keeps up
// to date (see tools/content/README.md in the repo):
//   GET/HEAD /packs/manifest.json   the newest content set (KV packs:manifest)
//   GET/HEAD /packs/<file>          one pack (KV pack:<file>:<i> chunks of
//                                   20 MiB + packmeta:<file>), Range supported
// Uploads need the UPLOAD_TOKEN secret: PUT /upload/<key>, DELETE
// /upload/<key>, GET /upload-list?prefix=<p> (key names, for cleanup).

const APK_TYPE = "application/vnd.android.package-archive";
const UPLOAD_KEY = /^(apk:\d+|apk:manifest|icon\.png|packs:manifest|pack:[A-Za-z0-9_.-]+:\d+|packmeta:[A-Za-z0-9_.-]+)$/;
const PACK_FILE = /^[A-Za-z0-9_.-]+\.pck$/;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path.startsWith("/upload/") || path === "/upload-list") {
      if (!env.UPLOAD_TOKEN || request.headers.get("x-upload-token") !== env.UPLOAD_TOKEN) {
        return new Response("forbidden", { status: 403 });
      }
      if (path === "/upload-list" && request.method === "GET") {
        const prefix = url.searchParams.get("prefix") || "";
        const names = [];
        let cursor;
        do {
          const page = await env.BUILDS.list({ prefix, cursor });
          for (const k of page.keys) names.push(k.name);
          cursor = page.list_complete ? undefined : page.cursor;
        } while (cursor);
        return Response.json(names);
      }
      const key = decodeURIComponent(path.slice("/upload/".length));
      if (!UPLOAD_KEY.test(key)) {
        return new Response("bad key", { status: 400 });
      }
      if (request.method === "PUT") {
        await env.BUILDS.put(key, request.body);
        return new Response("ok " + key);
      }
      if (request.method === "DELETE") {
        await env.BUILDS.delete(key);
        return new Response("deleted " + key);
      }
      return new Response("method not allowed", { status: 405 });
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("method not allowed", { status: 405 });
    }

    if (path === "/icon.png") {
      const icon = await env.BUILDS.get("icon.png", { type: "stream" });
      if (!icon) return new Response("not found", { status: 404 });
      return new Response(icon, { headers: { "content-type": "image/png", "cache-control": "public, max-age=3600" } });
    }

    if (path === "/packs/manifest.json") {
      const m = await env.BUILDS.get("packs:manifest");
      if (!m) return new Response("no content uploaded yet", { status: 404 });
      return new Response(request.method === "HEAD" ? null : m, {
        headers: { "content-type": "application/json", "cache-control": "no-store", "access-control-allow-origin": "*" },
      });
    }

    if (path.startsWith("/packs/")) {
      const file = decodeURIComponent(path.slice("/packs/".length));
      if (!PACK_FILE.test(file)) return new Response("not found", { status: 404 });
      return servePack(request, env, ctx, file);
    }

    const manifest = await env.BUILDS.get("apk:manifest", { type: "json" });

    if (path === "/RaGoonCity.apk") {
      if (!manifest) return new Response("No build uploaded yet.", { status: 404 });
      const headers = {
        "content-type": APK_TYPE,
        "content-length": String(manifest.size),
        "content-disposition": 'attachment; filename="RaGoonCity.apk"',
        "cache-control": "no-store",
      };
      if (request.method === "HEAD") return new Response(null, { headers });
      const { readable, writable } = new FixedLengthStream(manifest.size);
      const pump = async () => {
        for (let i = 0; i < manifest.chunks; i++) {
          const part = await env.BUILDS.get(`apk:${i}`, { type: "stream" });
          if (!part) { await writable.abort(new Error("missing chunk " + i)); return; }
          await part.pipeTo(writable, { preventClose: true });
        }
        await writable.close();
      };
      ctx.waitUntil(pump());
      return new Response(readable, { headers });
    }

    if (path === "/" || path === "/index.html") {
      const content = await env.BUILDS.get("packs:manifest", { type: "json" });
      return new Response(page(manifest, content), { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    return new Response("not found", { status: 404 });
  },
};

// Streams one content pack out of its KV chunks, whole or a byte range.
async function servePack(request, env, ctx, file) {
  const meta = await env.BUILDS.get("packmeta:" + file, { type: "json" });
  if (!meta) return new Response("not found", { status: 404 });
  const size = meta.size;
  const chunk = meta.chunk || 20971520;
  let start = 0;
  let end = size - 1;
  let status = 200;
  const range = request.headers.get("range");
  if (range) {
    const m = /^bytes=(\d*)-(\d*)$/.exec(range.trim());
    if (m && (m[1] !== "" || m[2] !== "")) {
      if (m[1] === "") {
        start = Math.max(0, size - parseInt(m[2], 10));
      } else {
        start = parseInt(m[1], 10);
        if (m[2] !== "") end = Math.min(parseInt(m[2], 10), size - 1);
      }
      if (start > end || start >= size) {
        return new Response(null, { status: 416, headers: { "content-range": `bytes */${size}` } });
      }
      status = 206;
    }
  }
  const length = end - start + 1;
  const headers = {
    "content-type": "application/octet-stream",
    "content-length": String(length),
    "accept-ranges": "bytes",
    "cache-control": "public, max-age=31536000, immutable",
    "etag": `"${meta.sha256}"`,
    "x-sha256": meta.sha256,
    "access-control-allow-origin": "*",
    "access-control-expose-headers": "content-length, content-range, x-sha256",
  };
  if (status === 206) headers["content-range"] = `bytes ${start}-${end}/${size}`;
  if (request.method === "HEAD" || length === 0) return new Response(null, { status, headers });
  const { readable, writable } = new FixedLengthStream(length);
  const pump = async () => {
    try {
      for (let i = Math.floor(start / chunk); i <= Math.floor(end / chunk); i++) {
        const lo = Math.max(start - i * chunk, 0);
        const hi = Math.min(end - i * chunk, chunk - 1);
        const key = `pack:${file}:${i}`;
        if (lo === 0 && hi === chunk - 1 || lo === 0 && i * chunk + hi === size - 1) {
          const part = await env.BUILDS.get(key, { type: "stream" });
          if (!part) throw new Error("missing " + key);
          await part.pipeTo(writable, { preventClose: true });
        } else {
          const buf = await env.BUILDS.get(key, { type: "arrayBuffer" });
          if (!buf) throw new Error("missing " + key);
          const w = writable.getWriter();
          await w.write(new Uint8Array(buf, lo, hi - lo + 1));
          w.releaseLock();
        }
      }
      await writable.close();
    } catch (e) {
      await writable.abort(e);
    }
  };
  ctx.waitUntil(pump());
  return new Response(readable, { status, headers });
}

function page(m, content) {
  const size = m ? (m.size / 1048576).toFixed(0) + " MB" : "";
  const ver = m ? m.version : "";
  const game = content ? (content.packs.reduce((n, p) => n + p.size, 0) / 1048576).toFixed(0) + " MB" : "about 520 MB";
  const btn = m
    ? `<a class="btn" href="/RaGoonCity.apk">Download for Android</a><p class="meta">App ${ver} · ${size}. The game itself (${game}) downloads inside the app on first start, then it updates itself.</p>`
    : `<p class="meta">No build uploaded yet.</p>`;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>RaGoon City</title>
<style>
body{margin:0;background:#0b0606;color:#eadfd6;font:17px/1.5 system-ui,sans-serif}
main{max-width:520px;margin:0 auto;padding:32px 20px 48px;text-align:center}
img{width:160px;height:160px;border-radius:28px;box-shadow:0 8px 40px #6b0d0899}
h1{color:#e0321f;letter-spacing:.06em;margin:20px 0 4px;font-size:34px}
.tag{color:#b9a89c;margin:0 0 28px}
.btn{display:block;background:#8e130c;color:#fff;text-decoration:none;font-weight:600;padding:18px;border-radius:14px;font-size:20px;border:1px solid #d0402f}
.meta{color:#9d8f86;font-size:14px;margin:10px 0 28px}
ol{text-align:left;padding-left:22px;color:#d7cbc2}
li{margin:8px 0}
b{color:#fff}
</style></head><body><main>
<img src="/icon.png" alt="">
<h1>RAGOON CITY</h1>
<p class="tag">Two-player co-op survival horror. The city has gone silent.</p>
${btn}
<ol>
<li>Tap the button and open the file when it finishes downloading.</li>
<li>If Android asks, allow installs from this app.</li>
<li>If Samsung blocks it: <b>Settings → Security and privacy → Auto Blocker</b>, turn it off.</li>
<li>If Play Protect warns: <b>More details → Install anyway</b>.</li>
<li>Open RaGoon City. The first start downloads the game (use Wi-Fi). After that it updates itself whenever there's a new version: just open it. You only come back here if the game says it needs the new app.</li>
<li>To play together: one of you taps <b>Co-op: Invite a Friend</b> and shares the room code, the other taps <b>Join with Code</b>.</li>
</ol>
</main></body></html>`;
}
