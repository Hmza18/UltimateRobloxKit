"""Customer picks a product off the shelf into the basket, R15, 140 f one-shot (Scene 3).

Looks at the product (eyes first, 14 f) -> leans in and reaches (30 f, eased out) -> Grab (54) ->
eases it off the shelf -> brings it across the body while the left hand lifts the basket to meet
it -> Drop (94) -> settles back to the basket stance. Product shelf slot wrist target (0.35, 0.0, -1.6).
"""
from _sm import BASKET_L, REST_R, keyed_clip

NAME = "SM_ReachPick"
LIFT_BASKET = ("chest", (-1.05, -0.85, -1.15), (-1.0, -0.3, 0.3), (0, 0, 10))

KEYS = [
    (0, "io", {"lh": BASKET_L}),
    (14, "io", {"head": (6, -8, 0), "chest": (-1, -3, 0)}),
    (30, "io", {"move": (0, -0.09, 0), "head": (2, -6, 0), "rh": ("chest", (1.25, -0.4, -0.9), (1.0, -0.3, 0.0), (-6, 0, 0))}),
    (46, "out", {"hips": (-5, -7, 0), "chest": (-11, -8, 0), "head": (-2, -2, 0),
                 "rh": ("world", (0.5, 0.15, -1.45), (1.0, -0.15, -0.2), (-12, 0, 0))}),
    (54, "out", {"rh": ("world", (0.35, 0.0, -1.6), (1.0, -0.15, -0.2), (-6, 0, 0))}),          # Grab
    (64, "io", {"rh": ("world", (0.45, 0.08, -1.4), (1.0, -0.15, -0.2), (-4, 0, 0)), "hips": (-3, -5, 0), "chest": (-6, -5, 0)}),
    (84, "io", {"hips": (-2, 6, 0), "chest": (-8, 10, 0), "head": (-14, 8, 0), "lh": LIFT_BASKET,
                "rh": ("chest", (-0.3, -0.45, -1.45), (1.0, -0.2, -0.15), (-10, 0, 0))}),
    (94, "out", {"rh": ("chest", (-0.6, -0.6, -1.4), (1.0, -0.2, -0.15), (-14, 0, 0))}),        # Drop
    (108, "io", {"lh": BASKET_L, "rh": ("chest", (1.0, -0.7, -0.9), (1.0, -0.4, 0.2), (-4, 0, 0)), "head": (-4, 4, 0)}),
    (124, "back", {"hips": (0, 0, 0), "chest": (0, 0, 0), "head": (0, 0, 0), "rh": REST_R, "move": (0, -0.06, 0)}),
    (140, "io", {}),
]


def build():
    return keyed_clip(NAME, 140, KEYS, markers=[(54, "Grab"), (94, "Drop")])
