"""Customer browses the shelf, basket in the left hand, R15, 150 f one-shot (Scene 3).

Scans up-left, then right with the chest following 40 % of the head, a thinking hand to the chin
(the readable "which one?" beat), then a decided little nod toward the product.
"""
from _sm import BASKET_L, REST_R, keyed_clip

NAME = "SM_Browse"
CHIN = ("chest", (0.35, 0.38, -1.25), (1.0, -0.8, 0.0), (-20, 0, 0))

KEYS = [
    (0, "io", {"lh": BASKET_L}),
    (18, "io", {"head": (12, 18, 0), "chest": (1, 6, 0)}),
    (40, "io", {"head": (10, 20, 2), "chest": (1, 7, 0)}),
    (62, "io", {"head": (8, -22, -2), "chest": (0, -8, 0), "rh": ("chest", (0.9, 0.0, -1.1), (1.0, -0.8, 0.1), (-20, 0, 0))}),
    (72, "out", {"rh": CHIN, "head": (6, -20, -4)}),
    (100, "io", {"head": (4, -14, -6), "rh": ("chest", (0.37, 0.40, -1.23), (1.0, -0.8, 0.0), (-26, 0, 0))}),
    (114, "io", {"head": (-8, -10, 0), "chest": (-2, -6, 0)}),
    (121, "io", {"rh": ("chest", (1.15, -0.2, -1.0), (1.0, -0.5, 0.2), (-10, 0, 0)), "head": (-2, -9, 0)}),
    (132, "back", {"rh": REST_R, "head": (2, -8, 0)}),
    (150, "io", {"head": (2, -6, 0), "chest": (0, -4, 0)}),
]


def build():
    return keyed_clip(NAME, 150, KEYS)
