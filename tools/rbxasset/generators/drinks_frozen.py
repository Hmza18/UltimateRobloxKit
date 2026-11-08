"""Batch 6 and 7 shapes from the guide: slim drink can, curvy shake bottle and pear-shaped shrink bag."""
from __future__ import annotations

from ..meshkit import MeshData, ellipse, lathe_rings


def soda_can(w, d, h, **_):
    """330 ml can: base ring, wrap label, tapered neck, rolled rim and a recessed printed lid."""
    r = w / 2
    profile = [(r * 0.8, 0), (r * 0.9, h * 0.012), (r, h * 0.075), (r, h * 0.82), (r * 0.86, h * 0.925), (r * 0.84, h * 0.965), (r * 0.9, h * 0.98), (r * 0.87, h), (r * 0.77, h * 0.975)]
    spans = ["rim", "rim", "label", "neck", "rim", "rim", "rim", "rim"]
    mesh = MeshData()
    mesh.wrap_loft(lathe_rings(profile, 20), spans, weights={"front": 1, "back": 1, "rim": 0.1, "neck": 0.18, "top": 0.4, "bottom": 0.04})
    return mesh


def shake_bottle(w, d, h, **_):
    """Curvy protein-shake bottle: a pinched waist, a full shrink sleeve that follows it, and a ribbed cap."""
    r = w / 2
    profile = [(r * 0.76, 0), (r * 0.96, h * 0.025), (r, h * 0.09), (r * 0.97, h * 0.2), (r * 0.82, h * 0.38), (r * 0.93, h * 0.54), (r, h * 0.66), (r * 0.82, h * 0.76),
               (r * 0.58, h * 0.81), (r * 0.66, h * 0.825), (r * 0.66, h * 0.985), (r * 0.56, h)]
    spans = ["base", "label", "label", "label", "label", "label", "label", "neck", "cap", "cap", "cap"]
    mesh = MeshData()
    mesh.wrap_loft(lathe_rings(profile, 16), spans, weights={"front": 1, "back": 1, "base": 0.08, "neck": 0.12, "cap": 0.25, "top": 0.14, "bottom": 0.04})
    return mesh


def shrink_bag(w, d, h, **_):
    """Whole chicken in a pear-shaped shrink bag, with a gathered neck, a clip and a tuft of film."""
    mesh = MeshData()

    def ring(sx, sy, z):
        return ellipse(w * sx / 2, d * sy / 2, z, 12)

    rings = [ring(0.62, 0.62, 0), ring(0.9, 0.92, h * 0.07), ring(1.0, 1.0, h * 0.24), ring(0.97, 0.96, h * 0.42), ring(0.86, 0.86, h * 0.6), ring(0.55, 0.55, h * 0.72),
             ring(0.13, 0.13, h * 0.81), ring(0.13, 0.13, h * 0.86), ring(0.36, 0.12, h)]
    mesh.planar_loft(rings, w, d, h, smooth="soft", weights={"front": 1.0, "back": 1.0, "top": 0.04, "bottom": 0.04}, sides=False)
    return mesh


GENERATORS = {f.__name__: f for f in (soda_can, shake_bottle, shrink_bag)}
