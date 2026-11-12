"""Customer idle holding a basket in the left hand, R15, 120-frame loop."""
import math

from _sm import BASE, BASKET_L, TAU, solve
import animkit as ak

NAME = "SM_BasketIdle"
LENGTH = 120


def build():
    a = ak.Anim(NAME, rig="R15", length=LENGTH, loop=True, priority="Idle")
    for t in range(0, LENGTH, 10):
        br = math.cos(TAU * t / 60)
        sh = math.sin(TAU * t / LENGTH)
        p = dict(BASE)
        p.update(hips=(0.5 * br, 2 * sh, 1.2 * sh), move=(0.04 * sh, -0.07 + 0.03 * br, 0),
                 chest=(-1 - 1.4 * br, -1.2 * sh, 0), head=(1 + sh, 3 * math.sin(TAU * (t + 20) / LENGTH), 0),
                 lh=("chest", (-1.45, -1.05 + 0.02 * br, -0.35), (-0.7, -0.2, 1), (0, 0, 8)))
        a.full(t, solve(p, p, 0.0), ease="bezier")
    return a
