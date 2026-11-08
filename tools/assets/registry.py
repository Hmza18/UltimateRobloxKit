#!/usr/bin/env python3
"""Smart asset registry: index every asset, find duplicates, and suggest what to reuse.

  python3 tools/assets/registry.py scan [roots...] [--out .urk/assets.json]   # default roots: assets/ examples/
  python3 tools/assets/registry.py search coin --kind image
  python3 tools/assets/registry.py dupes [--near 6]                           # exact and near-duplicate images
  python3 tools/assets/registry.py suggest "gold coin icon for the shop"       # reuse before you make

What is indexed: images (png, jpg), meshes (fbx, obj, glb), audio (ogg, mp3, wav), fonts (ttf, otf), Luau
modules and JSON specs. Each entry has a path, kind, size, sha256, tags (from the path and file name, split
on case and separators), the licence found beside it (LICENSE*, PROVENANCE.md, icons.json licenseNote) and,
for images when Pillow is available, a 64-bit difference hash for near-duplicate detection.

`dupes` reports identical files (same sha256) and visually near-identical images (hash distance <= --near).
`suggest` ranks existing assets by tag overlap with your words, so agents reuse an asset before generating a
new one. Standard library, plus Pillow for image hashes (skipped without it).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ROOTS = ["assets", "examples"]
DEFAULT_OUT = ROOT / ".urk" / "assets.json"
KINDS = {
    "image": {".png", ".jpg", ".jpeg"}, "mesh": {".fbx", ".obj", ".glb", ".gltf"},
    "audio": {".ogg", ".mp3", ".wav"}, "font": {".ttf", ".otf"}, "code": {".luau", ".lua"}, "spec": {".json"},
}
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".urk", "Packages", "ServerPackages"}
STOP = {"the", "a", "an", "for", "and", "of", "to", "in", "with", "my", "new", "png", "icon", "icons", "sheet", "default"}

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    Image = None


def kind_of(path: Path) -> str | None:
    ext = path.suffix.lower()
    for kind, exts in KINDS.items():
        if ext in exts:
            return kind
    return None


def words(text: str) -> list[str]:
    text = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", text)
    return [w for w in re.split(r"[^a-z0-9]+", text.lower()) if w and not w.isdigit()]


def tags_for(path: Path, root: Path) -> list[str]:
    rel = path.relative_to(root).with_suffix("")
    seen, out = set(), []
    for part in rel.parts:
        for w in words(part):
            if w not in seen and w not in STOP and len(w) > 1:
                seen.add(w)
                out.append(w)
    return out


def dhash(path: Path) -> str | None:
    if Image is None:
        return None
    try:
        with Image.open(path) as im:
            im = im.convert("RGBA")
            # Mid-grey backdrop, so white glyphs, black glyphs and colour art all keep their shape.
            bg = Image.new("RGBA", im.size, (128, 128, 128, 255))
            bg.alpha_composite(im)
            g = bg.convert("L").resize((9, 8), Image.LANCZOS)
            px = list(g.tobytes())
            avg = bg.convert("RGB").resize((1, 1), Image.BOX).getpixel((0, 0))
    except Exception:
        return None
    bits = 0
    for row in range(8):
        for col in range(8):
            bits = (bits << 1) | (1 if px[row * 9 + col] > px[row * 9 + col + 1] else 0)
    if bits == 0 or bits == (1 << 64) - 1:
        return None  # flat image: no shape to compare
    return f"{bits:016x}-{avg[0]:02x}{avg[1]:02x}{avg[2]:02x}"


def licence_for(path: Path, root: Path) -> str | None:
    for folder in [path.parent, *path.parent.parents]:
        for name in ("LICENSE.md", "LICENSE.txt", "LICENSE", "LICENSE-kenney.txt", "PROVENANCE.md"):
            f = folder / name
            if f.exists():
                text = f.read_text(errors="ignore")
                m = re.search(r"(CC0|CC-BY[- ][0-9.]+|MIT|Apache[- ]2\.0|OFL|SIL Open Font)", text)
                return f"{m.group(1) if m else 'see file'} ({f.relative_to(ROOT) if f.is_relative_to(ROOT) else f})"
        catalog = folder / "icons.json"
        if catalog.exists():
            try:
                note = json.loads(catalog.read_text()).get("licenseNote") or json.loads(catalog.read_text()).get("license")
            except json.JSONDecodeError:
                note = None
            if note:
                return str(note)[:80]
        if folder == root or folder == ROOT:
            break
    return None


def scan(roots: list[Path]) -> dict:
    entries = []
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*")):
            if not path.is_file() or any(p in SKIP_DIRS for p in path.parts):
                continue
            kind = kind_of(path)
            if kind is None:
                continue
            data = path.read_bytes()
            base = ROOT if path.is_relative_to(ROOT) else root
            entry = {"path": path.relative_to(base).as_posix(), "kind": kind, "bytes": len(data),
                     "sha256": hashlib.sha256(data).hexdigest(), "tags": tags_for(path, root),
                     "licence": licence_for(path, root)}
            if kind == "image":
                entry["dhash"] = dhash(path)
            entries.append(entry)
    return {"version": 1, "roots": [str(r) for r in roots], "count": len(entries), "assets": entries}


def load(out: Path) -> dict:
    if not out.exists():
        sys.exit(f"{out} not found: run `registry.py scan` first")
    return json.loads(out.read_text())


def hamming(a: str, b: str) -> int:
    """Shape distance in bits, or 99 when the average colours differ noticeably (colour variants)."""
    shape_a, _, colour_a = a.partition("-")
    shape_b, _, colour_b = b.partition("-")
    if colour_a and colour_b:
        ca = [int(colour_a[i:i + 2], 16) for i in (0, 2, 4)]
        cb = [int(colour_b[i:i + 2], 16) for i in (0, 2, 4)]
        if max(abs(x - y) for x, y in zip(ca, cb)) > 24:
            return 99
    return bin(int(shape_a, 16) ^ int(shape_b, 16)).count("1")


def dupes(reg: dict, near: int) -> dict:
    by_sha: dict[str, list[str]] = {}
    for e in reg["assets"]:
        by_sha.setdefault(e["sha256"], []).append(e["path"])
    exact = [paths for paths in by_sha.values() if len(paths) > 1]
    images = [e for e in reg["assets"] if e.get("dhash") and e["bytes"] > 0]
    similar = []
    seen_pairs = set()
    for i, a in enumerate(images):
        for b in images[i + 1:]:
            if a["sha256"] == b["sha256"] or (a["path"], b["path"]) in seen_pairs:
                continue
            d = hamming(a["dhash"], b["dhash"])
            if d <= near:
                seen_pairs.add((a["path"], b["path"]))
                similar.append({"a": a["path"], "b": b["path"], "distance": d})
    similar.sort(key=lambda s: s["distance"])
    return {"exact": exact, "similar": similar}


def score(entry: dict, query: list[str]) -> float:
    tags = entry["tags"]
    s = 0.0
    for q in query:
        for t in tags:
            if t == q:
                s += 3
            elif t.startswith(q) or q.startswith(t) and len(t) >= 3:
                s += 1
    return s


def search(reg: dict, text: str, kind: str | None, limit: int) -> list[dict]:
    query = [w for w in words(text) if w not in STOP] or words(text)
    ranked = [(score(e, query), e) for e in reg["assets"] if kind is None or e["kind"] == kind]
    ranked = [r for r in ranked if r[0] > 0]
    ranked.sort(key=lambda r: (-r[0], r[1]["path"]))
    return [dict(e, score=s) for s, e in ranked[:limit]]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_scan = sub.add_parser("scan")
    p_scan.add_argument("roots", nargs="*", type=Path)
    p_scan.add_argument("--out", type=Path, default=DEFAULT_OUT)
    for name in ("search", "suggest"):
        p = sub.add_parser(name)
        p.add_argument("query", nargs="+")
        p.add_argument("--kind", choices=sorted(KINDS))
        p.add_argument("--limit", type=int, default=10)
        p.add_argument("--registry", type=Path, default=DEFAULT_OUT)
        p.add_argument("--json", action="store_true")
    p_d = sub.add_parser("dupes")
    p_d.add_argument("--near", type=int, default=2, help="max hash distance for near duplicates (0-64)")
    p_d.add_argument("--registry", type=Path, default=DEFAULT_OUT)
    p_d.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    if a.cmd == "scan":
        roots = [r if r.is_absolute() else (Path.cwd() / r) for r in (a.roots or [ROOT / r for r in DEFAULT_ROOTS])]
        reg = scan(roots)
        a.out.parent.mkdir(parents=True, exist_ok=True)
        a.out.write_text(json.dumps(reg, indent=1) + "\n")
        kinds: dict[str, int] = {}
        for e in reg["assets"]:
            kinds[e["kind"]] = kinds.get(e["kind"], 0) + 1
        unlicensed = sum(1 for e in reg["assets"] if e["kind"] in ("image", "mesh", "audio", "font") and not e["licence"])
        print(f"{reg['count']} assets indexed -> {a.out}  " + ", ".join(f"{k} {v}" for k, v in sorted(kinds.items())))
        if Image is None:
            print("Pillow not installed: near-duplicate image hashes skipped")
        if unlicensed:
            print(f"{unlicensed} media files have no licence file beside them (see `search` output, licence column)")
        return 0
    reg = load(a.registry)
    if a.cmd in ("search", "suggest"):
        hits = search(reg, " ".join(a.query), a.kind, a.limit)
        if a.json:
            print(json.dumps(hits, indent=1))
            return 0
        if not hits:
            print("no existing asset matches; making a new one is reasonable" if a.cmd == "suggest" else "no match")
            return 0
        if a.cmd == "suggest":
            print("Reuse before you make. Closest existing assets:")
        for h in hits:
            print(f"{h['score']:4.0f}  {h['kind']:6} {h['path']}  [{' '.join(h['tags'][:6])}]  {h['licence'] or 'no licence found'}")
        return 0
    result = dupes(reg, a.near)
    if a.json:
        print(json.dumps(result, indent=1))
        return 0
    for group in result["exact"]:
        print("identical: " + "  ==  ".join(group))
    for s in result["similar"][:200]:
        print(f"similar (distance {s['distance']}): {s['a']}  ~  {s['b']}")
    print(f"{len(result['exact'])} identical groups, {len(result['similar'])} near-duplicate pairs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
