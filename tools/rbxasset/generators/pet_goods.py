"""Batch 4 shapes from the guide: rice bag with a handle flap, pet food bags, plush toy on a card, litter box."""
from __future__ import annotations

import math

from ..meshkit import MeshData, ellipse, lathe_rings, triangulate
from .packaging import add_box, octagon


def slotted_sheet(mesh, w, z0, z1, thick, hole, front="flap", back="flap_back", edge="flap_edge", weights=(0.4, 0.3, 0.05)):
    """A thin upright sheet with a real rectangular hole, front toward -Y, built as a closed frame.
    Both faces read upright from their own side. Returns its first vertex index."""
    start = len(mesh.verts)
    hw = w / 2
    hx, hz0, hz1 = hole
    outer = [(-hw, z0), (hw, z0), (hw, z1), (-hw, z1)]
    inner = [(-hx, hz0), (hx, hz0), (hx, hz1), (-hx, hz1)]
    mesh.panel(front, w, z1 - z0, weights[0])
    mesh.panel(back, w, z1 - z0, weights[1])
    mesh.panel(edge, thick * 4, thick * 4, weights[2])
    fo = mesh.add_ring([(x, -thick / 2, z) for x, z in outer])
    fi = mesh.add_ring([(x, -thick / 2, z) for x, z in inner])
    bo = mesh.add_ring([(x, thick / 2, z) for x, z in outer])
    bi = mesh.add_ring([(x, thick / 2, z) for x, z in inner])
    front_uv = lambda q: ((q[0] + hw) / w, (q[1] - z0) / (z1 - z0))  # noqa: E731
    back_uv = lambda q: ((hw - q[0]) / w, (q[1] - z0) / (z1 - z0))  # noqa: E731
    wall = ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))
    for i in range(4):
        j = (i + 1) % 4
        mesh.face((fo[i], fo[j], fi[j], fi[i]), front, [front_uv(q) for q in (outer[i], outer[j], inner[j], inner[i])])
        mesh.face((bo[j], bo[i], bi[i], bi[j]), back, [back_uv(q) for q in (outer[j], outer[i], inner[i], inner[j])])
        mesh.face((fo[i], bo[i], bo[j], fo[j]), edge, wall)
        mesh.face((fi[j], bi[j], bi[i], fi[i]), edge, wall)
    return start


def basmati_bag(w, d, h, **_):
    """Rice sack: pillow body with crimped seals, and a clear handle flap with a real hole."""
    mesh = MeshData()
    body = h * 0.84

    def ring(sw, sd, z):
        return ellipse(w * sw / 2, max(d * sd, 0.012) / 2, z, 12)

    rings = [ring(0.97, 0.05, 0), ring(0.97, 0.05, body * 0.05), ring(0.99, 0.55, body * 0.12), ring(1.0, 0.9, body * 0.3), ring(1.0, 1.0, body * 0.5),
             ring(1.0, 0.88, body * 0.72), ring(0.98, 0.45, body * 0.9), ring(0.96, 0.05, body * 0.97), ring(0.96, 0.05, body)]
    mesh.planar_loft(rings, w, d, body, smooth=True, weights={"front": 1.0, "back": 1.0, "top": 0.05, "bottom": 0.05}, sides=False)
    # Thicker than the crimp it grips, so the crimp sits fully inside and no faces share a plane.
    slotted_sheet(mesh, w * 0.84, body * 0.975, h, d * 0.065, (w * 0.17, h * 0.885, h * 0.955))
    return mesh


def folded_pet_bag(w, d, h, **_):
    """Dog-food bag: block bottom, flat gusset sides, and a folded sealed top with a handle slot."""
    mesh = MeshData()
    top = h * 0.875
    c = d * 0.16
    rings = [octagon(w * 0.94, d * 0.88, 0, c), octagon(w, d, h * 0.04, c), octagon(w, d, h * 0.45, c), octagon(w * 0.98, d * 0.88, h * 0.7, c),
             octagon(w * 0.96, d * 0.34, h * 0.84, c * 0.5), octagon(w * 0.95, d * 0.12, top, c * 0.15)]
    mesh.planar_loft(rings, w, d, top, smooth=True, weights={"front": 1.0, "back": 1.0, "left": 0.55, "right": 0.55, "top": 0.05, "bottom": 0.05})
    slotted_sheet(mesh, w * 0.95, h * 0.85, h, d * 0.1, (w * 0.18, h * 0.915, h * 0.965), weights=(0.3, 0.25, 0.05))
    return mesh


def crimped_pet_bag(w, d, h, **_):
    """Cat-food bag: block bottom, full body and a crimped pillow-style seal at the top."""
    mesh = MeshData()
    c = d * 0.16
    rings = [octagon(w * 0.92, d * 0.86, 0, c), octagon(w, d, h * 0.04, c), octagon(w, d, h * 0.5, c), octagon(w * 0.99, d * 0.8, h * 0.74, c),
             octagon(w * 0.97, d * 0.3, h * 0.88, c * 0.5), octagon(w * 0.96, d * 0.07, h * 0.92, c * 0.12), octagon(w * 0.96, d * 0.07, h, c * 0.12)]
    mesh.planar_loft(rings, w, d, h, smooth=True, weights={"front": 1.0, "back": 1.0, "left": 0.55, "right": 0.55, "top": 0.05, "bottom": 0.05})
    return mesh


def _bone_outline(width, height, n=28):
    """Points around a vertical bone: a clear shaft with two round lobes at each end."""
    shaft = width * 0.36
    lobe = width * 0.2
    cx, cz = width * 0.5 - lobe, height * 0.5 - lobe * 0.95

    def inside(x, z):
        if abs(x) <= shaft / 2 and abs(z) <= cz:
            return True
        return any(math.hypot(x - sx * cx, z - sz * cz) <= lobe for sx in (-1, 1) for sz in (-1, 1))

    points = []
    for i in range(n):
        a = 2 * math.pi * (i + 0.5) / n
        far = 0.0
        t = 0.0
        while t < max(width, height):
            if inside(t * math.cos(a), t * math.sin(a)):
                far = t
            t += 0.002
        points.append((far * math.cos(a), far * math.sin(a)))
    return points


def plush_toy_card(w, d, h, **_):
    """Kraft hang card on a fold-back foot, with a puffy smooth plush bone on its front and an elastic band."""
    mesh = MeshData()
    bone_depth = d * 0.27
    thick = d * 0.05
    card_y = -d / 2 + bone_depth
    # The card starts inside the foot, so their undersides never share a plane.
    start = slotted_sheet(mesh, w, h * 0.012, h, thick, (w * 0.11, h * 0.925, h * 0.965), "front", "back", "card_edge", (1.0, 0.8, 0.05))
    mesh.translate(start, 0, card_y + thick / 2, 0)
    # The fold-back foot that lets the card stand on a shelf.
    start = len(mesh.verts)
    foot_d = d - bone_depth
    add_box(mesh, w * 0.94, foot_d - thick * 0.4, h * 0.022, c=h * 0.003, prefix="foot_", weights={k: 0.08 for k in ("front", "back", "left", "right", "top", "bottom")})
    # Starts just behind the card's face, so the two never share a plane.
    mesh.translate(start, 0, card_y + thick * 0.4 + (foot_d - thick * 0.4) / 2, 0)
    # A puffy bone: the outline shrinks toward the card and the front, and everything shades smooth.
    bw, bh = w * 0.8, h * 0.61
    center_z = h * 0.395
    outline = _bone_outline(bw, bh)
    # Starts inside the card, so its back never shares a plane with the card's front.
    layers = [(0.7, -thick * 0.4 / bone_depth, "bone_back"), (1.0, 0.45, "bone_back"), (0.9, 0.78, "bone"), (0.6, 1.0, "bone")]
    mesh.panel("bone", bw, bh, 1.0)
    mesh.panel("bone_back", bw, bh, 0.1)
    ids = []
    rings = []
    for scale, depth, _p in layers:
        ring = [(x * scale, card_y - bone_depth * depth, center_z + z * scale) for x, z in outline]
        rings.append(ring)
        ids.append(mesh.add_ring(ring))
    n = len(outline)

    def uv(p):
        return ((p[0] + bw / 2) / bw, (p[2] - center_z + bh / 2) / bh)

    for s in range(len(layers) - 1):
        panel = layers[s + 1][2]
        for i in range(n):
            j = (i + 1) % n
            # Rings step toward the viewer at the front, with points counter-clockwise seen from there.
            quad = (ids[s][i], ids[s][j], ids[s + 1][j], ids[s + 1][i])
            pts = (rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i])
            mesh.face(quad, panel, [_flip_u(uv(q), panel) for q in pts], smooth="soft")
    flat = [(x, z) for x, z in outline]
    for a, b, c in triangulate(flat):
        mesh.face((ids[-1][a], ids[-1][b], ids[-1][c]), "bone", [uv(rings[-1][k]) for k in (a, b, c)], smooth="soft")
        mesh.face((ids[0][c], ids[0][b], ids[0][a]), "bone_back", [_flip_u(uv(rings[0][k]), "bone_back") for k in (c, b, a)], smooth="soft")
    # The elastic band that straps the toy to the card.
    start = len(mesh.verts)
    add_box(mesh, w * 0.86, bone_depth * 0.5, h * 0.03, c=h * 0.004, prefix="band_", weights={k: 0.06 for k in ("front", "back", "left", "right", "top", "bottom")})
    mesh.translate(start, 0, card_y - bone_depth * 0.5, center_z - bh * 0.17)
    return mesh


def _flip_u(uv, panel):
    return (1 - uv[0], uv[1]) if panel == "bone_back" else uv


def litter_box(w, d, h, **_):
    """Hooded self-cleaning litter box: grey base, white hood, tinted door flap, drawer and a side cover with crank."""
    mesh = MeshData()
    cover_out = w * 0.065
    bw = w - cover_out
    c = min(bw, d) * 0.1
    rings = [octagon(bw * 0.96, d * 0.96, 0, c), octagon(bw, d, h * 0.05, c), octagon(bw, d, h * 0.33, c), octagon(bw * 0.975, d * 0.975, h * 0.345, c),
             octagon(bw * 0.96, d * 0.96, h * 0.62, c), octagon(bw * 0.84, d * 0.82, h * 0.86, c * 1.2), octagon(bw * 0.62, d * 0.6, h, c)]
    mesh.planar_loft(rings, bw, d, h, smooth=False, weights={"front": 1.0, "back": 0.9, "left": 0.6, "right": 0.6, "top": 0.8, "bottom": 0.04})
    # Tinted door flap: an arch on the hood's front.
    start = len(mesh.verts)
    ax, z0, z1 = bw * 0.21, h * 0.355, h * 0.78
    arch = [(-ax, z0), (ax, z0), (ax, z1 - ax * 0.7)] + [(ax * math.cos(math.pi * i / 6), z1 - ax * 0.7 + ax * 0.7 * math.sin(math.pi * i / 6)) for i in range(1, 6)] + [(-ax, z1 - ax * 0.7)]
    mesh.extrude(arch, -d * 0.1, d * 0.1, "flap_edge", "flap_back", "flap", False)
    mesh.panels["flap"]["weight"], mesh.panels["flap_back"]["weight"], mesh.panels["flap_edge"]["weight"] = 0.3, 0.02, 0.04
    mesh.rotate_x(start)
    mesh.translate(start, 0, -d * 0.39, 0)
    # The waste drawer, carrying the sticker with the product name.
    start = len(mesh.verts)
    add_box(mesh, bw * 0.62, d * 0.06, h * 0.21, c=h * 0.008, prefix="drawer_", weights={"front": 0.5, "back": 0.03, "left": 0.03, "right": 0.03, "top": 0.03, "bottom": 0.03})
    mesh.translate(start, 0, -d * 0.475, h * 0.075)
    # Side cover with a crank, on +X.
    start = len(mesh.verts)
    r = h * 0.2
    mesh.loft(lathe_rings([(r, 0), (r, cover_out * 0.62), (r * 0.82, cover_out * 0.8)], 12), "cover", "cover_face", "cover_face", weights={"cover": 0.08, "cover_face": 0.15})
    mesh.rotate_y(start)
    mesh.translate(start, bw * 0.47, 0, h * 0.28)
    start = len(mesh.verts)
    mesh.loft(lathe_rings([(r * 0.14, 0), (r * 0.14, cover_out * 0.25)], 6), "crank", "crank", "crank", weights={"crank": 0.04})
    mesh.rotate_y(start)
    mesh.translate(start, bw * 0.47 + cover_out * 0.75, 0, h * 0.28)
    return mesh


GENERATORS = {f.__name__: f for f in (basmati_bag, folded_pet_bag, crimped_pet_bag, plush_toy_card, litter_box)}
