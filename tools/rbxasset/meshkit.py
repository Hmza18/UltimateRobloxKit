"""Blender-independent mesh building and validation.

Generators produce a MeshData: vertices, faces, and per-corner UVs expressed in *panel space*
(0..1 inside a named panel such as "front"). The atlas module later places panels on the 1024
texture, so geometry and artwork share one layout without either knowing about the other.
All closed-surface checks here run in plain Python, so generators can be tested without Blender.
"""
from __future__ import annotations

import math
from collections import defaultdict


class MeshData:
    def __init__(self):
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[dict] = []
        self.panels: dict[str, dict] = {}

    def panel(self, name: str, phys_w: float, phys_h: float, weight: float = 1.0):
        current = self.panels.get(name)
        if current:
            current["w"], current["h"] = max(current["w"], phys_w), max(current["h"], phys_h)
        else:
            self.panels[name] = {"w": max(phys_w, 1e-3), "h": max(phys_h, 1e-3), "weight": weight}

    def add_ring(self, ring) -> list[int]:
        start = len(self.verts)
        self.verts.extend((float(x), float(y), float(z)) for x, y, z in ring)
        return list(range(start, len(self.verts)))

    def face(self, idx, panel: str, uv, smooth: bool = False):
        self.faces.append({"v": tuple(idx), "panel": panel, "uv": tuple(uv), "smooth": smooth})

    # ---- surface builders -------------------------------------------------------------
    def loft(self, rings, span_panels, cap_bottom="cap_bottom", cap_top="cap_top", smooth=True, weights=None):
        """Skin rings of equal vertex count, closed around and capped at both ends.

        rings go bottom to top and run counter-clockwise seen from above. span_panels names a
        wrap-around panel per span. Consecutive spans sharing a name share one continuous panel.
        """
        weights = weights or {}
        ids = [self.add_ring(r) for r in rings]
        n = len(rings[0])
        if isinstance(span_panels, str):
            span_panels = [span_panels] * (len(rings) - 1)
        vs = _wrap_v(rings, span_panels)
        perim = {}
        for s, p in enumerate(span_panels):
            perim[p] = max(perim.get(p, 0), _perimeter(rings[s]), _perimeter(rings[s + 1]))
        for p, (_, _, length) in vs.items():
            self.panel(p, perim[p], length, weights.get(p, 1.0))
        for s, p in enumerate(span_panels):
            v0, v1 = vs[p][0][s], vs[p][0][s + 1]
            for i in range(n):
                j = (i + 1) % n
                self.face(
                    (ids[s][i], ids[s][j], ids[s + 1][j], ids[s + 1][i]),
                    p,
                    ((i / n, v0), ((i + 1) / n, v0), ((i + 1) / n, v1), (i / n, v1)),
                    smooth,
                )
        if cap_bottom:
            self.cap(ids[0], rings[0], cap_bottom, flip=True, weight=weights.get(cap_bottom, 0.5))
        if cap_top:
            self.cap(ids[-1], rings[-1], cap_top, flip=False, weight=weights.get(cap_top, 0.5))
        return ids

    def wrap_loft(self, rings, spans, cap_bottom="bottom", cap_top="top", smooth=True, weights=None):
        """Lathe-style skin with a wrap-around label, following the guide's sleeve rule.

        Spans named "label" print the front art over the front half and the back art over the back
        half, reading left to right from each side. Other spans wrap one plain panel. Ring size
        must be a multiple of 4 so the art changes exactly at the product's sides.
        """
        weights = weights or {}
        n = len(rings[0])
        if n % 4:
            raise ValueError("wrap_loft rings need a vertex count divisible by 4")
        ids = [self.add_ring(r) for r in rings]
        vs = _wrap_v(rings, spans)
        perimeter = {}
        for s, name in enumerate(spans):
            perimeter[name] = max(perimeter.get(name, 0), _perimeter(rings[s]), _perimeter(rings[s + 1]))
        for name, (_, _, length) in vs.items():
            if name == "label":
                for side in ("front", "back"):
                    self.panel(side, perimeter[name] / 2, length, weights.get(side, 1.0))
                    self.panels[side]["curved"] = True
            else:
                self.panel(name, perimeter[name], length, weights.get(name, 0.2))
        for s, name in enumerate(spans):
            v0, v1 = vs[name][0][s], vs[name][0][s + 1]
            for i in range(n):
                j = (i + 1) % n
                f0 = i / n
                f1 = (i + 1) / n
                if name != "label":
                    panel, u0, u1 = name, f0, f1
                elif 0.25 <= f0 < 0.75:
                    panel, u0, u1 = "front", (f0 - 0.25) * 2, (f1 - 0.25) * 2
                else:
                    start = f0 if f0 >= 0.75 else f0 + 1
                    panel, u0, u1 = "back", (start - 0.75) * 2, (start + 1 / n - 0.75) * 2
                self.face((ids[s][i], ids[s][j], ids[s + 1][j], ids[s + 1][i]), panel, ((u0, v0), (u1, v0), (u1, v1), (u0, v1)), smooth)
        self.cap(ids[0], rings[0], cap_bottom, flip=True, weight=weights.get(cap_bottom, 0.05))
        self.cap(ids[-1], rings[-1], cap_top, flip=False, weight=weights.get(cap_top, 0.1))
        return ids

    def planar_loft(self, rings, w, d, h, smooth=True, weights=None, sides=True):
        """Skin rings with box-like projection for soft packaging.

        Each quad joins front, back, left or right by the way it faces, so bag art reads like a
        printed flat label. Maps use the bag's full width and height, so tapered tops take the
        matching part of the art. Reading direction is correct from every side. Only quads facing
        mostly sideways join a side panel, so rounded corners keep the front art. Pass sides=False
        for lens-shaped pillow bags, which have no flat sides: side art would cut across the front.
        """
        weights = weights or {}
        ids = [self.add_ring(r) for r in rings]
        n = len(rings[0])
        for name, pw in (("front", w), ("back", w)) + ((("left", d), ("right", d)) if sides else ()):
            self.panel(name, pw, h, weights.get(name, 1.0))

        def mapped(panel, p):
            x, y, z = p
            v = min(max(z / h, 0.0), 1.0)
            u = {"front": (x + w / 2) / w, "back": (w / 2 - x) / w, "right": (y + d / 2) / d, "left": (d / 2 - y) / d}[panel]
            return (min(max(u, 0.0), 1.0), v)

        for s in range(len(rings) - 1):
            for i in range(n):
                j = (i + 1) % n
                a, b, c, e = rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i]
                # Outward horizontal normal of a quad on a counter-clockwise ring.
                ex, ey = (b[0] - a[0]) + (c[0] - e[0]), (b[1] - a[1]) + (c[1] - e[1])
                nx, ny = ey, -ex
                if sides and abs(nx) > 2.0 * abs(ny):
                    panel = "right" if nx > 0 else "left"
                else:
                    panel = "front" if ny < 0 else "back"
                self.face((ids[s][i], ids[s][j], ids[s + 1][j], ids[s + 1][i]), panel, [mapped(panel, q) for q in (a, b, c, e)], smooth)
        self.cap(ids[0], rings[0], "bottom", flip=True, weight=weights.get("bottom", 0.05))
        self.cap(ids[-1], rings[-1], "top", flip=False, weight=weights.get("top", 0.1))
        return ids

    def cap(self, ids, ring, panel, flip=False, weight=0.5):
        xs, ys = [p[0] for p in ring], [p[1] for p in ring]
        x0, y0 = min(xs), min(ys)
        w, h = max(max(xs) - x0, 1e-3), max(max(ys) - y0, 1e-3)
        self.panel(panel, w, h, weight)
        # A bottom cap is seen from below, so v flips to keep its art unmirrored.
        uv = {i: ((ring[k][0] - x0) / w, 1 - (ring[k][1] - y0) / h if flip else (ring[k][1] - y0) / h) for k, i in enumerate(ids)}
        for a, b, c in triangulate([(p[0], p[1]) for p in ring]):
            tri = (ids[a], ids[b], ids[c])
            if flip:
                tri = tri[::-1]
            self.face(tri, panel, tuple(uv[i] for i in tri))

    def extrude(self, outline, z0, z1, side="side", bottom="cap_bottom", top="cap_top", smooth=False):
        """Extrude a CCW outline from z0 to z1 (may be non-convex)."""
        outline = ensure_ccw(outline)
        return self.loft(
            [[(x, y, z0) for x, y in outline], [(x, y, z1) for x, y in outline]], side, bottom, top, smooth
        )

    # ---- helpers ----------------------------------------------------------------------
    def tri_count(self) -> int:
        return sum(len(f["v"]) - 2 for f in self.faces)

    def bounds(self):
        xs, ys, zs = zip(*self.verts)
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

    def recenter_bottom(self):
        (x0, y0, z0), (x1, y1, _) = self.bounds()
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        self.verts = [(x - cx, y - cy, z - z0) for x, y, z in self.verts]
        return self

    def translate(self, start, dx=0.0, dy=0.0, dz=0.0):
        """Move vertices from index `start` on, so one shell can be placed after it is built."""
        self.verts[start:] = [(x + dx, y + dy, z + dz) for x, y, z in self.verts[start:]]

    def rotate_x(self, start=0):
        """+90 deg about X: a loft's +Z axis becomes -Y, so its top cap faces the product front
        with the art upright (u follows +X, v follows +Z)."""
        self.verts[start:] = [(x, -z, y) for x, y, z in self.verts[start:]]

    def rotate_y(self, start=0):
        """+90 deg about Y: a loft's +Z axis becomes +X."""
        self.verts[start:] = [(z, y, -x) for x, y, z in self.verts[start:]]

    def fit(self, w, d, h):
        """Scale non-uniformly to exactly w x d x h, then put the origin bottom-center."""
        (x0, y0, z0), (x1, y1, z1) = self.bounds()
        sx, sy, sz = w / max(x1 - x0, 1e-9), d / max(y1 - y0, 1e-9), h / max(z1 - z0, 1e-9)
        self.verts = [(x * sx, y * sy, z * sz) for x, y, z in self.verts]
        return self.recenter_bottom()


def _perimeter(ring):
    return sum(math.dist(ring[i], ring[(i + 1) % len(ring)]) for i in range(len(ring)))


def _wrap_v(rings, span_panels):
    """Per-panel v coordinate at each ring, proportional to arc length along the profile."""
    lengths = [
        sum(math.dist(rings[s][i], rings[s + 1][i]) for i in range(len(rings[s]))) / len(rings[s])
        for s in range(len(rings) - 1)
    ]
    out = {}
    for p in set(span_panels):
        total = sum(l for s, l in enumerate(lengths) if span_panels[s] == p) or 1e-6
        v = {}
        acc = 0.0
        for s, panel in enumerate(span_panels):
            if panel == p:
                v[s] = acc / total
                acc += lengths[s]
                v[s + 1] = acc / total
        out[p] = (v, None, total)
    return out


def _area2(poly):
    return sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))


def triangulate(poly):
    """Ear clipping for a simple polygon in CCW order. Returns index triples."""
    n = len(poly)
    idx = list(range(n))
    if _area2(poly) < 0:
        idx.reverse()
    tris = []

    def inside(p, a, b, c):
        def sign(u, v, w):
            return (u[0] - w[0]) * (v[1] - w[1]) - (v[0] - w[0]) * (u[1] - w[1])

        return sign(p, a, b) >= -1e-12 and sign(p, b, c) >= -1e-12 and sign(p, c, a) >= -1e-12

    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        m = len(idx)
        for k in range(m):
            ia, ib, ic = idx[k - 1], idx[k], idx[(k + 1) % m]
            a, b, c = poly[ia], poly[ib], poly[ic]
            if (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) <= 1e-12:
                continue
            if any(inside(poly[o], a, b, c) for o in idx if o not in (ia, ib, ic)):
                continue
            tris.append((ia, ib, ic))
            idx.pop(k)
            break
        else:
            raise ValueError("triangulate: polygon is not simple")
    tris.append(tuple(idx))
    return tris


# ---- profile helpers ------------------------------------------------------------------
# Convention for all closed rings: counter-clockwise from above, vertex 0 at the back (+Y), so the
# product front (-Y) is the centre of a wrap panel (u = 0.5) and the texture seam stays at the back.
def ellipse(rx, ry, z, n=16):
    return [(-rx * math.sin(2 * math.pi * i / n), ry * math.cos(2 * math.pi * i / n), z) for i in range(n)]


def lathe_rings(profile, n=16, ry_scale=1.0):
    """profile is [(radius, z)...] from bottom to top."""
    return [ellipse(r, r * ry_scale, z, n) for r, z in profile]


def rrect(w, d, r, z, per_corner=2):
    """Rounded rectangle ring with vertices at back-centre and front-centre."""
    r = min(r, w / 2 - 1e-4, d / 2 - 1e-4)
    pts = [(0.0, d / 2, z)]
    for x, y, base in ((-w / 2 + r, d / 2 - r, 90), (-w / 2 + r, -d / 2 + r, 180)):
        for k in range(per_corner + 1):
            a = math.radians(base + 90 * k / per_corner)
            pts.append((x + r * math.cos(a), y + r * math.sin(a), z))
    pts.append((0.0, -d / 2, z))
    for x, y, base in ((w / 2 - r, -d / 2 + r, 270), (w / 2 - r, d / 2 - r, 0)):
        for k in range(per_corner + 1):
            a = math.radians(base + 90 * k / per_corner)
            pts.append((x + r * math.cos(a), y + r * math.sin(a), z))
    return pts


def ensure_ccw(outline):
    return list(outline) if _area2(outline) > 0 else list(reversed(outline))


def arc(cx, cy, rx, ry, a0, a1, n):
    return [
        (cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n)))
        for i in range(n + 1)
    ]


# ---- validation -----------------------------------------------------------------------
def validate(mesh: MeshData) -> dict:
    """Closedness, orientation consistency, outward normals (signed volume), degenerates."""
    edge_use = defaultdict(lambda: [0, 0])
    degenerate = 0
    volume = 0.0
    for f in mesh.faces:
        v = f["v"]
        if len(set(v)) != len(v):
            degenerate += 1
        for i in range(len(v)):
            a, b = v[i], v[(i + 1) % len(v)]
            edge_use[(a, b) if a < b else (b, a)][0 if a < b else 1] += 1
        o = mesh.verts[v[0]]
        for i in range(1, len(v) - 1):
            b, c = mesh.verts[v[i]], mesh.verts[v[i + 1]]
            ux, uy, uz = b[0] - o[0], b[1] - o[1], b[2] - o[2]
            vx, vy, vz = c[0] - o[0], c[1] - o[1], c[2] - o[2]
            nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            volume += (o[0] * nx + o[1] * ny + o[2] * nz) / 6
            if nx * nx + ny * ny + nz * nz < 1e-20:
                degenerate += 1
    open_edges = sum(1 for a, b in edge_use.values() if a + b == 1)
    non_manifold = sum(1 for a, b in edge_use.values() if a + b > 2)
    flipped = sum(1 for a, b in edge_use.values() if a + b == 2 and a != b)
    return {
        "tris": mesh.tri_count(),
        "open_edges": open_edges,
        "non_manifold_edges": non_manifold,
        "inconsistent_edges": flipped,
        "degenerate_faces": degenerate,
        "signed_volume": round(volume, 6),
        "closed": open_edges == 0 and non_manifold == 0 and flipped == 0,
        "outward": volume > 0,
    }
