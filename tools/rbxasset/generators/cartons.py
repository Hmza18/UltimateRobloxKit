"""Chilled packaging from the guide: gable-top carton with a screw cap, cheddar block and egg carton."""
from __future__ import annotations

import math

from ..meshkit import MeshData, lathe_rings
from .packaging import _fan, add_box, octagon


def _segment_span(mesh, ids_a, ids_b, ring_a, ring_b, chooser):
    """Skin one span of two 8-point rings, with chooser(seg) returning (panel, uv function)."""
    for i in range(8):
        j = (i + 1) % 8
        panel, uv = chooser(i)
        points = (ring_a[i], ring_a[j], ring_b[j], ring_b[i])
        mesh.face((ids_a[i], ids_a[j], ids_b[j], ids_b[i]), panel, [uv(p) for p in points])


def _box_chooser(w, d, front, back, left, right, v):
    """Eight segments of an octagon ring. Chamfers keep the art of the wide face beside them."""

    def choose(seg):
        if seg in (7, 0, 1):
            return front, lambda p: ((p[0] + w / 2) / w, v(p))
        if seg in (3, 4, 5):
            return back, lambda p: ((w / 2 - p[0]) / w, v(p))
        if seg == 2:
            return right, lambda p: ((p[1] + d / 2) / d, v(p))
        return left, lambda p: ((d / 2 - p[1]) / d, v(p))

    return choose


def _basis(normal):
    nx, ny, nz = normal
    length = math.sqrt(nx * nx + ny * ny + nz * nz)
    n = (nx / length, ny / length, nz / length)
    u = (1.0, 0.0, 0.0)
    v = (n[1] * u[2] - n[2] * u[1], n[2] * u[0] - n[0] * u[2], n[0] * u[1] - n[1] * u[0])
    return u, v, n


def screw_cap(mesh, center, normal, r, height):
    """Knurled screw cap on a pour spout collar, as one closed shell along the slope's normal."""
    start = len(mesh.verts)
    profile = [(r * 1.14, -height * 0.3), (r * 1.14, height * 0.06), (r * 1.02, height * 0.1), (r * 1.02, height * 0.92), (r * 0.9, height)]
    mesh.loft(lathe_rings(profile, 12), "cap", "cap_end", "cap_end", weights={"cap": 0.14, "cap_end": 0.14})
    u, v, n = _basis(normal)
    cx, cy, cz = center
    mesh.verts[start:] = [
        (cx + x * u[0] + y * v[0] + z * n[0], cy + x * u[1] + y * v[1] + z * n[1], cz + x * u[2] + y * v[2] + z * n[2]) for x, y, z in mesh.verts[start:]
    ]


def _ring10(w, d, z, c, side_in=0.0):
    """Ten-point carton ring, counter-clockwise from the front-left. side_in folds the side panels'
    centres inward, like the V fold of a real gable top."""
    hw, hd = w / 2, d / 2
    return [(-hw + c, -hd, z), (hw - c, -hd, z), (hw, -hd + c, z), (hw - side_in, 0.0, z), (hw, hd - c, z),
            (hw - c, hd, z), (-hw + c, hd, z), (-hw, hd - c, z), (-hw + side_in, 0.0, z), (-hw, -hd + c, z)]


def _span10(mesh, ids_a, ids_b, ring_a, ring_b, w, d, names, v):
    front, back, left, right = names

    def uv(panel, p):
        if panel == front:
            u = (p[0] + w / 2) / w
        elif panel == back:
            u = (w / 2 - p[0]) / w
        elif panel == right:
            u = (p[1] + d / 2) / d
        else:
            u = (d / 2 - p[1]) / d
        return (u, v(p))

    for i in range(10):
        j = (i + 1) % 10
        if i in (9, 0, 1):
            panel = front
        elif i in (4, 5, 6):
            panel = back
        elif i in (2, 3):
            panel = right
        else:
            panel = left
        pts = (ring_a[i], ring_a[j], ring_b[j], ring_b[i])
        mesh.face((ids_a[i], ids_a[j], ids_b[j], ids_b[i]), panel, [uv(panel, q) for q in pts])


def gable_carton(w, d, h, **_):
    """Gable-top carton built like the real fold: creased shoulder, sloped roof panels, side panels
    tucked inward in a V, a sealed double fin, and a screw cap on the front slope."""
    mesh = MeshData()
    c = min(w, d) * 0.03
    shoulder, ridge, seal = h * 0.69, h * 0.885, h * 0.96
    thin = d * 0.06
    mid = (shoulder + ridge) / 2
    mid_d = (d + thin) / 2
    rings = [_ring10(w * 0.98, d * 0.98, 0, c), _ring10(w, d, h * 0.012, c), _ring10(w * 1.006, d * 1.012, shoulder * 0.5, c), _ring10(w, d, shoulder, c),
             _ring10(w, mid_d, mid, c * 0.6, d * 0.16), _ring10(w, thin, ridge, c * 0.2, 0.0), _ring10(w, thin, seal, c * 0.2), _ring10(w * 0.995, thin * 0.7, h, c * 0.15)]
    ids = [mesh.add_ring(r) for r in rings]
    run = d / 2 - thin / 2
    rise = ridge - shoulder
    slope = math.hypot(run, rise)
    for name, pw, ph, weight in (("front", w, shoulder, 1.0), ("back", w, shoulder, 1.0), ("left", d, shoulder, 0.5), ("right", d, shoulder, 0.5),
                                 ("gable_front", w, slope, 0.35), ("gable_back", w, slope, 0.35), ("gable_side", d, rise, 0.14), ("fin", w, h - ridge, 0.2), ("bottom", w, d, 0.03)):
        mesh.panel(name, pw, ph, weight)
    body = lambda p: min(p[2] / shoulder, 1.0)  # noqa: E731
    for s in (0, 1, 2):
        _span10(mesh, ids[s], ids[s + 1], rings[s], rings[s + 1], w, d, ("front", "back", "left", "right"), body)
    roof = lambda p: min(max((p[2] - shoulder) / rise, 0.0), 1.0)  # noqa: E731
    for s in (3, 4):
        _span10(mesh, ids[s], ids[s + 1], rings[s], rings[s + 1], w, d, ("gable_front", "gable_back", "gable_side", "gable_side_r"), roof)
    fin = lambda p: min(max((p[2] - ridge) / (h - ridge), 0.0), 1.0)  # noqa: E731
    for s in (5, 6):
        _span10(mesh, ids[s], ids[s + 1], rings[s], rings[s + 1], w, d, ("fin", "fin_b", "fin_l", "fin_r"), fin)
    mesh.panel("gable_side_r", d, rise, 0.14)
    for name in ("fin_b", "fin_l", "fin_r"):
        mesh.panel(name, w if name == "fin_b" else thin, h - ridge, 0.2 if name == "fin_b" else 0.05)
    _fan(mesh, ids[0], rings[0], "bottom", lambda p: ((p[0] + w / 2) / w, (d / 2 - p[1]) / d), flip=True)
    _fan(mesh, ids[-1], rings[-1], "fin_r", lambda p: ((p[0] + w / 2) / w, (p[1] + thin / 2) / thin * 0.98 + 0.01))
    center = (0.0, -d / 2 + run * 0.5, shoulder + rise * 0.5)
    screw_cap(mesh, center, (0.0, -rise, run), min(w, d) * 0.15, min(w, d) * 0.13)
    return mesh


def cheese_block(w, d, h, **_):
    """Chamfered block of cheddar. The guide prints art on both its front and its top."""
    mesh = MeshData()
    add_box(mesh, w, d, h, c=min(w, d, h) * 0.09, weights={"front": 1.0, "back": 0.7, "left": 0.5, "right": 0.5, "top": 1.0, "bottom": 0.05})
    return mesh


def egg_carton(w, d, h, **_):
    """Moulded pulp carton: six round cups, tray, flange, sloped lid with a printed top, lock bumps and tab."""
    mesh = MeshData()
    tab = d * 0.09
    body_d = d - tab
    tray_bottom, lip, lid_top = h * 0.26, h * 0.5, h
    c = min(w, body_d) * 0.1
    rings = [octagon(w * 0.88, body_d * 0.86, tray_bottom, c), octagon(w * 0.97, body_d * 0.97, lip - h * 0.05, c), octagon(w, body_d, lip - h * 0.03, c), octagon(w, body_d, lip, c),
             octagon(w * 0.84, body_d * 0.68, lid_top, c * 0.8)]
    ids = [mesh.add_ring(r) for r in rings]
    run, rise = body_d * 0.16, lid_top - lip
    slope = math.hypot(run, rise)
    top_w, top_d = w * 0.84, body_d * 0.68
    for name, pw, ph, weight in (("front", top_w, top_d, 1.0), ("lid_front", w, slope, 0.55), ("back", w, slope, 0.55), ("lid_side", body_d, rise, 0.08), ("tray", w, lip, 0.2), ("bottom", w, d, 0.03), ("pulp", 0.3, 0.3, 0.06)):
        mesh.panel(name, pw, ph, weight)
    tray_v = lambda p: (p[2] - tray_bottom) / (lip - tray_bottom)  # noqa: E731
    for s in (0, 1, 2):
        _segment_span(mesh, ids[s], ids[s + 1], rings[s], rings[s + 1], _box_chooser(w, body_d, "tray", "tray", "tray", "tray", tray_v))
    lid_v = lambda p: (p[2] - lip) / rise  # noqa: E731
    _segment_span(mesh, ids[3], ids[4], rings[3], rings[4], _box_chooser(w, body_d, "lid_front", "back", "lid_side", "lid_side", lid_v))
    _fan(mesh, ids[0], rings[0], "bottom", lambda p: ((p[0] + w / 2) / w, (d / 2 - p[1]) / d), flip=True)
    _fan(mesh, ids[-1], rings[-1], "front", lambda p: ((p[0] + top_w / 2) / top_w, (p[1] + top_d / 2) / top_d))
    rad = min(w * 0.135, body_d * 0.2)
    for ix in (-1, 0, 1):
        for iy in (-1, 1):
            start = len(mesh.verts)
            mesh.loft(lathe_rings([(rad * 0.6, 0), (rad * 0.94, tray_bottom * 0.62), (rad, tray_bottom * 1.25)], 8), "pulp", "pulp", "pulp")
            mesh.translate(start, ix * w * 0.3, iy * body_d * 0.235, 0)
    for sx in (-0.2, 0.2):
        start = len(mesh.verts)
        r = w * 0.035
        mesh.loft(lathe_rings([(r, 0), (r * 0.6, r * 0.8)], 6), "pulp", "pulp", "pulp")
        mesh.rotate_x(start)
        mesh.translate(start, sx * w, -body_d / 2 + r * 0.3, lip - h * 0.035)
    start = len(mesh.verts)
    half = w * 0.09
    tab_top = lip + h * 0.02
    tab_low = lip - h * 0.09
    outline = [(-half, tab_low), (half, tab_low), (half * 1.1, tab_top), (-half * 1.1, tab_top)]
    mesh.extrude(outline, 0, tab + c * 0.25, "pulp", "pulp", "pulp", False)
    mesh.verts[start:] = [(x, -z, y) for x, y, z in mesh.verts[start:]]
    mesh.translate(start, 0, -body_d / 2 + c * 0.25, 0)
    return mesh


GENERATORS = {f.__name__: f for f in (gable_carton, cheese_block, egg_carton)}
