"""Happy double fist pump for the final reveal, R15, 100 f one-shot (employee and cashier, Scene 5).
Dip (10 f) -> arms shoot up with the chest opening (8 f, eased out) -> two pumps -> arms drop with
overshoot -> settle on the stance."""
from _sm import BASE, keyed_clip

NAME = "SM_Cheer"


def up(y, z=-0.25):
    return (("chest", (1.25, y, z), (1.0, -0.4, 0.4), (0, 0, -10)), ("chest", (-1.25, y, z), (-1.0, -0.4, 0.4), (0, 0, 10)))


R1, L1 = up(1.75)
R2, L2 = up(1.35, -0.4)
MID_R, MID_L = up(0.4, -0.7)
KEYS = [
    (0, "io", {}),
    (10, "io", {"move": (0, -0.16, 0), "chest": (-6, 0, 0), "head": (-6, 0, 0), "rh": ("chest", (1.2, -0.6, -0.6), (0.6, -0.6, 0.6), (0, 0, 0)), "lh": ("chest", (-1.2, -0.6, -0.6), (-0.6, -0.6, 0.6), (0, 0, 0))}),
    (14, "in", {"rh": MID_R, "lh": MID_L, "move": (0, -0.08, 0)}),
    (17, "lin", {"rh": up(1.1, -0.55)[0], "lh": up(1.1, -0.55)[1], "move": (0, -0.04, 0)}),
    (23, "out", {"rh": R1, "lh": L1, "move": (0, -0.01, 0), "chest": (6, 0, 0), "head": (10, 0, 0)}),
    (34, "io", {"rh": R2, "lh": L2, "move": (0, -0.08, 0), "chest": (2, 0, 0)}),
    (42, "out", {"rh": R1, "lh": L1, "move": (0, -0.02, 0), "chest": (6, 0, 0)}),
    (56, "io", {"rh": R2, "lh": L2, "move": (0, -0.07, 0), "chest": (3, 0, 0), "head": (6, 0, 0)}),
    (66, "in", {"rh": MID_R, "lh": MID_L}),
    (78, "back", BASE),
    (100, "io", BASE),
]


def build():
    return keyed_clip(NAME, 100, KEYS, markers=[(23, "Cheer")])
