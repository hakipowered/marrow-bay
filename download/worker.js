// RaGoon City download page: serves the latest Android build from Workers KV.
// KV values are capped at 25 MiB, so the APK is stored as numbered chunks
// (apk:0, apk:1, ...) plus apk:manifest, and streamed back in order.
// Uploads (PUT /upload/<key>) need the UPLOAD_TOKEN secret.

const APK_TYPE = "application/vnd.android.package-archive";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === "PUT" && path.startsWith("/upload/")) {
      if (!env.UPLOAD_TOKEN || request.headers.get("x-upload-token") !== env.UPLOAD_TOKEN) {
        return new Response("forbidden", { status: 403 });
      }
      const key = decodeURIComponent(path.slice("/upload/".length));
      if (!/^(apk:\d+|apk:manifest|icon\.png)$/.test(key)) {
        return new Response("bad key", { status: 400 });
      }
      await env.BUILDS.put(key, request.body);
      return new Response("ok " + key);
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("method not allowed", { status: 405 });
    }

    if (path === "/icon.png") {
      const icon = await env.BUILDS.get("icon.png", { type: "stream" });
      if (!icon) return new Response("not found", { status: 404 });
      return new Response(icon, { headers: { "content-type": "image/png", "cache-control": "public, max-age=3600" } });
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
      return new Response(page(manifest), { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    return new Response("not found", { status: 404 });
  },
};

function page(m) {
  const size = m ? (m.size / 1048576).toFixed(0) + " MB" : "";
  const ver = m ? m.version : "";
  const btn = m
    ? `<a class="btn" href="/RaGoonCity.apk">Download for Android</a><p class="meta">Version ${ver} · ${size} · use Wi-Fi</p>`
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
<li>To play together: one of you taps <b>Co-op: Invite a Friend</b> and shares the room code, the other taps <b>Join with Code</b>.</li>
</ol>
</main></body></html>`;
}
