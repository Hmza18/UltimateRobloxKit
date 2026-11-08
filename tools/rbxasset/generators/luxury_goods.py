"""Batch 10 and 11 hero shapes: folded Lucci clothes, a hobo bag, statement sunglasses, a diver watch and a gaming headset.

They spend their triangles on what shows at shop size: real folds, relief, chain links and swivelled ear cups.
Raised details print from the same picture as the surface below them, so art runs across them without a break.
"""
from __future__ import annotations

import math

from ..meshkit import MeshData, ellipse, rrect, triangulate
from .packaging import octagon


# ---- Shared pieces ----------------------------------------------------------------------------------
def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _unit(a):
    length = math.sqrt(_dot(a, a))
    return (a[0] / length, a[1] / length, a[2] / length)


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def tube(mesh, path, a, b=None, sides=6, panel="tube", weight=0.1, phase=0.0, up=(0.0, 1.0, 0.0), alternate=False):
    """A closed bar along a 3D path. alternate swaps its section at every station, which reads as chain links."""
    b = a if b is None else b
    rings, e2 = [], _unit(up)
    for i, c in enumerate(path):
        t = _unit(_sub(path[min(i + 1, len(path) - 1)], path[max(i - 1, 0)]))
        # Carry the frame along the path, so the section never twists.
        e2 = _unit(_sub(e2, tuple(t[k] * _dot(e2, t) for k in range(3))))
        e1 = _cross(e2, t)
        ra, rb = (b, a) if alternate and i % 2 else (a, b)
        ring = []
        for k in range(sides):
            ang = 2 * math.pi * k / sides + phase
            ca, sa = ra * math.cos(ang), rb * math.sin(ang)
            ring.append(tuple(c[m] + ca * e1[m] + sa * e2[m] for m in range(3)))
        rings.append(ring)
    ids = mesh.loft(rings, panel, None, None, weights={panel: weight})
    end = panel + "_end"
    mesh.panel(end, 2 * max(a, b), 2 * max(a, b), 0.03)
    uv = [(0.5 + 0.5 * math.cos(2 * math.pi * k / sides), 0.5 + 0.5 * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    for k in range(1, sides - 1):
        mesh.face((ids[0][0], ids[0][k + 1], ids[0][k]), end, [(1 - u, v) for u, v in (uv[0], uv[k + 1], uv[k])])
        mesh.face((ids[-1][0], ids[-1][k], ids[-1][k + 1]), end, (uv[0], uv[k], uv[k + 1]))
    return ids


def plate(mesh, outline, z0, z1, top_map, top_panel, wall_panel, wall_weight=0.03, under_panel=None):
    """A raised shape: its top prints from top_map, and its walls and hidden underside take a plain panel.
    Name an under_panel if the underside shows, and it reads correctly from behind once stood up."""
    low = mesh.add_ring([(x, y, z0) for x, y in outline])
    high = mesh.add_ring([(x, y, z1) for x, y in outline])
    n = len(outline)
    perimeter = sum(math.dist(outline[i], outline[(i + 1) % n]) for i in range(n))
    mesh.panel(wall_panel, perimeter, max(z1 - z0, 1e-3) * 4, wall_weight)
    for i in range(n):
        j = (i + 1) % n
        mesh.face((low[i], low[j], high[j], high[i]), wall_panel, ((i / n, 0), ((i + 1) / n, 0), ((i + 1) / n, 1), (i / n, 1)))
    xs, ys = [p[0] for p in outline], [p[1] for p in outline]
    x0, y0, sx, sy = min(xs), min(ys), max(max(xs) - min(xs), 1e-3), max(max(ys) - min(ys), 1e-3)
    for a, b, c in triangulate(outline):
        mesh.face((high[a], high[b], high[c]), top_panel, [top_map(*outline[k]) for k in (a, b, c)])
        # Seen from the other side, so its map flips left to right.
        mesh.face((low[c], low[b], low[a]), under_panel or wall_panel, [(1 - (outline[k][0] - x0) / sx, (outline[k][1] - y0) / sy) for k in (c, b, a)])


def ring_plate(mesh, outer, inner, z0, z1, top_map, top_panel, wall_panel, wall_weight=0.05):
    """A raised ring between two loops of equal size, such as a lens rim. Its top prints from top_map."""
    n = len(outer)
    out_low = mesh.add_ring([(x, y, z0) for x, y in outer])
    out_high = mesh.add_ring([(x, y, z1) for x, y in outer])
    in_low = mesh.add_ring([(x, y, z0) for x, y in inner])
    in_high = mesh.add_ring([(x, y, z1) for x, y in inner])
    perimeter = sum(math.dist(outer[i], outer[(i + 1) % n]) for i in range(n))
    mesh.panel(wall_panel, perimeter, max(z1 - z0, 1e-3) * 4, wall_weight)
    for i in range(n):
        j = (i + 1) % n
        wall = ((i / n, 0), ((i + 1) / n, 0), ((i + 1) / n, 1), (i / n, 1))
        mesh.face((out_low[i], out_low[j], out_high[j], out_high[i]), wall_panel, wall)
        mesh.face((out_high[i], out_high[j], in_high[j], in_high[i]), top_panel, [top_map(*p) for p in (outer[i], outer[j], inner[j], inner[i])])
        mesh.face((in_high[i], in_high[j], in_low[j], in_low[i]), wall_panel, wall)
        mesh.face((in_low[i], in_low[j], out_low[j], out_low[i]), wall_panel, wall)


def loop_band(mesh, center, radial, up, half_r, half_up, n, panel, inner_panel, length, weight=0.4):
    """A closed strap that loops back on itself. U runs along the loop and V across the strap, so art is one long strip."""
    corners = []
    for i in range(n):
        c, r = center(i / n), radial(i / n)
        for sr, su in ((1, -1), (1, 1), (-1, 1), (-1, -1)):
            corners.append(tuple(c[m] + sr * half_r * r[m] + su * half_up * up[m] for m in range(3)))
    ids = mesh.add_ring(corners)
    mesh.panel(panel, length, half_up * 2, weight)
    mesh.panel(inner_panel, length, half_up * 2, 0.02)
    for i in range(n):
        j = (i + 1) % n
        a, b = i * 4, j * 4
        u0, u1 = i / n, (i + 1) / n
        strip = ((u0, 0), (u1, 0), (u1, 1), (u0, 1))
        mesh.face((ids[a], ids[b], ids[b + 1], ids[a + 1]), panel, strip)  # outer face
        mesh.face((ids[a + 1], ids[b + 1], ids[b + 2], ids[a + 2]), inner_panel, strip)
        mesh.face((ids[a + 2], ids[b + 2], ids[b + 3], ids[a + 3]), inner_panel, strip)  # inner face
        mesh.face((ids[a + 3], ids[b + 3], ids[b], ids[a]), inner_panel, strip)


def _rename(mesh, first_face, mapping):
    for f in mesh.faces[first_face:]:
        f["panel"] = mapping.get(f["panel"], f["panel"])
    for old, new in mapping.items():
        if old in mesh.panels:
            mesh.panels[new] = mesh.panels.pop(old)


def plinth(mesh, w, d, h, c, face_weight=0.5):
    """A low display base, with its own front, back, side and top art."""
    first = len(mesh.faces)
    rings = [octagon(w * 0.975, d * 0.97, 0, c), octagon(w, d, 0, c), octagon(w, d, 0, c), octagon(w * 0.975, d * 0.97, 0, c)]
    zs = (0, h * 0.12, h * 0.86, h)
    rings = [[(x, y, zs[i]) for x, y, _ in r] for i, r in enumerate(rings)]
    mesh.planar_loft(rings, w, d, h, smooth=False, weights={"front": face_weight, "back": face_weight * 0.6, "left": 0.08, "right": 0.08, "top": 0.14, "bottom": 0.03})
    _rename(mesh, first, {k: "base_" + k for k in ("front", "back", "left", "right", "top", "bottom")})


def lathe_piece(mesh, profile, n, face_from, face_panel, radius, side_panel, end_panel, center, normal, face_weight=1.0, side_weight=0.15):
    """A turned part whose front prints one flat picture, such as a dial or an ear cup plate. Its art stays upright when tilted."""
    start = len(mesh.verts)
    rings = [ellipse(r, r, z, n) for r, z in profile]
    ids = [mesh.add_ring(r) for r in rings]
    mesh.panel(face_panel, radius * 2, radius * 2, face_weight)
    length = sum(math.dist(profile[i], profile[i + 1]) for i in range(face_from))
    mesh.panel(side_panel, 2 * math.pi * max(r for r, _ in profile), max(length, 1e-3), side_weight)

    def planar(p):
        return ((p[0] + radius) / (2 * radius), (p[1] + radius) / (2 * radius))

    v = 0.0
    for s in range(len(rings) - 1):
        step = math.dist(profile[s], profile[s + 1]) / max(length, 1e-3)
        for i in range(n):
            j = (i + 1) % n
            quad = (ids[s][i], ids[s][j], ids[s + 1][j], ids[s + 1][i])
            if s >= face_from:
                mesh.face(quad, face_panel, [planar(p) for p in (rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i])])
            else:
                mesh.face(quad, side_panel, ((i / n, v), ((i + 1) / n, v), ((i + 1) / n, v + step), (i / n, v + step)))
        if s < face_from:
            v += step
    for a, b, c in triangulate([(p[0], p[1]) for p in rings[-1]]):
        mesh.face((ids[-1][a], ids[-1][b], ids[-1][c]), face_panel, [planar(rings[-1][k]) for k in (a, b, c)])
    mesh.cap(ids[0], rings[0], end_panel, flip=True, weight=0.03)
    n_axis = _unit(normal)
    u_axis = _unit(_cross((0.0, 0.0, 1.0), n_axis))
    v_axis = _cross(n_axis, u_axis)
    mesh.verts[start:] = [tuple(center[m] + x * u_axis[m] + y * v_axis[m] + z * n_axis[m] for m in range(3)) for x, y, z in mesh.verts[start:]]
    return u_axis, v_axis, n_axis


# ---- Folded clothes ---------------------------------------------------------------------------------
def _folded_stack(mesh, w, d, h, sections, corner, edge_weight=0.5):
    """A soft folded garment lying flat. The top prints as one picture, called front as the guide does, and the folds wrap around it."""
    rings = [rrect(w * s, d * s, corner * s, h * z, 1) for s, z, _ in sections]
    ids = [mesh.add_ring(r) for r in rings]
    kinds = [kind for _, _, kind in sections[1:]]
    mesh.panel("front", w, d, 1.0)
    for name, pw, weight in (("edge_front", w, edge_weight), ("edge_back", w, edge_weight), ("left", d, 0.3), ("right", d, 0.3)):
        mesh.panel(name, pw, h, weight)

    def top_uv(p):
        return ((p[0] + w / 2) / w, (p[1] + d / 2) / d)

    def side_uv(panel, p):
        x, y, z = p
        u = {"edge_front": (x + w / 2) / w, "edge_back": (w / 2 - x) / w, "right": (y + d / 2) / d, "left": (d / 2 - y) / d}[panel]
        return (min(max(u, 0.0), 1.0), min(max(z / h, 0.0), 1.0))

    n = len(rings[0])
    for s, kind in enumerate(kinds):
        for i in range(n):
            j = (i + 1) % n
            pts = (rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i])
            quad = (ids[s][i], ids[s][j], ids[s + 1][j], ids[s + 1][i])
            if kind == "top":
                mesh.face(quad, "front", [top_uv(p) for p in pts], True)
                continue
            ex, ey = (pts[1][0] - pts[0][0]) + (pts[2][0] - pts[3][0]), (pts[1][1] - pts[0][1]) + (pts[2][1] - pts[3][1])
            nx, ny = ey, -ex
            panel = ("right" if nx > 0 else "left") if abs(nx) > 2.0 * abs(ny) else ("edge_front" if ny < 0 else "edge_back")
            mesh.face(quad, panel, [side_uv(panel, p) for p in pts], True)
    for a, b, c in triangulate([(p[0], p[1]) for p in rings[-1]]):
        mesh.face((ids[-1][a], ids[-1][b], ids[-1][c]), "front", [top_uv(rings[-1][k]) for k in (a, b, c)], True)
    mesh.cap(ids[0], rings[0], "bottom", flip=True, weight=0.03)
    return top_uv


FOLD = [(0.95, 0, ""), (1.0, 0.08, "side"), (1.0, 0.42, "side"), (0.965, 0.5, "side"), (1.0, 0.58, "side"), (0.992, 0.86, "side"), (0.945, 0.965, "top"), (0.62, 1.0, "top")]


def folded_tee(w, d, h, **_):
    """Folded tee: two layers, a ribbed crew collar that stands taller at the back, and sleeves folded in as a real layer."""
    mesh = MeshData()
    uv = _folded_stack(mesh, w, d, h, FOLD, min(w, d) * 0.1)
    top = h * 0.985
    for sign in (-1, 1):
        x0, x1 = sign * w * 0.47, sign * w * 0.25
        outline = [(x0, d * 0.28), (x1, d * 0.28), (x1 + sign * w * 0.03, d * 0.2), (x1 + sign * w * 0.03, -d * 0.165), (x0, -d * 0.165), (x0 - sign * w * 0.01, 0)]
        if sign < 0:
            outline = outline[::-1]
        plate(mesh, outline, h * 0.8, h + h * 0.07, lambda x, y: uv((x, y, 0)), "front", "fabric_wall")

    def centre(t):
        a = 2 * math.pi * t
        # Standing taller at the back, like a real neck.
        lift = h * 0.1 * (0.5 + 0.5 * math.sin(a))
        return (w * 0.175 * math.cos(a), d * 0.3 + d * 0.105 * math.sin(a), top + lift)

    def radial(t):
        a = 2 * math.pi * t
        return (math.cos(a), math.sin(a), 0.0)

    loop_band(mesh, centre, radial, (0.0, 0.0, 1.0), w * 0.03, h * 0.17, 14, "collar", "collar_inner", 2 * math.pi * w * 0.15, weight=0.35)
    return mesh


def folded_jeans(w, d, h, **_):
    """Folded jeans: a raised waistband with belt loops and a button, and a raised leather patch."""
    mesh = MeshData()
    uv = _folded_stack(mesh, w, d, h, FOLD, min(w, d) * 0.08)
    mapped = lambda x, y: uv((x, y, 0))  # noqa: E731
    rise = h * 0.08
    base = h * 0.84
    # The waistband runs the full width and stands proud of the folded legs.
    hw, y0, y1, c = w * 0.47, d * 0.3, d * 0.465, d * 0.02
    band = [(-hw, y0 + c), (-hw + c, y0), (0, y0), (hw - c, y0), (hw, y0 + c), (hw, y1 - c), (hw - c, y1), (0, y1), (-hw + c, y1), (-hw, y1 - c)]
    plate(mesh, band, base, h + rise, mapped, "front", "fabric_wall")
    for x in (-0.36, -0.17, 0.17, 0.36):
        xc, half = x * w, w * 0.022
        plate(mesh, [(xc - half, y0 - d * 0.008), (xc + half, y0 - d * 0.008), (xc + half, y1 + d * 0.008), (xc - half, y1 + d * 0.008)], h, h + rise * 1.55, mapped, "front", "fabric_wall")
    # The tan leather patch, with cut corners.
    px, y2, y3, k = w * 0.24, -d * 0.2, d * 0.02, d * 0.018
    patch = [(-px + k, y2), (px - k, y2), (px, y2 + k), (px, y3 - k), (px - k, y3), (-px + k, y3), (-px, y3 - k), (-px, y2 + k)]
    plate(mesh, patch, base, h + h * 0.055, mapped, "front", "patch_wall")
    # The button, on the band's centre.
    r = w * 0.032
    button = [(r * math.cos(2 * math.pi * i / 8), (y0 + y1) / 2 + r * math.sin(2 * math.pi * i / 8)) for i in range(8)]
    plate(mesh, button, h, h + rise * 1.5, mapped, "front", "gold_wall")
    return mesh


# ---- LV Handbag ---------------------------------------------------------------------------------------
BAG_BODY_FRACTION = 0.68


def hobo_bag(w, d, h, **_):
    """Slouchy hobo bag. Its top dips in the middle and rises to the handle, which is a linked chain threaded with leather."""
    mesh = MeshData()
    bh = h * BAG_BODY_FRACTION

    def ring(sw, sd, z, tip=0.0):
        pts = rrect(w * sw, d * sd, min(w * sw, d * sd) * 0.46, 0, 2)
        return [(x, y, bh * (z + tip * (2 * x / (w * sw)) ** 2)) for x, y, _ in pts]

    rings = [ring(0.68, 0.62, 0), ring(0.92, 0.88, 0.05), ring(1.0, 1.0, 0.27), ring(0.97, 0.92, 0.58, 0.03), ring(0.91, 0.64, 0.8, 0.11), ring(0.87, 0.36, 0.88, 0.12)]
    mesh.planar_loft(rings, w, d, bh, smooth="soft", weights={"front": 1.0, "back": 1.0, "left": 0.3, "right": 0.3, "top": 0.2, "bottom": 0.08})
    # The chain: an arch from one clasp to the other.
    ax, az = w * 0.385, bh * 0.965
    top = h - w * 0.03
    path = []
    stations = 17
    for i in range(stations):
        t = math.pi * (1 - i / (stations - 1))
        path.append((ax * math.cos(t), 0.0, az + (top - az) * math.sin(t)))
    tube(mesh, path, w * 0.032, w * 0.017, sides=4, panel="chain", weight=0.5, alternate=True)
    # Gold clasps where the chain meets the bag.
    for sign in (-1, 1):
        x = sign * ax
        tube(mesh, [(x, 0, az - bh * 0.055), (x, 0, az - bh * 0.01), (x, 0, az + bh * 0.05)], w * 0.052, sides=6, panel="clasp", weight=0.04)
    # A gold sparkle charm hanging at the front, on its own short chain.
    sx, sz = -w * 0.29, bh * 0.6
    drop_top = (-w * 0.385, -d * 0.1, az - bh * 0.02)
    tube(mesh, [drop_top, (-w * 0.33, -d * 0.36, bh * 0.82), (sx, -d * 0.47, sz + bh * 0.05)], w * 0.009, sides=4, panel="charm_link", weight=0.02)
    start = len(mesh.verts)
    r = w * 0.058
    mesh.panel("charm", r * 2, r * 2.35, 1.2)
    charm = [(0, -r * 1.25), (r * 0.85, -r * 0.2), (r * 0.6, r * 0.8), (0, r * 1.1), (-r * 0.6, r * 0.8), (-r * 0.85, -r * 0.2)]
    plate(mesh, charm, -d * 0.03, d * 0.03, lambda x, y: ((x + r) / (2 * r), (y + r * 1.25) / (r * 2.35)), "charm", "clasp_wall")
    mesh.rotate_x(start)
    mesh.translate(start, sx, -d * 0.47, sz)
    return mesh


# ---- Channel Sunglasses ---------------------------------------------------------------------------------
LENS = {"cx": 0.262, "rx": 0.205, "ry": 0.4, "cy": 0.46, "power": 0.62}


def lens_loop(w, h, sign, scale, n, start=0.0, end=2 * math.pi):
    """A soft-cornered lens shape, as a counter-clockwise loop."""
    pts = []
    for i in range(n):
        a = start + (end - start) * i / n
        ca, sa = math.cos(a), math.sin(a)
        x = abs(ca) ** LENS["power"] * math.copysign(1, ca)
        y = abs(sa) ** LENS["power"] * math.copysign(1, sa)
        pts.append((sign * LENS["cx"] * w + x * LENS["rx"] * w * scale, LENS["cy"] * h + y * LENS["ry"] * h * scale))
    return pts


def _tapered_bar(mesh, a, b, panel, other):
    """A temple arm from end a to end b, each given as x, y, z and half sizes. Its back face prints left to right from behind."""
    x0, y0, z0, hy0, hz0 = a
    x1, y1, z1, hy1, hz1 = b
    corners = [(x0, y0 - hy0, z0 - hz0), (x1, y1 - hy1, z1 - hz1), (x1, y1 + hy1, z1 - hz1), (x0, y0 + hy0, z0 - hz0),
               (x0, y0 - hy0, z0 + hz0), (x1, y1 - hy1, z1 + hz1), (x1, y1 + hy1, z1 + hz1), (x0, y0 + hy0, z0 + hz0)]
    ids = mesh.add_ring(corners)
    length = abs(x1 - x0)
    mesh.panel(panel, length, (hy0 + hy1), 0.75)
    mesh.panel(other, length, hy0 + hy1, 0.02)
    square = ((0, 0), (1, 0), (1, 1), (0, 1))
    rising = x1 > x0
    # Local +z becomes the front after the frame stands up, so the -z face is what shows from behind.
    faces = [((0, 3, 2, 1) if rising else (0, 1, 2, 3), panel), ((4, 5, 6, 7) if rising else (4, 7, 6, 5), other),
             ((0, 1, 5, 4) if rising else (0, 4, 5, 1), other), ((3, 7, 6, 2) if rising else (3, 2, 6, 7), other),
             ((0, 4, 7, 3) if rising else (0, 3, 7, 4), other), ((1, 2, 6, 5) if rising else (1, 5, 6, 2), other)]
    for order, name in faces:
        p = [corners[k] for k in order]
        if name == panel:
            xs = [q[0] for q in p]
            lo, hi = min(xs), max(xs)
            # The bar tapers and drifts, so v follows its own edges and print stays straight along it.
            uv = [((hi - q[0]) / (hi - lo), 1.0 if k in (2, 3, 6, 7) else 0.0) for q, k in zip(p, order)]
        else:
            uv = square
        mesh.face(tuple(ids[k] for k in order), name, uv)


def statement_shades(w, d, h, **_):
    """Folded acetate frames standing on their rim, with raised rims, a thick brow bar, gold diamond studs and folded temples."""
    mesh = MeshData()
    t = d * 0.26
    top_map = lambda x, y: ((x + w / 2) / w, y / h)  # noqa: E731
    mesh.panel("front", w, h, 1.0)
    mesh.panel("back", w, h, 0.5)
    # The plate backs both lenses completely, so nothing shows through at their corners.
    lower_left = lens_loop(w, h, -1, 0.92, 8, math.pi, 2 * math.pi)
    lower_right = lens_loop(w, h, 1, 0.92, 8, math.pi, 2 * math.pi)
    inner = (LENS["cx"] - LENS["rx"] * 0.92) * w
    base = lower_left + [(-inner, LENS["cy"] * h), (0.0, h * 0.5), (inner, LENS["cy"] * h)] + lower_right[1:] + [(w * 0.47, h * 0.62), (w * 0.47, h * 0.84), (w * 0.43, h * 0.95), (-w * 0.43, h * 0.95), (-w * 0.47, h * 0.84), (-w * 0.47, h * 0.62)]
    plate(mesh, base, 0.0, t, top_map, "front", "frame_wall", wall_weight=0.06, under_panel="back")
    for sign in (-1, 1):
        outer = lens_loop(w, h, sign, 1.0, 12)
        inner = lens_loop(w, h, sign, 0.82, 12)
        ring_plate(mesh, outer, inner, t * 0.6, t * 1.32, top_map, "front", "frame_wall", wall_weight=0.06)
    brow = [(-w * 0.5, h * 0.69), (-w * 0.26, h * 0.755), (0.0, h * 0.715), (w * 0.26, h * 0.755), (w * 0.5, h * 0.69), (w * 0.5, h * 0.9), (w * 0.47, h), (-w * 0.47, h), (-w * 0.5, h * 0.9)]
    plate(mesh, brow, t * 0.7, t * 1.58, top_map, "front", "frame_wall", wall_weight=0.06)
    # A gold diamond stud on each end piece.
    mesh.panel("stud", 0.05, 0.05, 0.05)
    for sign in (-1, 1):
        cx, cy, r = sign * w * 0.44, h * 0.85, h * 0.078
        ring = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
        base_ids = mesh.add_ring([(x, y, t * 1.4) for x, y in ring])
        apex = mesh.add_ring([(cx, cy, t * 1.95)])[0]
        uv = ((0, 0), (1, 0), (0.5, 1))
        for i in range(4):
            mesh.face((base_ids[i], base_ids[(i + 1) % 4], apex), "stud", uv)
        mesh.face((base_ids[0], base_ids[3], base_ids[2]), "stud", uv)
        mesh.face((base_ids[0], base_ids[2], base_ids[1]), "stud", uv)
    # Temples folded behind, crossing without touching. Each hinge sinks into the frame.
    y_a, y_b = h * 0.76, h * 0.56
    _tapered_bar(mesh, (w * 0.455, y_a, t * 0.3, h * 0.085, d * 0.07), (-w * 0.44, y_a - h * 0.03, -d * 0.32, h * 0.075, d * 0.05), "temple", "temple_edge")
    _tapered_bar(mesh, (-w * 0.455, y_b, t * 0.3, h * 0.07, d * 0.07), (w * 0.44, y_b - h * 0.08, -d * 0.62, h * 0.05, d * 0.05), "temple_plain", "temple_edge")
    mesh.rotate_x()
    return mesh


# ---- Rolux Watch -------------------------------------------------------------------------------------
def diver_watch(w, d, h, **_):
    """A diver watch wrapped around a cushion on a slim base, its dial tilted up toward the shopper."""
    mesh = MeshData()
    base_h = h * 0.13
    plinth(mesh, w, d, base_h, min(w, d) * 0.07, face_weight=1.0)
    # The cushion, laid across the base.
    start = len(mesh.verts)
    rz, ry = h * 0.345, d * 0.3
    half = w * 0.33
    zc = base_h + rz * 0.93
    mesh.loft([ellipse(rz * 0.8, ry * 0.8, -half, 10), ellipse(rz * 0.98, ry * 0.98, -half * 0.78, 10), ellipse(rz, ry, half * 0.78, 10), ellipse(rz * 0.8, ry * 0.8, half, 10)],
              ["pillow_end", "pillow", "pillow_end"], "pillow_cap", "pillow_cap", smooth="soft", weights={"pillow": 0.16, "pillow_end": 0.05, "pillow_cap": 0.03})
    mesh.rotate_y(start)
    mesh.translate(start, 0, 0, zc)
    # The bracelet wraps the cushion.
    band_half = w * 0.17
    br_z, br_y = rz * 1.05, ry * 1.05

    def centre(t):
        a = 2 * math.pi * t
        return (0.0, br_y * math.cos(a), zc + br_z * math.sin(a))

    def radial(t):
        a = 2 * math.pi * t
        return (0.0, math.cos(a), math.sin(a))

    loop_band(mesh, centre, radial, (1.0, 0.0, 0.0), h * 0.018, band_half, 10, "bracelet", "bracelet_inner", 2 * math.pi * (br_z + br_y) / 2, weight=0.55)
    # The case, tilted up by the same angle the bracelet carries it.
    tilt = math.radians(14)
    normal = (0.0, -math.cos(tilt), math.sin(tilt))
    radius = w * 0.34
    t = h * 0.15
    center = (0.0, -br_y * math.cos(tilt) + h * 0.004, zc + br_z * math.sin(tilt))
    u, _, n = lathe_piece(mesh, [(radius * 0.86, -t * 0.28), (radius * 0.97, t * 0.22), (radius, t * 0.58), (radius * 0.84, t * 0.8), (radius * 0.78, t * 0.66)], 16, 2, "front", radius, "case", "case_back", center, normal, side_weight=0.1)
    # The winding knob at three o'clock.
    knob = tuple(center[m] + u[m] * radius * 0.94 + n[m] * t * 0.28 for m in range(3))
    tube(mesh, [knob, tuple(knob[m] + u[m] * radius * 0.17 for m in range(3)), tuple(knob[m] + u[m] * radius * 0.25 for m in range(3))], radius * 0.11, sides=4, panel="knob", weight=0.02, up=(0.0, 0.0, 1.0))
    return mesh


# ---- IronSeries Headsets -----------------------------------------------------------------------------
def gaming_headset(w, d, h, **_):
    """An over-ear headset on a steel plinth: padded band, cups swivelled toward the shopper and a boom mic with a lit tip."""
    mesh = MeshData()
    base_h = h * 0.085
    plinth(mesh, w, d, base_h, min(w, d) * 0.1, face_weight=1.0)
    cup_r = h * 0.235
    cx = w * 0.345
    cz = base_h + cup_r * 1.0
    swing = math.radians(40)
    t = cup_r * 0.8
    for sign in (-1, 1):
        normal = (sign * math.cos(swing), -math.sin(swing), 0.0)
        # The cushion faces in, the shell faces out, and the plate prints the emblem.
        lathe_piece(mesh, [(cup_r * 0.82, -t * 0.98), (cup_r * 1.0, -t * 0.55), (cup_r * 0.9, t * 0.1), (cup_r * 0.8, t * 0.2)], 12, 2, "front", cup_r * 0.9, "cup", "cushion_face",
                    (sign * cx, 0.0, cz), normal, side_weight=0.2)
    # The padded band, from one cup over the top to the other.
    top = h - h * 0.025
    az = cz + cup_r * 0.82
    ax = cx
    path = []
    stations = 14
    for i in range(stations):
        a = math.pi * (1 - i / (stations - 1))
        path.append((ax * math.cos(a), 0.0, az + (top - az) * math.sin(a) ** 0.82))
    tube(mesh, path, h * 0.038, d * 0.2, sides=4, panel="band", weight=0.16, phase=math.pi / 4)
    # The boom mic sweeps forward from the left cup.
    mic = [(cx, -cup_r * 0.1, cz - cup_r * 0.4), (cx - cup_r * 0.18, -d * 0.42, cz - cup_r * 0.62), (cx * 0.62, -d * 0.48, cz - cup_r * 0.5), (cx * 0.36, -d * 0.47, cz - cup_r * 0.26)]
    tube(mesh, mic, h * 0.016, sides=4, panel="mic", weight=0.05, up=(0.0, 0.0, 1.0))
    return mesh


GENERATORS = {f.__name__: f for f in (folded_tee, folded_jeans, hobo_bag, statement_shades, diver_watch, gaming_headset)}
