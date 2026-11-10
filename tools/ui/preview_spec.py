#!/usr/bin/env python3
"""Render a UrkUI screen spec to a self-contained HTML preview (approximation of the Roblox UI).

  python3 tools/ui/preview_spec.py library/src/UI/Spec/Screens/PetSimShop.json -o build/ui/PetSimShop.html
  python3 tools/ui/preview_spec.py --all -o build/ui/            # every built-in screen + index.html

What it is: a fast design check that uses the SAME inputs as the Roblox builder (design/tokens/
styles.json and the URK icon PNGs), so palettes, outlines, sizes and layout match the intent. What it is
not: Roblox rendering. Fonts, UIStroke and gradients are approximated with CSS, and nothing here proves
the Luau builder works; that needs the Studio playground (library/examples/playground).
The spec is validated first (tools/ui/spec_rules.py); invalid specs are refused with every error.
Icons and the kit's OFL fonts (assets/fonts) are embedded as data URIs, so the file is fully offline.
"""
from __future__ import annotations

import argparse
import base64
import html
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from spec_rules import ROOT, ispackicon, resolved_style, validate  # noqa: E402

ICON_DIR = ROOT / "assets" / "icons" / "urk" / "png"
SCREENS = ROOT / "library" / "src" / "UI" / "Spec" / "Screens"
_icon_cache: dict = {}


def esc(text) -> str:
    return html.escape(str(text))


def icon(name: str | None, size: int = 56) -> str:
    if not name:
        return ""
    if ispackicon(name):
        # Icons of an imported pack are not part of the kit: draw a labelled tile, never the artwork.
        return (f'<span class="ic packic" title="pack icon {esc(name)}" style="width:{size}px;height:{size}px;'
                f'font-size:{max(7, size // 6)}px">{esc(name.split(":", 1)[1])}</span>')
    path = ICON_DIR / f"{name}.png"
    if not path.exists():
        path = ICON_DIR / f"{name}-color.png"
    if not path.exists():
        return f'<span class="missing" title="missing icon {esc(name)}">?</span>'
    if name not in _icon_cache:
        _icon_cache[name] = base64.b64encode(path.read_bytes()).decode()
    return f'<img class="ic" alt="{esc(name)}" style="width:{size}px;height:{size}px" src="data:image/png;base64,{_icon_cache[name]}">'


def clock(seconds: int) -> str:
    """Same rule as the Timer component's "clock" format: h:mm:ss from one hour, else m:ss."""
    seconds = max(0, int(seconds))
    h, rem = divmod(seconds, 3600)
    m, sec = divmod(rem, 60)
    return f"{h}:{m:02d}:{sec:02d}" if h else f"{m}:{sec:02d}"


def fmt_price(price: dict | None) -> str:
    if not price:
        return ""
    k = price.get("kind")
    if k == "robux":
        return f"R$ {price.get('amount', 0):,}"
    if k == "free":
        return "FREE"
    return f"{icon(price.get('currency'), 20)} {price.get('amount', 0):,}"


def abbrev(value) -> str:
    """Rough twin of Core/Format "abbrev": 1250 -> 1.3K. Strings pass through."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return str(value)
    for limit, suffix in ((1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")):
        if abs(value) >= limit:
            return f"{value / limit:.1f}".rstrip("0").rstrip(".") + suffix
    return f"{value:g}"


def pct(value, mx) -> float:
    try:
        return max(0.0, min(100.0, float(value) * 100 / float(mx)))
    except (TypeError, ValueError, ZeroDivisionError):
        return 0.0


class Renderer:
    def __init__(self, style: dict):
        self.s = style

    def swatch(self, name: str | None) -> dict:
        pal = self.s["palette"]
        return pal.get(name or "blue", pal["blue"])

    def grad(self, sw: dict) -> str:
        return f"linear-gradient(180deg,{sw['top']} 0%,{sw['bottom']} 100%)"

    def badge(self, b: dict | None) -> str:
        if not b:
            return ""
        d = self.s["badges"].get(b.get("kind", "new"), self.s["badges"]["new"])
        sw = self.swatch(d["palette"])
        text = b.get("text") or d.get("text") or b.get("kind", "").upper()
        cls = "badge circle" if d["shape"] == "circle" else "badge"
        return f'<span class="{cls}" style="background:{self.grad(sw)}">{esc(text)}</span>'

    def price_button(self, price: dict | None, gift: bool = False) -> str:
        if not price:
            return ""
        kind = "robux" if price.get("kind") == "robux" else ("buy" if price.get("kind") == "free" else "price")
        bdef = self.s["buttons"][kind]
        bg = self.grad(self.s["surfaces"][bdef["surface"]]) if bdef.get("surface") else self.grad(self.swatch(bdef["palette"]))
        gift_html = ""
        if gift:
            gs = self.swatch(self.s["buttons"]["gift"]["palette"])
            gift_html = f'<span class="btn gift" style="background:{self.grad(gs)}">{icon("gift-color", 22)}</span>'
        return f'<div class="pricerow"><span class="btn price" style="background:{bg}">{fmt_price(price)}</span>{gift_html}</div>'

    def el(self, e: dict) -> str:
        """One element. Hidden elements are skipped; `motion` becomes a hover title (nothing animates here)."""
        if e.get("visible") is False:
            return ""
        out = self.el_animated(e)
        if out is None:
            out = self.el_basic(e)
        motion = e.get("motion")
        if motion:
            name = motion if isinstance(motion, str) else motion.get("preset", "")
            out = f'<div class="motion" title="motion: {esc(name)}">{out}</div>'
        return out

    def rarity_color(self, name) -> str:
        return self.s["rarity"].get(name, {}).get("color", self.s["outline"]["color"])

    def chips(self, items) -> str:
        return "".join(f'<span class="chip">{icon(c.get("icon"), 16)}{esc(c.get("text", ""))}</span>' for c in items or [])

    def art(self, e: dict, size: int) -> str:
        if e.get("icon"):
            return icon(e["icon"], size)
        if e.get("image"):
            return f'<span class="ic imgph" style="width:{size}px;height:{size}px" title="{esc(e["image"])}"></span>'
        return ""

    def el_animated(self, e: dict):
        """Static approximations of the animated Game components (UI/Game/README.md)."""
        t = e["type"]
        if t == "premiumButton":
            sw = self.swatch(e.get("palette", "gold"))
            shine = " shine" if e.get("shine", True) else ""
            text = f'<span class="t">{esc(e["text"])}</span>' if e.get("text") else ""
            return f'<span class="btn big premium{shine}" style="background:{self.grad(sw)}">{self.art(e, 28)}{text}</span>'
        if t == "tabBar":
            active = e.get("value") or e["tabs"][0]["id"]
            sw = self.swatch(e.get("palette", "blue"))
            tabs = []
            for tab in e["tabs"]:
                on = tab["id"] == active
                style = f' style="background:{self.grad(sw)}"' if on else ""
                label = f'<span class="{"t" if on else "ink"}">{esc(tab["text"])}</span>' if tab.get("text") else ""
                tabs.append(f'<span class="tab{" on" if on else ""}"{style}>{icon(tab.get("icon"), 20)}{label}</span>')
            return f'<div class="tabs">{"".join(tabs)}</div>'
        if t == "modal":
            hp = self.swatch(e.get("headerPalette", "blue"))
            buttons = "".join(self.el({"type": "button", "text": b["text"], "kind": b.get("kind", "primary")}) for b in e.get("buttons", []))
            body = f'<div class="plain center">{esc(e["text"])}</div>' if e.get("text") else ""
            return (f'<div class="modalbox" title="modal {esc(e["id"])}: hidden until opened">'
                    f'<div class="header small" style="background:{self.grad(hp)}"><span class="t">{esc(e["title"])}</span></div>'
                    f'<div class="content center">{body}<div class="row nowrap">{buttons}</div></div></div>')
        if t == "tooltip":
            return f'<div class="tooltip {esc(e.get("side", "top"))}" title="tooltip for {esc(e["target"])}">{esc(e["text"])}</div>'
        if t == "xpBar":
            value, mx = e.get("value", 0), e.get("max", 100)
            sw = self.swatch(e.get("palette", "blue"))
            return (f'<div class="bar xp"><span class="lvlbadge t" style="background:{self.grad(self.swatch("gold"))}">{esc(e.get("level", 1))}</span>'
                    f'<div class="track"><div class="fill" style="width:{pct(value, mx)}%;background:{self.grad(sw)}"></div></div>'
                    f'<span class="t small">{esc(value)}/{esc(mx)}</span></div>')
        if t == "inventorySlot":
            ring = f"border-color:{self.rarity_color(e['rarity'])};" if e.get("rarity") else ""
            cls = "slot" + (" selected" if e.get("selected") else "") + (" locked" if e.get("locked") else "")
            count = f'<span class="count t">x{esc(e["count"])}</span>' if (e.get("count") or 0) > 1 else ""
            mark = icon("lock-color", 20) if e.get("locked") else (icon("success-color", 18) if e.get("equipped") else "")
            return f'<div class="{cls}" style="{ring}">{self.art(e, 44)}{count}<span class="corner">{mark}</span></div>'
        if t == "petCard":
            sw = self.swatch(e.get("palette", "blue"))
            ring = f"box-shadow:0 0 0 3px {self.rarity_color(e['rarity'])} inset;" if e.get("rarity") else ""
            badge = self.el({"type": "rarityBadge", "rarity": e["rarity"]}) if e.get("rarity") else ""
            mark = f'<span class="corner">{icon("success-color", 20)}</span>' if e.get("equipped") else ""
            cls = "card pet" + (" selected" if e.get("selected") else "")
            return (f'<div class="{cls}" style="background:{self.grad(sw)};{ring}">{mark}<div class="art">{self.art(e, 64)}</div>'
                    f'<div class="t name">{esc(e["title"])}</div>{badge}<div class="chips">{self.chips(e.get("stats"))}</div></div>')
        if t == "rarityBadge":
            color = self.rarity_color(e["rarity"])
            return f'<span class="rarity t" style="background:{color}">{esc(e.get("text") or e["rarity"].upper())}</span>'
        if t == "rewardPanel":
            cols = e.get("columns") or min(4, len(e["rewards"]))
            tiles = "".join(
                f'<div class="tile" style="border-color:{self.rarity_color(r.get("rarity"))}">{self.art(r, 40)}'
                f'<span class="t small">{esc(r.get("amount", ""))}</span></div>' for r in e["rewards"])
            title = f'<div class="t heading">{esc(e["title"])}</div>' if e.get("title") else ""
            claimed = e.get("claimed")
            claim = self.el({"type": "button", "text": "CLAIMED" if claimed else e.get("claimText", "CLAIM"), "kind": "neutral" if claimed else "buy"})
            panel = f'style="background:{self.grad(self.swatch(e["palette"]))}"' if e.get("palette") else ""
            return (f'<div class="panel rewardpanel" {panel}>{title}<div class="grid" style="grid-template-columns:repeat({cols},56px);justify-content:center">'
                    f'{tiles}</div>{claim}</div>')
        if t == "questCard":
            value, mx = e.get("value", 0), e.get("max", 1)
            state = e.get("state") or ("claimable" if value >= mx else "active")
            sw = self.swatch(e.get("palette", "green"))
            label = "CLAIMED" if state == "claimed" else e.get("claimText", "CLAIM")
            claim = self.el({"type": "button", "text": label, "kind": "buy" if state == "claimable" else "neutral"})
            desc = f'<div class="plain small">{esc(e["description"])}</div>' if e.get("description") else ""
            return (f'<div class="panel quest {esc(state)}"><div class="lr"><div class="ink name">{esc(e["title"])}</div>{desc}'
                    f'<div class="track slim"><div class="fill" style="width:{pct(value, mx)}%;background:{self.grad(sw)}"></div></div>'
                    f'<div class="chips">{self.chips(e.get("rewards"))}</div></div>{claim}</div>')
        if t == "achievementCard":
            tier, max_tier = e.get("tier", 0), e.get("maxTier", 3)
            unlocked = e.get("unlocked", tier > 0)
            sw = self.swatch(e.get("palette", "gold") if unlocked else "gray")
            stars = "".join(f'<span class="star{" on" if i < tier else ""}">★</span>' for i in range(max_tier))
            desc = f'<div class="plain small">{esc(e["description"])}</div>' if e.get("description") else ""
            prog = ""
            if e.get("max"):
                prog = (f'<div class="track slim"><div class="fill" style="width:{pct(e.get("value", 0), e["max"])}%;'
                        f'background:{self.grad(self.swatch("green"))}"></div></div>')
            cls = "panel achievement" + ("" if unlocked else " dim")
            return (f'<div class="{cls}"><span class="round" style="background:{self.grad(sw)}">{self.art(e, 34)}</span>'
                    f'<div class="lr"><div class="ink name">{esc(e["title"])}</div>{desc}{prog}</div><span class="stars">{stars}</span></div>')
        if t == "notification":
            accents = {"info": "blue", "success": "green", "warning": "orange", "error": "red"}
            sw = self.swatch(e.get("palette") or accents.get(e.get("kind", "info"), "blue"))
            mark = self.art(e, 26) or '<span class="t">!</span>'
            text = f'<div class="plain small">{esc(e["text"])}</div>' if e.get("text") else ""
            return (f'<div class="panel toast"><span class="round" style="background:{self.grad(sw)}">{mark}</span>'
                    f'<div class="lr"><div class="ink name">{esc(e["title"])}</div>{text}</div></div>')
        if t == "leaderboardRow":
            medals = {1: "#FFC83D", 2: "#C9D2DE", 3: "#D98B4A"}
            rank = e.get("rank")
            medal = f'style="background:{medals[rank]}"' if rank in medals else ""
            rank_html = f'<span class="medal ink" {medal}>{esc(rank)}</span>' if rank is not None else ""
            cls = "panel lbrow" + (" me" if e.get("highlight") else "")
            return (f'<div class="{cls}">{rank_html}<span class="avatar"></span><div class="lr ink name">{esc(e["title"])}</div>'
                    f'<span class="ink val">{esc(abbrev(e.get("value", 0)))}</span></div>')
        if t == "loadingScreen":
            sw = self.swatch(e.get("palette", "green"))
            tips = e.get("tips") or []
            tip = f'<div class="tip">{esc(tips[0])}</div>' if tips else ""
            title = f'<div class="t title">{esc(e["title"])}</div>' if e.get("title") else ""
            return (f'<div class="loading">{self.art(e, 64)}{title}<div class="track"><div class="fill" style="width:{pct(e.get("progress", 0), 1)}%;'
                    f'background:{self.grad(sw)}"></div></div>{tip}</div>')
        if t == "selectionCard":
            sw = self.swatch(e.get("palette", "blue"))
            tick = f'<span class="corner">{icon("success-color", 24)}</span>' if e.get("selected") else ""
            desc = f'<div class="t sub">{esc(e["description"])}</div>' if e.get("description") else ""
            cls = "card select" + (" selected" if e.get("selected") else "")
            return (f'<div class="{cls}" style="background:{self.grad(sw)}">{tick}<div class="art">{self.art(e, 72)}</div>'
                    f'<div class="t name">{esc(e["title"])}</div>{desc}</div>')
        if t == "hotbarSlot":
            bg = f'style="background:{self.grad(self.swatch(e["palette"]))}"' if e.get("palette") else ""
            key = f'<span class="key">{esc(e["keybind"])}</span>' if e.get("keybind") else ""
            return f'<div class="slot hotbar" {bg}>{self.art(e, 40)}{key}</div>'
        if t == "statChip":
            bg = f'style="background:{self.grad(self.swatch(e["palette"]))}"' if e.get("palette") else ""
            value = e.get("value", 0)
            text = f'{e.get("prefix", "")} {abbrev(value)}{e.get("suffix", "")}'.strip()
            return f'<span class="chip stat" {bg}>{self.art(e, 20)}{esc(text)}</span>'
        return None

    def el_basic(self, e: dict) -> str:
        t = e["type"]
        if t == "banner":
            sw = self.swatch(e["palette"])
            timer = f'<span class="timer">{icon("stopwatch-color", 18)} {clock(e["timer"])}</span>' if e.get("timer") else ""
            return (f'<div class="card banner pattern" style="background:{self.grad(sw)}">{self.badge(e.get("badge"))}'
                    f'<div class="art">{icon(e.get("icon"), 96)}</div><div class="txt"><div class="t title">{esc(e["title"])}</div>'
                    f'<div class="t sub">{esc(e.get("subtitle", ""))}</div>{timer}{self.price_button(e["price"])}</div></div>')
        if t == "product":
            sw = self.swatch(e["palette"])
            rar = e.get("rarity")
            ring = f"box-shadow:0 0 0 3px {self.s['rarity'][rar]['color']} inset;" if rar in self.s["rarity"] else ""
            sub = f'<div class="t sub">{esc(e["subtitle"])}</div>' if e.get("subtitle") else ""
            # Owned items keep their art visible; the price pill becomes a grey OWNED pill with a check.
            if e.get("owned"):
                pill = (f'<div class="pricerow"><span class="btn price" style="background:{self.grad(self.swatch("gray"))}">'
                        f'{icon("success-color", 18)} OWNED</span></div>')
            else:
                pill = self.price_button(e["price"], bool(e.get("gift")))
            return (f'<div class="card product pattern" style="background:{self.grad(sw)};{ring}">{self.badge(e.get("badge"))}'
                    f'<div class="art">{icon(e.get("icon"), 72)}</div><div class="t name">{esc(e["title"])}</div>{sub}{pill}</div>')
        if t == "grid":
            cols = e.get("columns") or {}
            cols = cols if isinstance(cols, int) else cols.get("desktop", 3)
            return f'<div class="grid" style="grid-template-columns:repeat({cols},minmax(0,1fr))">' + "".join(self.el(c) for c in e["items"]) + "</div>"
        if t == "row":
            return '<div class="row">' + "".join(self.el(c) for c in e["items"]) + "</div>"
        if t == "heading":
            return f'<div class="t heading">{esc(e["text"])}</div>'
        if t == "divider":
            return '<div class="divider"></div>'
        if t == "text":
            return f'<div class="plain">{esc(e["text"])}</div>'
        if t == "button":
            bdef = self.s["buttons"].get(e.get("kind", "primary"), self.s["buttons"]["primary"])
            sw = self.swatch(e.get("palette") or bdef.get("palette"))
            inner = (icon(e.get("icon"), 26) if e.get("icon") else "") + (f'<span class="t">{esc(e["text"])}</span>' if e.get("text") else "")
            return f'<span class="btn big" style="background:{self.grad(sw)}">{inner}</span>'
        if t == "iconButton":
            sw = self.swatch(e.get("palette"))
            label = f'<div class="t lbl">{esc(e["label"])}</div>' if e.get("label") else ""
            shape = "circle" if e.get("shape") == "circle" else ""
            return f'<div class="iconbtn {shape}">{self.badge(e.get("badge"))}<div class="ibox" style="background:{self.grad(sw)}">{icon(e["icon"], 46)}</div>{label}</div>'
        if t == "currency":
            sw = self.swatch(e.get("palette", "green"))
            plus = '<span class="plus">+</span>' if e.get("plus") else ""
            return f'<div class="currency" style="background:{self.grad(sw)}">{icon(e["icon"], 34)}<span class="t">{esc(e.get("value", 0))}</span>{plus}</div>'
        if t in ("level", "progress"):
            value, mx = e.get("value", 0), e.get("max", 100)
            pct = 0 if not mx else max(0, min(100, value * 100 / mx))
            sw = self.swatch(e.get("palette", "blue" if t == "level" else "green"))
            lvl = f'<span class="t lvl">Lvl. {esc(e.get("level", 0))}</span>' if t == "level" else ""
            return (f'<div class="bar">{lvl}<div class="track"><div class="fill" style="width:{pct}%;background:{self.grad(sw)}"></div></div>'
                    f'<span class="t small">{esc(value)}/{esc(mx)}</span></div>')
        if t == "timer":
            sec = int(e["seconds"])
            return f'<div class="timerbig">{icon(e.get("icon", "stopwatch-color"), 40)}<span class="t">{clock(sec)}</span></div>'
        if t == "toggle":
            on = "on" if e.get("value") else ""
            return f'<div class="setting"><span class="ink lbl2">{esc(e["label"])}</span><span class="toggle {on}"><i></i></span></div>'
        if t == "slider":
            mn, mx, v = e.get("min", 0), e.get("max", 100), e.get("value", 50)
            pct = (v - mn) * 100 / ((mx - mn) or 1)
            return f'<div class="setting"><span class="ink lbl2">{esc(e["label"])}</span><span class="slider"><span style="width:{pct}%"></span><i style="left:{pct}%"></i></span></div>'
        if t == "dropdown":
            return f'<div class="setting"><span class="ink lbl2">{esc(e["label"])}</span><span class="dropdown">{esc(e.get("value", e["options"][0]))} ▾</span></div>'
        if t == "dayCard":
            state = e.get("state", "locked")
            sw = self.swatch(e.get("palette") or ("gold" if e.get("premium") else "blue"))
            mark = icon("success-color", 34) if state == "claimed" else (icon("lock-color", 30) if state == "locked" else "")
            return (f'<div class="card day {state}" style="background:{self.grad(sw)}"><div class="t name">DAY {esc(e["day"])}</div>'
                    f'<div class="art">{icon(e.get("icon"), 58)}</div><div class="t sub">{esc(e["reward"])}</div><div class="mark">{mark}</div></div>')
        if t == "listRow":
            sw = self.swatch(e.get("palette", "blue"))
            rank = f'<span class="rank ink">#{esc(e["rank"])}</span>' if e.get("rank") is not None else ""
            prog = ""
            if isinstance(e.get("progress"), dict):
                p = e["progress"]
                pct = max(0, min(100, p.get("value", 0) * 100 / (p.get("max", 1) or 1)))
                prog = f'<div class="track slim"><div class="fill" style="width:{pct}%;background:{self.grad(self.swatch("green"))}"></div></div>'
            btn = self.el({"type": "button", **e["button"]}) if isinstance(e.get("button"), dict) else ""
            val = f'<span class="ink val">{esc(e["value"])}</span>' if e.get("value") is not None else ""
            return (f'<div class="listrow" style="border-color:{sw["bottom"]}">{rank}{icon(e.get("icon"), 44)}<div class="lr"><div class="ink name">{esc(e["title"])}</div>'
                    f'<div class="plain small">{esc(e.get("subtitle", ""))}</div>{prog}</div>{val}{btn}</div>')
        return f'<div class="missing">{esc(t)}</div>'

    def popup(self, p: dict, body: list) -> str:
        sw = self.swatch(p.get("palette", "gold"))
        rays = '<div class="rays"></div>' if p.get("rays") else ""
        msg = f'<div class="plain center">{esc(p["message"])}</div>' if p.get("message") else ""
        amount = f'<div class="t amount">{esc(p["amount"])}</div>' if p.get("amount") else ""
        extra = "".join(self.el(e) for e in body)
        if p.get("variant") == "confirm":
            cancel = self.el({"type": "button", "text": p.get("cancelText", "CANCEL"), "kind": "neutral"})
            if p.get("price"):
                confirm = self.price_button(p["price"])
            else:
                confirm = self.el({"type": "button", "text": p.get("confirmText", "OK"), "kind": "buy"})
            actions = f'<div class="row nowrap">{cancel}{confirm}</div>'
        else:
            actions = self.el({"type": "button", "text": "AWESOME!", "kind": "buy"})
        return (f'<div class="stage dim">{rays}<div class="popup" style="background:{self.grad(self.s["surfaces"]["window"])}">'
                f'<div class="header" style="background:{self.grad(sw)}"><span class="t wtitle">{esc(p.get("title", ""))}</span></div>'
                f'<div class="content center">{icon(p.get("icon"), 120)}{amount}{msg}{extra}{actions}</div></div></div>')

    def screen(self, spec: dict) -> str:
        if spec["kind"] == "hud":
            parts = []
            for rail, els in spec["rails"].items():
                parts.append(f'<div class="rail {rail}">' + "".join(self.el(e) for e in els) + "</div>")
            return '<div class="stage hud">' + "".join(parts) + "</div>"
        if spec["kind"] == "popup" and isinstance(spec.get("popup"), dict):
            return self.popup(spec["popup"], spec.get("body") or [])
        w = spec.get("window") or {"title": spec["id"]}
        hp = self.swatch(w.get("headerPalette", "red"))
        body = "".join(self.el(e) for e in spec["body"])
        cls = "popup" if spec["kind"] == "popup" else "window " + w.get("sizeClass", "md")
        surface = self.s["surfaces"]["window"]
        close = f'<span class="close" style="background:{self.grad(self.swatch("red"))}">{icon("close", 22)}</span>' if w.get("closable", True) else ""
        return (f'<div class="stage"><div class="{cls}" style="background:{self.grad(surface)}"><div class="header" style="background:{self.grad(hp)}">'
                f'<span class="t wtitle">{esc(w["title"])}</span>{close}</div><div class="content">{body}</div></div></div>')


def css(style: dict) -> str:
    o = style["outline"]["color"]
    ot = style["outline"]["regular"]
    pat = style["pattern"]
    win, inset, dark = (style["surfaces"][k] for k in ("window", "inset", "dark"))
    g = lambda sw: f"linear-gradient(180deg,{sw['top']},{sw['bottom']})"  # noqa: E731
    return f"""
:root{{--o:{o};--ot:{ot}px;--wt:{win['text']};--it:{inset['text']};--ib:{g(inset)};--dt:{dark['text']};--db:{g(dark)}}}
*{{box-sizing:border-box}} body{{margin:0;background:#8db4d9}} body,.stage{{font-family:UrkTitle,'Fredoka One',system-ui,sans-serif;color:var(--wt)}}
.note{{font:12px system-ui;color:#22324a;background:#fff9;padding:6px 10px;border-radius:6px;position:fixed;bottom:8px;left:8px;max-width:640px}}
.stage{{width:1000px;height:563px;position:relative;margin:16px auto;background:linear-gradient(#6fb6ff,#cfe8ff 45%,#8a8f99 46%,#6e737c);border-radius:12px;overflow:hidden;display:flex;align-items:center;justify-content:center}}
.window{{width:360px;max-height:520px;border:{ot+1}px solid var(--o);border-radius:22px;overflow:hidden;box-shadow:0 6px 0 #0004}}
.window.lg{{width:400px}} .window.md{{width:360px}} .window.full{{width:900px}}
.popup{{width:300px;border:{ot+1}px solid var(--o);border-radius:22px;overflow:hidden;box-shadow:0 6px 0 #0004}}
.header{{height:50px;display:flex;align-items:center;justify-content:space-between;padding:0 12px;border-bottom:{ot}px solid var(--o)}}
.t{{color:#fff;-webkit-text-stroke:{style['textStroke']['thickness']}px {style['textStroke']['color']};paint-order:stroke fill;letter-spacing:.3px}}
.wtitle{{font-size:28px}} .close{{width:34px;height:34px;border:{ot}px solid var(--o);border-radius:9px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:20px;-webkit-text-stroke:1px var(--o)}}
.content{{padding:10px;overflow:auto;max-height:460px;display:flex;flex-direction:column;gap:8px}} .content>*{{flex-shrink:0}}
.card{{position:relative;border:{ot}px solid var(--o);border-radius:14px;padding:8px;box-shadow:0 4px 0 #0003;overflow:visible}}
.pattern{{background-blend-mode:normal}}
.pattern::before{{content:"";position:absolute;inset:0;border-radius:11px;opacity:{1-pat['transparency']:.2f};background-image:conic-gradient(#fff 25%,transparent 0 50%,#fff 0 75%,transparent 0);background-size:{pat['cell']}px {pat['cell']}px;pointer-events:none}}
.card::after{{content:"";position:absolute;left:6px;right:6px;top:4px;height:40%;border-radius:10px;background:linear-gradient(#fff6,#fff0);pointer-events:none}}
.banner{{display:flex;align-items:center;gap:8px;min-height:96px}} .banner .txt{{flex:1;text-align:center}}
.title{{font-size:22px}} .sub{{font-size:11px;-webkit-text-stroke:1.5px {style['textStroke']['color']}}} .name{{font-size:13px;text-align:center}}
.product{{display:flex;flex-direction:column;align-items:center;gap:2px;min-height:118px}}
.grid{{display:grid;gap:8px}} .row{{display:flex;gap:8px;flex-wrap:wrap;justify-content:center}}
.heading{{font-size:20px;text-align:center}} .divider{{height:5px;background:var(--o);border-radius:3px;margin:2px 6px}}
.plain{{font:600 13px UrkBody,system-ui;color:var(--wt)}} .small{{font-size:11px}}
.ink{{color:var(--it);letter-spacing:.3px}}
.hud .rail>.plain,.hud .rail>.row>.plain{{background:var(--db);color:var(--dt);border-radius:8px;padding:2px 8px}}
.setting .plain,.listrow .plain,.panel .plain{{color:var(--it)}}
.pricerow{{display:flex;gap:4px;justify-content:center;margin-top:4px;width:100%}}
.btn{{display:inline-flex;align-items:center;justify-content:center;gap:4px;border:{ot}px solid var(--o);border-radius:10px;padding:2px 10px;color:#fff;font-size:14px;-webkit-text-stroke:1.5px var(--o);paint-order:stroke fill;box-shadow:0 3px 0 #0004;min-height:28px}}
.btn.price{{flex:1;max-width:120px;min-width:0;white-space:nowrap;overflow:hidden}} .t.name,.t.sub{{overflow-wrap:anywhere}} .btn.gift{{padding:2px 4px}} .btn.big{{font-size:18px;padding:6px 16px}}
.ic{{display:block;filter:drop-shadow(0 2px 0 #0002)}} .btn .ic{{display:inline}}
.art{{display:flex;justify-content:center}}
.badge{{position:absolute;top:-10px;right:-8px;z-index:2;border:{ot}px solid var(--o);border-radius:999px;padding:1px 8px;color:#fff;font-size:12px;-webkit-text-stroke:1px var(--o);paint-order:stroke fill;transform:rotate(8deg)}}
.badge.circle{{width:28px;height:28px;padding:0;display:flex;align-items:center;justify-content:center;font-size:18px;transform:none}}
.owned{{position:absolute;inset:0;background:#0006;border-radius:11px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:18px}}
.timer{{font-size:12px;display:inline-flex;gap:4px;align-items:center;color:#fff}}
.bar{{display:flex;align-items:center;gap:8px;width:420px}} .lvl{{font-size:16px}}
.track{{flex:1;height:18px;border:{ot}px solid var(--o);border-radius:9px;background:#2a2f4a;overflow:hidden}} .track.slim{{height:12px;margin-top:3px}}
.fill{{height:100%;border-radius:6px}}
.currency{{display:inline-flex;align-items:center;gap:6px;border:{ot}px solid var(--o);border-radius:14px;padding:2px 14px 2px 4px;font-size:24px;box-shadow:0 4px 0 #0004}}
.plus{{background:#2FC33A;border:{ot}px solid var(--o);border-radius:8px;width:24px;height:24px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:18px}}
.iconbtn{{display:flex;flex-direction:column;align-items:center;position:relative;width:70px}}
.ibox{{width:62px;height:62px;border:{ot}px solid var(--o);border-radius:14px;display:flex;align-items:center;justify-content:center;box-shadow:0 4px 0 #0004}}
.iconbtn.circle .ibox{{border-radius:50%}} .lbl{{font-size:11px;margin-top:-6px}}
.timerbig{{display:flex;align-items:center;gap:4px;font-size:22px}}
.setting{{display:flex;align-items:center;justify-content:space-between;background:var(--ib);color:var(--it);border:{ot}px solid var(--o);border-radius:12px;padding:8px 10px}}
.lbl2{{font-size:16px}} .toggle{{width:52px;height:28px;border-radius:14px;border:{ot}px solid var(--o);background:#9AA4B8;position:relative}}
.toggle i{{position:absolute;top:2px;left:2px;width:18px;height:18px;border-radius:50%;background:#fff;border:2px solid var(--o)}}
.toggle.on{{background:#2FC33A}} .toggle.on i{{left:26px}}
.slider{{width:150px;height:14px;border:{ot}px solid var(--o);border-radius:7px;background:#2a2f4a;position:relative}}
.slider span{{display:block;height:100%;background:#2C7BEA;border-radius:5px}} .slider i{{position:absolute;top:-7px;width:22px;height:22px;margin-left:-11px;border-radius:50%;background:#fff;border:{ot}px solid var(--o)}}
.dropdown{{background:var(--db);color:var(--dt);border:{ot}px solid var(--o);border-radius:8px;padding:2px 10px;font:600 14px system-ui}}
.day{{display:flex;flex-direction:column;align-items:center;min-height:118px}} .day.claimed{{filter:saturate(.5) brightness(.9)}} .mark{{position:absolute;bottom:-8px;right:-8px}}
.day.today{{outline:4px solid #FFE45C;outline-offset:1px}}
.listrow{{display:flex;align-items:center;gap:8px;background:var(--ib);color:var(--it);border:{ot}px solid var(--o);border-left-width:8px;border-radius:12px;padding:6px 8px}}
.lr{{flex:1;min-width:0}} .ink.name{{text-align:left;font-size:14px}} .rank{{font-size:20px;width:36px}} .val{{font-size:16px}}
.motion{{display:contents}}
.packic,.imgph{{display:inline-flex;align-items:center;justify-content:center;text-align:center;overflow:hidden;border:2px dashed var(--o);border-radius:8px;background:var(--db);color:var(--dt);font-family:system-ui;line-height:1}}
.premium{{position:relative;overflow:hidden;min-height:44px;box-shadow:0 3px 0 #0004,0 0 10px 1px #ffe45c88}}
.premium.shine::after{{content:"";position:absolute;top:0;bottom:0;left:18%;width:22%;background:linear-gradient(100deg,#fff0,#fff9,#fff0);transform:skewX(-20deg)}}
.tabs{{display:flex;gap:4px;background:var(--ib);border:{ot}px solid var(--o);border-radius:12px;padding:4px}}
.tab{{flex:1;display:flex;align-items:center;justify-content:center;gap:4px;min-height:32px;border-radius:8px;font-size:14px}} .tab.on{{border:{ot}px solid var(--o)}}
.modalbox{{border:{ot}px dashed var(--o);border-radius:14px;overflow:hidden;background:{g(win)}}} .header.small{{height:34px;font-size:16px;justify-content:center}}
.tooltip{{align-self:center;background:var(--db);color:var(--dt);border:{ot}px solid var(--o);border-radius:8px;padding:3px 10px;font:600 12px UrkBody,system-ui;max-width:240px}}
.bar.xp{{width:100%}} .lvlbadge{{width:30px;height:30px;border:{ot}px solid var(--o);border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:15px;flex-shrink:0}}
.slot{{position:relative;width:64px;height:64px;border:{ot+1}px solid var(--o);border-radius:12px;background:var(--ib);display:flex;align-items:center;justify-content:center;box-shadow:0 3px 0 #0003}}
.slot.hotbar{{background:var(--db)}} .slot.locked{{filter:saturate(.3) brightness(.8)}} .selected{{outline:3px solid #fff;outline-offset:2px;transform:translateY(-2px)}}
.count{{position:absolute;right:3px;bottom:0;font-size:13px}} .corner{{position:absolute;top:-6px;right:-6px;z-index:2}}
.key{{position:absolute;left:3px;top:2px;background:var(--db);color:var(--dt);border:1px solid var(--o);border-radius:4px;padding:0 4px;font:700 10px system-ui}}
.pet,.select{{display:flex;flex-direction:column;align-items:center;gap:3px;min-height:130px}}
.rarity{{display:inline-block;border:{ot}px solid var(--o);border-radius:999px;padding:0 8px;font-size:11px;align-self:center}}
.chips{{display:flex;gap:4px;flex-wrap:wrap;justify-content:center;margin-top:2px}} .lr .chips{{justify-content:flex-start}}
.chip{{display:inline-flex;align-items:center;gap:3px;background:var(--db);color:var(--dt);border:2px solid var(--o);border-radius:999px;padding:1px 8px;font-size:12px;white-space:nowrap}}
.chip.stat{{font-size:14px;padding:3px 10px}}
.panel{{position:relative;display:flex;align-items:center;gap:8px;background:var(--ib);color:var(--it);border:{ot}px solid var(--o);border-radius:12px;padding:6px 8px}}
.panel.dim{{filter:saturate(.25);opacity:.8}} .panel.quest.claimable{{outline:3px solid #FFE45C}} .panel.lbrow.me{{outline:3px solid #FFE45C;outline-offset:-1px}}
.rewardpanel{{flex-direction:column}} .tile{{width:56px;height:56px;border:3px solid var(--o);border-radius:10px;background:var(--db);display:flex;flex-direction:column;align-items:center;justify-content:center}}
.round{{width:44px;height:44px;border:{ot}px solid var(--o);border-radius:50%;display:flex;align-items:center;justify-content:center;flex-shrink:0}}
.stars{{font-size:18px;white-space:nowrap}} .star{{opacity:.3}} .star.on{{opacity:1;color:#FFC83D;-webkit-text-stroke:1px var(--o)}}
.toast{{max-width:320px;box-shadow:0 4px 0 #0003}}
.medal{{width:28px;height:28px;border-radius:50%;display:flex;align-items:center;justify-content:center;border:2px solid var(--o);font-size:14px;flex-shrink:0}}
.medal[style]{{color:#1B1530}} .avatar{{width:32px;height:32px;border-radius:50%;background:var(--db);border:2px solid var(--o);flex-shrink:0}}
.loading{{display:flex;flex-direction:column;align-items:center;gap:6px;background:var(--db);color:var(--dt);border:{ot}px solid var(--o);border-radius:12px;padding:12px}}
.loading .track{{flex:none;width:80%}} .tip{{font:600 12px UrkBody,system-ui;color:var(--dt)}}
.hud .rail{{position:absolute;display:flex;gap:6px}}
.rail.left{{left:12px;top:90px;display:grid;grid-template-columns:repeat(3,70px);gap:2px 0}}
.rail.right{{right:12px;top:90px;flex-direction:column}} .rail.top,.rail.topRight{{top:10px}} .rail.top{{left:50%;transform:translateX(-50%)}}
.rail.topRight{{right:12px}} .rail.topLeft{{left:12px;top:10px}}
.rail.bottom{{bottom:10px;left:50%;transform:translateX(-50%);flex-direction:column;align-items:center}}
.rail.bottomLeft{{left:12px;bottom:10px}} .rail.bottomRight{{right:12px;bottom:10px}} .rail.center{{left:50%;top:50%;transform:translate(-50%,-50%)}}
.missing{{color:red;font-weight:bold}}
.stage.dim::after{{content:"";position:absolute;inset:0;background:#0007;z-index:0}} .stage.dim>*{{z-index:1}}
.rays{{position:absolute;width:900px;height:900px;border-radius:50%;z-index:1;background:repeating-conic-gradient(#fff5 0 10deg,#fff0 10deg 20deg);
  -webkit-mask:radial-gradient(circle,#000 20%,transparent 65%);mask:radial-gradient(circle,#000 20%,transparent 65%)}}
.popup{{position:relative;z-index:2}} .popup .content,.window .content{{color:var(--wt)}} .content.center{{align-items:center;text-align:center}} .center{{text-align:center}}
.amount{{font-size:24px}} .row.nowrap{{flex-wrap:nowrap}} .row.nowrap .pricerow{{width:auto;margin:0}}
"""


FONT_DIR = ROOT / "assets" / "fonts"

# ?capture=<name>: render the stage to PNG via SVG foreignObject and POST it to capture_server.py.
CAPTURE_JS = """<script>
(async () => {
  const name = new URLSearchParams(location.search).get("capture");
  if (!name) return;
  await document.fonts.ready;
  const stage = document.querySelector(".stage");
  const w = stage.offsetWidth, h = stage.offsetHeight;
  const clone = stage.cloneNode(true);
  clone.style.margin = "0";
  const css = [...document.querySelectorAll("style")].map(s => s.textContent).join("\\n");
  const xhtml = new XMLSerializer().serializeToString(clone);
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><foreignObject width="100%" height="100%">` +
    `<div xmlns="http://www.w3.org/1999/xhtml"><style>${css}</style>${xhtml}</div></foreignObject></svg>`;
  const src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
  const canvas = document.createElement("canvas");
  canvas.width = w * 2; canvas.height = h * 2;
  const ctx = canvas.getContext("2d"); ctx.scale(2, 2);
  // An SVG image may paint before its embedded fonts decode: draw once to warm them, wait, draw again.
  for (const delay of [0, 600]) {
    await new Promise(r => setTimeout(r, delay));
    const img = new Image(); img.src = src; await img.decode();
    ctx.clearRect(0, 0, w, h); ctx.drawImage(img, 0, 0);
  }
  const blob = await new Promise(r => canvas.toBlob(r, "image/png"));
  const res = await fetch(`/save/${name}.png`, { method: "POST", body: blob });
  document.title = "captured: " + (await res.text());
})();
</script>"""


def font_faces() -> str:
    """Embed the kit's OFL fonts (assets/fonts) so previews look right offline and in captures.
    Lilita One stands in for Roblox's FredokaOne/LuckiestGuy titles; Fredoka for body text."""
    faces = []
    for family, file in (("UrkTitle", "LilitaOne-Regular.ttf"), ("UrkBody", "Fredoka.ttf")):
        path = FONT_DIR / file
        if path.exists():
            data = base64.b64encode(path.read_bytes()).decode()
            faces.append(f"@font-face{{font-family:{family};src:url(data:font/ttf;base64,{data}) format('truetype')}}")
    return "".join(faces)


def page(title: str, body: str, style: dict) -> str:
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{esc(title)}</title>'
            f'<style>{font_faces()}{css(style)}</style></head><body>{body}'
            f'{CAPTURE_JS}<div class="note">Spec preview: an HTML approximation built from the same tokens and icons as the Roblox builder. '
            f'Real rendering: library/examples/playground in Studio.</div></body></html>')


def render_spec(spec: dict) -> str:
    errors = validate(spec)
    if errors:
        raise SystemExit("spec is invalid:\n" + "\n".join(f"  {e['path']}: {e['message']}" for e in errors))
    style = resolved_style(spec.get("style", "cartoon"))
    return page(spec["id"], Renderer(style).screen(spec), style)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("spec", nargs="?", type=Path)
    ap.add_argument("--all", action="store_true", help="render every spec in library/src/UI/Spec/Screens")
    ap.add_argument("-o", "--out", type=Path, required=True)
    a = ap.parse_args(argv)
    if a.all:
        a.out.mkdir(parents=True, exist_ok=True)
        links = []
        for f in sorted(SCREENS.glob("*.json")):
            (a.out / f"{f.stem}.html").write_text(render_spec(json.loads(f.read_text())), encoding="utf-8")
            links.append(f'<li><a href="{f.stem}.html">{f.stem}</a></li>')
        (a.out / "index.html").write_text(f"<!doctype html><meta charset=utf-8><title>UrkUI screens</title><ul>{''.join(links)}</ul>")
        print(f"{len(links)} screens -> {a.out}")
        return 0
    if not a.spec:
        ap.error("give a spec file or --all")
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(render_spec(json.loads(a.spec.read_text())), encoding="utf-8")
    print(f"preview -> {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
