"""Shared stances and the gait generator for the Supermarket Simulator intro cast (R15).

Authored with the make-anim pose language and its R15 IK helpers (`_r15.py`), method by fwjelaa
(FWJ STUDIOS). These files are original pose scripts; building them needs the make-anim pack:
copy this folder's *.py into the pack's anims/ and run  python kit/run.py make <Name>.

Character space: studs from the HumanoidRootPart centre, X right, Y up, Z back (faces -Z), floor y = -3.
"""
import math

from mathutils import Vector

import animkit as ak
from _r15 import fk, guard, orient, periodic, plant, reach, root_height_for

TAU = 2 * math.pi

# Relaxed, friendly standing pose: soft knees, feet hip-width and a little turned out.
FEET = {"Left": (-0.48, 0.02, 7), "Right": (0.48, -0.02, -7)}  # x, z, yaw


def arm(pose, side, fwd=0.0, out=4.0, twist=0.0, elbow=10.0, wrist=0.0):
    """FK arm in UpperTorso axes: fwd > 0 swings forward, out > 0 lifts away from the body."""
    s = 1 if side == "Right" else -1
    pose[f"{side}UpperArm"] = (fwd, twist * s, out * s)
    pose[f"{side}LowerArm"] = (elbow, 0.0, 0.0)
    pose[f"{side}Hand"] = (wrist, 0.0, 0.0)
    return pose


def stand(hips=(0, 0, 0), move=(0, -0.06, 0), chest=(0, 0, 0), head=(0, 0, 0), feet=None, arms=True):
    """Both feet planted by IK; the body is placed by `hips` (deg) and `move` (studs)."""
    feet = feet or FEET
    pose = {"LowerTorso": (*hips, *move), "UpperTorso": tuple(chest), "Head": tuple(head)}
    for side in ("Left", "Right"):
        x, z, yaw = feet[side]
        plant(pose, side, x=x, z=z, yaw=yaw)
    if arms:
        arm(pose, "Right")
        arm(pose, "Left")
    return pose


def legs_only(pose):
    return {j: v for j, v in pose.items() if "Leg" in j or "Foot" in j or j == "LowerTorso"}


# Box carried at the chest: wrist targets in UpperTorso axes. Runtime puts the box between the
# hands, so these numbers only need to give a believable grip width (1.4-stud box).
BOX_HOLD = {"Right": ((1.12, -0.55, -1.05), (0.6, -1, 0.5)), "Left": ((-1.12, -0.55, -1.05), (-0.6, -1, 0.5))}
# Basket hangs from the left hand, arm slightly bent and a little away from the hip.
BASKET_HOLD = ((-1.45, -1.05, -0.35), (-0.7, -0.2, 1))


def hold_box(pose, bob=0.0):
    for side in ("Right", "Left"):
        (x, y, z), elbow = BOX_HOLD[side]
        guard(pose, side, (x, y + bob, z), elbow, hand=(0, 0, -12 if side == "Right" else 12))
    return pose


def hold_basket(pose, sway=0.0):
    (x, y, z), elbow = BASKET_HOLD
    guard(pose, "Left", (x, y, z + sway), elbow, hand=(0, 0, 8))
    return pose


# ---------------------------------------------------------------------------------------------
# Walk: the planted foot slides back at one constant ground speed (no skating), double support
# between steps, root height solved from a knee curve, swing leg keyed in FK.

class Gait:
    def __init__(self, step=20, speed=0.06, contact_z=-0.6, hip_pitch=-3.0, chest_pitch=-2.0,
                 turn=5.0, roll=2.0, track=0.42):
        self.step, self.speed, self.contact_z = step, speed, contact_z
        self.cycle = 2 * step
        self.stance = step + 4  # frames each foot stays planted (4 frames of double support)
        self.hip_pitch, self.chest_pitch, self.track = hip_pitch, chest_pitch, track
        pts = [(0, (turn, roll)), (step * 0.5, (0, -roll * 0.5))]
        pts += [(f + step, (-y, -r)) for f, (y, r) in pts]
        self._turn = periodic(pts, self.cycle)
        # stance knee per frame after heel strike: absorb a little, straighten through passing
        n = self.stance + 1
        self.knee = [10 + 8 * math.sin(math.pi * min(1.0, k / 6)) * (1 - k / n) - 4 * math.sin(math.pi * k / n) for k in range(n)]
        self.py = self._heights()

    def foot_plan(self, k):
        g = self.contact_z + self.speed * k
        if k <= 3:
            u = k / 3
            return self.track, g + 0.5, 12 * (1 - u * u * (3 - 2 * u)), "heel"
        if k <= self.step - 2:
            return self.track, g, 0.0, "flat"
        u = (k - self.step + 2) / (self.stance - self.step + 2)
        return self.track, g - 0.5, -28 * u * u, "toe"

    def _heights(self):
        py = []
        for k in range(self.step):
            yaw, roll = self._turn(k)
            x, z, pitch, anchor = self.foot_plan(k)
            pose = {"LowerTorso": (self.hip_pitch, yaw, roll, 0, 0, 0)}
            py.append(root_height_for(pose, "Right", self.knee[k], x, z, pitch=pitch, anchor=anchor))
        return py

    def root_at(self, t):
        yaw, roll = self._turn(t)
        return (self.hip_pitch, yaw, roll, 0, self.py[t % self.step], 0)

    def legs(self, a):
        """Key both legs (and the root) on `a`."""
        for t in range(self.cycle):
            a.key(t, {"LowerTorso": self.root_at(t)}, ease="linear")
        for side, start in (("Right", 0), ("Left", self.step)):
            s = 1 if side == "Right" else -1
            for k in range(self.stance + 1):
                t = (start + k) % self.cycle
                pose = {"LowerTorso": self.root_at(t)}
                x, z, pitch, anchor = self.foot_plan(k)
                plant(pose, side, x=x * s, z=z, pitch=pitch, anchor=anchor, knee=(0.12 * s, 0, -1))
                a.key(t, {j: pose[j] for j in (f"{side}UpperLeg", f"{side}LowerLeg", f"{side}Foot")}, ease="bezier")
            swing = self.cycle - self.stance  # frames in the air
            for u, (thigh, knee, pitch) in ((0.3, (-8, -52, -22)), (0.6, (16, -58, -6)), (0.85, (24, -22, 6))):
                t = (start + self.stance + round(u * swing)) % self.cycle
                pose = {"LowerTorso": self.root_at(t)}
                yaw = pose["LowerTorso"][1]
                pose[f"{side}UpperLeg"] = (thigh - self.hip_pitch, -0.7 * yaw, 2 * s)
                pose[f"{side}LowerLeg"] = (knee, 0, 0)
                orient(pose, f"{side}Foot", pitch, 0)
                a.key(t, {j: pose[j] for j in (f"{side}UpperLeg", f"{side}LowerLeg", f"{side}Foot")}, ease="bezier")
        return a

    def chest(self, t, extra=0.0):
        _, yaw, roll, *_ = self.root_at(t)
        return (self.chest_pitch + extra, -1.6 * yaw, -roll)

    def bob(self, t):
        """+1 at the top of the bob (passing), -1 at contact: follows the solved root height."""
        lo, hi = min(self.py), max(self.py)
        return 2 * (self.py[t % self.step] - lo) / max(1e-6, hi - lo) - 1


def walk_upper(g, a, arms="swing", lag=2):
    """Chest, head and arms over a gait. arms: swing | box | basket."""
    for t in range(0, g.cycle, 5):
        b = g.bob(t)
        _, yaw, *_ = g.root_at(t)
        pose = {"UpperTorso": g.chest(t, 1.2 * b), "Head": (1.5 - 1.2 * b, 1.2 * yaw, 0)}
        phase = math.cos(TAU * t / g.cycle)  # +1 when the right foot lands (left arm forward)
        if arms in ("swing", "basket"):
            arm(pose, "Right", fwd=-22 * phase, out=6, elbow=16 + 10 * max(0, -phase), wrist=-6)
        if arms == "swing":
            arm(pose, "Left", fwd=22 * phase, out=6, elbow=16 + 10 * max(0, phase), wrist=-6)
        a.key(t, pose, ease="bezier")
    # hands solved by IK need their own pass because they depend on the chest pose
    if arms in ("box", "basket"):
        for t in range(0, g.cycle, 5):
            b = g.bob(t)
            _, yaw, *_ = g.root_at(t)
            pose = {"LowerTorso": g.root_at(t), "UpperTorso": g.chest(t, 1.2 * b)}
            if arms == "box":
                hold_box(pose, bob=-0.03 * b)
                keys = ("RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand")
            else:
                hold_basket(pose, sway=0.05 * math.sin(TAU * t / g.cycle))
                keys = ("LeftUpperArm", "LeftLowerArm", "LeftHand")
            a.key(t, {k: pose[k] for k in keys}, ease="bezier")
    for part in ("UpperArm", "LowerArm", "Hand"):
        a.offset(f"Right{part}", lag).offset(f"Left{part}", lag)
    a.offset("Head", 2)
    return a


def wrist_world(pose, side):
    """Wrist position for a pose (studs, character space): used to check prop alignment."""
    from _r15 import joint_pos
    return joint_pos(pose, f"{side}Hand")


# ---------------------------------------------------------------------------------------------
# Action clips: key poses are written as body parameters + hand targets, sampled every 2 frames
# and solved by IK. Feet stay locked on their marks and hands land exactly on contact points.
#   hand = (space, (x, y, z), elbow_hint, hand_angles); space "chest" (UpperTorso axes, rides the
#   body) or "world" (character space, stays on a prop while the body moves).

REST_R = ("chest", (1.45, -0.86, -0.12), (0.4, -0.2, 1.0), (-4, 0, 0))
REST_L = ("chest", (-1.45, -0.86, -0.12), (-0.4, -0.2, 1.0), (-4, 0, 0))
BASE = {"hips": (0, 0, 0), "move": (0, -0.06, 0), "chest": (0, 0, 0), "head": (0, 0, 0), "rh": REST_R, "lh": REST_L}
BOX_R = ("chest", BOX_HOLD["Right"][0], BOX_HOLD["Right"][1], (0, 0, -12))
BOX_L = ("chest", BOX_HOLD["Left"][0], BOX_HOLD["Left"][1], (0, 0, 12))
BASKET_L = ("chest", BASKET_HOLD[0], BASKET_HOLD[1], (0, 0, 8))


def _ease(name, u):
    u = max(0.0, min(1.0, u))
    if name == "lin":
        return u
    if name == "in":
        return u ** 3
    if name == "out":
        return 1 - (1 - u) ** 3
    if name == "back":  # overshoot ~8 % then settle
        c = 1.4
        return 1 + (c + 1) * (u - 1) ** 3 + c * (u - 1) ** 2
    if name == "hold":
        return 0.0
    return 3 * u * u - 2 * u * u * u if name == "io" else 0.5 - 0.5 * math.cos(math.pi * u)


def _lerp(a, b, w):
    return tuple(x + (y - x) * w for x, y in zip(a, b))


class Keys:
    """keys = [(frame, ease_into_this_key, {params})]; missing params carry over from the previous key."""

    def __init__(self, keys, base=None):
        self.keys = []
        cur = dict(base or BASE)
        for f, ease, params in sorted(keys, key=lambda k: k[0]):
            cur = dict(cur)
            cur.update(params)
            self.keys.append((f, ease, cur))

    def at(self, t):
        ks = self.keys
        if t <= ks[0][0]:
            return ks[0][2], ks[0][2], 0.0
        for (f0, _, p0), (f1, ease, p1) in zip(ks, ks[1:]):
            if t <= f1:
                return p0, p1, _ease(ease, (t - f0) / (f1 - f0))
        return ks[-1][2], ks[-1][2], 0.0


def _hand_world(pose, hand):
    space, at, elbow, angles = hand
    if space == "world":
        return Vector(at), Vector(elbow), angles
    f = fk(pose)["UpperTorso"]
    return f @ Vector(at), f.to_3x3() @ Vector(elbow), angles


def solve(p0, p1, w, feet=None, hints=None):
    """Pose for params interpolated w between p0 and p1 (hints: optional per-side elbow overrides)."""
    body = {k: _lerp(p0[k], p1[k], w) for k in ("hips", "move", "chest", "head")}
    pose = stand(body["hips"], body["move"], body["chest"], body["head"], feet=feet, arms=False)
    for side, key in (("Right", "rh"), ("Left", "lh")):
        a_at, a_el, a_ang = _hand_world(pose, p0[key])
        b_at, b_el, b_ang = _hand_world(pose, p1[key])
        at = a_at.lerp(b_at, w)
        el = a_el.normalized().lerp(b_el.normalized(), w)
        if hints and side in hints:
            el = hints[side]
        reach(pose, side, at, elbow=el, hand=_lerp(a_ang, b_ang, w))
    return pose


def _hint_of(pose, p0, p1, w, key):
    a = _hand_world(pose, p0[key])[1].normalized()
    b = _hand_world(pose, p1[key])[1].normalized()
    return a.lerp(b, w).normalized()


def solve_clean(p0, p1, w, feet=None, prev=None, limit=0.12):
    """solve(), then if an arm sinks into the body, nudge its elbow hint (staying within reach of the
    previous frame's hint so the motion stays continuous). prev/returned = {side: hint}."""
    pose = solve(p0, p1, w, feet=feet)
    chosen = {}
    for side, key in (("Right", "rh"), ("Left", "lh")):
        base = _hint_of(pose, p0, p1, w, key)
        anchor = prev[side] if prev and side in prev else base
        if overlap(pose, side) <= limit:
            chosen[side] = base
            continue
        s = 1 if side == "Right" else -1
        dirs = [Vector((s * a, b, c)).normalized() for a in (0.25, 0.6, 1.0) for b in (-1.0, -0.6, -0.25, 0.15) for c in (-0.6, -0.2, 0.2, 0.6)]
        cands = [base, anchor] + [(base * 0.6 + d * 0.4).normalized() for d in dirs]
        def score(h):
            return overlap(solve(p0, p1, w, feet=feet, hints={**chosen, side: h}), side) + 0.05 * (1 - h.dot(anchor))
        chosen[side] = min(cands, key=score)
    return solve(p0, p1, w, feet=feet, hints=chosen), chosen


def overlap(pose, side=None):
    """Deepest limb-into-body penetration (studs) for a pose, measured exactly like make-anim's
    checks (same rig pairs, same sample points). side limits it to pairs with that arm."""
    import checks
    from _r15 import RIG
    frames = fk(pose)
    worst = 0.0
    for a, b in RIG["pairs"]:
        if side and not (a.startswith(side) or b.startswith(side)):
            continue
        d = max(checks._depth_inside(q, frames[b], RIG["parts"][b]) for q in checks._samples_along(frames[a], RIG["parts"][a]))
        worst = max(worst, d)
    return worst


def _best_hints(track, feet=None):
    """Per key pose and hand, pick the elbow hint (near the authored one) that keeps the arm out of
    the body. Hints interpolate between keys, so this cannot introduce frame-to-frame flips."""
    last = {}
    for i, (f, ease, params) in enumerate(track.keys):
        for side, key in (("Right", "rh"), ("Left", "lh")):
            space, at, hint, ang = params[key]
            s = 1 if side == "Right" else -1
            given = Vector(hint).normalized()
            # world-space elbow direction chosen on the previous key: the next key prefers to stay close
            prev_dir = last.get(side)
            cands = [given] + [Vector((s * a, b, c)).normalized() for a in (0.25, 0.6, 1.0)
                               for b in (-1.0, -0.6, -0.25, 0.15) for c in (-0.6, -0.2, 0.2, 0.6)]
            def world_dir(h):
                trial = dict(params)
                trial[key] = (space, at, tuple(h), ang)
                pose = solve(trial, trial, 0.0, feet=feet)
                return pose, _hand_world(pose, trial[key])[1].normalized()

            def score(h):
                pose, wd = world_dir(h)
                keep = 0.08 * (1 - wd.dot(prev_dir)) if prev_dir is not None else 0.0
                return overlap(pose, side) + 0.03 * (1 - h.dot(given)) + keep
            best = min(cands, key=score)
            params[key] = (space, at, tuple(best), ang)
            last[side] = world_dir(best)[1]


def keyed_clip(name, length, keys, markers=(), loop=False, priority="Action", feet=None, step=2, tune=True):
    track = Keys(keys)
    if tune:
        _best_hints(track, feet=feet)
    a = ak.Anim(name, rig="R15", length=length, loop=loop, priority=priority)
    frames = list(range(0, length + 1, step))
    if frames[-1] != length:
        frames.append(length)
    prev = None
    for t in frames:
        p0, p1, w = track.at(t)
        if tune == "frames":  # experimental; produced twist flips in tests, kept off by default
            pose, prev = solve_clean(p0, p1, w, feet=feet, prev=prev)
        else:
            pose = solve(p0, p1, w, feet=feet)
        a.full(t, pose, ease="linear")
    for f, m in markers:
        a.marker(f, m)
    return a


def residual(keys, frame, side="Right", feet=None):
    """Distance (studs) between the solved wrist and its target at a key frame: reach check."""
    from _r15 import joint_pos
    track = Keys(keys)
    p0, p1, w = track.at(frame)
    pose = solve(p0, p1, w, feet=feet)
    target, _, _ = _hand_world(pose, p1["rh" if side == "Right" else "lh"] if w > 0.999 else p0["rh" if side == "Right" else "lh"])
    return (joint_pos(pose, f"{side}Hand") - target).length
