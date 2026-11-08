"""Organic and soft goods: bread, toys, candy, clothing, accessories, paper rolls."""
from __future__ import annotations

from ..meshkit import MeshData, arc, ellipse, lathe_rings, rrect
from .electronics import _slab


def bread_loaf(w, d, h, **_):
    """Sliced loaf: mushroom-top cross section lofted along its length."""
    mesh = MeshData()

    def slice_ring(y, s=1.0):
        # Cross-section is drawn in local (x, y) where local y is height; loft axis is local z.
        hw, hh = w / 2 * s, h / 2 * s
        outline = [(hw * 0.86, -hh), (hw * 0.92, -hh * 0.2), (hw * 0.84, hh * 0.1), (hw, hh * 0.4), (hw * 0.86, hh * 0.86), (hw * 0.4, hh),
                   (-hw * 0.4, hh), (-hw * 0.86, hh * 0.86), (-hw, hh * 0.4), (-hw * 0.84, hh * 0.1), (-hw * 0.92, -hh * 0.2), (-hw * 0.86, -hh)]
        return [(x, yy, y) for x, yy in outline]

    rings = [slice_ring(0, 0.94), slice_ring(d * 0.04), slice_ring(d * 0.33, 1.0), slice_ring(d * 0.66, 1.0), slice_ring(d * 0.96), slice_ring(d, 0.94)]
    mesh.loft(rings, "body", "back_end", "front_end", weights={"body": 1.0, "front_end": 0.7, "back_end": 0.4})
    mesh.rotate_x()
    return mesh


def paper_rolls(w, d, h, **_):
    """Four toilet-paper rolls in a 2 x 2 pack."""
    mesh = MeshData()
    r = w * 0.25
    for ix in (-1, 1):
        for iy in (-1, 1):
            start = len(mesh.verts)
            mesh.loft(lathe_rings([(r * 0.94, 0), (r, h * 0.03), (r, h * 0.97), (r * 0.94, h)], 12), "body", "roll_end", "roll_end", weights={"body": 1.0, "roll_end": 0.3})
            mesh.translate(start, ix * r, iy * r)
    return mesh


def pet_toy_bone(w, d, h, **_):
    """Chew-bone toy: shaft with bulbous ends, laid along X."""
    mesh = MeshData()
    r = d / 2
    profile = [(r * 0.3, 0), (r * 0.8, w * 0.03), (r, w * 0.1), (r * 0.8, w * 0.18), (r * 0.46, w * 0.25), (r * 0.46, w * 0.75),
               (r * 0.8, w * 0.82), (r, w * 0.9), (r * 0.8, w * 0.97), (r * 0.3, w)]
    mesh.loft(lathe_rings(profile, 10), "body", "end", "end", weights={"body": 1.0, "end": 0.15})
    mesh.rotate_y()
    return mesh


def lollipop(w, d, h, **_):
    """Swirl lollipop: disc on a stick, disc faces the product front."""
    mesh = MeshData()
    stick_r = min(w, d) * 0.07
    mesh.loft(lathe_rings([(stick_r, 0), (stick_r, h * 0.6)], 6), "stick", "stick_cap", "stick_cap", weights={"stick": 0.15, "stick_cap": 0.05})
    start = len(mesh.verts)
    r = w / 2
    t = d
    mesh.loft(lathe_rings([(r * 0.7, 0), (r * 0.94, t * 0.2), (r, t * 0.5), (r * 0.94, t * 0.8), (r * 0.7, t)], 16), "rim", "swirl_back", "swirl", weights={"swirl": 1.0, "swirl_back": 0.6, "rim": 0.2})
    mesh.rotate_x(start)
    mesh.translate(start, 0, t / 2, h - r)
    return mesh


def clothing_shirt(w, d, h, **_):
    """Hanging T-shirt silhouette with thickness, front toward -Y."""
    mesh = MeshData()
    outline = [(-w * 0.28, 0), (w * 0.28, 0), (w * 0.28, h * 0.62), (w * 0.38, h * 0.54), (w * 0.5, h * 0.72), (w * 0.3, h * 0.97), (w * 0.12, h),
               (w * 0.05, h * 0.92), (-w * 0.05, h * 0.92), (-w * 0.12, h), (-w * 0.3, h * 0.97), (-w * 0.5, h * 0.72), (-w * 0.38, h * 0.54), (-w * 0.28, h * 0.62)]
    mesh.extrude(outline, -d / 2, d / 2, "seam", "back", "front", False)
    mesh.panels["front"]["weight"], mesh.panels["back"]["weight"] = 1.0, 0.7
    mesh.panels["seam"]["weight"] = 0.15
    mesh.rotate_x()
    return mesh


def clothing_pants(w, d, h, **_):
    """Hanging trousers silhouette with thickness, front toward -Y."""
    mesh = MeshData()
    outline = [(-w * 0.5, 0), (-w * 0.08, 0), (0, h * 0.62), (w * 0.08, 0), (w * 0.5, 0), (w * 0.44, h * 0.92), (w * 0.44, h), (-w * 0.44, h), (-w * 0.44, h * 0.92)]
    mesh.extrude(outline, -d / 2, d / 2, "seam", "back", "front", False)
    mesh.panels["front"]["weight"], mesh.panels["back"]["weight"] = 1.0, 0.7
    mesh.panels["seam"]["weight"] = 0.15
    mesh.rotate_x()
    return mesh


def handbag(w, d, h, **_):
    """Structured handbag with arched handle."""
    mesh = MeshData()
    bh = h * 0.68
    r = d * 0.2
    rings = [rrect(w, d, r, 0, 1), rrect(w, d, r, bh * 0.04, 1), rrect(w * 0.9, d * 0.8, r, bh * 0.96, 1), rrect(w * 0.88, d * 0.76, r, bh, 1)]
    mesh.loft(rings, "body", weights={"body": 1.0, "cap_top": 0.3, "cap_bottom": 0.15})
    start = len(mesh.verts)
    t = h * 0.045
    outer = arc(0, bh * 0.95, w * 0.3, h - bh * 0.95, 0, 180, 8)
    inner = arc(0, bh * 0.95, w * 0.3 - t, h - bh * 0.95 - t, 180, 0, 8)
    mesh.extrude(outer + inner, -d * 0.05, d * 0.05, "handle", "handle_cap", "handle_cap", True)
    mesh.rotate_x(start)
    return mesh


def sunglasses(w, d, h, **_):
    """Sunglasses, front toward -Y: one-piece frame with lenses, two temple arms."""
    mesh = MeshData()
    t = d * 0.08
    lens_w, cy = w * 0.22, h / 2
    right = arc(w * 0.27, cy, lens_w, h * 0.5, -180, 180, 10)[:-1]
    left = arc(-w * 0.27, cy, lens_w, h * 0.5, 0, 360, 10)[:-1]
    # Bridge the two lenses into a single outline, walking the lower edge then the upper edge.
    lower_right = [p for p in right if p[1] <= cy]
    upper_right = [p for p in right if p[1] > cy]
    lower_left = [p for p in left if p[1] <= cy]
    upper_left = [p for p in left if p[1] > cy]
    outline = sorted(lower_left, key=lambda p: p[0]) + [(0, cy - h * 0.1)] + sorted(lower_right, key=lambda p: p[0]) + \
        sorted(upper_right, key=lambda p: -p[0]) + [(0, cy + h * 0.16)] + sorted(upper_left, key=lambda p: -p[0])
    mesh.extrude(outline, 0, t, "rim", "back", "front", False)
    mesh.panels["front"]["weight"], mesh.panels["rim"]["weight"] = 1.0, 0.2
    mesh.rotate_x()
    for sign in (-1, 1):
        start = len(mesh.verts)
        arm = [(0, 0), (d - t, 0), (d - t, h * 0.09), (0, h * 0.09)]
        mesh.extrude(arm, -w * 0.012, w * 0.012, "arm", "arm_cap", "arm_cap", False)
        mesh.rotate_y(start)
        mesh.translate(start, sign * w * 0.485, -t * 0 + 0, cy + h * 0.14)
    return mesh


def watch(w, d, h, **_):
    """Wristwatch displayed standing in a closed loop: dial facing -Y, strap behind."""
    mesh = MeshData()
    strap_w = w * 0.5
    cx, cz, rx, rz = 0.0, h * 0.5, d * 0.5, h * 0.5
    t = d * 0.06
    outer = arc(cx, cz, rx, rz, -80, 260, 16)
    inner = arc(cx, cz, rx - t, rz - t, 260, -80, 16)
    mesh.extrude(outer + inner, -strap_w / 2, strap_w / 2, "strap", "strap_edge", "strap_edge", True, )
    mesh.rotate_y()
    start = len(mesh.verts)
    r = w * 0.42
    case_t = d * 0.2
    mesh.loft(lathe_rings([(r * 0.86, 0), (r, case_t * 0.2), (r, case_t * 0.8), (r * 0.9, case_t)], 16), "case", "case_back", "dial", weights={"dial": 1.0, "case": 0.25, "case_back": 0.1})
    mesh.rotate_x(start)
    mesh.translate(start, 0, -rx + case_t * 0.7, cz)
    return mesh


GENERATORS = {f.__name__: f for f in (bread_loaf, paper_rolls, pet_toy_bone, lollipop, clothing_shirt, clothing_pants, handbag, sunglasses, watch)}
