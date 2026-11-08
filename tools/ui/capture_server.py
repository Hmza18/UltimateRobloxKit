#!/usr/bin/env python3
"""Serve spec previews and save PNG captures they post back (screenshots without headless browsers).

  python3 tools/ui/preview_spec.py --all -o build/ui
  python3 tools/ui/capture_server.py build/ui --out docs/images/ui --port 8767
  # then open http://127.0.0.1:8767/PetSimShop.html?capture=PetSimShop in any browser

A page opened with ?capture=<name> draws its stage into a canvas (SVG foreignObject; icons and fonts
are already embedded data URIs) and POSTs the PNG to /save/<name>.png, which this server writes into
--out. Binds to 127.0.0.1 only and accepts names made of letters, digits, '-' and '_'.
"""
from __future__ import annotations

import argparse
import functools
import http.server
import re
import sys
from pathlib import Path

NAME = re.compile(r"^/save/([A-Za-z0-9_-]{1,64})\.png$")


class Handler(http.server.SimpleHTTPRequestHandler):
    out_dir: Path = Path(".")

    def do_POST(self):  # noqa: N802 (http.server API)
        m = NAME.match(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        if not m or not 0 < length <= 20_000_000:
            self.send_error(400, "bad capture request")
            return
        data = self.rfile.read(length)
        if not data.startswith(b"\x89PNG"):
            self.send_error(400, "not a PNG")
            return
        target = self.out_dir / f"{m.group(1)}.png"
        target.write_bytes(data)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(f"saved {target}".encode())
        print(f"saved {target} ({len(data) // 1024} KB)", flush=True)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--port", type=int, default=8767)
    a = ap.parse_args(argv)
    a.out.mkdir(parents=True, exist_ok=True)
    Handler.out_dir = a.out.resolve()
    handler = functools.partial(Handler, directory=str(a.root.resolve()))
    with http.server.ThreadingHTTPServer(("127.0.0.1", a.port), handler) as server:
        print(f"serving {a.root} on http://127.0.0.1:{a.port}, saving captures to {a.out}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    sys.exit(main())
