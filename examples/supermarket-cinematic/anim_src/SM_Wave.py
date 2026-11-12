"""Welcoming wave, R15, 130 f one-shot (store employee, Scene 1).

Anticipation dip (10 f) -> arm sweeps up with the chest opening (14 f, eased out) -> three wave
beats on 10 f each, hand counter-tilting -> arm drops with a small overshoot -> settle on the stance.
Marker Wave = the first beat (UI/audio can sync to it).
"""
from _sm import BASE, REST_R, keyed_clip

NAME = "SM_Wave"
UP = ("chest", (1.55, 1.55, -0.35), (1.0, -0.6, 0.4), (0, 0, -8))


def up(x, tilt):
    return ("chest", (x, 1.55, -0.35), (1.0, -0.6, 0.4), (0, 0, tilt))


KEYS = [
    (0, "io", {}),
    (10, "io", {"move": (0, -0.13, 0), "chest": (-4, 0, 2), "head": (-5, 0, 0)}),
    (17, "in", {"rh": ("chest", (2.05, 0.35, -0.45), (0.9, -0.9, 0.5), (0, 0, -6)), "move": (0, -0.08, 0)}),
    (24, "out", {"move": (0, -0.03, 0), "chest": (3, 7, 4), "head": (5, -9, 7), "rh": up(1.6, -10)}),
    (34, "io", {"rh": up(1.95, 16)}),
    (44, "io", {"rh": up(1.3, -18), "head": (5, -9, 9)}),
    (54, "io", {"rh": up(1.95, 16)}),
    (64, "io", {"rh": up(1.4, -14), "head": (4, -8, 6)}),
    (80, "in", {"rh": ("chest", (1.5, 0.6, -0.5), (1, -0.5, 0.5), (0, 0, -4)), "chest": (1, 3, 2)}),
    (94, "back", {"rh": REST_R, "move": (0, -0.09, 0), "chest": (-1.5, 0, 0), "head": (-2, -2, 0)}),
    (130, "io", BASE),
]


def build():
    return keyed_clip(NAME, 130, KEYS, markers=[(24, "Wave")])
