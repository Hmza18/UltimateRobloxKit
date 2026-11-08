"""Work out where artwork can safely go on each panel, from the real mesh.

For every panel we rasterize its faces in panel space and measure how much each triangle stretches
the art. A cell is usable only when a face covers it with little distortion, so folds, chamfers,
tapers and parts of a panel the mesh never shows are all excluded. The largest usable rectangle is
the panel's safe area. Pure Python, so it can be tested without Blender.
"""
from __future__ import annotations

import math

GRID = 96
MAX_STRETCH = 1.35  # art may be at most this much stretched or squeezed in any direction
CURVED_U = (0.17, 0.83)  # on a wrap label, print stays within 60 degrees of the panel's centre
NAME_U = (0.2, 0.8)  # the guide keeps the product name in the middle of the front art
UNCOVERED, DISTORTED, USABLE = 0, 1, 2


def tighten_panels(mesh):
    """Fit each flat panel's u range to the faces that use it.

    Otherwise a side panel keeps art for its rounded corners, which actually belong to the front
    and back, so text at its edges never appears on the model. v stays put because art such as
    the bread's slices lines up with mesh heights.
    """
    ranges = {}
    for f in mesh.faces:
        lo, hi = ranges.get(f["panel"], (1.0, 0.0))
        us = [uv[0] for uv in f["uv"]]
        ranges[f["panel"]] = (min(lo, *us), max(hi, *us))
    for name, (lo, hi) in ranges.items():
        if hi - lo < 1e-6 or (lo <= 1e-6 and hi >= 1 - 1e-6):
            continue
        mesh.panels[name]["w"] *= hi - lo
    for f in mesh.faces:
        lo, hi = ranges[f["panel"]]
        if hi - lo >= 1e-6:
            f["uv"] = tuple(((u - lo) / (hi - lo), v) for u, v in f["uv"])
    return mesh


def stretch(p0, p1, p2, uv0, uv1, uv2, w, h):
    """Largest and smallest stretch of a triangle's map from physical panel space to 3D."""
    a = (uv1[0] - uv0[0]) * w, (uv1[1] - uv0[1]) * h
    b = (uv2[0] - uv0[0]) * w, (uv2[1] - uv0[1]) * h
    det = a[0] * b[1] - a[1] * b[0]
    if abs(det) < 1e-12:
        return None
    e1 = [p1[i] - p0[i] for i in range(3)]
    e2 = [p2[i] - p0[i] for i in range(3)]
    su = [(b[1] * e1[i] - a[1] * e2[i]) / det for i in range(3)]
    sv = [(-b[0] * e1[i] + a[0] * e2[i]) / det for i in range(3)]
    ee, ff, gg = sum(x * x for x in su), sum(x * y for x, y in zip(su, sv)), sum(y * y for y in sv)
    root = math.sqrt(max(0.0, (ee - gg) ** 2 + 4 * ff * ff))
    return math.sqrt((ee + gg + root) / 2), math.sqrt(max(0.0, (ee + gg - root) / 2))


def raster(verts, faces, panels) -> dict:
    grids = {name: [[UNCOVERED] * GRID for _ in range(GRID)] for name in panels}
    for f in faces:
        cells = grids[f["panel"]]
        panel = panels[f["panel"]]
        for k in range(1, len(f["v"]) - 1):
            ids = (0, k, k + 1)
            pts = [verts[f["v"][i]] for i in ids]
            uvs = [f["uv"][i] for i in ids]
            s = stretch(*pts, *uvs, panel["w"], panel["h"])
            good = s is not None and s[0] <= MAX_STRETCH and s[1] >= 1 / MAX_STRETCH
            xs = [u * GRID for u, _ in uvs]
            ys = [(1 - v) * GRID for _, v in uvs]
            d = (xs[1] - xs[0]) * (ys[2] - ys[0]) - (ys[1] - ys[0]) * (xs[2] - xs[0])
            if abs(d) < 1e-9:
                continue
            if not good:
                # Folds and walls can be thinner than a cell, so walk their edges too.
                for a, b in ((0, 1), (1, 2), (2, 0)):
                    steps = max(1, int(2 * max(abs(xs[a] - xs[b]), abs(ys[a] - ys[b]))))
                    for t in range(steps + 1):
                        col = int(xs[a] + (xs[b] - xs[a]) * t / steps)
                        row = int(ys[a] + (ys[b] - ys[a]) * t / steps)
                        if 0 <= col < GRID and 0 <= row < GRID:
                            cells[row][col] = DISTORTED
            for row in range(max(0, int(min(ys))), min(GRID, int(max(ys)) + 1)):
                for col in range(max(0, int(min(xs))), min(GRID, int(max(xs)) + 1)):
                    x, y = col + 0.5, row + 0.5
                    l1 = ((x - xs[0]) * (ys[2] - ys[0]) - (y - ys[0]) * (xs[2] - xs[0])) / d
                    l2 = ((xs[1] - xs[0]) * (y - ys[0]) - (ys[1] - ys[0]) * (x - xs[0])) / d
                    if l1 >= -1e-9 and l2 >= -1e-9 and l1 + l2 <= 1 + 1e-9:
                        # Distortion wins, so a bad face is never hidden by a good neighbour.
                        cells[row][col] = USABLE if good and cells[row][col] != DISTORTED else DISTORTED
    return grids


def largest_rect(cells) -> tuple:
    """Largest all-usable rectangle, as fractions (x0, y0, x1, y1) with y down from the top."""
    heights = [0] * GRID
    best = (0, 0, 0, 0, 0)
    for row in range(GRID):
        heights = [heights[c] + 1 if cells[row][c] == USABLE else 0 for c in range(GRID)]
        stack = []
        for c in range(GRID + 1):
            current = heights[c] if c < GRID else 0
            start = c
            while stack and stack[-1][1] >= current:
                left, height = stack.pop()
                area = height * (c - left)
                if area > best[0]:
                    best = (area, left, row - height + 1, c, row + 1)
                start = left
            stack.append((start, current))
    _, x0, y0, x1, y1 = best
    return (x0 / GRID, y0 / GRID, x1 / GRID, y1 / GRID)


def analyze(verts, faces, panels) -> dict:
    """{panel: {"safe": (x0, y0, x1, y1), "usable": fraction of the panel that is usable}}"""
    out = {}
    for name, cells in raster(verts, faces, panels).items():
        usable = sum(row.count(USABLE) for row in cells) / (GRID * GRID)
        safe = largest_rect(cells)
        if panels[name].get("curved"):
            # A curved label turns away from the viewer, so print near its edges cannot be read.
            safe = (max(safe[0], CURVED_U[0]), safe[1], min(safe[2], CURVED_U[1]), safe[3])
        out[name] = {"safe": safe, "usable": round(usable, 3)}
    return out


def element_clear(cells, box, w, h) -> bool:
    """True when a pixel box on a w x h panel lands only on usable cells."""
    x0, y0, x1, y1 = box
    for row in range(max(0, int(y0 / h * GRID)), min(GRID, math.ceil(y1 / h * GRID))):
        for col in range(max(0, int(x0 / w * GRID)), min(GRID, math.ceil(x1 / w * GRID))):
            if cells[row][col] != USABLE:
                return False
    return True
