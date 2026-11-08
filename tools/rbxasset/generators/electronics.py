"""Electronics: TV, console, phone, game case, headset."""
from __future__ import annotations

from ..meshkit import MeshData, arc, lathe_rings, rrect, triangulate
from .packaging import add_box


def _slab(mesh, w, thick, h, r, front="front", back="back", side="side", cz=None, cy=0.0, cx=0.0):
    """Upright rounded slab whose large face looks along -Y. Built lying down, then stood up."""
    start = len(mesh.verts)
    t = thick
    c = min(t * 0.25, r)
    rings = [rrect(w - 2 * c, h - 2 * c, r, 0, 2), rrect(w, h, r, c, 2), rrect(w, h, r, t - c, 2), rrect(w - 2 * c, h - 2 * c, r, t, 2)]
    mesh.loft(rings, side, back, front, smooth=False, weights={front: 1.0, back: 0.5, side: 0.15})
    mesh.rotate_x(start)
    mesh.translate(start, cx, cy + t / 2, (h / 2) if cz is None else cz)
    return start


def phone(w, d, h, **_):
    mesh = MeshData()
    _slab(mesh, w, d, h, w * 0.14)
    start = len(mesh.verts)
    cam = w * 0.17
    mesh.loft([rrect(cam * 2, cam * 2, cam * 0.45, 0, 1), rrect(cam * 2, cam * 2, cam * 0.45, d * 0.2, 1)], "camera", "camera", "camera", weights={"camera": 0.15})
    mesh.rotate_x(start)
    # Rotated bump points to -Y; flip it to the back by mirroring across the slab centre is not
    # orientation-preserving, so it is placed through the slab and protrudes past the back face.
    mesh.translate(start, -w * 0.22, d * 1.15, h * 0.82)
    return mesh


def tv_flat(w, d, h, **_):
    """Flat-screen TV on a foot: panel, neck, base."""
    mesh = MeshData()
    panel_h, panel_t = h * 0.88, d * 0.2
    _slab(mesh, w, panel_t, panel_h, w * 0.012, cz=h - panel_h / 2, cy=-panel_t / 2)
    start = len(mesh.verts)
    add_box(mesh, w * 0.12, d * 0.16, h * 0.14, c=d * 0.02, prefix="neck_", weights={"front": 0.1, "back": 0.1, "left": 0.1, "right": 0.1, "top": 0.1, "bottom": 0.1})
    start = len(mesh.verts)
    add_box(mesh, w * 0.42, d, h * 0.03, c=d * 0.03, prefix="foot_", weights={"front": 0.1, "back": 0.1, "left": 0.1, "right": 0.1, "top": 0.2, "bottom": 0.1})
    return mesh


def console_box(w, d, h, **_):
    """Upright games console tower with a raised vent cap."""
    mesh = MeshData()
    add_box(mesh, w, d, h * 0.94, c=w * 0.05)
    start = len(mesh.verts)
    add_box(mesh, w * 0.82, d * 0.86, h * 0.07, c=w * 0.03, prefix="vent_", weights={"front": 0.1, "back": 0.1, "left": 0.1, "right": 0.1, "top": 0.25, "bottom": 0.05})
    mesh.translate(start, 0, 0, h * 0.93)
    return mesh


def game_case(w, d, h, **_):
    """Clamshell game case: front and back covers overhang a slightly inset page block, around one solid spine.
    The covers' rounded rims carry the cover art, so no edge colour shows around it."""
    mesh = MeshData()
    c = min(w, h) * 0.035
    groove = d * 0.09
    y0 = -d / 2

    def ring(y, inset=0.0, open_side=0.0):
        """Eight points seen from the front. open_side moves the top, bottom and right edges in, leaving the spine."""
        x0, x1, z0, z1 = -w / 2 + inset, w / 2 - inset - open_side, inset + open_side, h - inset - open_side
        return [(x0 + c, y, z0), (x1 - c, y, z0), (x1, y, z0 + c), (x1, y, z1 - c), (x1 - c, y, z1), (x0 + c, y, z1), (x0, y, z1 - c), (x0, y, z0 + c)]

    bevel = d * 0.14
    rings = [ring(y0, bevel * 0.5), ring(y0 + bevel), ring(-d * 0.24), ring(-d * 0.2, open_side=groove), ring(d * 0.2, open_side=groove), ring(d * 0.24), ring(d / 2 - bevel), ring(d / 2, bevel * 0.5)]
    ids = [mesh.add_ring(r) for r in rings]
    weights = {"front": 1.0, "back": 0.9, "left": 1.0, "right": 0.05, "top": 0.05, "bottom": 0.05}
    for name, pw, ph in (("front", w, h), ("back", w, h), ("left", d, h), ("right", d, h), ("top", w, d), ("bottom", w, d)):
        mesh.panel(name, pw, ph, weights[name])

    def mapped(panel, p):
        x, y, z = p
        return {"front": ((x + w / 2) / w, z / h), "back": ((w / 2 - x) / w, z / h), "left": ((d / 2 - y) / d, z / h), "right": ((y + d / 2) / d, z / h),
                "top": ((x + w / 2) / w, (y + d / 2) / d), "bottom": ((x + w / 2) / w, (d / 2 - y) / d)}[panel]

    # Each edge of the ring belongs to one side panel, and the end spans belong to the covers.
    side_of = {0: "bottom", 1: "right", 2: "right", 3: "right", 4: "top", 5: "left", 6: "left", 7: "left"}
    last = len(rings) - 2
    for s in range(last + 1):
        for i in range(8):
            j = (i + 1) % 8
            panel = "front" if s == 0 else "back" if s == last else side_of[i]
            corners = (rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i])
            # Rings run from front to back, so this order faces outward.
            mesh.face((ids[s][i], ids[s + 1][i], ids[s + 1][j], ids[s][j]), panel, [mapped(panel, q) for q in (corners[0], corners[3], corners[2], corners[1])])
    for end, panel, flip in ((0, "front", False), (len(rings) - 1, "back", True)):
        ring_ids, pts = ids[end], rings[end]
        for a, b, e in triangulate([(q[0], q[2]) for q in pts]):
            tri = (a, b, e)[::-1] if flip else (a, b, e)
            mesh.face(tuple(ring_ids[k] for k in tri), panel, [mapped(panel, pts[k]) for k in tri])
    return mesh


def flat_box(w, d, h, **_):
    """Retail box lying flat. As in the guide, the lid art takes the texture's front block and the long edges share the side block."""
    mesh = MeshData()
    add_box(mesh, w, d, h, c=h * 0.1, weights={"front": 0.5, "back": 0.5, "left": 0.4, "right": 0.4, "top": 1.0, "bottom": 0.6})
    rename = {"top": "front", "front": "edge_front", "back": "edge_back"}
    mesh.panels = {rename.get(k, k): v for k, v in mesh.panels.items()}
    for f in mesh.faces:
        f["panel"] = rename.get(f["panel"], f["panel"])
    return mesh


def headset(w, d, h, **_):
    """Over-ear gaming headset: headband arc, two ear cups."""
    mesh = MeshData()
    t = h * 0.07
    cx, cz = 0.0, h * 0.5
    outer = arc(cx, cz, w * 0.42, h * 0.5, 0, 180, 10)
    inner = arc(cx, cz, w * 0.42 - t, h * 0.5 - t, 180, 0, 10)
    start = len(mesh.verts)
    mesh.extrude(outer + inner, -d * 0.2, d * 0.2, "band", "band_side", "band_side", True)
    mesh.rotate_x(start)
    for sign in (-1, 1):
        start = len(mesh.verts)
        r = d * 0.5
        mesh.loft(lathe_rings([(r * 0.7, 0), (r, w * 0.03), (r, w * 0.12), (r * 0.8, w * 0.16)], 12), "cup", "cup_cap", "cup_cap", weights={"cup": 0.5, "cup_cap": 0.5})
        mesh.rotate_y(start)
        mesh.translate(start, sign * w * 0.42 - w * 0.08, 0, r)
    return mesh


GENERATORS = {f.__name__: f for f in (phone, tv_flat, console_box, game_case, flat_box, headset)}
