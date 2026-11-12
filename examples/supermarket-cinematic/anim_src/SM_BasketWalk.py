"""Walk with a shopping basket in the left hand, right arm swinging. R15, supermarket intro cast.

Legs come from _sm.Gait: the stance foot slides back at exactly SPEED studs per frame, so the
runtime moves the character at SPEED * 60 studs/s and the feet do not skate.
"""
import animkit as ak
from _sm import Gait, walk_upper

NAME = "SM_BasketWalk"
GAIT = Gait()
SPEED = GAIT.speed  # studs per frame


def build():
    a = ak.Anim(NAME, rig="R15", length=GAIT.cycle, loop=True, priority="Movement")
    GAIT.legs(a)
    walk_upper(GAIT, a, arms="basket")
    a.marker(0, "Step")  # right heel strike
    a.marker(GAIT.step, "Step")  # left heel strike
    return a
