#!/usr/bin/env python3
"""Serve a web export locally the way the download worker does, with the
cross-origin isolation headers Godot's threaded build needs.
  python3 tools/web/serve.py [dir=build/web] [port=8060] [content=build/content]
Then open http://localhost:8060/ (localhost counts as a secure context).
With a content dir (tools/build_content.sh), /packs/manifest.json and
/packs/<file>.pck are served from it like the worker's /packs/ routes."""
import http.server, os, sys, functools

root = sys.argv[1] if len(sys.argv) > 1 else "build/web"
port = int(sys.argv[2]) if len(sys.argv) > 2 else 8060
content = os.path.abspath(sys.argv[3]) if len(sys.argv) > 3 else None

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".js": "application/javascript",
                      ".pck": "application/octet-stream", ".webmanifest": "application/manifest+json"}

    def translate_path(self, path):
        p = path.split("?", 1)[0]
        if content and p.startswith("/packs/"):
            name = os.path.basename(p)
            return os.path.join(content, "manifest.json" if name == "manifest.json" else os.path.join("packs", name))
        return super().translate_path(path)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt, *args):
        if os.environ.get("VERBOSE"):
            super().log_message(fmt, *args)

http.server.ThreadingHTTPServer(("0.0.0.0", port), functools.partial(Handler, directory=root)).serve_forever()
