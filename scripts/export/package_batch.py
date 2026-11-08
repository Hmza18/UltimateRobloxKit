#!/usr/bin/env python3
"""Copy approved assets of a batch into a delivery folder and optional zip.

  python3 scripts/export/package_batch.py build/props --dest dist/props --zip dist/props.zip

Only assets whose status.json state is `approved` are packaged; anything else is listed and the
script exits 1, so an unapproved batch can never be shipped by accident. Existing destination
folders are never overwritten: the previous copy moves to <dest>/_versions/<timestamp>/.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
import zipfile
from pathlib import Path

DELIVER = (".fbx", ".obj", ".mtl", ".glb", ".png", ".blend")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out")
    ap.add_argument("--dest", required=True)
    ap.add_argument("--zip")
    a = ap.parse_args(argv)
    out, dest = Path(a.out), Path(a.dest)
    status = json.loads((out / "status.json").read_text())
    pending = {n: e["state"] for n, e in status["assets"].items() if e["state"] != "approved"}
    if pending:
        print("Not packaged - these assets are not approved:")
        for n, s in pending.items():
            print(f"  {n}: {s}")
        return 1
    dest.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    for name in status["assets"]:
        src, target = out / name, dest / name
        if target.exists():
            archive = dest / "_versions" / stamp
            archive.mkdir(parents=True, exist_ok=True)
            shutil.move(str(target), str(archive / name))
        target.mkdir()
        for f in src.iterdir():
            if f.suffix.lower() in DELIVER:
                shutil.copy2(f, target / f.name)
        hero = src / "views" / "hero.png"
        if hero.exists():
            shutil.copy2(hero, target / f"{name}_Image.png")
    if a.zip:
        Path(a.zip).parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(a.zip, "w", zipfile.ZIP_DEFLATED) as z:
            for f in sorted(dest.rglob("*")):
                if f.is_file() and "_versions" not in f.parts:
                    z.write(f, f.relative_to(dest))
    print(f"packaged {len(status['assets'])} assets into {dest}" + (f" and {a.zip}" if a.zip else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
