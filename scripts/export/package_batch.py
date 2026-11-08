#!/usr/bin/env python3
"""Copy approved assets of a batch into a delivery folder and optional zip.

  python3 scripts/export/package_batch.py build/props --dest dist/props --zip dist/props.zip
  python3 scripts/export/package_batch.py build/batch-01 --license 1 --dest handoff

--license N uses the License delivery format from the supermarket project (see the
license-folder-delivery skill): handoff/License<N>/<Asset>/ with <Asset>_FBX.fbx, <Asset>_OBJ.obj,
<Asset>.mtl, <Asset>.png, <Asset>_Image.png and <Asset>.blend, plus handoff/License<N>.zip whose
entries start with License<N>/. Every copy and every zip entry is compared byte for byte.

Only assets whose status.json state is `approved` are packaged; anything else is listed and the
script exits 1, so an unapproved batch can never be shipped by accident. Existing destination
folders are never overwritten: the previous copy moves to <dest>/_versions/<timestamp>/.
"""
from __future__ import annotations

import argparse
import filecmp
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
    ap.add_argument("--license", type=int, help="License<N> delivery format (implies --zip <dest>/License<N>.zip)")
    a = ap.parse_args(argv)
    out, dest = Path(a.out), Path(a.dest)
    if a.license is not None:
        return license_handoff(out, dest, a.license)
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


def _approved(out: Path):
    status = json.loads((out / "status.json").read_text())
    pending = {n: e["state"] for n, e in status["assets"].items() if e["state"] != "approved"}
    if pending:
        print("Not packaged - these assets are not approved:")
        for n, s in pending.items():
            print(f"  {n}: {s}")
        return None
    return list(status["assets"])


def license_handoff(out: Path, handoff: Path, number: int) -> int:
    names = _approved(out)
    if names is None:
        return 1
    label = f"License{number}"
    stamp = time.strftime("%Y%m%d-%H%M%S")
    handoff.mkdir(parents=True, exist_ok=True)
    for old in (handoff / label, handoff / f"{label}.zip"):
        if old.exists():  # never overwrite an earlier delivery
            (handoff / "_previous" / stamp).mkdir(parents=True, exist_ok=True)
            shutil.move(str(old), str(handoff / "_previous" / stamp / old.name))
    target = handoff / label
    for name in names:
        src = out / name
        folder = target / name
        folder.mkdir(parents=True)
        pairs = [(src / f"{name}.fbx", f"{name}_FBX.fbx"), (src / f"{name}.obj", f"{name}_OBJ.obj"),
                 (src / f"{name}.mtl", f"{name}.mtl"), (src / f"{name}.png", f"{name}.png"),
                 (src / "views" / "hero.png", f"{name}_Image.png"), (src / f"{name}.blend", f"{name}.blend")]
        if (src / f"{name}.glb").exists():
            pairs.append((src / f"{name}.glb", f"{name}_GLB.glb"))
        for s, n in pairs:
            if not s.exists():
                raise SystemExit(f"{name}: missing {s.name}; rebuild the asset (renders are needed for _Image.png)")
            shutil.copy2(s, folder / n)
            if not filecmp.cmp(s, folder / n, shallow=False):
                raise SystemExit(f"copy differs: {s}")
    archive = handoff / f"{label}.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(target.rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(handoff).as_posix())
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:
            raise SystemExit(f"corrupt zip: {archive}")
        for f in target.rglob("*"):
            if f.is_file() and z.read(f.relative_to(handoff).as_posix()) != f.read_bytes():
                raise SystemExit(f"zip mismatch: {f}")
        count = len(z.namelist())
    print(f"{label}.zip: {len(names)} assets, {count} files: {', '.join(names)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
