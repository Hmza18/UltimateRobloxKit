"""Pick up a product box from a crate, R15, 110 f one-shot (employee, Scene 2).

The box rests on a crate in front of the employee (top at y = -1.75, box centre (0, -1.30, -1.45),
1.1 x 0.9 x 1.0 studs). Eyes lead (10 f) -> bend and reach (20 f) -> hands close on the box sides
(Grab, 42) -> load dip (10 f) -> lift through an arc into the carry pose (24 f) -> settle.
Ends in the carry pose SM_CarryWalk uses.
"""
from _sm import BOX_L, BOX_R, keyed_clip

NAME = "SM_BoxLift"
GRIP_R = ("world", (1.07, -1.17, -1.45), (0.8, -0.3, 0.6), (0, 0, -8))
GRIP_L = ("world", (-1.07, -1.17, -1.45), (-0.8, -0.3, 0.6), (0, 0, 8))

KEYS = [
    (0, "io", {}),
    (10, "io", {"head": (-16, 0, 0), "chest": (-3, 0, 0)}),
    (30, "io", {"hips": (-16, 0, 0), "move": (0, -0.30, 0.05), "chest": (-20, 0, 0), "head": (-8, 0, 0),
                "rh": ("world", (1.35, -0.95, -1.35), (0.8, -0.3, 0.6), (0, 0, -20)),
                "lh": ("world", (-1.35, -0.95, -1.35), (-0.8, -0.3, 0.6), (0, 0, 20))}),
    (42, "out", {"rh": GRIP_R, "lh": GRIP_L, "hips": (-18, 0, 0), "move": (0, -0.34, 0.05), "chest": (-22, 0, 0)}),
    (52, "io", {"move": (0, -0.42, 0.06), "chest": (-24, 0, 0), "head": (-2, 0, 0),
                "rh": ("world", (1.07, -1.20, -1.45), (0.8, -0.3, 0.6), (0, 0, -10)),
                "lh": ("world", (-1.07, -1.20, -1.45), (-0.8, -0.3, 0.6), (0, 0, 10))}),
    (64, "in", {"hips": (-6, 0, 0), "move": (0, -0.20, 0.02), "chest": (-8, 0, 0),
                "rh": ("world", (1.08, -0.75, -1.3), (0.7, -0.6, 0.6), (0, 0, -10)),
                "lh": ("world", (-1.08, -0.75, -1.3), (-0.7, -0.6, 0.6), (0, 0, 10))}),
    (78, "out", {"hips": (3, 0, 0), "move": (0, -0.03, 0), "chest": (4, 0, 0), "head": (3, 0, 0), "rh": BOX_R, "lh": BOX_L}),
    (90, "io", {"hips": (-1, 0, 0), "move": (0, -0.08, 0), "chest": (-3, 0, 0), "head": (0, 0, 0)}),
    (110, "io", {"hips": (-2, 0, 0), "move": (0, -0.06, 0), "chest": (-2, 0, 0)}),
]


def build():
    return keyed_clip(NAME, 110, KEYS, markers=[(42, "Grab"), (78, "Lifted")], tune=False)
