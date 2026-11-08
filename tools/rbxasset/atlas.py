"""Pack a mesh's named panels onto the texture and convert panel UVs to texture UVs.

Each panel gets size = physical size x global scale x sqrt(weight), so the front receives more
pixels per stud than the bottom. A MaxRects packer (best short side fit) may rotate a panel 90
degrees to use space well. We search for the largest scale that still fits, with padding so
filtering never bleeds between panels.
"""
from __future__ import annotations

import math


def _maxrects(sizes: dict, tex: int, pad: int, free=None):
    free = list(free) if free else [(pad, pad, tex - 2 * pad, tex - 2 * pad)]
    placed = {}
    for name, (w, h) in sorted(sizes.items(), key=lambda kv: (-max(kv[1]), -min(kv[1]), kv[0])):
        best = None
        for fx, fy, fw, fh in free:
            for rot, (pw, ph) in ((False, (w, h)), (True, (h, w))):
                if pw + pad <= fw + pad and ph + pad <= fh + pad:
                    score = (min(fw - pw, fh - ph), max(fw - pw, fh - ph), fy, fx, rot)
                    if best is None or score < best[0]:
                        best = (score, fx, fy, pw, ph, rot)
        if best is None:
            return None
        _, x, y, pw, ph, rot = best
        placed[name] = (x, y, w, h, rot)
        used = (x, y, pw + pad, ph + pad)
        next_free = []
        for fx, fy, fw, fh in free:
            if used[0] >= fx + fw or used[0] + used[2] <= fx or used[1] >= fy + fh or used[1] + used[3] <= fy:
                next_free.append((fx, fy, fw, fh))
                continue
            if used[0] > fx:
                next_free.append((fx, fy, used[0] - fx, fh))
            if used[0] + used[2] < fx + fw:
                next_free.append((used[0] + used[2], fy, fx + fw - used[0] - used[2], fh))
            if used[1] > fy:
                next_free.append((fx, fy, fw, used[1] - fy))
            if used[1] + used[3] < fy + fh:
                next_free.append((fx, used[1] + used[3], fw, fy + fh - used[1] - used[3]))
        free = [r for i, r in enumerate(next_free) if r[2] > 0 and r[3] > 0 and not any(
            j != i and r[0] >= o[0] and r[1] >= o[1] and r[0] + r[2] <= o[0] + o[2] and r[1] + r[3] <= o[1] + o[3] and (r != o or j < i)
            for j, o in enumerate(next_free))]
    return placed


def pack(panels: dict, tex: int = 1024, pad: int = 12) -> dict:
    """Returns {panel: {x, y, w, h, rot, density}}. x, y is the footprint's top-left in image pixels.
    w, h are the panel's own size; a rotated panel occupies h x w on the texture."""

    def sizes_at(scale):
        return {
            k: (max(8, round(p["w"] * scale * math.sqrt(p["weight"]))), max(8, round(p["h"] * scale * math.sqrt(p["weight"]))))
            for k, p in panels.items()
        }

    lo, hi = 1.0, 8192.0
    best = None
    for _ in range(40):
        mid = (lo + hi) / 2
        result = _maxrects(sizes_at(mid), tex, pad)
        if result:
            best, lo = result, mid
        else:
            hi = mid
    if best is None:
        raise ValueError("Panels do not fit the texture")
    return {
        k: {"x": x, "y": y, "w": w, "h": h, "rot": rot, "density": round(w / panels[k]["w"], 1)}
        for k, (x, y, w, h, rot) in best.items()
    }


def pack_guide(panels: dict, tex: int = 1024, pad: int = 6) -> dict:
    """Guide layout: front art in uv 0-0.75 x 0-1, everything else in the side block
    uv 0.75-1 x 0.25-1, and the shared palette in the corner uv 0.75-1 x 0-0.25.
    Unused front-block space, if a strip is wide enough, also takes small panels."""
    block_w, side_w = int(tex * 0.75), tex - int(tex * 0.75)
    side_h = int(tex * 0.75)
    front = panels.get("front") or next(iter(panels.values()))
    front_name = "front" if "front" in panels else next(iter(panels))
    fit = min((block_w - pad) / front["w"], tex / front["h"])
    fw, fh = int(front["w"] * fit), int(front["h"] * fit)
    rects = {front_name: {"x": 0, "y": 0, "w": fw, "h": fh, "rot": False, "density": round(fit, 1)}}
    free = [(block_w + pad, pad, side_w - 2 * pad, side_h - 2 * pad)]
    if block_w - fw - pad >= 40:
        free.append((fw + pad, pad, block_w - fw - 2 * pad, tex - 2 * pad))
    if tex - fh - pad >= 40:
        free.append((pad, fh + pad, fw - 2 * pad, tex - fh - 2 * pad))
    rest = {k: p for k, p in panels.items() if k != front_name}

    def sizes_at(scale):
        return {
            k: (max(8, round(p["w"] * scale * math.sqrt(p["weight"]))), max(8, round(p["h"] * scale * math.sqrt(p["weight"]))))
            for k, p in rest.items()
        }

    lo, hi = 1.0, 8192.0
    best = None
    for _ in range(40):
        mid = (lo + hi) / 2
        result = _maxrects(sizes_at(mid), tex, pad, free)
        if result:
            best, lo = result, mid
        else:
            hi = mid
    if best is None:
        raise ValueError("Panels do not fit the guide's side block")
    for k, (x, y, w, h, rot) in best.items():
        rects[k] = {"x": x, "y": y, "w": w, "h": h, "rot": rot, "density": round(w / panels[k]["w"], 1)}
    return rects


def to_texture_uv(panel_uv, rect: dict, tex: int = 1024):
    """Panel (u, v), v up -> texture UV, v up. Half-pixel inset keeps samples off the padding.
    A rotated panel was turned 90 degrees counter-clockwise when composed."""
    u, v = panel_uv
    px = 0.5 + u * (rect["w"] - 1)
    py = 0.5 + (1 - v) * (rect["h"] - 1)
    if rect.get("rot"):
        ax, ay = rect["x"] + py, rect["y"] + (rect["w"] - px)
    else:
        ax, ay = rect["x"] + px, rect["y"] + py
    return ax / tex, 1 - ay / tex
