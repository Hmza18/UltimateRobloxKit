"""Friendly idle with breathing, R15, 120-frame loop (supermarket intro cast).

breath 60 f (chest +-1.6 deg, root bob 0.035 studs), weight shift 120 f toward each foot,
arms hang soft and trail the chest 6 f, head drifts on its own 120 f curve so it never looks frozen.
"""
import math

import animkit as ak
from _sm import TAU, arm, stand

NAME = "SM_Idle"
LENGTH = 120


def pose_at(t):
    br = math.cos(TAU * t / 60)
    sh = math.sin(TAU * t / LENGTH)
    p = stand(hips=(0.6 * br, 2.0 * sh, 1.4 * sh), move=(0.05 * sh, -0.07 + 0.035 * br, 0),
              chest=(-1.0 - 1.6 * br, -1.5 * sh, -1.0 * sh),
              head=(1.0 + 1.2 * math.sin(TAU * (t - 10) / LENGTH), 3.0 * math.sin(TAU * (t + 20) / LENGTH), 0.8 * sh))
    sway = math.cos(TAU * (t - 6) / 60)
    arm(p, "Right", fwd=2 + 1.5 * sway, out=5 + 1.0 * sway, elbow=12 + 2 * sway, wrist=-4)
    arm(p, "Left", fwd=2 + 1.5 * sway, out=5 + 1.0 * sway, elbow=12 + 2 * sway, wrist=-4)
    return p


def build():
    a = ak.Anim(NAME, rig="R15", length=LENGTH, loop=True, priority="Idle")
    for t in range(0, LENGTH, 10):
        a.full(t, pose_at(t), ease="bezier")
    return a
