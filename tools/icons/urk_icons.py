"""URK Icons: an original game-UI icon set drawn from code (MIT, part of UltimateRobloxKit).

Each icon is a function that draws white shapes on a 100 x 100 design grid through `Pen`.
`build_icons.py` renders them supersampled, so edges stay smooth at every size, and writes
single PNGs, sprite sheets for Roblox (ImageRectOffset/ImageRectSize), and a catalog.
Glyphs are solid white on transparency, so Roblox can tint them with ImageColor3 for any theme.

Style rules (keep new icons consistent): chunky silhouettes, strokes of 9-12 units, rounded
joins, optical size about 80 units inside the 100 grid, holes cut with `pen.cut()`.
"""
from __future__ import annotations

import math

ICONS: dict = {}


def icon(name: str, category: str, tags: str = ""):
    def register(fn):
        if name in ICONS:
            raise ValueError(f"duplicate icon {name}")
        ICONS[name] = {"draw": fn, "category": category, "tags": [t for t in tags.split() if t]}
        return fn
    return register


class Pen:
    """Drawing on a 100-unit grid. `fill` is 255 for ink and 0 while cutting holes."""

    def __init__(self, draw, scale: float):
        self.d, self.s, self.fill = draw, scale, 255

    def cut(self):
        self.fill = 0
        return self

    def ink(self):
        self.fill = 255
        return self

    def _p(self, pts):
        return [(x * self.s, y * self.s) for x, y in pts]

    def circle(self, cx, cy, r):
        self.d.ellipse([(cx - r) * self.s, (cy - r) * self.s, (cx + r) * self.s, (cy + r) * self.s], fill=self.fill)

    def ellipse(self, cx, cy, rx, ry):
        self.d.ellipse([(cx - rx) * self.s, (cy - ry) * self.s, (cx + rx) * self.s, (cy + ry) * self.s], fill=self.fill)

    def ring(self, cx, cy, r, w):
        self.circle(cx, cy, r)
        f = self.fill
        self.fill = 0 if f else 255
        self.circle(cx, cy, r - w)
        self.fill = f

    def rect(self, x0, y0, x1, y1, r=0):
        box = [x0 * self.s, y0 * self.s, x1 * self.s, y1 * self.s]
        if r:
            self.d.rounded_rectangle(box, radius=r * self.s, fill=self.fill)
        else:
            self.d.rectangle(box, fill=self.fill)

    def poly(self, pts):
        self.d.polygon(self._p(pts), fill=self.fill)

    def line(self, pts, w):
        """Polyline with round caps and joins."""
        pts = list(pts)
        for a, b in zip(pts, pts[1:]):
            self.d.line(self._p([a, b]), fill=self.fill, width=max(1, int(w * self.s)))
        for x, y in pts:
            self.circle(x, y, w / 2)

    def arc(self, cx, cy, r, a0, a1, w, steps=40):
        """Stroke an arc; angles in degrees, 0 = right, clockwise on screen (y down)."""
        pts = [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / steps)),
                cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / steps))) for i in range(steps + 1)]
        self.line(pts, w)

    def star(self, cx, cy, r_out, r_in, n=5, rot=-90):
        pts = []
        for i in range(n * 2):
            r = r_out if i % 2 == 0 else r_in
            a = math.radians(rot + i * 180 / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        self.poly(pts)

    def heart(self, cx, cy, size):
        pts = []
        for i in range(120):
            t = 2 * math.pi * i / 120
            x = 16 * math.sin(t) ** 3
            y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
            pts.append((cx + x * size / 17, cy + y * size / 17))
        self.poly(pts)

    def bolt(self, cx, cy, s):
        self.poly([(cx + 6 * s, cy - 40 * s), (cx - 22 * s, cy + 6 * s), (cx - 2 * s, cy + 6 * s),
                   (cx - 8 * s, cy + 40 * s), (cx + 22 * s, cy - 8 * s), (cx + 2 * s, cy - 8 * s)])


# ---------------------------------------------------------------- currency and rewards
@icon("coin", "currency", "money gold cash currency")
def _(p):
    p.circle(50, 50, 40)
    p.cut().ring(50, 50, 31, 6)
    p.rect(44, 30, 56, 70, 5)


@icon("coins", "currency", "money stack gold")
def _(p):
    # Three stacked coins seen from the side, separated by thin gaps.
    for y in (72, 52, 32):
        p.ink().rect(14, y - 9, 86, y + 9, 9)
        p.cut().rect(10, y + 9, 90, y + 12)
    p.ink().rect(14, 23, 86, 41, 9)


@icon("gem", "currency", "diamond premium jewel")
def _(p):
    p.poly([(20, 38), (34, 18), (66, 18), (80, 38), (50, 86)])
    p.cut().line([(20, 38), (80, 38)], 4)
    p.line([(42, 20), (36, 38), (50, 82)], 4)
    p.line([(58, 20), (64, 38), (50, 82)], 4)


@icon("cash", "currency", "money bill dollar banknote")
def _(p):
    p.rect(8, 26, 92, 74, 8)
    p.cut().ring(50, 50, 15, 6)
    p.circle(22, 50, 5)
    p.circle(78, 50, 5)


@icon("ticket", "currency", "token pass event")
def _(p):
    p.rect(10, 26, 90, 74, 8)
    p.cut().circle(10, 50, 10)
    p.circle(90, 50, 10)
    for y in range(32, 72, 10):
        p.rect(60, y, 64, y + 5)


@icon("token", "currency", "chip credit")
def _(p):
    p.circle(50, 50, 40)
    p.cut().star(50, 50, 24, 11)


@icon("gift", "rewards", "present reward daily")
def _(p):
    p.rect(14, 40, 86, 58, 4)
    p.rect(20, 58, 80, 88, 4)
    p.cut().rect(45, 40, 55, 88)
    p.ink().ellipse(38, 30, 14, 9)
    p.ellipse(62, 30, 14, 9)
    p.cut().ellipse(38, 30, 7, 4)
    p.ellipse(62, 30, 7, 4)


@icon("chest", "rewards", "treasure loot box")
def _(p):
    p.rect(12, 44, 88, 86, 6)
    p.d.pieslice([12 * p.s, 14 * p.s, 88 * p.s, 74 * p.s], 180, 360, fill=255)
    p.cut().rect(12, 40, 88, 46)
    p.rect(42, 50, 58, 66, 3)
    p.ink().rect(47, 54, 53, 62)


@icon("trophy", "rewards", "win achievement cup leaderboard")
def _(p):
    p.poly([(26, 14), (74, 14), (70, 46), (50, 60), (30, 46)])
    p.arc(26, 30, 14, 90, 270, 7)
    p.arc(74, 30, 14, -90, 90, 7)
    p.rect(44, 58, 56, 74)
    p.rect(30, 74, 70, 88, 4)


@icon("medal", "rewards", "badge achievement award")
def _(p):
    p.poly([(28, 8), (44, 8), (56, 40), (40, 40)])
    p.poly([(72, 8), (56, 8), (44, 40), (60, 40)])
    p.circle(50, 62, 28)
    p.cut().star(50, 62, 17, 8)


@icon("crown", "rewards", "vip king premium rank")
def _(p):
    p.poly([(12, 30), (32, 52), (50, 20), (68, 52), (88, 30), (80, 74), (20, 74)])
    p.rect(20, 78, 80, 88, 3)
    p.circle(12, 28, 7)
    p.circle(50, 18, 7)
    p.circle(88, 28, 7)


@icon("star", "rewards", "favorite rating level")
def _(p):
    p.star(50, 52, 44, 19)


@icon("level-up", "rewards", "arrow upgrade xp")
def _(p):
    p.poly([(50, 10), (86, 48), (64, 48), (64, 88), (36, 88), (36, 48), (14, 48)])


# ---------------------------------------------------------------- navigation and actions
@icon("close", "actions", "x cancel dismiss")
def _(p):
    p.line([(24, 24), (76, 76)], 14)
    p.line([(76, 24), (24, 76)], 14)


@icon("check", "actions", "confirm ok done tick")
def _(p):
    p.line([(18, 52), (40, 74), (82, 28)], 14)


@icon("plus", "actions", "add more increase")
def _(p):
    p.line([(50, 16), (50, 84)], 14)
    p.line([(16, 50), (84, 50)], 14)


@icon("minus", "actions", "remove less decrease")
def _(p):
    p.line([(16, 50), (84, 50)], 14)


@icon("arrow-left", "actions", "back previous")
def _(p):
    p.line([(78, 50), (24, 50)], 13)
    p.line([(46, 24), (22, 50), (46, 76)], 13)


@icon("arrow-right", "actions", "next forward")
def _(p):
    p.line([(22, 50), (76, 50)], 13)
    p.line([(54, 24), (78, 50), (54, 76)], 13)


@icon("arrow-up", "actions", "up raise")
def _(p):
    p.line([(50, 78), (50, 24)], 13)
    p.line([(24, 46), (50, 22), (76, 46)], 13)


@icon("arrow-down", "actions", "down lower")
def _(p):
    p.line([(50, 22), (50, 76)], 13)
    p.line([(24, 54), (50, 78), (76, 54)], 13)


@icon("refresh", "actions", "reload retry restart")
def _(p):
    p.arc(50, 50, 30, -60, 230, 11)
    p.poly([(66, 8), (88, 28), (60, 36)])


@icon("search", "actions", "find magnifier zoom")
def _(p):
    p.ring(42, 42, 28, 11)
    p.line([(62, 62), (84, 84)], 14)


@icon("settings", "actions", "gear options preferences")
def _(p):
    for i in range(8):
        a = math.radians(i * 45)
        cx, cy = 50 + 34 * math.cos(a), 50 + 34 * math.sin(a)
        p.circle(cx, cy, 9)
    p.circle(50, 50, 34)
    p.cut().circle(50, 50, 13)


@icon("menu", "actions", "hamburger list more")
def _(p):
    for y in (26, 50, 74):
        p.line([(18, y), (82, y)], 12)


@icon("more", "actions", "dots ellipsis options")
def _(p):
    for x in (22, 50, 78):
        p.circle(x, 50, 9)


@icon("info", "status", "help about details")
def _(p):
    p.circle(50, 50, 42)
    p.cut().circle(50, 28, 7)
    p.rect(44, 42, 56, 74, 4)


@icon("warning", "status", "alert caution danger")
def _(p):
    p.poly([(50, 8), (94, 88), (6, 88)])
    p.cut().rect(45, 34, 55, 62, 4)
    p.circle(50, 74, 6)


@icon("question", "status", "help unknown faq")
def _(p):
    p.circle(50, 50, 42)
    p.cut().arc(50, 38, 13, 180, 405, 9)
    p.line([(59, 47), (50, 55), (50, 60)], 9)
    p.circle(50, 73, 6)


@icon("lock", "status", "locked secure private")
def _(p):
    p.arc(50, 40, 18, 180, 360, 10)
    p.line([(32, 40), (32, 48)], 10)
    p.line([(68, 40), (68, 48)], 10)
    p.rect(20, 46, 80, 88, 8)
    p.cut().circle(50, 62, 7)
    p.rect(47, 62, 53, 76)


@icon("unlock", "status", "unlocked open")
def _(p):
    p.arc(50, 34, 18, 180, 340, 10)
    p.line([(32, 34), (32, 48)], 10)
    p.rect(20, 46, 80, 88, 8)
    p.cut().circle(50, 62, 7)
    p.rect(47, 62, 53, 76)


@icon("trash", "actions", "delete remove bin")
def _(p):
    p.rect(14, 18, 86, 28, 4)
    p.rect(40, 10, 60, 20, 3)
    p.poly([(22, 32), (78, 32), (72, 90), (28, 90)])
    p.cut()
    for x in (38, 50, 62):
        p.rect(x - 3, 42, x + 3, 80, 2)


@icon("edit", "actions", "pencil rename write")
def _(p):
    p.poly([(66, 12), (88, 34), (38, 84), (16, 84), (16, 62)])
    p.cut().line([(58, 22), (78, 42)], 5)


@icon("share", "actions", "send export link")
def _(p):
    p.circle(74, 22, 13)
    p.circle(26, 50, 13)
    p.circle(74, 78, 13)
    p.line([(26, 50), (74, 22)], 8)
    p.line([(26, 50), (74, 78)], 8)


@icon("download", "actions", "save get")
def _(p):
    p.line([(50, 12), (50, 60)], 12)
    p.line([(28, 40), (50, 62), (72, 40)], 12)
    p.line([(16, 70), (16, 86), (84, 86), (84, 70)], 11)


@icon("play", "actions", "start resume go")
def _(p):
    p.poly([(28, 14), (84, 50), (28, 86)])


@icon("pause", "actions", "stop wait")
def _(p):
    p.rect(22, 16, 42, 84, 5)
    p.rect(58, 16, 78, 84, 5)


@icon("filter", "actions", "sort funnel")
def _(p):
    p.poly([(10, 14), (90, 14), (60, 50), (60, 86), (40, 76), (40, 50)])


@icon("expand", "actions", "fullscreen maximize")
def _(p):
    for sx, sy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
        cx, cy = 50 + sx * 30, 50 + sy * 30
        p.line([(cx - sx * 22, cy), (cx, cy), (cx, cy - sy * 22)], 11)


# ---------------------------------------------------------------- interface places
@icon("home", "interface", "house lobby main")
def _(p):
    p.poly([(50, 10), (92, 48), (80, 48), (80, 88), (20, 88), (20, 48), (8, 48)])
    p.cut().rect(41, 60, 59, 88, 3)


@icon("shop", "interface", "store cart buy market")
def _(p):
    p.line([(8, 18), (22, 18), (32, 64), (80, 64), (88, 32), (26, 32)], 9)
    p.poly([(26, 32), (88, 32), (80, 64), (32, 64)])
    p.circle(36, 80, 8)
    p.circle(74, 80, 8)


@icon("bag", "interface", "inventory backpack items")
def _(p):
    p.arc(50, 30, 15, 180, 360, 8)
    p.rect(16, 30, 84, 90, 12)
    p.cut().rect(30, 52, 70, 62, 4)


@icon("map", "interface", "world travel location")
def _(p):
    p.poly([(8, 22), (34, 12), (66, 24), (92, 14), (92, 78), (66, 88), (34, 76), (8, 86)])
    p.cut().line([(34, 18), (34, 72)], 4)
    p.line([(66, 28), (66, 82)], 4)


@icon("pin", "interface", "location marker waypoint")
def _(p):
    p.circle(50, 38, 30)
    p.poly([(24, 50), (76, 50), (50, 92)])
    p.cut().circle(50, 38, 12)


@icon("chat", "interface", "message talk speech")
def _(p):
    p.rect(8, 12, 92, 70, 14)
    p.poly([(24, 66), (44, 66), (22, 90)])
    p.cut()
    for x in (30, 50, 70):
        p.circle(x, 41, 6)


@icon("mail", "interface", "inbox letter message")
def _(p):
    p.rect(8, 20, 92, 80, 8)
    p.cut().line([(16, 30), (50, 56), (84, 30)], 7)


@icon("bell", "interface", "notification alert")
def _(p):
    p.poly([(26, 70), (28, 40), (40, 22), (60, 22), (72, 40), (74, 70), (84, 78), (16, 78)])
    p.circle(50, 22, 12)
    p.circle(50, 84, 8)


@icon("user", "interface", "player profile account")
def _(p):
    p.circle(50, 32, 20)
    p.d.pieslice([14 * p.s, 56 * p.s, 86 * p.s, 128 * p.s], 180, 360, fill=255)


@icon("users", "interface", "friends party group team")
def _(p):
    p.circle(36, 34, 16)
    p.d.pieslice([6 * p.s, 56 * p.s, 66 * p.s, 116 * p.s], 180, 360, fill=255)
    p.circle(70, 30, 13)
    p.d.pieslice([50 * p.s, 50 * p.s, 94 * p.s, 100 * p.s], 180, 360, fill=255)


@icon("clock", "interface", "time timer wait")
def _(p):
    p.ring(50, 50, 42, 10)
    p.line([(50, 26), (50, 50), (66, 62)], 9)


@icon("calendar", "interface", "date daily event")
def _(p):
    p.rect(10, 18, 90, 90, 10)
    p.cut().rect(18, 38, 82, 82, 4)
    p.ink()
    p.rect(26, 8, 34, 26, 3)
    p.rect(66, 8, 74, 26, 3)
    for x in (30, 50, 70):
        for y in (50, 68):
            p.rect(x - 6, y - 5, x + 6, y + 5, 2)


@icon("flag", "interface", "goal finish checkpoint")
def _(p):
    p.rect(16, 8, 26, 92, 4)
    p.poly([(26, 12), (86, 12), (72, 32), (86, 52), (26, 52)])


@icon("target", "interface", "aim goal objective quest")
def _(p):
    p.ring(50, 50, 42, 9)
    p.ring(50, 50, 25, 9)
    p.circle(50, 50, 8)


@icon("quest", "interface", "scroll mission task")
def _(p):
    p.rect(22, 14, 78, 86, 6)
    p.ellipse(22, 20, 10, 10)
    p.ellipse(78, 80, 10, 10)
    p.cut()
    for y in (32, 46, 60):
        p.rect(32, y, 68, y + 6, 3)


@icon("leaderboard", "interface", "ranking podium top")
def _(p):
    p.rect(8, 50, 34, 90, 3)
    p.rect(37, 26, 63, 90, 3)
    p.rect(66, 62, 92, 90, 3)
    p.cut().rect(47, 36, 53, 52)


@icon("volume", "interface", "sound audio speaker on")
def _(p):
    p.poly([(10, 36), (30, 36), (54, 14), (54, 86), (30, 64), (10, 64)])
    p.arc(56, 50, 18, -50, 50, 8)
    p.arc(56, 50, 32, -50, 50, 8)


@icon("mute", "interface", "sound off silent")
def _(p):
    p.poly([(10, 36), (30, 36), (54, 14), (54, 86), (30, 64), (10, 64)])
    p.line([(66, 36), (90, 64)], 9)
    p.line([(90, 36), (66, 64)], 9)


@icon("music", "interface", "song note audio")
def _(p):
    p.ellipse(28, 76, 16, 12)
    p.ellipse(74, 66, 16, 12)
    p.rect(36, 18, 44, 76)
    p.rect(82, 10, 90, 66)
    p.poly([(36, 18), (90, 8), (90, 24), (36, 34)])


@icon("eye", "interface", "view visible show")
def _(p):
    p.ellipse(50, 50, 44, 26)
    p.cut().circle(50, 50, 18)
    p.ink().circle(50, 50, 9)


@icon("camera", "interface", "photo screenshot view")
def _(p):
    p.rect(8, 28, 92, 84, 10)
    p.rect(34, 16, 66, 30, 4)
    p.cut().circle(50, 56, 19)
    p.ink().circle(50, 56, 10)


@icon("gamepad", "interface", "controller console input")
def _(p):
    p.rect(8, 30, 92, 74, 22)
    p.cut()
    p.rect(22, 47, 42, 55, 2)
    p.rect(28, 41, 36, 61, 2)
    p.circle(66, 46, 6)
    p.circle(76, 58, 6)


@icon("keyboard", "interface", "keys input pc")
def _(p):
    p.rect(6, 26, 94, 76, 8)
    p.cut()
    for row, y in enumerate((36, 50)):
        for x in range(16, 86, 14):
            p.rect(x, y, x + 9, y + 8, 2)
    p.rect(28, 62, 72, 68, 2)


@icon("touch", "interface", "tap mobile finger")
def _(p):
    p.rect(40, 30, 54, 82, 7)
    p.rect(52, 50, 64, 82, 6)
    p.rect(62, 54, 74, 82, 6)
    p.rect(36, 64, 76, 92, 10)
    p.ring(47, 22, 16, 5)


# ---------------------------------------------------------------- game items
@icon("sword", "items", "weapon attack combat melee")
def _(p):
    p.poly([(80, 8), (92, 8), (92, 20), (44, 68), (32, 56)])
    p.line([(22, 50), (50, 78)], 12)
    p.line([(36, 64), (14, 86)], 12)


@icon("shield", "items", "defense armor protect")
def _(p):
    p.poly([(50, 8), (88, 22), (84, 56), (50, 92), (16, 56), (12, 22)])
    p.cut().poly([(50, 22), (74, 31), (71, 54), (50, 76)])


@icon("bow", "items", "archery ranged weapon")
def _(p):
    p.arc(30, 50, 40, -70, 70, 9)
    p.line([(44, 13), (44, 87)], 3)
    p.line([(18, 50), (88, 50)], 5)
    p.poly([(92, 50), (78, 42), (78, 58)])


@icon("potion", "items", "health heal flask consumable")
def _(p):
    p.rect(40, 8, 60, 18, 3)
    p.rect(42, 16, 58, 36)
    p.circle(50, 62, 30)
    p.cut().rect(28, 56, 72, 60)


@icon("key", "items", "unlock door access")
def _(p):
    p.ring(30, 36, 22, 10)
    p.line([(44, 50), (86, 88)], 11)
    p.line([(64, 68), (74, 58)], 9)
    p.line([(74, 78), (84, 68)], 9)


@icon("bomb", "items", "explosive tnt")
def _(p):
    p.circle(44, 60, 32)
    p.rect(56, 22, 72, 36, 3)
    p.arc(76, 24, 9, 180, 300, 5)
    p.star(84, 14, 7, 3, 4)


@icon("hammer", "items", "build tool craft")
def _(p):
    p.poly([(20, 22), (58, 22), (66, 34), (58, 46), (20, 46)])
    p.rect(42, 46, 56, 92, 4)


@icon("pickaxe", "items", "mine dig tool resource")
def _(p):
    p.arc(50, 66, 42, 215, 325, 10)
    p.line([(50, 28), (50, 92)], 10)


@icon("axe", "items", "chop wood tool")
def _(p):
    p.line([(30, 90), (62, 14)], 10)
    p.poly([(56, 18), (88, 30), (86, 56), (66, 44)])


@icon("wrench", "items", "repair fix tool settings")
def _(p):
    p.line([(26, 74), (64, 36)], 13)
    p.circle(70, 30, 20)
    p.cut().poly([(70, 8), (92, 8), (92, 30), (74, 34), (66, 26)])
    p.ink().circle(22, 78, 10)


@icon("magnet", "items", "attract collect pickup")
def _(p):
    p.arc(50, 46, 28, 0, 180, 18)
    p.line([(22, 46), (22, 18)], 18)
    p.line([(78, 46), (78, 18)], 18)
    p.cut().rect(12, 14, 88, 24)


@icon("rocket", "items", "launch boost speed")
def _(p):
    p.poly([(50, 6), (66, 26), (66, 66), (34, 66), (34, 26)])
    p.poly([(34, 46), (18, 70), (34, 66)])
    p.poly([(66, 46), (82, 70), (66, 66)])
    p.poly([(40, 70), (60, 70), (50, 94)])
    p.cut().circle(50, 36, 8)


@icon("egg", "items", "pet hatch spawn")
def _(p):
    p.ellipse(50, 56, 32, 38)
    p.ellipse(50, 40, 24, 24)
    p.cut().line([(24, 58), (36, 50), (44, 60), (56, 50), (64, 60), (76, 52)], 5)


@icon("paw", "items", "pet animal companion")
def _(p):
    p.ellipse(50, 66, 22, 18)
    p.ellipse(26, 44, 9, 12)
    p.ellipse(42, 28, 9, 12)
    p.ellipse(58, 28, 9, 12)
    p.ellipse(74, 44, 9, 12)


@icon("dice", "items", "random chance roll luck")
def _(p):
    p.rect(12, 12, 88, 88, 16)
    p.cut()
    for x, y in ((32, 32), (68, 32), (50, 50), (32, 68), (68, 68)):
        p.circle(x, y, 7)


@icon("puzzle", "items", "piece module plugin")
def _(p):
    p.rect(16, 30, 74, 88, 6)
    p.circle(45, 26, 11)
    p.circle(78, 59, 11)
    p.cut().circle(16, 59, 9)


@icon("car", "items", "vehicle drive transport")
def _(p):
    p.poly([(22, 34), (78, 34), (88, 56), (12, 56)])
    p.rect(6, 52, 94, 74, 8)
    p.circle(28, 76, 11)
    p.circle(72, 76, 11)
    p.cut().poly([(30, 40), (48, 40), (48, 52), (24, 52)])
    p.poly([(54, 40), (72, 40), (78, 52), (54, 52)])


@icon("block", "items", "build cube placement voxel")
def _(p):
    p.poly([(50, 8), (88, 28), (50, 48), (12, 28)])
    p.poly([(12, 34), (47, 54), (47, 92), (12, 72)])
    p.poly([(88, 34), (53, 54), (53, 92), (88, 72)])


# ---------------------------------------------------------------- stats and elements
@icon("health", "stats", "hp heart life")
def _(p):
    p.heart(50, 52, 42)


@icon("health-plus", "stats", "heal regenerate medkit")
def _(p):
    p.heart(50, 52, 42)
    p.cut().rect(44, 28, 56, 66, 2)
    p.rect(31, 41, 69, 53, 2)


@icon("energy", "stats", "power stamina lightning bolt")
def _(p):
    p.bolt(50, 50, 1.0)


@icon("speed", "stats", "fast run boots")
def _(p):
    p.arc(50, 60, 38, 180, 360, 11)
    p.line([(50, 60), (72, 36)], 10)
    p.circle(50, 60, 9)


@icon("strength", "stats", "power muscle attack damage")
def _(p):
    p.rect(8, 38, 20, 62, 4)
    p.rect(20, 28, 32, 72, 4)
    p.rect(32, 44, 68, 56)
    p.rect(68, 28, 80, 72, 4)
    p.rect(80, 38, 92, 62, 4)


@icon("xp", "stats", "experience level progress")
def _(p):
    p.star(50, 50, 44, 34, 8, -90)
    p.cut().line([(32, 36), (48, 64)], 7)
    p.line([(48, 36), (32, 64)], 7)
    p.rect(56, 34, 62, 66)
    p.arc(62, 43, 9, -90, 90, 6)


@icon("fire", "stats", "flame burn hot")
def _(p):
    p.poly([(50, 6), (74, 36), (82, 62), (70, 86), (50, 94), (30, 86), (18, 62), (28, 42), (40, 50), (42, 28)])
    p.cut().poly([(50, 52), (62, 70), (58, 86), (42, 86), (38, 70)])


@icon("snowflake", "stats", "ice cold freeze winter")
def _(p):
    for a in (0, 60, 120):
        r = math.radians(a)
        dx, dy = 40 * math.cos(r), 40 * math.sin(r)
        p.line([(50 - dx, 50 - dy), (50 + dx, 50 + dy)], 8)
    p.circle(50, 50, 10)


@icon("leaf", "stats", "nature plant eco grow")
def _(p):
    p.poly([(14, 86), (20, 40), (44, 18), (88, 12), (82, 54), (60, 80)])
    p.cut().line([(20, 82), (70, 30)], 5)


@icon("water", "stats", "drop liquid rain")
def _(p):
    p.circle(50, 62, 28)
    p.poly([(50, 8), (75, 50), (25, 50)])


@icon("skull", "stats", "death danger hazard")
def _(p):
    p.circle(50, 42, 34)
    p.rect(30, 58, 70, 88, 8)
    p.cut().circle(37, 44, 9)
    p.circle(63, 44, 9)
    p.rect(38, 74, 43, 88)
    p.rect(48, 74, 53, 88)
    p.rect(58, 74, 62, 88)


# ---------------------------------------------------------------- V2 additions (economy, social, status, gameplay)
@icon("wallet", "currency", "money purse balance")
def _(p):
    p.rect(8, 26, 86, 84, 10)
    p.rect(14, 14, 70, 32, 6)
    p.cut().rect(58, 44, 94, 66, 8)
    p.ink().circle(70, 55, 5)


@icon("money-bag", "currency", "sack loot cash")
def _(p):
    p.ellipse(50, 62, 36, 30)
    p.poly([(34, 30), (66, 30), (58, 40), (42, 40)])
    p.ellipse(50, 22, 14, 9)
    p.cut().rect(46, 46, 54, 80, 3)
    p.rect(38, 52, 62, 58, 2)
    p.rect(38, 68, 62, 74, 2)


@icon("gem-stack", "currency", "gems diamonds premium pile")
def _(p):
    # Two gems side by side and one in front, separated by cut lines so they read as three.
    for cx, cy, k in ((30, 40, 0.62), (70, 40, 0.62), (50, 62, 0.78)):
        p.ink().poly([(cx - 30 * k, cy - 8 * k), (cx - 16 * k, cy - 26 * k), (cx + 16 * k, cy - 26 * k),
                      (cx + 30 * k, cy - 8 * k), (cx, cy + 30 * k)])
    p.cut().line([(28, 46), (50, 30), (72, 46)], 3)


@icon("boost", "items", "x2 multiplier double potion")
def _(p):
    p.rect(8, 22, 92, 78, 18)
    p.cut().line([(22, 38), (40, 62)], 8)
    p.line([(40, 38), (22, 62)], 8)
    p.arc(64, 42, 9, 200, 380, 7)
    p.line([(72, 46), (54, 64), (76, 64)], 7)


@icon("egg-cracked", "items", "hatch pet open")
def _(p):
    p.ellipse(50, 60, 32, 34)
    p.cut().line([(18, 48), (32, 40), (42, 50), (54, 38), (66, 50), (82, 42)], 5)
    p.ink().poly([(22, 34), (34, 12), (46, 28), (56, 10), (66, 26), (78, 30), (70, 36), (30, 36)])


@icon("pet", "items", "animal companion cat")
def _(p):
    p.ellipse(50, 58, 36, 32)
    p.poly([(18, 44), (22, 12), (42, 32)])
    p.poly([(82, 44), (78, 12), (58, 32)])
    p.cut().circle(38, 56, 6)
    p.circle(62, 56, 6)
    p.poly([(44, 68), (56, 68), (50, 74)])


@icon("power-up", "items", "ability upgrade boost star arrow")
def _(p):
    p.circle(50, 50, 42)
    p.cut().poly([(50, 18), (78, 50), (60, 50), (60, 80), (40, 80), (40, 50), (22, 50)])


@icon("megaphone", "interface", "announce news shout")
def _(p):
    p.poly([(10, 38), (30, 38), (78, 12), (78, 88), (30, 62), (10, 62)])
    p.rect(22, 60, 38, 88, 4)
    p.cut().rect(16, 44, 28, 56)


@icon("news", "interface", "updates changelog paper")
def _(p):
    p.rect(10, 14, 90, 88, 8)
    p.cut().rect(20, 24, 80, 40, 3)
    for y in (50, 62, 74):
        p.rect(20, y, 80, y + 5, 2)


@icon("teleport", "interface", "portal travel warp")
def _(p):
    p.ellipse(50, 50, 34, 44)
    p.cut().ellipse(50, 50, 22, 32)
    p.ink().ellipse(50, 50, 12, 18)


@icon("trade", "interface", "swap exchange arrows")
def _(p):
    p.line([(16, 34), (78, 34)], 11)
    p.poly([(70, 18), (92, 34), (70, 50)])
    p.line([(84, 66), (22, 66)], 11)
    p.poly([(30, 50), (8, 66), (30, 82)])


@icon("backpack", "interface", "inventory bag items storage")
def _(p):
    p.rect(18, 22, 82, 92, 16)
    p.arc(50, 22, 14, 180, 360, 8)
    p.cut().rect(30, 52, 70, 76, 6)
    p.ink().rect(44, 56, 56, 64, 2)


@icon("profile", "interface", "player card account")
def _(p):
    p.rect(8, 18, 92, 82, 10)
    p.cut().circle(32, 44, 11)
    p.d.pieslice([17 * p.s, 54 * p.s, 47 * p.s, 84 * p.s], 180, 360, fill=0)
    p.rect(56, 36, 82, 42, 2)
    p.rect(56, 50, 82, 56, 2)
    p.rect(56, 64, 74, 70, 2)


@icon("invite", "social", "add friend user plus")
def _(p):
    p.circle(40, 32, 18)
    p.d.pieslice([8 * p.s, 54 * p.s, 72 * p.s, 118 * p.s], 180, 360, fill=255)
    p.rect(68, 34, 80, 70, 3)
    p.rect(56, 46, 92, 58, 3)


@icon("party", "social", "group celebrate event confetti")
def _(p):
    p.poly([(12, 90), (34, 30), (72, 68)])
    p.circle(70, 20, 6)
    p.circle(86, 40, 5)
    p.rect(52, 10, 58, 26, 2)
    p.rect(80, 56, 94, 62, 2)


@icon("group", "social", "clan guild team")
def _(p):
    p.poly([(50, 8), (88, 22), (84, 58), (50, 92), (16, 58), (12, 22)])
    p.cut().circle(50, 38, 10)
    p.d.pieslice([32 * p.s, 50 * p.s, 68 * p.s, 86 * p.s], 180, 360, fill=0)


@icon("success", "status", "done ok tick circle")
def _(p):
    p.circle(50, 50, 42)
    p.cut().line([(28, 52), (44, 66), (72, 36)], 10)


@icon("error", "status", "fail wrong cross circle")
def _(p):
    p.circle(50, 50, 42)
    p.cut().line([(34, 34), (66, 66)], 10)
    p.line([(66, 34), (34, 66)], 10)


@icon("equipped", "status", "worn selected badge")
def _(p):
    p.rect(10, 10, 90, 90, 20)
    p.cut().rect(22, 22, 78, 78, 12)
    p.ink().line([(30, 52), (44, 64), (70, 38)], 10)


@icon("loading", "status", "spinner wait busy")
def _(p):
    for i in range(8):
        a = math.radians(i * 45 - 90)
        r = 4 + i * 0.9
        p.circle(50 + 34 * math.cos(a), 50 + 34 * math.sin(a), r)


@icon("stopwatch", "interface", "timer countdown speedrun")
def _(p):
    p.ring(50, 56, 36, 10)
    p.rect(42, 8, 58, 18, 3)
    p.line([(50, 56), (50, 34)], 8)
    p.line([(76, 26), (84, 18)], 8)


@icon("badge", "rewards", "rosette award ribbon")
def _(p):
    p.poly([(30, 56), (22, 94), (38, 86), (46, 94), (46, 60)])
    p.poly([(70, 56), (78, 94), (62, 86), (54, 94), (54, 60)])
    p.star(50, 40, 34, 26, 12)
    p.cut().circle(50, 40, 18)


@icon("event", "rewards", "special limited calendar star")
def _(p):
    p.rect(10, 18, 90, 90, 10)
    p.rect(26, 8, 34, 26, 3)
    p.rect(66, 8, 74, 26, 3)
    p.cut().star(50, 58, 24, 11)


@icon("notification", "interface", "alert badge bell dot")
def _(p):
    p.poly([(24, 70), (26, 40), (38, 22), (60, 22), (72, 40), (74, 70), (84, 78), (14, 78)])
    p.circle(48, 86, 7)
    p.circle(78, 22, 16)
    p.cut().rect(75, 12, 81, 26, 2)
    p.circle(78, 31, 3)


@icon("rebirth", "rewards", "prestige reset restart cycle")
def _(p):
    p.arc(50, 50, 32, -40, 250, 12)
    p.poly([(62, 4), (86, 22), (56, 32)])
    p.star(50, 52, 14, 6)


@icon("codes", "interface", "redeem promo twitter")
def _(p):
    p.rect(6, 26, 94, 74, 14)
    p.cut()
    for x in (22, 40, 58, 76):
        p.rect(x - 6, 42, x + 6, 58, 3)
