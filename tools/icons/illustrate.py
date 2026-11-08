"""Illustrated ("-color") versions of URK Icons, in the chunky simulator style.

Recipe, applied to every glyph so the whole set stays consistent:
  1. silhouette = the glyph with its holes filled (flood fill from the border)
  2. shadow     = silhouette, offset down, dark, soft
  3. outline    = silhouette dilated by OUTLINE px, near-black (#1B1530)
  4. detail     = holes of the glyph, filled with a darker shade of the base colour
  5. body       = the glyph, filled with a vertical gradient (light top -> base -> darker bottom)
  6. gloss      = a soft white ellipse in the upper-left, clipped to the body
Colours come from PALETTE (per icon) with category defaults. Multi-part icons can name extra
regions in REGIONS: (bbox in 100-unit design space, colour) recolours the body inside that box.
"""
from __future__ import annotations

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUTLINE_COLOR = (27, 21, 48)
CATEGORY_COLORS = {
    "currency": "#F7C21B", "rewards": "#FFB020", "actions": "#3D8BFF", "status": "#3D8BFF",
    "interface": "#5AB8FF", "items": "#9AA4B8", "stats": "#FF5A5A",
}
PALETTE = {
    # currency and rewards
    "coin": "#F7C21B", "coins": "#F7C21B", "gem": "#41D7FF", "cash": "#3CCB4A", "ticket": "#FF7AC8",
    "token": "#B98CFF", "gift": "#FF5A5A", "chest": "#C9822F", "trophy": "#F7C21B", "medal": "#F7C21B",
    "crown": "#F7C21B", "star": "#FFD23F", "level-up": "#4CD964",
    "gem-stack": "#41D7FF", "money-bag": "#C9822F", "wallet": "#C9822F", "badge": "#FFB020", "event": "#FF8A3D",
    "rebirth": "#FFB020", "boost": "#9FB3C8", "egg-cracked": "#F2F4F8", "pet": "#9FB3C8", "power-up": "#4CD964",
    "megaphone": "#3D8BFF", "news": "#5AB8FF", "teleport": "#5AB8FF", "trade": "#5AB8FF", "backpack": "#3D8BFF",
    "profile": "#5AB8FF", "invite": "#3D8BFF", "party": "#3D8BFF", "group": "#3D8BFF", "success": "#4CD964",
    "error": "#FF4D4D", "equipped": "#3D8BFF", "loading": "#5AB8FF", "stopwatch": "#5AB8FF", "notification": "#FFD23F",
    "codes": "#5AB8FF",
    # actions
    "close": "#FF4D4D", "check": "#4CD964", "plus": "#4CD964", "minus": "#FF4D4D", "refresh": "#4CD964",
    "search": "#5AB8FF", "settings": "#9FB3C8", "menu": "#9FB3C8", "more": "#9FB3C8", "trash": "#FF5A5A",
    "edit": "#FFB347", "share": "#5AB8FF", "download": "#4CD964", "play": "#4CD964", "pause": "#FFB347",
    "filter": "#B98CFF", "expand": "#5AB8FF", "arrow-left": "#5AB8FF", "arrow-right": "#5AB8FF",
    "arrow-up": "#4CD964", "arrow-down": "#FF5A5A",
    # status
    "info": "#3D8BFF", "warning": "#FFD23F", "question": "#B98CFF", "lock": "#FFB020", "unlock": "#4CD964",
    # interface
    "home": "#FF8A3D", "shop": "#FF5A5A", "bag": "#C9822F", "map": "#F2D49B", "pin": "#FF4D6D",
    "chat": "#5AB8FF", "mail": "#F2F4F8", "bell": "#FFD23F", "user": "#3D8BFF", "users": "#3D8BFF",
    "clock": "#F2F4F8", "calendar": "#FF5A5A", "flag": "#FF4D4D", "target": "#FF4D4D", "quest": "#F2D49B",
    "leaderboard": "#F7C21B", "volume": "#5AB8FF", "mute": "#9FB3C8", "music": "#B98CFF", "eye": "#5AB8FF",
    "camera": "#7A869E", "gamepad": "#7A869E", "keyboard": "#9FB3C8", "touch": "#FFD0A8",
    # items
    "sword": "#C9D6E6", "shield": "#3D8BFF", "bow": "#C9822F", "potion": "#FF4DD2", "key": "#F7C21B",
    "bomb": "#3A3F55", "hammer": "#8C96A8", "pickaxe": "#8C96A8", "axe": "#8C96A8", "wrench": "#9FB3C8",
    "magnet": "#FF4D4D", "rocket": "#F2F4F8", "egg": "#F2F4F8", "paw": "#C9822F", "dice": "#F2F4F8",
    "puzzle": "#4CD964", "car": "#FF4D4D", "block": "#4CD964",
    # stats
    "health": "#FF3B5C", "health-plus": "#FF3B5C", "energy": "#FFD23F", "speed": "#5AB8FF",
    "strength": "#9FB3C8", "xp": "#B98CFF", "fire": "#FF7A1F", "snowflake": "#8FE3FF", "leaf": "#4CD964",
    "water": "#3DA9FF", "skull": "#F2F4F8",
}
# Second colours for multi-part icons: (x0, y0, x1, y1) in the 100-unit design grid -> colour.
REGIONS = {
    "sword": [((0, 40, 60, 100), "#A0642B")],
    "axe": [((20, 40, 50, 100), "#A0642B")],
    "hammer": [((38, 44, 62, 100), "#A0642B")],
    "pickaxe": [((40, 40, 60, 100), "#A0642B")],
    "rocket": [((30, 44, 50, 72), "#FF4D4D"), ((50, 44, 70, 72), "#FF4D4D"), ((38, 68, 62, 100), "#FF9A2E")],
    "trophy": [((28, 72, 72, 100), "#A0642B")],
    "medal": [((20, 0, 80, 42), "#3D8BFF")],
    "bomb": [((56, 0, 100, 34), "#FFB020")],
    "potion": [((36, 0, 64, 36), "#C9D6E6")],
    "gift": [((40, 10, 60, 100), "#FFD23F")],
    "lamp": [],
    "pin": [],
    "car": [((10, 64, 46, 100), "#3A3F55"), ((54, 64, 90, 100), "#3A3F55")],
    "magnet": [((8, 0, 92, 26), "#C9D6E6")],
    "paw": [],
}


def hex_rgb(value: str):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def shade(rgb, k):
    return tuple(max(0, min(255, int(c * k))) for c in rgb)


def lighten(rgb, k):
    return tuple(max(0, min(255, int(c + (255 - c) * k))) for c in rgb)


def color_for(name: str, category: str):
    return hex_rgb(PALETTE.get(name, CATEGORY_COLORS.get(category, "#5AB8FF")))


def dilate(mask: Image.Image, radius: float) -> Image.Image:
    """Round dilation by `radius` px, fast: blur, then a soft threshold (keeps edges antialiased).
    MaxFilter with large kernels is far too slow at supersampled sizes."""
    blurred = mask.filter(ImageFilter.GaussianBlur(radius / 2.0))
    return blurred.point(lambda v: 0 if v < 8 else (255 if v > 40 else int((v - 8) * 255 / 32)))


def _fill_holes(mask: Image.Image) -> Image.Image:
    """Silhouette: everything not reachable from the border through empty pixels."""
    w, h = mask.size
    inv = mask.point(lambda v: 0 if v > 96 else 255).convert("L")
    flood = inv.copy()
    ImageDraw.floodfill(flood, (0, 0), 128)
    outside = flood.point(lambda v: 255 if v == 128 else 0)
    return ImageChops.invert(outside)


def _gradient(size, top, mid, bottom):
    w, h = size
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        if t < 0.5:
            k = t / 0.5
            c = tuple(int(top[i] + (mid[i] - top[i]) * k) for i in range(3))
        else:
            k = (t - 0.5) / 0.5
            c = tuple(int(mid[i] + (bottom[i] - mid[i]) * k) for i in range(3))
        grad.putpixel((0, y), c)
    return grad.resize((w, h))


def illustrate(mask: Image.Image, base, regions=(), outline_px=None) -> Image.Image:
    """mask: L-mode glyph at working resolution (ink = 255). Returns RGBA at the same size."""
    size = mask.size
    w, h = size
    s = w / 100.0
    outline_px = outline_px or max(3, int(round(w * 0.045)))
    glyph = mask.point(lambda v: 255 if v > 110 else 0)
    sil = _fill_holes(glyph)
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    # 2 shadow
    shadow = dilate(sil, outline_px).filter(ImageFilter.GaussianBlur(outline_px * 0.6))
    shadow_layer = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow_layer.paste((0, 0, 0, 90), (0, int(outline_px * 0.9)), shadow)
    out.alpha_composite(shadow_layer)
    # 3 outline
    ring = dilate(sil, outline_px)
    out.paste(OUTLINE_COLOR + (255,), (0, 0), ring)
    # 4 detail (holes) in a darker shade
    holes = ImageChops.subtract(sil, glyph)
    out.paste(shade(base, 0.62) + (255,), (0, 0), holes)
    # 5 body gradient, with region recolouring
    body_rgb = _gradient(size, lighten(base, 0.35), base, shade(base, 0.78))
    for (x0, y0, x1, y1), hexcol in regions:
        col = hex_rgb(hexcol)
        region = _gradient(size, lighten(col, 0.35), col, shade(col, 0.78))
        box = Image.new("L", size, 0)
        ImageDraw.Draw(box).rectangle([x0 * s, y0 * s, x1 * s, y1 * s], fill=255)
        body_rgb.paste(region, (0, 0), box)
    out.paste(body_rgb, (0, 0), glyph)
    # 5b soft inner shade along the bottom edge of the body
    lower = Image.new("L", size, 0)
    ImageDraw.Draw(lower).rectangle([0, h * 0.62, w, h], fill=70)
    out.paste((0, 0, 0), (0, 0), ImageChops.multiply(lower, glyph))
    # 6 gloss
    gloss = Image.new("L", size, 0)
    ImageDraw.Draw(gloss).ellipse([w * 0.16, h * 0.1, w * 0.6, h * 0.38], fill=150)
    gloss = gloss.filter(ImageFilter.GaussianBlur(w * 0.018))
    out.paste((255, 255, 255), (0, 0), ImageChops.multiply(gloss, glyph))
    return out
