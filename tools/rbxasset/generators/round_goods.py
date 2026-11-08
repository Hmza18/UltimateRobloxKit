"""Round packaging from the guide: canister, ribbed bottle, can, noodle cup and lidded tub.
Each uses wrap_loft: the label's front art covers the front half, its back art the back half."""
from __future__ import annotations

from ..meshkit import MeshData, lathe_rings


def _lathe(mesh, profile, spans, n, weights):
    mesh.wrap_loft(lathe_rings(profile, n), spans, weights=weights)
    return mesh


def salt_canister(w, d, h, **_):
    """Salt canister: wrap label, shoulder, and a white cap with a pour spout. The user's favourite look."""
    r = w / 2
    profile = [(r * 0.9, 0), (r, h * 0.03), (r, h * 0.8), (r * 0.95, h * 0.83), (r * 0.94, h * 0.84), (r * 0.94, h * 0.92),
               (r * 0.62, h * 0.955), (r * 0.26, h * 0.965), (r * 0.26, h)]
    spans = ["base", "label", "shoulder", "cap", "cap", "cap", "cap", "cap"]
    return _lathe(MeshData(), profile, spans, 16, {"front": 1, "back": 1, "base": 0.1, "shoulder": 0.1, "cap": 0.2, "top": 0.05, "bottom": 0.05})


def ribbed_bottle(w, d, h, **_):
    """PET oil bottle with real proportions: petal base, label panel, gripping ribs, rounded shoulder, neck ring, cap."""
    r = w / 2
    profile = [(r * 0.74, 0), (r, h * 0.035), (r, h * 0.5), (r * 0.94, h * 0.535), (r * 0.99, h * 0.57), (r * 0.94, h * 0.605), (r, h * 0.65),
               (r * 0.64, h * 0.76), (r * 0.36, h * 0.83), (r * 0.46, h * 0.855), (r * 0.43, h * 0.985), (r * 0.34, h)]
    spans = ["glass", "label", "glass", "glass", "glass", "glass", "glass", "glass", "cap", "cap", "cap"]
    return _lathe(MeshData(), profile, spans, 16, {"front": 1, "back": 1, "glass": 0.4, "cap": 0.14, "top": 0.05, "bottom": 0.05})


def food_can(w, d, h, **_):
    """Steel food can: double seams top and bottom, a smooth label wall and a recessed lid."""
    r = w / 2
    profile = [(r * 0.9, 0), (r * 0.985, h * 0.012), (r * 0.95, h * 0.035), (r, h * 0.055), (r, h * 0.945), (r * 0.95, h * 0.965), (r * 0.985, h * 0.985), (r * 0.955, h), (r * 0.84, h * 0.985)]
    spans = ["rim", "rim", "rim", "label", "rim", "rim", "rim", "rim"]
    return _lathe(MeshData(), profile, spans, 20, {"front": 1, "back": 1, "rim": 0.14, "top": 0.5, "bottom": 0.05})


def noodle_cup(w, d, h, **_):
    """Tapered noodle cup with a big overhanging foil lid and a peel tab on +X."""
    R = d / 2
    tab = w - d
    profile = [(R * 0.7, 0), (R * 0.74, h * 0.02), (R * 0.88, h * 0.85), (R * 0.9, h * 0.87), (R, h * 0.875), (R, h * 0.955), (R * 0.97, h)]
    spans = ["base", "label", "base", "lid", "lid", "lid"]
    mesh = _lathe(MeshData(), profile, spans, 16, {"front": 1, "back": 1, "base": 0.08, "lid": 0.2, "top": 1, "bottom": 0.05})
    half = R * 0.24
    outline = [(R * 0.84, -half), (R + tab * 0.65, -half), (R + tab, 0), (R + tab * 0.65, half), (R * 0.84, half)]
    mesh.extrude(outline, h * 0.93, h * 0.97, "tab", "tab", "tab", False)
    return mesh


def fish_tub(w, d, h, **_):
    """Fish-food tub: gently tapered wrap label under a big lid with a printed top."""
    r = w / 2
    profile = [(r * 0.84, 0), (r * 0.87, h * 0.02), (r * 0.95, h * 0.72), (r * 0.97, h * 0.73), (r, h * 0.745), (r, h * 0.93), (r * 0.95, h * 0.975), (r * 0.9, h)]
    spans = ["base", "label", "base", "lid", "lid", "lid", "lid"]
    return _lathe(MeshData(), profile, spans, 16, {"front": 1, "back": 1, "base": 0.08, "lid": 0.2, "top": 1, "bottom": 0.05})


GENERATORS = {f.__name__: f for f in (salt_canister, ribbed_bottle, food_can, noodle_cup, fish_tub)}
