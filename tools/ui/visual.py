#!/usr/bin/env python3
"""Visual UI loop tools: reference image -> spec hints, and capture vs reference -> rubric score.

  python3 tools/ui/visual.py extract reference.png [--json hints.json]
  python3 tools/ui/visual.py compare reference.png capture.png [--json score.json] [--diff diff.png]

`extract` reads a reference screenshot (yours, or one you have the right to use as a reference; it is not
copied into the output) and reports what a screen spec needs: the dominant colours mapped to the nearest
kit palettes, background brightness, saturation, outline darkness and weight, aspect ratio, and a coarse
layout grid (which regions are busy). It suggests `style`, `palette` and layout choices for a spec.

`compare` scores a capture (from `urk ui preview` + capture_server.py, or a Studio screenshot) against the
reference with a fixed rubric. Each part is 0-100, the total is a weighted mean:

  palette 30   nearest-colour distance between the two images' dominant colours
  layout 25    similarity of the 24x24 edge maps (where things are)
  contrast 15  brightness and contrast difference
  outline 15   dark-edge ratio difference (chunky outlined cartoon look)
  colour 15    saturation difference

The scores measure resemblance in style, not quality and not legal similarity: never use this to make a
near copy of someone else's design. Pillow is required. Nothing here takes screenshots: captures come from
the preview capture server or from Studio, and reports name the capture file they scored.
"""
from __future__ import annotations

import argparse
import colorsys
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

try:
    from PIL import Image, ImageChops, ImageFilter, ImageStat
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: python3 -m pip install pillow")

WEIGHTS = {"palette": 30, "layout": 25, "contrast": 15, "outline": 15, "colour": 15}
GRID = 24


def load(path: Path, size: int = 384) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    bg = Image.new("RGBA", im.size, (0, 0, 0, 255))
    bg.alpha_composite(im)
    rgb = bg.convert("RGB")
    rgb.thumbnail((size, size), Image.LANCZOS)
    return rgb


def hexof(rgb) -> str:
    return "#{:02X}{:02X}{:02X}".format(*[int(c) for c in rgb[:3]])


def rgb_of(hex_: str):
    hex_ = hex_.lstrip("#")
    return tuple(int(hex_[i:i + 2], 16) for i in (0, 2, 4))


def dominant(im: Image.Image, k: int = 6) -> list[dict]:
    q = im.quantize(colors=k, method=Image.Quantize.MEDIANCUT)
    pal = q.getpalette()[: k * 3]
    counts = sorted(q.getcolors(), reverse=True)
    total = sum(c for c, _ in counts)
    out = []
    for count, idx in counts:
        rgb = tuple(pal[idx * 3: idx * 3 + 3])
        out.append({"hex": hexof(rgb), "share": round(count / total, 3)})
    return out


def accents(im: Image.Image, k: int = 8) -> tuple[list[dict], float]:
    """Dominant colours among saturated pixels only (cards, buttons, badges), and their share of the image."""
    small = im.resize((128, max(1, round(128 * im.height / im.width))), Image.BOX)
    raw = small.tobytes()
    picked = []
    for i in range(0, len(raw), 3):
        r, g, b = raw[i], raw[i + 1], raw[i + 2]
        _, sat, val = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if sat > 0.45 and val > 0.35:
            picked.append((r, g, b))
    share = len(picked) / max(1, len(raw) // 3)
    if len(picked) < 16:
        return [], share
    strip = Image.new("RGB", (len(picked), 1))
    strip.putdata(picked)
    return dominant(strip, k), share


def distance(a, b) -> float:
    # Weighted RGB ("redmean") distance: cheap and close enough to perceptual for palette matching.
    r = (a[0] + b[0]) / 2
    dr, dg, db = a[0] - b[0], a[1] - b[1], a[2] - b[2]
    return math.sqrt((2 + r / 256) * dr * dr + 4 * dg * dg + (2 + (255 - r) / 256) * db * db)


def kit_palettes(style: str = "cartoon") -> dict:
    try:
        from spec_rules import resolve_palettes
        return resolve_palettes(style)
    except Exception:
        return {}


def nearest_palette(hex_: str, palettes: dict) -> tuple[str | None, float]:
    best, best_d = None, 1e9
    rgb = rgb_of(hex_)
    for name, sw in palettes.items():
        for key in ("top", "bottom"):
            if key in sw:
                d = distance(rgb, rgb_of(sw[key]))
                if d < best_d:
                    best, best_d = name, d
    return best, best_d


def edges(im: Image.Image) -> Image.Image:
    return im.convert("L").filter(ImageFilter.FIND_EDGES).resize((GRID, GRID), Image.BOX)


def outline_ratio(im: Image.Image) -> float:
    """Share of strong edge pixels that sit on dark colour: high for outlined cartoon art."""
    gray = im.convert("L")
    edge = gray.filter(ImageFilter.FIND_EDGES)
    # An edge counts as outlined when the darkest pixel next to it is dark.
    e, g = edge.tobytes(), gray.filter(ImageFilter.MinFilter(3)).tobytes()
    strong = [i for i, v in enumerate(e) if v > 60]
    if not strong:
        return 0.0
    dark = sum(1 for i in strong if g[i] < 70)
    return dark / len(strong)


def saturation(im: Image.Image) -> float:
    small = im.resize((48, 48), Image.BOX)
    raw = small.tobytes()
    vals = [colorsys.rgb_to_hsv(raw[i] / 255, raw[i + 1] / 255, raw[i + 2] / 255)[1] for i in range(0, len(raw), 3)]
    return sum(vals) / len(vals)


def stats(im: Image.Image) -> dict:
    st = ImageStat.Stat(im.convert("L"))
    return {"brightness": st.mean[0] / 255, "contrast": st.stddev[0] / 128}


def busy_grid(im: Image.Image, cells: int = 3) -> list[list[float]]:
    e = im.convert("L").filter(ImageFilter.FIND_EDGES).resize((cells, cells), Image.BOX)
    raw = e.tobytes()
    return [[round(raw[r * cells + c] / 255, 3) for c in range(cells)] for r in range(cells)]


def extract(path: Path, style: str = "cartoon") -> dict:
    full = Image.open(path)
    im = load(path)
    colours = dominant(im)
    pals = kit_palettes(style)
    for c in colours:
        name, d = nearest_palette(c["hex"], pals)
        c["nearestPalette"], c["paletteDistance"] = name, round(d, 1)
    st = stats(im)
    sat = saturation(im)
    outline = outline_ratio(im)
    accent_colours, accent_share = accents(im)
    for c in accent_colours:
        name, d = nearest_palette(c["hex"], pals)
        c["nearestPalette"], c["paletteDistance"] = name, round(d, 1)
    picked = [c for c in accent_colours if c["nearestPalette"] and c["share"] > 0.04]
    suggestion = {
        "style": "cartoon" if outline > 0.3 and accent_share > 0.15 else "clean",
        "palettes": list(dict.fromkeys(c["nearestPalette"] for c in picked))[:6],
        "background": "dark" if st["brightness"] < 0.4 else "light",
        "layout": "grid" if sum(sum(r) for r in busy_grid(im)) > 1.2 else "panel",
    }
    return {
        "source": str(path), "size": list(full.size), "aspect": round(full.size[0] / full.size[1], 3),
        "dominantColours": colours, "accentColours": accent_colours, "accentShare": round(accent_share, 3),
        "brightness": round(st["brightness"], 3), "contrast": round(st["contrast"], 3),
        "saturation": round(sat, 3), "outlineRatio": round(outline, 3), "busyGrid": busy_grid(im),
        "suggestion": suggestion,
    }


def palette_score(a: Image.Image, b: Image.Image) -> float:
    ca, cb = dominant(a), dominant(b)
    total = 0.0
    for c in ca:
        best = min(distance(rgb_of(c["hex"]), rgb_of(d["hex"])) for d in cb)
        total += c["share"] * best
    # 0 distance -> 100, ~250 (very different colours) -> 0
    return max(0.0, 100 - total / 2.5)


def layout_score(a: Image.Image, b: Image.Image) -> float:
    ea, eb = edges(a), edges(b)
    diff = ImageChops.difference(ea, eb)
    mean = ImageStat.Stat(diff).mean[0]
    return max(0.0, 100 - mean * 2)


def compare(ref: Path, cap: Path, diff_out: Path | None = None) -> dict:
    a, b = load(ref), load(cap)
    b = b.resize(a.size, Image.LANCZOS)
    sa, sb = stats(a), stats(b)
    parts = {
        "palette": palette_score(a, b),
        "layout": layout_score(a, b),
        "contrast": max(0.0, 100 - (abs(sa["brightness"] - sb["brightness"]) + abs(sa["contrast"] - sb["contrast"])) * 150),
        "outline": max(0.0, 100 - abs(outline_ratio(a) - outline_ratio(b)) * 200),
        "colour": max(0.0, 100 - abs(saturation(a) - saturation(b)) * 250),
    }
    total = sum(parts[k] * w for k, w in WEIGHTS.items()) / sum(WEIGHTS.values())
    notes = []
    if parts["palette"] < 70:
        notes.append("colours differ: run `extract` on the reference and use its suggested palettes")
    if parts["layout"] < 70:
        notes.append("layout differs: compare busyGrid; move or resize the main panel and grid")
    if parts["outline"] < 70:
        notes.append("outline weight differs: change style outline (thin/regular/thick/heavy)")
    if parts["colour"] < 70:
        notes.append("saturation differs: pick more (or less) saturated palettes")
    if parts["contrast"] < 70:
        notes.append("brightness/contrast differs: check the background and surface colours")
    if diff_out:
        pair = Image.new("RGB", (a.width * 3, a.height), (0, 0, 0))
        pair.paste(a, (0, 0))
        pair.paste(b, (a.width, 0))
        pair.paste(ImageChops.difference(a, b), (a.width * 2, 0))
        pair.save(diff_out)
    return {"reference": str(ref), "capture": str(cap), "scores": {k: round(v, 1) for k, v in parts.items()},
            "weights": WEIGHTS, "total": round(total, 1), "notes": notes, "diff": str(diff_out) if diff_out else None}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("extract")
    e.add_argument("image", type=Path)
    e.add_argument("--style", default="cartoon")
    e.add_argument("--json", type=Path)
    c = sub.add_parser("compare")
    c.add_argument("reference", type=Path)
    c.add_argument("capture", type=Path)
    c.add_argument("--json", type=Path)
    c.add_argument("--diff", type=Path, help="write reference | capture | difference side by side")
    c.add_argument("--min", type=float, default=None, help="exit 1 when the total is below this")
    a = ap.parse_args(argv)
    if a.cmd == "extract":
        result = extract(a.image, a.style)
    else:
        result = compare(a.reference, a.capture, a.diff)
    text = json.dumps(result, indent=1)
    if a.json:
        a.json.write_text(text + "\n")
    print(text)
    if a.cmd == "compare" and a.min is not None and result["total"] < a.min:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
