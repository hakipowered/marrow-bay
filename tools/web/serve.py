#!/usr/bin/env python3
"""Serve a web export locally the way the download worker does, with the
cross-origin isolation headers Godot's threaded build needs.
  python3 tools/web/serve.py [dir=build/web] [port=8060]
Then open http://localhost:8060/ (localhost counts as a secure context)."""
import http.server, os, sys, functools

root = sys.argv[1] if len(sys.argv) > 1 else "build/web"
port = int(sys.argv[2]) if len(sys.argv) > 2 else 8060

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".js": "application/javascript",
                      ".pck": "application/octet-stream", ".webmanifest": "application/manifest+json"}

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
