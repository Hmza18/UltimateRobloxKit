"""Stylized environment props: crates, barrels, furniture, street furniture, nature.

Every generator takes the target size (w, d, h) in studs plus keyword parameters and returns a
MeshData whose shells are each closed and outward-facing. Panel names double as material slots:
the spec's `colors` map gives each panel its colour, so a prop needs no hand-painted texture.
Proportions are chunky on purpose (thick boards, fat rims), which reads well at Roblox distances.
"""
from __future__ import annotations

import math
import random

from ..meshkit import MeshData, lathe_rings, rrect


def _ring(ring, cx=0.0, cy=0.0):
    return [(x + cx, y + cy, z) for x, y, z in ring]


def block(mesh, cx, cy, z0, w, d, h, panel, r=0.04, per_corner=1, smooth=False):
    """A closed rounded block centred on (cx, cy) from z0 to z0 + h."""
    r = min(r, w * 0.45, d * 0.45)
    rings = [_ring(rrect(w, d, r, z0, per_corner), cx, cy), _ring(rrect(w, d, r, z0 + h, per_corner), cx, cy)]
    mesh.loft(rings, panel, cap_bottom=panel, cap_top=panel, smooth=smooth)


def cylinder(mesh, cx, cy, z0, radius, h, panel, n=12, smooth=True):
    rings = [_ring(r, cx, cy) for r in lathe_rings([(radius, z0), (radius, z0 + h)], n)]
    mesh.loft(rings, panel, cap_bottom=panel, cap_top=panel, smooth=smooth)


def crate(w, d, h, rim=0.12, **_):
    """Wooden crate: a body with raised rims at the bottom and top, and a raised band at mid height."""
    mesh = MeshData()
    t = min(w, d) * rim * 0.35
    zs = [0, h * 0.12, h * 0.12, h * 0.45, h * 0.45, h * 0.55, h * 0.55, h * 0.88, h * 0.88, h]
    insets = [0, 0, t, t, 0, 0, t, t, 0, 0]
    rings = [rrect(w - 2 * i, d - 2 * i, 0.05, z, 1) for z, i in zip(zs, insets)]
    mesh.loft(rings, ["wood"] * (len(rings) - 1), cap_bottom="wood_end", cap_top="wood_end", smooth=False)
    return mesh


def barrel(w, d, h, hoops=True, **_):
    """Bulged barrel with metal hoops modelled as small ledges in one closed lathe."""
    mesh = MeshData()
    r = w / 2
    prof = [(r * 0.82, 0), (r * 0.86, h * 0.04), (r * 0.86, h * 0.1), (r * 0.94, h * 0.12), (r * 0.98, h * 0.3),
            (r, h * 0.5), (r * 0.98, h * 0.7), (r * 0.94, h * 0.88), (r * 0.86, h * 0.9), (r * 0.86, h * 0.96), (r * 0.82, h)]
    spans = ["metal", "metal", "wood", "wood", "wood", "wood", "wood", "metal", "metal", "metal"] if hoops else ["wood"] * 10
    mesh.loft(lathe_rings(prof, 14), spans, cap_bottom="wood_end", cap_top="wood_end")
    return mesh


def shelf_unit(w, d, h, shelves=3, **_):
    """Open shelving: four posts and evenly spaced boards. Each part is its own closed shell."""
    mesh = MeshData()
    post = min(w, d) * 0.12
    for sx in (-1, 1):
        for sy in (-1, 1):
            block(mesh, sx * (w - post) / 2, sy * (d - post) / 2, 0, post, post, h, "frame", r=post * 0.2)
    board_t = h * 0.035
    for i in range(shelves):
        z = h * 0.06 + i * (h * 0.9 - board_t) / max(shelves - 1, 1)
        block(mesh, 0, 0, z, w - post * 1.2, d - post * 0.4, board_t, "board", r=0.02)
    return mesh


def table(w, d, h, **_):
    mesh = MeshData()
    top_t, leg = h * 0.1, min(w, d) * 0.1
    block(mesh, 0, 0, h - top_t, w, d, top_t, "top", r=min(w, d) * 0.08, per_corner=2)
    for sx in (-1, 1):
        for sy in (-1, 1):
            block(mesh, sx * (w / 2 - leg * 1.2), sy * (d / 2 - leg * 1.2), 0, leg, leg, h - top_t, "legs", r=leg * 0.25)
    return mesh


def bench(w, d, h, **_):
    """Park bench: two chunky supports, a seat and a backrest along the back (+Y)."""
    mesh = MeshData()
    seat_z, seat_t = h * 0.45, h * 0.08
    for sx in (-1, 1):
        block(mesh, sx * w * 0.38, 0, 0, w * 0.08, d * 0.9, seat_z, "frame", r=0.03)
    block(mesh, 0, -d * 0.05, seat_z, w, d * 0.75, seat_t, "wood", r=0.04)
    block(mesh, 0, d * 0.4, seat_z + seat_t, w, d * 0.12, h - seat_z - seat_t, "wood", r=0.04)
    return mesh


def lamp_post(w, d, h, **_):
    mesh = MeshData()
    r = w / 2
    mesh.loft(lathe_rings([(r, 0), (r, h * 0.04), (r * 0.35, h * 0.06), (r * 0.25, h * 0.08), (r * 0.2, h * 0.82)], 10),
              ["base", "base", "base", "pole"], cap_bottom="base", cap_top="pole")
    mesh.loft(lathe_rings([(r * 0.3, h * 0.8), (r * 0.7, h * 0.84), (r * 0.75, h * 0.94), (r * 0.5, h * 0.98), (r * 0.2, h)], 10),
              ["lamp", "glow", "lamp", "lamp"], cap_bottom="lamp", cap_top="lamp")
    return mesh


def traffic_cone(w, d, h, **_):
    mesh = MeshData()
    block(mesh, 0, 0, 0, w, d, h * 0.06, "base", r=w * 0.12, per_corner=2)
    r = w * 0.36
    mesh.loft(lathe_rings([(r, h * 0.06), (r * 0.78, h * 0.3), (r * 0.62, h * 0.45), (r * 0.42, h * 0.7), (r * 0.12, h)], 12),
              ["cone", "stripe", "cone", "cone"], cap_bottom="cone", cap_top="cone")
    return mesh


def coin_pickup(w, d, h, **_):
    """Upright coin facing the front (-Y): a thick disc with a raised rim, for collectables."""
    mesh = MeshData()
    r, t = min(w, h) / 2, d
    prof = [(r * 0.9, 0), (r, t * 0.15), (r, t * 0.85), (r * 0.9, t), (r * 0.8, t * 0.92)]
    start = len(mesh.verts)
    mesh.loft(lathe_rings(prof, 16), ["rim"] * 4, cap_bottom="face", cap_top="face")
    mesh.rotate_x(start)
    return mesh.recenter_bottom()


def stylized_tree(w, d, h, tiers=3, seed=1, **_):
    """Trunk plus stacked faceted cones. Low segment counts keep it chunky and under budget."""
    mesh = MeshData()
    rng = random.Random(seed)
    tr = w * 0.09
    mesh.loft(lathe_rings([(tr * 1.4, 0), (tr, h * 0.12), (tr * 0.85, h * 0.4)], 7), ["trunk", "trunk"], cap_bottom="trunk", cap_top="trunk")
    base, top = h * 0.25, h
    step = (top - base) / tiers
    for i in range(tiers):
        z0 = base + i * step * 0.8
        rad = w / 2 * (1 - i / (tiers + 0.6))
        twist = rng.uniform(0, 0.5)
        rings = []
        for rr, zz in ((rad * 0.55, z0), (rad, z0 + step * 0.25), (rad * 0.08, z0 + step * 1.25)):
            rings.append([(-rr * math.sin(2 * math.pi * (k + twist) / 8), rr * math.cos(2 * math.pi * (k + twist) / 8), zz) for k in range(8)])
        mesh.loft(rings, ["foliage", "foliage"], cap_bottom="foliage", cap_top="foliage", smooth=False)
    return mesh


def rock(w, d, h, seed=7, **_):
    """Irregular boulder from jittered rings, deterministic per seed."""
    mesh = MeshData()
    rng = random.Random(seed)
    n = 9
    jitter = [rng.uniform(0.8, 1.15) for _ in range(n)]
    rings = []
    for frac, scale in ((0.0, 0.7), (0.15, 0.95), (0.45, 1.0), (0.75, 0.75), (1.0, 0.3)):
        z = h * frac
        rings.append([(-w / 2 * scale * jitter[k] * math.sin(2 * math.pi * k / n),
                       d / 2 * scale * jitter[(k + 2) % n] * math.cos(2 * math.pi * k / n), z) for k in range(n)])
    mesh.loft(rings, ["stone"] * 4, cap_bottom="stone", cap_top="stone", smooth=False)
    return mesh


def wall_panel(w, d, h, window=False, **_):
    """Modular wall section on a stud grid (for example 8 x 1 x 12). With window=True a frame is
    built as four blocks around an opening, so the opening is real geometry, not a decal."""
    mesh = MeshData()
    if not window:
        block(mesh, 0, 0, 0, w, d, h * 0.08, "trim", r=0.05)
        block(mesh, 0, 0, h * 0.08, w * 0.98, d * 0.8, h * 0.84, "wall", r=0.02)
        block(mesh, 0, 0, h * 0.92, w, d, h * 0.08, "trim", r=0.05)
        return mesh
    ow, oz0, oz1 = w * 0.4, h * 0.35, h * 0.75
    block(mesh, 0, 0, 0, w, d, oz0, "wall", r=0.02)
    block(mesh, 0, 0, oz1, w, d, h - oz1, "wall", r=0.02)
    side = (w - ow) / 2
    for sx in (-1, 1):
        block(mesh, sx * (ow / 2 + side / 2), 0, oz0, side, d, oz1 - oz0, "wall", r=0.02)
    block(mesh, 0, -d * 0.05, oz0 - h * 0.03, ow + w * 0.06, d * 1.1, h * 0.03, "trim", r=0.02)
    return mesh


def floor_tile(w, d, h, **_):
    mesh = MeshData()
    block(mesh, 0, 0, 0, w, d, h, "floor", r=min(w, d) * 0.03, per_corner=1)
    return mesh


GENERATORS = {f.__name__: f for f in (crate, barrel, shelf_unit, table, bench, lamp_post, traffic_cone, coin_pickup,
                                      stylized_tree, rock, wall_panel, floor_tile)}
