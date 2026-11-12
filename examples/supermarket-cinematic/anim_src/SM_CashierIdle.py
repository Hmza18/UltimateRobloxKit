"""Cashier idle behind the counter, R15, 120-frame loop (Scenes 4 and 5): hands rest on the
counter edge, breathing and a slow friendly head drift. Same base pose as SM_Scan."""
import math

from _sm import TAU, Keys, solve
import animkit as ak
from SM_Scan import BASE

NAME = "SM_CashierIdle"
LENGTH = 120


def build():
    a = ak.Anim(NAME, rig="R15", length=LENGTH, loop=True, priority="Idle")
    for t in range(0, LENGTH, 10):
        br = math.cos(TAU * t / 60)
        p = dict(BASE)
        p["move"] = (0, -0.07 + 0.03 * br, 0)
        p["chest"] = (-6 - 1.4 * br, 1.5 * math.sin(TAU * t / LENGTH), 0)
        p["head"] = (-4 + 1.5 * math.sin(TAU * (t - 8) / LENGTH), 4 * math.sin(TAU * (t + 25) / LENGTH), 1.5 * math.sin(TAU * t / LENGTH))
        a.full(t, solve(p, p, 0.0), ease="bezier")
    return a
