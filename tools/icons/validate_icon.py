#!/usr/bin/env python3
"""Check icon PNGs against the kit's illustrated style before importing them. Needs Pillow.

  python3 tools/icons/validate_icon.py path/to/icons/*.png [--json] [--min-size 128]

Use it on hand-drawn icons, outsourced art or image-generator output (see the roblox-icon-design
skill for the generation workflow). Checks, each PASS or FAIL with a number:
  format        PNG, RGBA, square, at least --min-size px
  transparent   the corners and border are fully transparent (no baked background)
  size          the art's largest side fills 62-96% of the canvas, every margin >= 2% (consistent sizing)
  centred       the art's bounding box is centred within 6% (optical alignment in rows and buttons)
  outline       most edge pixels of the silhouette are dark (the thick dark outline of the style)
  saturation    the body is not greyscale (mean saturation >= 0.06; white or silver items are allowed);
                glyph packs: --glyph skips this and the outline check
  coverage      the art fills 7-85% of the canvas (not a speck, not a block)
Exit 1 if any icon fails. Fix the art rather than loosening a check, unless the style changed.
"""
from __future__ import annotations

import argparse
import colorsys
import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageFilter
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: python3 -m pip install pillow")


def check(path: Path, min_size: int = 128, glyph: bool = False):
    results = {}

    def add(name, ok, value):
        results[name] = {"ok": bool(ok), "value": value}

    img = Image.open(path)
    add("format", img.format == "PNG" and img.mode == "RGBA" and img.width == img.height and img.width >= min_size,
        f"{img.format} {img.mode} {img.width}x{img.height}")
    img = img.convert("RGBA")
    w, h = img.size
    alpha = img.getchannel("A")
    border = [alpha.getpixel((x, y)) for x in range(w) for y in (0, h - 1)] + \
             [alpha.getpixel((x, y)) for y in range(h) for x in (0, w - 1)]
    add("transparent", max(border) <= 8, f"max border alpha {max(border)}")
    box = alpha.point(lambda v: 255 if v > 32 else 0).getbbox()
    if not box:
        add("padding", False, "empty image")
        return results
    margins = [box[0] / w, box[1] / h, (w - box[2]) / w, (h - box[3]) / h]
    extent = max((box[2] - box[0]) / w, (box[3] - box[1]) / h)
    add("size", 0.62 <= extent <= 0.96 and min(margins) >= 0.02, f"largest side {extent:.2f}, min margin {min(margins):.2f}")
    small = img.resize((64, 64), Image.BILINEAR)
    a = small.getchannel("A")
    total = sx = sy = 0
    for y in range(64):
        for x in range(64):
            v = a.getpixel((x, y))
            total += v
            sx += x * v
            sy += y * v
    cx, cy = sx / total / 64, sy / total / 64
    bx, by = (box[0] + box[2]) / 2 / w, (box[1] + box[3]) / 2 / h
    add("centred", abs(bx - 0.5) <= 0.06 and abs(by - 0.5) <= 0.06,
        f"box centre ({bx:.2f}, {by:.2f}), mass centre ({cx:.2f}, {cy:.2f})")
    coverage = total / (255 * 64 * 64)
    add("coverage", 0.07 <= coverage <= 0.85, f"{coverage:.2f}")
    if glyph:
        return results
    solid = alpha.point(lambda v: 255 if v > 128 else 0)
    edge = solid.filter(ImageFilter.FIND_EDGES)
    rgb = img.convert("RGB")
    dark = edges = 0
    sats = []
    step = max(1, w // 128)
    for y in range(0, h, step):
        for x in range(0, w, step):
            if edge.getpixel((x, y)):
                edges += 1
                r, g, b = rgb.getpixel((x, y))
                if (r + g + b) / 3 < 80:
                    dark += 1
            elif solid.getpixel((x, y)):
                r, g, b = rgb.getpixel((x, y))
                sats.append(colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[1])
    ratio = dark / edges if edges else 0
    add("outline", ratio >= 0.6, f"{ratio:.2f} of edge pixels dark")
    mean_sat = sum(sats) / len(sats) if sats else 0
    add("saturation", mean_sat >= 0.06, f"{mean_sat:.2f}")
    return results


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--min-size", type=int, default=128)
    ap.add_argument("--glyph", action="store_true", help="monochrome glyph pack: skip outline and saturation")
    a = ap.parse_args(argv)
    report, failed = {}, 0
    for f in a.files:
        r = check(f, a.min_size, a.glyph)
        report[str(f)] = r
        bad = [k for k, v in r.items() if not v["ok"]]
        failed += bool(bad)
        if not a.json:
            detail = ", ".join(f"{k}: {r[k]['value']}" for k in bad)
            print(f"{'FAIL' if bad else 'PASS'} {f}" + (f"  ({detail})" if bad else ""))
    if a.json:
        print(json.dumps(report, indent=1))
    if not a.json:
        print(f"{len(a.files) - failed} of {len(a.files)} icons pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
