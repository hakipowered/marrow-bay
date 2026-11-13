// RaGoon City download page: serves the latest Android build from Workers KV.
// KV values are capped at 25 MiB, so the APK is stored as numbered chunks
// (apk:0, apk:1, ...) plus apk:manifest, and streamed back in order.
// Uploads (PUT /upload/<key>) need the UPLOAD_TOKEN secret, or an Ed25519
// content signature for web:/pack: keys only (see uploadAllowed).
//
// The APK is a thin base; the game itself is content packs the app keeps up
// to date (tools/content/README.md in the repo):
//   GET/HEAD /packs/manifest.json   the newest content set (KV packs:manifest)
//   GET/HEAD /packs/<file>          one pack, streamed from 20 MiB KV chunks
//                                   pack:<file>:<i> (+ packmeta:<file>), Range ok
//
// /play/ is the browser version (Godot Web export, see tools/build_web.sh and
// tools/upload_web.sh). Its files live under web:<build>/<file>:<i> in the
// same chunk format, listed in web:manifest; the manifest is switched only
// after every file of a new build is up, so players never get a mixed build.

const APK_TYPE = "application/vnd.android.package-archive";

// Public half of the Ed25519 key that signs browser-version and content-pack
// uploads (tools/web/upload_auth.py; the private half is in the project's
// private .signing folder). Being public, it needs no secret binding.
const CONTENT_UPLOAD_PUBKEY = "uiTZcoT8heCSq0o/6BSHmnq0/3IyJKmxiikTCb1fvMM=";
const CONTENT_KEY = /^(web|pack|packs|packmeta):/;

// UPLOAD_TOKEN (build thread) may write anything. A content signature may only
// write the browser version and content packs, so it can't replace the APK.
async function uploadAllowed(env, request, key) {
  const token = request.headers.get("x-upload-token");
  if (token && env.UPLOAD_TOKEN && token === env.UPLOAD_TOKEN) return true;
  const sig = request.headers.get("x-upload-sig");
  const ts = Number(request.headers.get("x-upload-ts"));
  if (!sig || !ts || !CONTENT_KEY.test(key) || Math.abs(Date.now() / 1000 - ts) > 600) return false;
  const length = request.method === "PUT" ? Number(request.headers.get("content-length") || 0) : 0;
  try {
    const pub = await crypto.subtle.importKey("raw", b64(CONTENT_UPLOAD_PUBKEY), { name: "Ed25519" }, false, ["verify"]);
    const msg = new TextEncoder().encode(`${request.method}\n${key}\n${ts}\n${length}`);
    return await crypto.subtle.verify({ name: "Ed25519" }, pub, b64(sig), msg);
  } catch (e) {
    return false;
  }
}

function b64(s) {
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === "PUT" && path.startsWith("/upload/")) {
      const key = decodeURIComponent(path.slice("/upload/".length));
      if (!(await uploadAllowed(env, request, key))) {
        return new Response("forbidden", { status: 403 });
      }
      if (!/^(apk:\d+|apk:manifest|icon\.png|web:manifest|web:[\w.-]+\/[\w.-]+:\d+|packs:manifest|pack:[\w.-]+:\d+|packmeta:[\w.-]+)$/.test(key)) {
        return new Response("bad key", { status: 400 });
      }
      await env.BUILDS.put(key, request.body);
      return new Response("ok " + key);
    }

    // Cleanup of old browser builds / packs: DELETE /upload/<key>, and
    // GET /upload-list?prefix=<p>[&cursor=<c>] -> {keys: [...], cursor}.
    if (request.method === "DELETE" && path.startsWith("/upload/")) {
      const key = decodeURIComponent(path.slice("/upload/".length));
      if (!(await uploadAllowed(env, request, key))) return new Response("forbidden", { status: 403 });
      await env.BUILDS.delete(key);
      return new Response("deleted " + key);
    }
    if (request.method === "GET" && path === "/upload-list") {
      const prefix = url.searchParams.get("prefix") || "";
      if (!(await uploadAllowed(env, request, prefix || "apk:"))) return new Response("forbidden", { status: 403 });
      const res = await env.BUILDS.list({ prefix, cursor: url.searchParams.get("cursor") || undefined });
      return Response.json({ keys: res.keys.map((k) => k.name), cursor: res.list_complete ? null : res.cursor });
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
      if (!/^[\w.-]+\.pck$/.test(file)) return new Response("not found", { status: 404 });
      return servePack(request, env, ctx, file);
    }

    if (path === "/play") return Response.redirect(url.origin + "/play/" + url.search, 301);
    if (path.startsWith("/play/")) return servePlay(request, env, ctx, path.slice("/play/".length) || "index.html");

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
      const web = await env.BUILDS.get("web:manifest", { type: "json", cacheTtl: 60 });
      const content = await env.BUILDS.get("packs:manifest", { type: "json", cacheTtl: 60 });
      return new Response(page(manifest, web, content), { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    return new Response("not found", { status: 404 });
  },
};

// ---------------------------------------------------------------------------
// Content packs (/packs/)

// Streams one pack out of its KV chunks, whole or a byte range. Packs are
// named after their SHA-256, so they never change: cache them forever.
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
    etag: `"${meta.sha256}"`,
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
        const hi = Math.min(end - i * chunk, chunk - 1, size - 1 - i * chunk);
        const key = `pack:${file}:${i}`;
        const whole = lo === 0 && i * chunk + hi === Math.min((i + 1) * chunk, size) - 1;
        if (whole) {
          const part = await env.BUILDS.get(key, { type: "stream", cacheTtl: 3600 });
          if (!part) throw new Error("missing " + key);
          await part.pipeTo(writable, { preventClose: true });
        } else {
          const buf = await env.BUILDS.get(key, { type: "arrayBuffer", cacheTtl: 3600 });
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

// ---------------------------------------------------------------------------
// Browser version (/play/)

const WEB_TYPES = {
  html: "text/html; charset=utf-8",
  js: "application/javascript",
  wasm: "application/wasm",
  pck: "application/octet-stream",
  png: "image/png",
  jpg: "image/jpeg",
  json: "application/json",
  webmanifest: "application/manifest+json",
};

// Godot's threaded web build needs SharedArrayBuffer, which browsers only
// allow on cross-origin isolated pages.
const ISOLATION = {
  "cross-origin-opener-policy": "same-origin",
  "cross-origin-embedder-policy": "require-corp",
  "cross-origin-resource-policy": "same-origin",
};

async function servePlay(request, env, ctx, name) {
  const web = await env.BUILDS.get("web:manifest", { type: "json", cacheTtl: 60 });
  const f = web && /^[\w.-]+$/.test(name) ? web.files[name] : null;
  if (!f) {
    if (name === "index.html") return new Response(waitingPage(), { status: 503, headers: { "content-type": WEB_TYPES.html, "cache-control": "no-store" } });
    return new Response("not found", { status: 404, headers: ISOLATION });
  }
  const etag = `"${f.sha256.slice(0, 24)}"`;
  const headers = {
    ...ISOLATION,
    "content-type": WEB_TYPES[name.split(".").pop()] || "application/octet-stream",
    // Revalidate every time (cheap 304s), so a new build shows up on the next load.
    "cache-control": "no-cache",
    etag,
    "x-ragoon-build": web.build,
  };
  if (request.headers.get("if-none-match") === etag) return new Response(null, { status: 304, headers });
  // Big files are stored gzipped. Every browser accepts gzip; anything that
  // doesn't gets it unpacked on the way out.
  const gz = !!f.gzip;
  const acceptsGzip = /\bgzip\b/.test(request.headers.get("accept-encoding") || "");
  if (gz && acceptsGzip) {
    headers["content-encoding"] = "gzip";
    headers["content-length"] = String(f.stored);
  } else if (!gz) {
    headers["content-length"] = String(f.size);
  }
  if (request.method === "HEAD") return new Response(null, { headers, encodeBody: "manual" });
  // Fixed length so the browser gets a content-length and can show progress.
  const length = gz ? f.stored : f.size;
  const { readable, writable } = new FixedLengthStream(length);
  const pump = async () => {
    for (let i = 0; i < f.chunks; i++) {
      const part = await env.BUILDS.get(`web:${web.build}/${name}:${i}`, { type: "stream", cacheTtl: 3600 });
      if (!part) { await writable.abort(new Error(`missing chunk ${name}:${i}`)); return; }
      await part.pipeTo(writable, { preventClose: true });
    }
    await writable.close();
  };
  ctx.waitUntil(pump());
  if (gz && !acceptsGzip) {
    return new Response(readable.pipeThrough(new DecompressionStream("gzip")), { headers });
  }
  return new Response(readable, { headers, encodeBody: gz ? "manual" : "automatic" });
}

function waitingPage() {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>RaGoon City</title><style>body{margin:0;background:#0b0606;color:#eadfd6;font:17px/1.5 system-ui,sans-serif;text-align:center;padding:60px 20px}h1{color:#e0321f}</style></head>
<body><h1>RAGOON CITY</h1><p>The browser version is being uploaded. Try again in a few minutes.</p></body></html>`;
}

function page(m, web, content) {
  const size = m ? (m.size / 1048576).toFixed(0) + " MB" : "";
  const ver = m ? m.version : "";
  const game = content ? (content.packs.reduce((n, p) => n + p.size, 0) / 1048576).toFixed(0) + " MB" : "";
  const btn = m
    ? `<a class="btn" href="/RaGoonCity.apk">Download for Android</a><p class="meta">App ${ver} · ${size}${game ? ` · then the game itself (${game}) downloads inside the app` : ""} · use Wi-Fi</p>`
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
.alt{background:#1d1110;border-color:#8e130c}
ol{text-align:left;padding-left:22px;color:#d7cbc2}
li{margin:8px 0}
b{color:#fff}
</style></head><body><main>
<img src="/icon.png" alt="">
<h1>RAGOON CITY</h1>
<p class="tag">Two-player co-op survival horror. The city has gone silent.</p>
${btn}
${web ? `<a class="btn alt" href="/play/">Play in the browser</a><p class="meta">No install · version ${web.version} · Chrome or Samsung Internet</p>` : ""}
<ol>
<li>Tap the button and open the file when it finishes downloading.</li>
<li>If Android asks, allow installs from this app.</li>
<li>If Samsung blocks it: <b>Settings → Security and privacy → Auto Blocker</b>, turn it off.</li>
<li>If Play Protect warns: <b>More details → Install anyway</b>.</li>
<li>Open RaGoon City. The first start downloads the game; after that it updates itself every time you open it. You only need this page again if the game says it needs the new app.</li>
<li>To play together: one of you taps <b>Co-op: Invite a Friend</b> and shares the room code, the other taps <b>Join with Code</b>.</li>
</ol>
</main></body></html>`;
}
