"""Stock the shelf from a box, R15, 210 f one-shot (employee, Scene 2).

Starts in the carry pose. The box shifts onto the left forearm (BoxToLeft) so the right hand is
free; three take -> place cycles fill the shelf, each a little quicker than the last (40, 40, 36 f)
with the third reaching up to the top shelf. A small satisfied nod ends it.
Shelf front at z = -1.2 from the employee's mark; slots are wrist targets in character space.
Markers: BoxToLeft, Take1..3, Place1..3 (runtime moves a product from the box to its slot).
"""
from _sm import BOX_L, BOX_R, keyed_clip

NAME = "SM_Stock"
CRADLE_L = ("chest", (-0.95, -0.80, -1.15), (-1.0, -0.4, 0.3), (0, 0, 14))
IN_BOX = ("chest", (-0.45, -0.42, -1.45), (1.0, -0.2, -0.15), (-20, 0, 0))
ABOVE_BOX = ("chest", (-0.30, -0.05, -1.50), (1.0, -0.2, -0.15), (-10, 0, 0))
SLOT = {
    1: ("world", (0.55, -0.05, -1.55), (1.0, -0.2, -0.15), (-8, 0, 0)),
    2: ("world", (-0.10, -0.05, -1.60), (1.0, -0.2, -0.15), (-8, 0, 0)),
    3: ("world", (0.45, 1.05, -1.45), (1.0, -0.4, 0.3), (-4, 0, 0)),
}
LEAN = {"hips": (-5, -5, 0), "chest": (-11, -6, 0), "head": (-6, -3, 0)}
UP = {"hips": (-2, -4, 0), "chest": (3, -5, 0), "head": (12, -3, 0)}
HOME = {"hips": (-1, 6, 0), "chest": (-6, 8, 0), "head": (-10, 6, 0)}

KEYS = [
    (0, "io", {"rh": BOX_R, "lh": BOX_L, "chest": (-2, 0, 0)}),
    (10, "io", {"rh": ("chest", (1.1, -0.5, -1.3), (0.6, -1, 0.5), (0, 0, -10)), "lh": ("chest", (-1.05, -0.65, -1.3), (-0.6, -1, 0.5), (0, 0, 10))}),
    (18, "io", {"lh": CRADLE_L, "rh": ("chest", (0.5, -0.5, -1.35), (1.0, -0.2, -0.1), (0, 0, -6)), **HOME}),
    (26, "in", {"rh": ABOVE_BOX}),
    (32, "out", {"rh": IN_BOX}),                          # Take1
    (50, "back", {"rh": SLOT[1], **LEAN}),               # Place1
    (58, "io", {"rh": ("world", (0.6, 0.05, -1.4), (1.0, -0.2, -0.15), (-4, 0, 0))}),
    (64, "io", {"rh": ("chest", (0.55, -0.05, -1.65), (1.0, -0.3, 0.0), (-6, 0, 0))}),
    (70, "in", {"rh": ABOVE_BOX, **HOME}),
    (74, "out", {"rh": IN_BOX}),                          # Take2
    (90, "back", {"rh": SLOT[2], **LEAN}),               # Place2
    (98, "io", {"rh": ("world", (0.0, 0.05, -1.45), (1.0, -0.2, -0.15), (-4, 0, 0))}),
    (104, "io", {"rh": ("chest", (0.25, -0.05, -1.7), (1.0, -0.3, 0.0), (-6, 0, 0))}),
    (110, "in", {"rh": ABOVE_BOX, **HOME}),
    (114, "out", {"rh": IN_BOX}),                         # Take3
    (126, "io", {"rh": ("world", (0.6, 0.5, -1.2), (1.0, -0.5, 0.3), (-4, 0, 0)), "hips": (-2, -3, 0), "chest": (-2, -4, 0)}),
    (134, "back", {"rh": SLOT[3], **UP}),                # Place3
    (146, "io", {"rh": ("world", (0.6, 1.1, -1.2), (1.0, -0.4, 0.3), (0, 0, 0))}),
    (155, "io", {"rh": ("chest", (1.25, -0.2, -1.2), (1.0, -0.4, 0.2), (-4, 0, 0))}),
    (166, "io", {"rh": ("chest", (1.4, -0.8, -0.3), (0.4, -0.3, 1.0), (-4, 0, 0)), "hips": (0, 2, 0), "chest": (-2, 3, 0), "head": (2, 2, 0)}),
    (178, "io", {"head": (-10, 2, 0)}),
    (190, "io", {"head": (2, 0, 0)}),
    (210, "io", {"hips": (0, 0, 0), "chest": (-1, 0, 0), "head": (0, 0, 0)}),
]
MARKERS = [(18, "BoxToLeft"), (32, "Take1"), (50, "Place1"), (74, "Take2"), (90, "Place2"), (114, "Take3"), (134, "Place3")]


def build():
    return keyed_clip(NAME, 210, KEYS, markers=MARKERS)
