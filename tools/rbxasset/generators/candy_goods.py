"""Candy shapes from the guide: wrapped bar on its long edge, see-through bag, domed lollipop, stand-up pouch, puffy pouch."""
from __future__ import annotations

from ..meshkit import MeshData, ellipse, lathe_rings, triangulate
from .packaging import add_box, octagon
from .pet_goods import slotted_sheet


def wrapped_bar(w, d, h, **_):
    """Candy bar standing on its long edge, lofted along its length, with crimped end fins and a printed back."""
    mesh = MeshData()
    W, H = w, h

    def section(x, sd, sh, c):
        hd, hh = d * sd / 2, h * sh / 2
        mid = h / 2
        # Counter-clockwise seen from the +X end, where +Y is right and +Z is up.
        return [(x, -hd + c, mid - hh), (x, hd - c, mid - hh), (x, hd, mid - hh + c), (x, hd, mid + hh - c), (x, hd - c, mid + hh), (x, -hd + c, mid + hh), (x, -hd, mid + hh - c), (x, -hd, mid - hh + c)]

    c = d * 0.2
    fin = w * 0.055
    sections = [section(-w / 2, 0.1, 0.84, 0.002), section(-w / 2 + fin, 0.1, 0.8, 0.002), section(-w / 2 + fin * 1.5, 0.82, 0.9, c * 0.8), section(-w / 2 + fin * 2.4, 1.0, 1.0, c),
                section(0, 1.0, 1.0, c), section(w / 2 - fin * 2.4, 1.0, 1.0, c), section(w / 2 - fin * 1.5, 0.82, 0.9, c * 0.8), section(w / 2 - fin, 0.1, 0.8, 0.002), section(w / 2, 0.1, 0.84, 0.002)]
    ids = [mesh.add_ring(r) for r in sections]
    mesh.panel("front", W, H, 1.0)
    mesh.panel("back", W, H, 1.0)
    mesh.panel("edge", W, d, 0.22)
    mesh.panel("fin_end", d, H, 0.03)

    def uv(seg, p):
        x, y, z = p
        if seg in (5, 6, 7):
            return "front", ((x + W / 2) / W, z / H)
        if seg in (1, 2, 3):
            return "back", ((W / 2 - x) / W, z / H)
        ny = (y + d / 2) / d
        return "edge", ((x + W / 2) / W, ny if seg == 4 else 1 - ny)

    for s in range(len(sections) - 1):
        for i in range(8):
            j = (i + 1) % 8
            panel = uv(i, sections[s][i])[0]
            pts = (sections[s][i], sections[s][j], sections[s + 1][j], sections[s + 1][i])
            mesh.face((ids[s][i], ids[s][j], ids[s + 1][j], ids[s + 1][i]), panel, [uv(i, q)[1] for q in pts], smooth=True)
    for ring, index, flip in ((sections[0], 0, True), (sections[-1], -1, False)):
        for a, b, cc in triangulate([(p[1], p[2]) for p in ring]):
            tri = (a, b, cc)[::-1] if flip else (a, b, cc)
            lo, span = min(p[1] for p in ring), max(max(p[1] for p in ring) - min(p[1] for p in ring), 1e-4)
            mesh.face(tuple(ids[index][k] for k in tri), "fin_end", [(1 - (ring[k][1] - lo) / span if flip else (ring[k][1] - lo) / span, ring[k][2] / H) for k in tri])
    return mesh


def clear_bag(w, d, h, **_):
    """See-through pillow bag with solid crimped seals and 12 real marshmallows inside."""
    mesh = MeshData()

    def ring(sw, sd, z):
        return ellipse(w * sw / 2, max(d * sd, 0.012) / 2, z, 12)

    rings = [ring(0.97, 0.05, 0), ring(0.97, 0.05, h * 0.06), ring(0.99, 0.6, h * 0.14), ring(1.0, 1.0, h * 0.5), ring(0.99, 0.6, h * 0.86), ring(0.97, 0.05, h * 0.94), ring(0.97, 0.05, h)]
    mesh.planar_loft(rings, w, d, h, smooth=True, weights={"front": 1.0, "back": 1.0, "top": 0.04, "bottom": 0.04}, sides=False)
    r = w * 0.12
    length = d * 0.42
    grid = [(ix, iz) for iz in range(4) for ix in range(3)]
    for k, (ix, iz) in enumerate(grid):
        start = len(mesh.verts)
        name = "marsh_a" if k % 2 == 0 else "marsh_b"
        mesh.loft(lathe_rings([(r, length * 0.14), (r * 0.9, length)], 6), name, f"{name}_end", f"{name}_end", smooth="soft", weights={name: 0.1, f"{name}_end": 0.1})
        mesh.rotate_x(start)
        x = (ix - 1) * w * 0.27 + (iz % 2) * w * 0.03
        z = h * 0.2 + iz * h * 0.195
        mesh.translate(start, x, length * 0.5 + (0.03 if (ix + iz) % 2 else -0.03) * d, z)
    return mesh


def domed_lollipop(w, d, h, **_):
    """Giant lollipop: faces domed like a hill, thin at the rim and round in the middle, on a stick in a display base."""
    mesh = MeshData()
    base_h = h * 0.17
    add_box(mesh, w * 0.72, d, base_h, c=d * 0.08, prefix="base_", weights={"front": 0.55, "back": 0.45, "left": 0.12, "right": 0.12, "top": 0.2, "bottom": 0.03})
    start = len(mesh.verts)
    stick_top = h - w
    mesh.loft(lathe_rings([(w * 0.022, base_h * 0.5), (w * 0.022, stick_top + w * 0.2)], 8), "stick", "stick_end", "stick_end", weights={"stick": 0.08, "stick_end": 0.03})
    R = w / 2
    t = d / 2 * 0.98
    start = len(mesh.verts)
    profile = [(R * 0.14, -t), (R * 0.56, -t * 0.82), (R * 0.88, -t * 0.32), (R, 0), (R * 0.88, t * 0.32), (R * 0.56, t * 0.82), (R * 0.14, t)]
    n = 20
    rings = lathe_rings(profile, n)
    ids = [mesh.add_ring(r) for r in rings]
    mesh.panel("front", w, w, 1.0)
    mesh.panel("back", w, w, 0.75)
    mesh.panel("swirl_rim", w, 0.1, 0.02)

    def front_uv(p):
        return ((p[0] + R) / w, (p[1] + R) / w)

    def back_uv(p):
        return ((R - p[0]) / w, (p[1] + R) / w)

    for s in range(len(rings) - 1):
        panel, mapper = ("back", back_uv) if s < 3 else ("front", front_uv)
        for i in range(n):
            j = (i + 1) % n
            pts = (rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i])
            uv = [mapper(q) for q in pts]
            mesh.face((ids[s][i], ids[s][j], ids[s + 1][j], ids[s + 1][i]), panel, uv, smooth="soft")
    flat = [(q[0], q[1]) for q in rings[-1]]
    for a, b, c in triangulate(flat):
        mesh.face((ids[-1][a], ids[-1][b], ids[-1][c]), "front", [front_uv(rings[-1][k]) for k in (a, b, c)], smooth="soft")
    for a, b, c in triangulate([(q[0], q[1]) for q in rings[0]]):
        mesh.face((ids[0][c], ids[0][b], ids[0][a]), "back", [back_uv(rings[0][k]) for k in (c, b, a)], smooth="soft")
    mesh.rotate_x(start)
    mesh.translate(start, 0, 0, h - R)
    return mesh


def standup_pouch(w, d, h, **_):
    """Stand-up pouch: gusseted bottom, flat sides, and an orange top seal with a real hang hole."""
    mesh = MeshData()
    top = h * 0.86
    c = d * 0.14
    rings = [octagon(w * 0.92, d * 0.9, 0, c), octagon(w, d, h * 0.035, c), octagon(w, d * 0.92, h * 0.42, c), octagon(w * 0.99, d * 0.66, h * 0.68, c * 0.8),
             octagon(w * 0.98, d * 0.24, h * 0.82, c * 0.3), octagon(w * 0.97, d * 0.09, top, c * 0.1)]
    mesh.planar_loft(rings, w, d, top, smooth=True, weights={"front": 1.0, "back": 1.0, "left": 0.45, "right": 0.45, "top": 0.04, "bottom": 0.04})
    slotted_sheet(mesh, w * 0.96, h * 0.845, h, d * 0.12, (w * 0.09, h * 0.905, h * 0.965), weights=(0.35, 0.25, 0.04))
    return mesh


def puffy_pouch(w, d, h, **_):
    """Puffy candy pouch with crimped seals top and bottom."""
    mesh = MeshData()

    def ring(sw, sd, z):
        return ellipse(w * sw / 2, max(d * sd, 0.012) / 2, z, 12)

    rings = [ring(0.96, 0.08, 0), ring(0.96, 0.08, h * 0.08), ring(0.99, 0.62, h * 0.17), ring(1.0, 0.95, h * 0.34), ring(1.0, 1.0, h * 0.5), ring(1.0, 0.95, h * 0.66),
             ring(0.99, 0.62, h * 0.83), ring(0.96, 0.08, h * 0.92), ring(0.96, 0.08, h)]
    mesh.planar_loft(rings, w, d, h, smooth=True, weights={"front": 1.0, "back": 1.0, "top": 0.04, "bottom": 0.04}, sides=False)
    return mesh


GENERATORS = {f.__name__: f for f in (wrapped_bar, clear_bag, domed_lollipop, standup_pouch, puffy_pouch)}
