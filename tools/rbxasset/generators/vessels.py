"""Bottles, cans, jars, canisters, tubs and household jugs."""
from __future__ import annotations

from ..meshkit import MeshData, arc, lathe_rings, rrect


def _body_weights():
    return {"body": 1.0, "base": 0.2, "shoulder": 0.35, "cap": 0.25, "lid": 0.3, "cap_top": 0.3, "cap_bottom": 0.15}


def bottle(w, d, h, neck=0.3, **_):
    """Drink bottle. neck is the neck radius as a fraction of body radius (wider = shake bottle)."""
    mesh = MeshData()
    r, rn = w / 2, w / 2 * neck
    profile = [(r * 0.8, 0), (r, h * 0.04), (r, h * 0.58), (r * 0.96, h * 0.64), (r * max(0.62, neck + 0.1), h * 0.74),
               (rn, h * 0.81), (rn, h * 0.85), (rn * 1.2, h * 0.86), (rn * 1.2, h * 0.99), (rn * 1.1, h)]
    spans = ["base", "body", "shoulder", "shoulder", "shoulder", "shoulder", "cap", "cap", "cap"]
    mesh.loft(lathe_rings(profile, 14), spans, weights=_body_weights())
    return mesh


def can(w, d, h, slim=False, **_):
    """Food or drink can: seamed rim, slight neck on slim drink cans."""
    mesh = MeshData()
    r = w / 2
    if slim:
        profile = [(r * 0.8, 0), (r, h * 0.06), (r, h * 0.8), (r * 0.82, h * 0.93), (r * 0.84, h * 0.97), (r * 0.82, h), (r * 0.7, h * 0.985)]
        spans = ["base", "body", "shoulder", "shoulder", "shoulder", "shoulder"]
    else:
        profile = [(r * 0.94, 0), (r * 0.96, h * 0.02), (r * 0.94, h * 0.05), (r * 0.94, h * 0.95), (r, h * 0.97), (r * 0.98, h), (r * 0.84, h * 0.985)]
        spans = ["base", "base", "body", "shoulder", "shoulder", "shoulder"]
    mesh.loft(lathe_rings(profile, 16), spans, weights=_body_weights())
    return mesh


def canister(w, d, h, **_):
    """Salt canister: straight wall with a slightly wider pour lid."""
    mesh = MeshData()
    r = w / 2
    profile = [(r * 0.92, 0), (r * 0.95, h * 0.03), (r * 0.95, h * 0.84), (r, h * 0.85), (r, h * 0.97), (r * 0.9, h)]
    mesh.loft(lathe_rings(profile, 14), ["base", "body", "lid", "lid", "lid"], weights=_body_weights())
    return mesh


def cup_tub(w, d, h, **_):
    """Tapered tub with a snap lid (ice cream, instant noodle cups)."""
    mesh = MeshData()
    r = w / 2
    profile = [(r * 0.72, 0), (r * 0.76, h * 0.03), (r * 0.94, h * 0.84), (r, h * 0.86), (r, h * 0.95), (r * 0.9, h)]
    mesh.loft(lathe_rings(profile, 16), ["base", "body", "lid", "lid", "lid"], weights={**_body_weights(), "cap_top": 0.7})
    return mesh


def jar(w, d, h, **_):
    """Wide-mouth jar with screw lid."""
    mesh = MeshData()
    r = w / 2
    profile = [(r * 0.85, 0), (r, h * 0.05), (r, h * 0.72), (r * 0.82, h * 0.8), (r * 0.82, h * 0.82), (r * 0.88, h * 0.83), (r * 0.88, h * 0.98), (r * 0.8, h)]
    mesh.loft(lathe_rings(profile, 14), ["base", "body", "shoulder", "shoulder", "lid", "lid", "lid"], weights=_body_weights())
    return mesh


def jug_household(w, d, h, slim_cap=False, **_):
    """Household bottle (bleach, shampoo, detergent). slim_cap gives a flip cap; otherwise a side handle."""
    mesh = MeshData()
    r = d * 0.42
    neck_w, neck_d = (w * 0.3, d * 0.42) if slim_cap else (w * 0.26, w * 0.26)
    rings = [rrect(w * 0.9, d * 0.9, r, 0), rrect(w, d, r, h * 0.05), rrect(w, d, r, h * 0.66), rrect(w * 0.82, d * 0.9, r * 0.8, h * 0.76),
             rrect(neck_w, neck_d, neck_d * 0.45, h * 0.82), rrect(neck_w * 1.15, neck_d * 1.15, neck_d * 0.5, h * 0.84), rrect(neck_w * 1.15, neck_d * 1.15, neck_d * 0.5, h)]
    mesh.loft(rings, ["base", "body", "shoulder", "shoulder", "cap", "cap"], weights=_body_weights())
    if not slim_cap:
        start = len(mesh.verts)
        t = d * 0.1
        outer = arc(w * 0.3, h * 0.66, w * 0.2, h * 0.16, -20, 80, 5)
        inner = arc(w * 0.3, h * 0.66, w * 0.2 - t * 1.4, h * 0.16 - t * 1.4, 80, -20, 5)
        mesh.extrude(outer + inner, -t, t, "handle", "handle_cap", "handle_cap", True)
        mesh.rotate_x(start)
        # rotate_x sends local +Y to +Z, so the arc is drawn in the X-Z plane; recentre on depth.
        mesh.translate(start, 0.0, 0.0, 0.0)
    return mesh


GENERATORS = {f.__name__: f for f in (bottle, can, canister, cup_tub, jar, jug_household)}
