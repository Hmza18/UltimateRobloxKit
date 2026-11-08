"""Stylized flat-colour texture painting with no dependencies.

Each atlas panel is filled with its colour, a soft vertical gradient (lighter at the top, a
cel-shaded cue that reads well in Roblox lighting) and a darker outline band, which gives the
chunky edge look of hand-painted low-poly art. Pillow is not needed; `write_png` is stdlib zlib.
"""
from __future__ import annotations

import struct
import zlib


def hex_rgb(value: str):
    value = value.lstrip("#")
    if len(value) != 6:
        raise ValueError(f"Colour must be #RRGGBB, got {value!r}")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def write_png(path, width: int, height: int, rows) -> None:
    """rows: list of bytearrays, each width * 4 bytes RGBA."""
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


def read_png_size(path):
    with open(path, "rb") as fh:
        head = fh.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    return struct.unpack(">II", head[16:24])


def _shade(rgb, k):
    return tuple(max(0, min(255, int(c * k))) for c in rgb)


def paint_panels(rects: dict, colors: dict, tex: int = 1024, default="#9AA5B1", outline=0.78, gradient=0.12, border_px=6):
    """Returns RGBA rows. rects come from atlas.pack/pack_guide; a rotated rect occupies h x w."""
    bg = hex_rgb(default)
    rows = [bytearray(bytes((*_shade(bg, 0.6), 255)) * tex) for _ in range(tex)]
    for name, r in rects.items():
        base = hex_rgb(colors.get(name, colors.get(name.split("_")[0], default)))
        fw, fh = (r["h"], r["w"]) if r.get("rot") else (r["w"], r["h"])
        edge = _shade(base, outline)
        for yy in range(fh):
            y = r["y"] + yy
            if not 0 <= y < tex:
                continue
            k = 1 + gradient * (0.5 - yy / max(fh - 1, 1))
            fill = bytes((*_shade(base, k), 255))
            line = bytes((*edge, 255))
            row = rows[y]
            for xx in range(fw):
                x = r["x"] + xx
                if 0 <= x < tex:
                    # Outline only the panel's top and bottom edges (its v ends). Its u ends are where wrap
                    # panels meet themselves, and a band there shows as a dark seam line on the model.
                    # A rotated panel is turned 90 degrees, so its v ends are the image's left and right.
                    if r.get("rot"):
                        on_edge = xx < border_px or xx >= fw - border_px
                    else:
                        on_edge = yy < border_px or yy >= fh - border_px
                    row[x * 4:x * 4 + 4] = line if on_edge else fill
    return rows
