"""Generator registry. A spec names a generator, a size in studs and optional params."""
from __future__ import annotations

from ..meshkit import validate
from ..safe_area import tighten_panels
from . import (candy_goods, cartons, drinks_frozen, electronics, household_goods, luxury_goods, packaging, pet_goods, props,
               round_goods, soft_goods, vessels)

REGISTRY = {}
for _module in (props, packaging, cartons, pet_goods, candy_goods, drinks_frozen, household_goods, luxury_goods, round_goods,
                vessels, electronics, soft_goods):
    REGISTRY.update(_module.GENERATORS)


def build(spec: dict):
    """Build an asset at exactly size = [width (X), depth (Y), height (Z)] studs, origin bottom-centre."""
    name = spec["generator"]
    if name not in REGISTRY:
        raise KeyError(f"No generator named {name!r}. Known: {', '.join(sorted(REGISTRY))}")
    w, d, h = spec["size"]
    try:
        mesh = REGISTRY[name](w, d, h, **spec.get("params", {}))
        check = validate(mesh)
        if not (check["closed"] and check["outward"]):
            raise ValueError(f"{name} is not closed at {w} x {d} x {h}: {check}")
        mesh.stretched = False
    except ValueError:
        # Some recovered generators were tuned for their product's proportions and cannot build
        # every aspect ratio directly (a cap outline self-intersects, or faces flip). Build at a cube of the same
        # volume scale, then stretch to size. Geometry stays closed; label art may distort, so the
        # layout reports `stretched` and QA flags it for visual review.
        s = (w * d * h) ** (1 / 3)
        mesh = REGISTRY[name](s, s, s, **spec.get("params", {}))
        mesh.stretched = True
    return tighten_panels(mesh.fit(w, d, h))
