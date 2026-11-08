"""Batch 8 and 9 household shapes from the guide: chamfered bleach jug, oval and waisted bottles, wrapped paper pack."""
from __future__ import annotations

import math

from ..meshkit import MeshData, rrect
from .cartons import screw_cap
from .packaging import octagon


def oval_ring(rx, ry, z, n):
    """Oval ring with evenly spaced points along its edge, so a wrap label keeps its proportions.
    It starts at the back centre and turns the same way as meshkit.ellipse."""
    samples = 720
    pts = [(-rx * math.sin(2 * math.pi * i / samples), ry * math.cos(2 * math.pi * i / samples)) for i in range(samples)]
    lengths = [0.0]
    for i in range(samples):
        a, b = pts[i], pts[(i + 1) % samples]
        lengths.append(lengths[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    ring, k = [], 0
    for i in range(n):
        target = lengths[-1] * i / n
        while lengths[k + 1] < target:
            k += 1
        ring.append((pts[k][0], pts[k][1], z))
    return ring


def _oval_loft(w, d, h, sections, n, weights):
    mesh = MeshData()
    rings = [oval_ring(w / 2 * s, d / 2 * s, h * z, n) for s, z, _ in sections]
    mesh.wrap_loft(rings, [span for _, _, span in sections[1:]], weights=weights)
    return mesh


def oval_bottle(w, d, h, **_):
    """Oval shampoo bottle with a soft shoulder and a flip-top cap, whose lid line is a real groove."""
    sections = [(0.84, 0, ""), (0.97, 0.025, "base"), (1.0, 0.08, "base"), (0.97, 0.68, "label"), (0.84, 0.79, "neck"), (0.62, 0.825, "neck"),
                (0.66, 0.83, "cap"), (0.66, 0.905, "cap"), (0.6, 0.912, "cap"), (0.63, 0.92, "cap"), (0.6, 0.985, "cap"), (0.48, 1.0, "cap")]
    return _oval_loft(w, d, h, sections, 16, {"front": 1, "back": 1, "base": 0.08, "neck": 0.14, "cap": 0.25, "top": 0.14, "bottom": 0.04})


def waist_bottle(w, d, h, **_):
    """Dish soap bottle with a grip waist and a push-pull cap: collar, stem and spout."""
    sections = [(0.82, 0, ""), (0.96, 0.02, "base"), (1.0, 0.08, "base"), (1.0, 0.24, "label"), (0.84, 0.44, "label"), (0.93, 0.58, "label"), (0.95, 0.68, "label"),
                (0.62, 0.76, "neck"), (0.34, 0.79, "neck"), (0.36, 0.8, "cap"), (0.36, 0.87, "cap"), (0.22, 0.88, "cap"), (0.22, 0.93, "cap"), (0.27, 0.94, "cap"), (0.2, 1.0, "cap")]
    return _oval_loft(w, d, h, sections, 12, {"front": 1, "back": 1, "base": 0.08, "neck": 0.14, "cap": 0.25, "top": 0.1, "bottom": 0.04})


def _sweep(mesh, path, half_t, half_d, panel, weight=0.12, sides=6):
    """A closed bar along a path in the XZ plane, for a jug's carry handle."""
    rings = []
    for i, (x, z) in enumerate(path):
        ax, az = path[max(i - 1, 0)]
        bx, bz = path[min(i + 1, len(path) - 1)]
        tx, tz = bx - ax, bz - az
        length = math.hypot(tx, tz)
        tx, tz = tx / length, tz / length
        # e1 x Y equals the travel direction, so the ring turns the way loft needs for outward faces.
        e1 = (tz, -tx)
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            ca, sa = math.cos(a), math.sin(a)
            ring.append((x + half_t * ca * e1[0], half_d * sa, z + half_t * ca * e1[1]))
        rings.append(ring)
    ids = mesh.loft(rings, panel, None, None, weights={panel: weight})
    # The ends stand upright, so loft's top-down caps cannot triangulate them.
    end = panel + "_end"
    mesh.panel(end, half_t * 2, half_d * 2, 0.04)
    uv = [(0.5 + 0.5 * math.cos(2 * math.pi * k / sides), 0.5 + 0.5 * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    for k in range(1, sides - 1):
        flipped = [(1 - u, v) for u, v in (uv[0], uv[k + 1], uv[k])]
        mesh.face((ids[0][0], ids[0][k + 1], ids[0][k]), end, flipped)
        mesh.face((ids[-1][0], ids[-1][k], ids[-1][k + 1]), end, (uv[0], uv[k], uv[k + 1]))


def bleach_jug(w, d, h, **_):
    """White chamfered jug. The shoulder leans to a capped spout on one side, with a carry handle over the other."""
    mesh = MeshData()
    c = min(w, d) * 0.16

    def ring(sw, sd, ox, z):
        return [(x + ox * w, y, z * h) for x, y, _ in octagon(w * sw, d * sd, 0, c * min(sw, sd))]

    rings = [ring(0.94, 0.94, 0, 0), ring(1, 1, 0, 0.03), ring(1, 1, 0, 0.55), ring(0.97, 0.98, -0.015, 0.62), ring(0.72, 0.76, -0.14, 0.7), ring(0.42, 0.46, -0.24, 0.8),
             ring(0.25, 0.29, -0.29, 0.835), ring(0.25, 0.29, -0.29, 0.87)]
    mesh.planar_loft(rings, w, d, h, smooth=True, weights={"front": 1.0, "back": 1.0, "left": 0.5, "right": 0.5, "top": 0.04, "bottom": 0.04})
    screw_cap(mesh, (-0.29 * w, 0, 0.875 * h), (0, 0, 1), w * 0.135, h * 0.125)
    path = [(-0.2, 0.82), (-0.05, 0.865), (0.15, 0.87), (0.32, 0.805), (0.42, 0.69), (0.43, 0.56), (0.4, 0.47)]
    _sweep(mesh, [(x * w, z * h) for x, z in path], w * 0.035, d * 0.11, "handle")
    return mesh


def paper_pack(w, d, h, **_):
    """Wrapped pack of 8 rolls, two layers of two by two, with soft corners and a waist between the layers."""
    mesh = MeshData()
    r = min(w, d) * 0.2

    def ring(s, z):
        return rrect(w * s, d * s, r * s, h * z, 2)

    rings = [ring(0.94, 0), ring(1.0, 0.05), ring(1.0, 0.26), ring(0.975, 0.5), ring(1.0, 0.74), ring(1.0, 0.95), ring(0.94, 1.0)]
    mesh.planar_loft(rings, w, d, h, smooth=True, weights={"front": 1.0, "back": 1.0, "left": 0.7, "right": 0.7, "top": 0.5, "bottom": 0.04})
    return mesh


GENERATORS = {f.__name__: f for f in (oval_bottle, waist_bottle, bleach_jug, paper_pack)}
