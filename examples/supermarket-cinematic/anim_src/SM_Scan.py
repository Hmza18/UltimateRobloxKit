"""Cashier scans one product, R15, 120 f one-shot (Scene 4).

Counter top at y = -0.5 in front of the cashier; product waits at the right (wrist target
(1.15, -0.15, -1.35)), scanner window centred at x = 0, bagging area at the left.
Look first -> reach (Grab 30) -> lift -> sweep across the scanner at an even speed (Beep 54, the
moment the product crosses x = 0) -> hand it off to the bagging side (Release 68) -> back to rest.
"""
from _sm import keyed_clip

NAME = "SM_Scan"
REST_RH = ("world", (1.32, -0.28, -1.25), (1.0, -0.25, 0.1), (-60, 0, 0))
REST_LH = ("world", (-1.32, -0.28, -1.25), (-1.0, -0.25, 0.1), (-60, 0, 0))
BASE = {"hips": (0, 0, 0), "move": (0, -0.06, 0), "chest": (-6, 0, 0), "head": (-4, 0, 0), "rh": REST_RH, "lh": REST_LH}

KEYS = [
    (0, "io", BASE),
    (12, "io", {"head": (-14, -26, 0), "chest": (-7, -5, 0)}),
    (28, "out", {"rh": ("world", (1.15, -0.10, -1.35), (1.0, -0.2, 0.1), (-20, 0, 0)), "chest": (-10, -14, 0)}),
    (32, "io", {"rh": ("world", (1.15, -0.15, -1.35), (1.0, -0.2, 0.1), (-20, 0, 0))}),                 # Grab 30
    (42, "io", {"rh": ("world", (0.85, -0.02, -1.42), (1.0, -0.2, -0.1), (-20, 0, 0)), "head": (-16, -10, 0)}),
    (54, "lin", {"rh": ("world", (0.0, -0.12, -1.45), (1.0, -0.15, -0.2), (-20, 0, 0)), "chest": (-9, 0, 0), "head": (-18, 0, 0)}),  # Beep
    (66, "out", {"rh": ("world", (-0.95, -0.12, -1.40), (1.0, -0.15, -0.25), (-20, 0, 0)), "chest": (-8, 12, 0), "head": (-14, 14, 0)}),  # Release 68
    (74, "io", {"rh": ("world", (0.15, -0.12, -1.6), (1.0, -0.3, 0.0), (-30, 0, 0)), "chest": (-7, 6, 0), "head": (-6, 6, 0)}),
    (84, "io", {"rh": REST_RH, "chest": (-6, 2, 0), "head": (0, 0, 0)}),
    (96, "io", {"head": (-6, 0, 0)}),
    (120, "io", {"head": (-4, 0, 0), "chest": (-6, 0, 0)}),
]


def build():
    a = keyed_clip(NAME, 120, KEYS, markers=[(30, "Grab"), (54, "Beep"), (68, "Release")])
    return a
