#!/usr/bin/env python3
"""Build a batch of procedural Roblox assets end to end, with QA and an approval gate.

  python3 scripts/export/asset_batch.py examples/asset-batch/props.json --out build/props
  python3 scripts/export/asset_batch.py examples/asset-batch/props.json --out build/props --only Crate
  python3 scripts/export/asset_batch.py --status build/props
  python3 scripts/export/asset_batch.py --approve Crate build/props    # only after the user approved in chat

Stages per asset: layout (mesh + UV atlas + texture, no Blender), blender (.blend, FBX, OBJ, GLB,
renders), verify (re-import every export), qa (checks below), sheet (contact sheet, needs Pillow).
QA reports PASS, FAIL or NEEDS MANUAL REVIEW per check. Studio import is never marked as passed by
this script: run docs/workflows/studio-validation.md and record the result by hand.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "scripts"))

from lib.env import find_blender  # noqa: E402
from rbxasset.layout import make_layout  # noqa: E402

ROBLOX_MAX_TRIS = 20000  # per-mesh import limit documented by Roblox
TOL = 0.002


def run_blender(blender, script, asset_dir, extra=()):
    cmd = [blender, "-b", "--factory-startup", "--python-exit-code", "1", "--python", str(ROOT / "scripts/blender" / script), "--", str(asset_dir), *extra]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    (asset_dir / f"{Path(script).stem}.log").write_text(proc.stdout[-20000:] + "\n--- stderr ---\n" + proc.stderr[-20000:])
    if proc.returncode != 0:
        raise RuntimeError(f"{script} failed (exit {proc.returncode}); see {asset_dir / (Path(script).stem + '.log')}")


def qa(spec, layout, asset_dir):
    checks = []

    def add(name, ok, detail="", manual=False):
        checks.append({"check": name, "result": "NEEDS MANUAL REVIEW" if manual else ("PASS" if ok else "FAIL"), "detail": detail})

    g = layout["geometry_check"]
    add("closed_outward_geometry", g["closed"] and g["outward"], json.dumps(g))
    add("triangle_budget", g["tris"] <= layout["max_tris"], f"{g['tris']} <= {layout['max_tris']}")
    add("roblox_mesh_limit", g["tris"] <= ROBLOX_MAX_TRIS, f"{g['tris']} <= {ROBLOX_MAX_TRIS}")
    metrics_path = asset_dir / "metrics.json"
    if metrics_path.exists():
        m = json.loads(metrics_path.read_text())
        add("blender_dims_match_spec", all(abs(a - b) <= TOL for a, b in zip(m["dims"], spec["size"])), f"{m['dims']} vs {spec['size']}")
        add("origin_bottom_centre", abs(m["low"][2]) <= TOL and all(abs(m["low"][i] + m["dims"][i] / 2) <= TOL for i in (0, 1)), str(m["low"]))
        add("identity_transforms", m["location"] == [0, 0, 0] and m["rotation"] == [0, 0, 0] and m["scale"] == [1, 1, 1])
        add("blender_closed_mesh", m["open_edges"] == 0 and m["non_manifold_edges"] == 0 and m["signed_volume"] > 0)
        add("no_ngons", m["ngons"] == 0, f"{m['ngons']} n-gons")
        add("uvs_in_range", m["uv_in_range"] and m["uv_layers"] == 1)
        add("single_material", len(m["materials"]) == 1, str(m["materials"]))
    else:
        add("blender_stage", False, "Blender stage did not run", manual=True)
    check_path = asset_dir / "export_check.json"
    if check_path.exists():
        c = json.loads(check_path.read_text())
        for kind in layout["exports"]:
            r = c.get(kind, {})
            ok = r.get("objects") == 1 and all(abs(a - b) <= TOL * 5 for a, b in zip(r.get("dims", []), _expected_dims(kind, spec["size"])))
            add(f"reimport_{kind}", ok and r.get("uv_layers", 0) >= 1, json.dumps({k: r.get(k) for k in ("objects", "dims", "tris", "uv_layers")}))
        add("blend_reopens_relative_paths", c["blend"]["reopens"] and c["blend"]["texture_paths_relative"])
    else:
        add("reimport", False, "verify stage did not run", manual=True)
    if layout.get("stretched"):
        add("generator_proportions", False, "Built at reference proportions and stretched to size; check art distortion.", manual=True)
    add("visual_inspection", False, "Open views/ and the contact sheet and look at every side.", manual=True)
    add("roblox_studio_import", False, "Not run by this script. Follow docs/workflows/studio-validation.md.", manual=True)
    return checks


def _expected_dims(kind, size):
    w, d, h = size
    # OBJ (-Z forward, Y up) and glTF (+Y up) re-import into Blender as Z-up again, so dims match.
    return [w, d, h]


def contact_sheet(asset_dirs, out):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        return "SKIPPED: Pillow not installed (pip install pillow) - inspect views/ folders instead"
    tiles = [(d.name, d / "views" / "hero.png") for d in asset_dirs if (d / "views" / "hero.png").exists()]
    if not tiles:
        return "SKIPPED: no renders"
    cell, cols = 256, min(4, len(tiles))
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 24)), (236, 238, 242))
    draw = ImageDraw.Draw(sheet)
    for i, (name, path) in enumerate(tiles):
        img = Image.open(path).convert("RGBA").resize((cell, cell))
        x, y = (i % cols) * cell, (i // cols) * (cell + 24)
        sheet.paste(img, (x, y), img)
        draw.text((x + 8, y + cell + 4), name, fill=(30, 30, 40))
    sheet.save(out)
    return str(out)


def load_status(out):
    p = out / "status.json"
    return json.loads(p.read_text()) if p.exists() else {"assets": {}}


def save_status(out, status):
    (out / "status.json").write_text(json.dumps(status, indent=1))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("batch", nargs="?", help="batch spec JSON")
    ap.add_argument("--out", help="output folder")
    ap.add_argument("--only", nargs="*", help="asset names to (re)build")
    ap.add_argument("--skip-blender", action="store_true", help="layout and texture only")
    ap.add_argument("--no-renders", action="store_true")
    ap.add_argument("--blender", help="path to Blender (default: auto-detect)")
    ap.add_argument("--status", metavar="OUT")
    ap.add_argument("--approve", nargs=2, metavar=("ASSET", "OUT"), help="record the user's approval given in chat")
    a = ap.parse_args(argv)

    if a.status:
        print(json.dumps(load_status(Path(a.status)), indent=1))
        return 0
    if a.approve:
        name, out = a.approve[0], Path(a.approve[1])
        status = load_status(out)
        entry = status["assets"].get(name)
        if not entry:
            raise SystemExit(f"{name} is not in {out}/status.json")
        if entry["state"] != "awaiting-approval":
            raise SystemExit(f"{name} is {entry['state']}; only an asset awaiting approval can be approved")
        entry.update(state="approved", approved_at=time.strftime("%Y-%m-%dT%H:%M:%S"))
        save_status(out, status)
        print(f"{name} approved")
        return 0
    if not a.batch or not a.out:
        ap.error("batch spec and --out are required")

    batch = json.loads(Path(a.batch).read_text())
    out = Path(a.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    blender = None if a.skip_blender else (a.blender or find_blender())
    status = load_status(out)
    dirs, failed = [], 0
    for spec in batch["assets"]:
        if a.only and spec["name"] not in a.only:
            continue
        if spec.get("texture") and not Path(spec["texture"]).is_absolute():
            spec = {**spec, "texture": str((Path(a.batch).parent / spec["texture"]).resolve())}
        asset_dir = out / spec["name"]
        dirs.append(asset_dir)
        print(f"== {spec['name']}")
        try:
            layout = make_layout(spec, str(asset_dir))
            print(f"   layout: {layout['geometry_check']['tris']} tris, {len(layout['rects'])} panels")
            if blender:
                run_blender(blender, "build_asset.py", asset_dir, ["--no-renders"] if a.no_renders else [])
                run_blender(blender, "verify_export.py", asset_dir)
                print("   blender: built, exported, re-imported")
            else:
                print("   blender: not found or skipped - geometry checked in Python only")
            checks = qa(spec, layout, asset_dir)
        except Exception as exc:  # report and continue with the rest of the batch
            checks = [{"check": "pipeline", "result": "FAIL", "detail": str(exc)}]
        (asset_dir / "qa.json").write_text(json.dumps(checks, indent=1)) if asset_dir.exists() else None
        fails = [c for c in checks if c["result"] == "FAIL"]
        failed += bool(fails)
        state = "failed" if fails else "awaiting-approval"
        status["assets"][spec["name"]] = {"state": state, "fails": [c["check"] for c in fails],
                                          "manual": [c["check"] for c in checks if c["result"] == "NEEDS MANUAL REVIEW"]}
        for c in checks:
            print(f"   {c['result']:<20} {c['check']}  {c['detail'][:90] if c['result'] != 'PASS' else ''}")
    status["contact_sheet"] = contact_sheet(dirs, out / "contact_sheet.png")
    save_status(out, status)
    print(f"contact sheet: {status['contact_sheet']}")
    print(f"{len(dirs) - failed} of {len(dirs)} assets awaiting approval, {failed} failed. Nothing is approved until the user says so.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
