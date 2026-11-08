"""Boxes, cartons, bags, pouches, wrappers, trays and frozen/pet food packaging."""
from __future__ import annotations

from ..meshkit import MeshData, ellipse, rrect


def add_box(mesh, w, d, h, c=0.012, bulge=0.0, flap=False, flap_t=0.012, prefix="", weights=None):
    """Chamfered, panel-mapped box. Vertical chamfers borrow the neighbouring front/back art,
    so no seam shows at the corners. bulge bows the large faces like real filled cardboard.
    Top may carry a raised tuck flap. Total height including the flap is h."""
    # Narrow sides carry the same copy as wide ones, so they get more of the texture.
    side = 1.0 if d / w < 0.5 else 0.6
    weights = weights or {"front": 1.0, "back": 1.0, "left": side, "right": side, "top": 0.4, "bottom": 0.05}
    body_h = h - flap_t if flap else h

    def ring(z, inset=0.0, by=0.0):
        hw, hd = w / 2 - inset, d / 2 - inset + by
        return [
            (-hw + c, -hd, z), (hw - c, -hd, z), (hw, -hd + c, z), (hw, hd - c, z),
            (hw - c, hd, z), (-hw + c, hd, z), (-hw, hd - c, z), (-hw, -hd + c, z),
        ]

    rings = [ring(0, inset=c), ring(c), ring(body_h / 2, by=bulge), ring(body_h - c), ring(body_h, inset=c)]
    ids = [mesh.add_ring(r) for r in rings]
    names = {k: prefix + k for k in ("front", "back", "left", "right", "top", "bottom")}
    mesh.panel(names["front"], w, body_h, weights["front"])
    mesh.panel(names["back"], w, body_h, weights["back"])
    mesh.panel(names["left"], d, body_h, weights["left"])
    mesh.panel(names["right"], d, body_h, weights["right"])
    mesh.panel(names["top"], w, d, weights["top"])
    mesh.panel(names["bottom"], w, d, weights["bottom"])

    def uv_for(seg, p):
        x, y, z = p
        v = min(max(z / body_h, 0.0), 1.0)
        if seg in (7, 0, 1):
            return names["front"], ((x + w / 2) / w, v)
        if seg in (3, 4, 5):
            return names["back"], ((w / 2 - x) / w, v)
        if seg == 2:
            return names["right"], ((y + d / 2) / d, v)
        return names["left"], ((d / 2 - y) / d, v)

    for s in range(len(rings) - 1):
        for i in range(8):
            j = (i + 1) % 8
            corners = [rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i]]
            uv = [uv_for(i, p)[1] for p in corners]
            mesh.face((ids[s][i], ids[s][j], ids[s + 1][j], ids[s + 1][i]), uv_for(i, corners[0])[0], uv, smooth=bulge > 0)

    top_uv = lambda p: ((p[0] + w / 2) / w, (p[1] + d / 2) / d)  # noqa: E731
    bottom_uv = lambda p: ((p[0] + w / 2) / w, (d / 2 - p[1]) / d)  # noqa: E731
    _fan(mesh, ids[0], rings[0], names["bottom"], bottom_uv, flip=True)
    if not flap:
        _fan(mesh, ids[-1], rings[-1], names["top"], top_uv)
        return
    fw, f0, f1 = w / 2 - 2.2 * c, -d / 2 + d * 0.30, d / 2 - 2.2 * c
    flap_ring = lambda z, e=0.0: [  # noqa: E731
        (-fw + c + e, f0 + e, z), (fw - c - e, f0 + e, z), (fw - e, f0 + c + e, z), (fw - e, f1 - c - e, z),
        (fw - c - e, f1 - e, z), (-fw + c + e, f1 - e, z), (-fw + e, f1 - c - e, z), (-fw + e, f0 + c + e, z),
    ]
    extra = [flap_ring(body_h), flap_ring(h, 0.004)]
    prev_ring, prev_ids = rings[-1], ids[-1]
    for r in extra:
        cur = mesh.add_ring(r)
        for i in range(8):
            j = (i + 1) % 8
            corners = [prev_ring[i], prev_ring[j], r[j], r[i]]
            mesh.face((prev_ids[i], prev_ids[j], cur[j], cur[i]), names["top"], [top_uv(p) for p in corners])
        prev_ring, prev_ids = r, cur
    _fan(mesh, prev_ids, prev_ring, names["top"], top_uv)


def _fan(mesh, ids, ring, panel, uv_fn, flip=False):
    from ..meshkit import triangulate

    for a, b, c in triangulate([(p[0], p[1]) for p in ring]):
        tri = (a, b, c)[::-1] if flip else (a, b, c)
        mesh.face(tuple(ids[k] for k in tri), panel, [uv_fn(ring[k]) for k in tri])


def carton_box(w, d, h, flap=True, **_):
    mesh = MeshData()
    # A thin box cannot show a raised flap or a bulge without looking broken.
    flap = flap and min(w, d, h) > 0.2
    add_box(mesh, w, d, h, c=min(w, d, h) * 0.05, bulge=d * 0.025 if flap else 0.0, flap=flap)
    return mesh


def bag_gusset(w, d, h, **_):
    """Flat-bottom sack (rice, flour, pet food): full belly, folded top seal."""
    mesh = MeshData()
    r = d * 0.42
    rings = [rrect(w * 0.9, d * 0.8, r * 0.8, 0), rrect(w * 0.98, d * 0.98, r, h * 0.05), rrect(w, d, r, h * 0.4),
             rrect(w * 0.98, d * 0.86, r * 0.85, h * 0.72), rrect(w * 0.96, d * 0.34, r * 0.3, h * 0.9),
             rrect(w * 0.97, d * 0.1, r * 0.1, h * 0.93), rrect(w * 0.97, d * 0.1, r * 0.1, h)]
    mesh.loft(rings, ["body"] * 4 + ["neck", "seal"], weights={"body": 1.0, "neck": 0.3, "seal": 0.2})
    return mesh


def pouch_pillow(w, d, h, **_):
    """Pillow bag (candy, fries): crimped seal at both ends."""
    mesh = MeshData()
    n = 14
    rings = [ellipse(w * 0.49, d * 0.05, 0, n), ellipse(w * 0.49, d * 0.05, h * 0.05, n), ellipse(w * 0.5, d * 0.34, h * 0.14, n),
             ellipse(w * 0.5, d * 0.5, h * 0.5, n), ellipse(w * 0.5, d * 0.34, h * 0.86, n),
             ellipse(w * 0.49, d * 0.05, h * 0.95, n), ellipse(w * 0.49, d * 0.05, h, n)]
    mesh.loft(rings, ["seal_b", "body", "body", "body", "body", "seal_t"], weights={"body": 1.0, "seal_b": 0.2, "seal_t": 0.2})
    return mesh


def octagon(w, d, z, c):
    """Eight-point ring, counter-clockwise from above, starting at the front-left."""
    hw, hd = w / 2, d / 2
    return [(-hw + c, -hd, z), (hw - c, -hd, z), (hw, -hd + c, z), (hw, hd - c, z),
            (hw - c, hd, z), (-hw + c, hd, z), (-hw, hd - c, z), (-hw, -hd + c, z)]


def sliced_loaf_bag(w, d, h, **_):
    """Upright bag of 12 modeled slices, gathered and tied on top. Guide: Sal's bread.
    Slices are real grooves, so the art's crust lines must match SLICE_ZONE in the template."""
    mesh = MeshData()
    step = h * 0.8 / 12
    c = min(w, d) * 0.16
    rings = []
    for i in range(12):
        if i:
            rings.append(octagon(w * 0.975, d * 0.965, i * step, c))
        rings.append(octagon(w, d, (i + 0.5) * step, c * 0.9))
    rings.insert(0, octagon(w * 0.93, d * 0.92, 0, c))
    rings.append(octagon(w * 0.16, d * 0.2, h * 0.875, w * 0.04))
    rings.append(octagon(w * 0.42, d * 0.42, h, w * 0.08))
    mesh.planar_loft(rings, w, d, h, smooth=True, weights=_bag_weights())
    return mesh


def _bag_weights():
    return {"front": 1.0, "back": 1.0, "left": 0.6, "right": 0.6, "top": 0.1, "bottom": 0.05}


def pillow_bag(w, d, h, **_):
    """Pillow bag with flat crimped seals top and bottom and a full belly. Guide: Pasta."""
    mesh = MeshData()

    def ring(sw, sd, z):
        # An elliptical ring has no vertical side edges, which would collapse in the front/back map.
        return ellipse(w * sw / 2, max(d * sd, 0.012) / 2, z, 12)

    rings = [ring(0.97, 0.05, 0), ring(0.97, 0.05, h * 0.055), ring(0.99, 0.5, h * 0.13), ring(1.0, 0.88, h * 0.3),
             ring(1.0, 1.0, h * 0.5), ring(1.0, 0.88, h * 0.7), ring(0.99, 0.5, h * 0.87), ring(0.97, 0.05, h * 0.945), ring(0.97, 0.05, h)]
    mesh.planar_loft(rings, w, d, h, smooth=True, weights=_bag_weights(), sides=False)
    return mesh


def paper_sack(w, d, h, **_):
    """Paper flour sack: block bottom, soft full body, folded and glued top with a raised flap."""
    mesh = MeshData()
    c = min(w, d) * 0.1
    rings = [octagon(w * 0.95, d * 0.95, 0, c), octagon(w, d, h * 0.03, c), octagon(w * 1.0, d * 1.0, h * 0.42, c * 1.3),
             octagon(w * 0.99, d * 0.96, h * 0.74, c * 1.2), octagon(w * 0.97, d * 0.6, h * 0.86, c * 0.6),
             octagon(w * 0.95, d * 0.2, h * 0.93, c * 0.25), octagon(w * 0.95, d * 0.2, h, c * 0.25)]
    mesh.planar_loft(rings, w, d, h, smooth=True, weights=_bag_weights())
    return mesh


def wrapper_bar(w, d, h, **_):
    """Foil-wrapped bar lying flat with its label up, crimped ends along X."""
    mesh = MeshData()
    n = 12
    # Lofted along Z, then laid along X. Local X becomes -Z (height), local Y stays depth.
    rings = [ellipse(h * 0.08, d * 0.47, 0, n), ellipse(h * 0.08, d * 0.47, w * 0.05, n), ellipse(h * 0.46, d * 0.5, w * 0.11, n),
             ellipse(h * 0.5, d * 0.5, w * 0.5, n), ellipse(h * 0.46, d * 0.5, w * 0.89, n),
             ellipse(h * 0.08, d * 0.47, w * 0.95, n), ellipse(h * 0.08, d * 0.47, w, n)]
    mesh.loft(rings, ["seal_b", "body", "body", "body", "body", "seal_t"], weights={"body": 1.0, "seal_b": 0.2, "seal_t": 0.2})
    mesh.rotate_y()
    return mesh


def wrapper_block(w, d, h, **_):
    """Vacuum-wrapped block of cheese."""
    mesh = MeshData()
    r = min(w, d) * 0.08
    rings = [rrect(w * 0.97, d * 0.96, r, 0, 1), rrect(w, d, r, h * 0.1, 1), rrect(w, d, r, h * 0.9, 1), rrect(w * 0.97, d * 0.96, r, h, 1)]
    mesh.loft(rings, "body", smooth=False, weights={"cap_top": 1.0})
    return mesh


def tray_lidded(w, d, h, **_):
    """Frozen meal tray: tapered tub, lip, film lid."""
    mesh = MeshData()
    r = min(w, d) * 0.14
    rings = [rrect(w * 0.84, d * 0.84, r * 0.8, 0, 1), rrect(w * 0.9, d * 0.9, r, h * 0.72, 1), rrect(w, d, r, h * 0.78, 1),
             rrect(w, d, r, h * 0.9, 1), rrect(w * 0.94, d * 0.94, r, h, 1)]
    mesh.loft(rings, ["tray", "tray", "lip", "lip"], weights={"cap_top": 1.0, "tray": 0.5, "lip": 0.2})
    return mesh


GENERATORS = {f.__name__: f for f in (sliced_loaf_bag, pillow_bag, paper_sack, carton_box, bag_gusset, pouch_pillow, wrapper_bar, wrapper_block, tray_lidded)}
