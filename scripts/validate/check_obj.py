#!/usr/bin/env python3
"""Check an OBJ without Blender: triangle count, closedness, consistent winding, bounds, UVs.

  python3 scripts/validate/check_obj.py model.obj --max-tris 400 [--json]

Vertices are welded by position first, because exporters split vertices at UV seams.
Exit 1 on FAIL. The OBJ is expected in the kit's export axes (Y up), so height = Y extent.
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict


def analyse(path):
    verts, faces, uvs = [], [], 0
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "v":
                verts.append(tuple(float(x) for x in parts[1:4]))
            elif parts[0] == "vt":
                uvs += 1
            elif parts[0] == "f":
                faces.append([int(p.split("/")[0]) for p in parts[1:]])
    key = {}
    weld = []
    for v in verts:
        k = tuple(round(c, 5) for c in v)
        weld.append(key.setdefault(k, len(key)))

    def idx(i):
        return weld[(i - 1) if i > 0 else len(verts) + i]

    edges = defaultdict(lambda: [0, 0])
    tris = 0
    for f in faces:
        f = [idx(i) for i in f]
        tris += len(f) - 2
        for i in range(len(f)):
            a, b = f[i], f[(i + 1) % len(f)]
            if a != b:
                edges[(min(a, b), max(a, b))][0 if a < b else 1] += 1
    open_edges = sum(1 for a, b in edges.values() if a + b == 1)
    non_manifold = sum(1 for a, b in edges.values() if a + b > 2)
    inconsistent = sum(1 for a, b in edges.values() if a + b == 2 and a != b)
    lo = [min(v[i] for v in verts) for i in range(3)] if verts else [0, 0, 0]
    hi = [max(v[i] for v in verts) for i in range(3)] if verts else [0, 0, 0]
    return {"tris": tris, "verts": len(verts), "faces": len(faces), "uvs": uvs, "open_edges": open_edges,
            "non_manifold_edges": non_manifold, "inconsistent_edges": inconsistent,
            "size_xyz": [round(hi[i] - lo[i], 4) for i in range(3)], "min_y": round(lo[1], 4)}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("obj")
    ap.add_argument("--max-tris", type=int, default=20000)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    r = analyse(a.obj)
    r["checks"] = {
        "closed": r["open_edges"] == 0 and r["non_manifold_edges"] == 0,
        "consistent_winding": r["inconsistent_edges"] == 0,
        "within_budget": r["tris"] <= a.max_tris,
        "has_uvs": r["uvs"] > 0,
        "sits_on_ground": abs(r["min_y"]) < 1e-3,
    }
    ok = all(r["checks"].values())
    if a.json:
        print(json.dumps(r, indent=1))
    else:
        for k, v in r["checks"].items():
            print(f"{'PASS' if v else 'FAIL':5} {k}")
        print(f"tris={r['tris']} size(x,y,z)={r['size_xyz']}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
