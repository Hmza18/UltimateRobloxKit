#!/usr/bin/env python3
"""Render URK Icons into Roblox-ready files. Needs Pillow (`python3 -m pip install pillow`).

  python3 tools/icons/build_icons.py            # write assets/icons/urk/** and library/src/Icons/IconData.luau
  python3 tools/icons/build_icons.py --check    # exit 1 if committed outputs differ from a fresh build (CI)

Outputs
  assets/icons/urk/png/<name>.png      256 px single icons (white glyph, transparent), for upload or docs
  assets/icons/urk/sheet-<n>.png       1024 px sprite sheets, 8 x 8 cells of 128 px, for one upload each
  assets/icons/urk/icons.json          catalog: name, category, tags, sheet, cell rect
  assets/icons/urk/preview.png         labelled gallery, dark and light rows
  library/src/Icons/IconData.luau      the same catalog as Luau, read by Icons.luau
"""
from __future__ import annotations

import argparse
import io
import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: python3 -m pip install pillow")

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from illustrate import REGIONS, color_for, hex_rgb, illustrate  # noqa: E402
from urk_icons import ICONS, Pen  # noqa: E402

# Colour variants of illustrated icons: base icon -> {variant name: base colour}. Each becomes
# "<base>-<variant>" in the colour style, for rarity eggs, gem tiers, medal places and so on.
VARIANTS = {
    "gem": {"red": "#FF4D6D", "green": "#4CD964", "blue": "#3D8BFF", "purple": "#B05CFF", "pink": "#FF7AC8", "gold": "#FFC21B"},
    "egg": {"common": "#E6EAF2", "uncommon": "#7CF05A", "rare": "#5AB8FF", "epic": "#B98CFF", "legendary": "#FFB020", "mythic": "#FF4D6D"},
    "potion": {"red": "#FF4D4D", "green": "#4CD964", "blue": "#3D8BFF", "yellow": "#FFD23F"},
    "medal": {"gold": "#F7C21B", "silver": "#C9D6E6", "bronze": "#D9894A"},
    "coin": {"silver": "#C9D6E6", "bronze": "#D9894A"},
    "trophy": {"silver": "#C9D6E6", "bronze": "#D9894A"},
    "key": {"silver": "#C9D6E6", "blue": "#3D8BFF"},
    "chest": {"gold": "#F7C21B", "purple": "#B05CFF"},
    "shield": {"red": "#FF4D4D", "green": "#4CD964", "gold": "#F7C21B"},
    "pet": {"orange": "#FF9A2E", "gray": "#9FB3C8", "pink": "#FF7AC8"},
    "boost": {"green": "#4CD964", "purple": "#B05CFF"},
    "ticket": {"gold": "#F7C21B"},
}

OUT = ROOT / "assets" / "icons" / "urk"
LUAU = ROOT / "library" / "src" / "Icons" / "IconData.luau"
CELL, SHEET, SUPER = 128, 1024, 4
PER_SHEET = (SHEET // CELL) ** 2
CATEGORIES = ["currency", "rewards", "actions", "status", "interface", "items", "stats", "social"]
PAD = 8  # transparent margin inside each 128 cell, so filtering never bleeds between icons


def glyph_mask(name: str, big: int, inset: float = 0.0) -> Image.Image:
    """The glyph drawn at `big` px; with inset, shrunk into the centre to leave room for outlines."""
    mask = Image.new("L", (big, big), 0)
    scale = 1 - 2 * inset
    draw = Image.new("L", (big, big), 0)
    ICONS[name]["draw"](Pen(ImageDraw.Draw(draw), big * scale / 100))
    mask.paste(draw.crop((0, 0, int(big * scale), int(big * scale))), (int(big * inset), int(big * inset)))
    return mask


# Automatic alignment: every icon's art is centred and its largest side scaled to this share of the
# canvas, so icons line up in rows and buttons whatever their drawn position on the design grid.
TARGET_EXTENT = {"glyph": 0.84, "color": 0.9}


def normalize(img: Image.Image, extent: float) -> Image.Image:
    box = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if not box:
        return img
    art = img.crop(box)
    size = img.width
    scale = extent * size / max(art.width, art.height)
    art = art.resize((max(1, round(art.width * scale)), max(1, round(art.height * scale))), Image.LANCZOS)
    out = Image.new("RGBA", img.size, (255, 255, 255, 0))
    out.alpha_composite(art, ((size - art.width) // 2, (size - art.height) // 2))
    return out


def render(name: str, size: int, style: str = "glyph", color=None) -> Image.Image:
    return normalize(_render(name, size, style, color), TARGET_EXTENT[style])


def _render(name: str, size: int, style: str = "glyph", color=None) -> Image.Image:
    big = size * (2 if style == "color" else SUPER)
    if style == "color":
        inset = 0.06  # leaves room for the outline and shadow while filling the cell like the reference art
        k = 1 - 2 * inset
        regions = [((x0 * k + inset * 100, y0 * k + inset * 100, x1 * k + inset * 100, y1 * k + inset * 100), c)
                   for (x0, y0, x1, y1), c in REGIONS.get(name, [])]
        art = illustrate(glyph_mask(name, big, inset), color or color_for(name, ICONS[name]["category"]), regions)
        return art.resize((size, size), Image.LANCZOS)
    mask = glyph_mask(name, big).resize((size, size), Image.LANCZOS)
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    img.putalpha(mask)
    return img


def all_entries():
    """(name, base glyph, style, category, tags, colour) for every icon in sheet order."""
    out = []
    for n in ordered_names():
        meta = ICONS[n]
        out.append((n, n, "glyph", meta["category"], meta["tags"], None))
    for n in ordered_names():
        meta = ICONS[n]
        out.append((f"{n}-color", n, "color", meta["category"], meta["tags"], None))
        for variant, hexcol in VARIANTS.get(n, {}).items():
            out.append((f"{n}-{variant}", n, "color", meta["category"], meta["tags"] + [variant], hex_rgb(hexcol)))
    return out


def png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def ordered_names():
    for name, meta in ICONS.items():
        if meta["category"] not in CATEGORIES:
            raise SystemExit(f"{name}: unknown category {meta['category']}")
    return sorted(ICONS, key=lambda n: (CATEGORIES.index(ICONS[n]["category"]), n))


def build():
    entries = all_entries()
    files: dict[str, bytes] = {}
    catalog = {"name": "URK Icons", "version": 1, "license": "MIT", "author": "UltimateRobloxKit contributors",
               "cell": CELL, "sheetSize": SHEET, "padding": PAD, "categories": CATEGORIES, "sheets": [], "icons": []}
    sheets = []
    for i, (name, base, style, category, tags, color) in enumerate(entries):
        sheet_index, slot = divmod(i, PER_SHEET)
        if sheet_index == len(sheets):
            sheets.append(Image.new("RGBA", (SHEET, SHEET), (255, 255, 255, 0)))
        x, y = (slot % (SHEET // CELL)) * CELL, (slot // (SHEET // CELL)) * CELL
        glyph = render(base, CELL - 2 * PAD, style, color)
        sheets[sheet_index].alpha_composite(glyph, (x + PAD, y + PAD))
        files[f"png/{name}.png"] = png_bytes(render(base, 256, style, color))
        catalog["icons"].append({"name": name, "base": base, "style": style, "category": category, "tags": tags,
                                 "sheet": sheet_index + 1, "x": x, "y": y, "w": CELL, "h": CELL})
    for i, sheet in enumerate(sheets, 1):
        files[f"sheet-{i}.png"] = png_bytes(sheet)
        catalog["sheets"].append({"file": f"sheet-{i}.png", "assetId": None})
    files["icons.json"] = (json.dumps(catalog, indent=1) + "\n").encode()
    files["preview.png"] = png_bytes(preview(ordered_names()))
    files["preview-color.png"] = png_bytes(preview_color([e[0] for e in entries if e[2] == "color"], entries))
    return files, catalog


def preview(names):
    cols, cell, label = 10, 96, 18
    rows = (len(names) + cols - 1) // cols
    img = Image.new("RGB", (cols * cell, rows * (cell + label) * 2), (240, 242, 246))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.load_default(size=11)
    except TypeError:
        font = ImageFont.load_default()
    for band, (bg, tint, text) in enumerate((((30, 33, 40), (255, 255, 255), (200, 205, 215)),
                                              ((250, 250, 252), (40, 44, 52), (90, 95, 105)))):
        y0 = band * rows * (cell + label)
        draw.rectangle([0, y0, cols * cell, y0 + rows * (cell + label)], fill=bg)
        for i, name in enumerate(names):
            x, y = (i % cols) * cell, y0 + (i // cols) * (cell + label)
            glyph = render(name, 56)
            solid = Image.new("RGBA", glyph.size, tint + (255,))
            solid.putalpha(glyph.getchannel("A"))
            img.paste(solid, (x + 20, y + 16), solid)
            draw.text((x + cell / 2, y + cell - 4), name, fill=text, font=font, anchor="ms")
    return img


def preview_color(names, entries):
    """Illustrated icons on the reference grey, labelled, like an artist's sheet."""
    by_name = {e[0]: e for e in entries}
    cols, cell, label = 12, 92, 16
    rows = (len(names) + cols - 1) // cols
    img = Image.new("RGBA", (cols * cell, rows * (cell + label)), (74, 74, 74, 255))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.load_default(size=10)
    except TypeError:
        font = ImageFont.load_default()
    for i, name in enumerate(names):
        _, base, style, _, _, color = by_name[name]
        art = render(base, 72, style, color)
        x, y = (i % cols) * cell, (i // cols) * (cell + label)
        img.alpha_composite(art, (x + 10, y + 6))
        draw.text((x + cell / 2, y + cell + 6), name, fill=(220, 224, 232), font=font, anchor="ms")
    return img


def luau(catalog) -> str:
    lines = ["--!strict", "-- Generated by tools/icons/build_icons.py from assets/icons/urk/icons.json. Do not edit.",
             "-- Upload each sheet once, then set its asset id with Icons.configure({ sheets = { \"rbxassetid://...\" } }).", "",
             "export type IconEntry = {",
             "\tname: string,", "\tbase: string?,", "\tstyle: string?,", "\tcategory: string,", "\ttags: { string },",
             "\tsheet: number,", "\tx: number,", "\ty: number,", "\tw: number,", "\th: number,", "}",
             "", "return {", f"\tcell = {catalog['cell']},", f"\tpadding = {catalog['padding']},",
             "\tsheetCount = %d," % len(catalog["sheets"]),
             "\tcategories = { %s }," % ", ".join(f'"{c}"' for c in catalog["categories"]), "\ticons = {"]
    for e in catalog["icons"]:
        tags = ", ".join(f'"{t}"' for t in e["tags"])
        lines.append(f'\t\t{{ name = "{e["name"]}", base = "{e["base"]}", style = "{e["style"]}", category = "{e["category"]}", '
                     f'tags = {{ {tags} }}, sheet = {e["sheet"]}, x = {e["x"]}, y = {e["y"]}, w = {e["w"]}, h = {e["h"]} }},')
    lines += ["\t} :: { IconEntry },", "}", ""]
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    files, catalog = build()
    targets = {OUT / k: v for k, v in files.items()}
    targets[LUAU] = luau(catalog).encode()
    if a.check:
        stale = [p for p, v in targets.items() if not p.exists() or (p.suffix != ".png" and p.read_bytes() != v)]
        for p in stale:
            print(f"stale: {p.relative_to(ROOT)}")
        return 1 if stale else 0
    for p, v in targets.items():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(v)
    print(f"{len(catalog['icons'])} icons, {len(catalog['sheets'])} sheet(s) -> {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
