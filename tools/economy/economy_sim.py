#!/usr/bin/env python3
"""Simulate a simulator-game economy before launch: time to each upgrade, world, egg and rebirth.

  python3 tools/economy/economy_sim.py tools/economy/examples/pet-sim.json
  python3 tools/economy/economy_sim.py my-economy.json --hours 6 --json report.json --players 200

A seeded, greedy "player" earns income every second and buys whatever gives the most income per coin:
upgrade levels, world unlocks, eggs (while it has free pet slots or a better pet is likely) and
rebirths. The cost curves are the same formulas as RebirthLogic.curveCost and UpgradesLogic, so the
numbers match the game code. Several players with different click rates and luck give a spread.

Warnings (exit code 1 with --strict):
- wall: a stretch longer than `limits.wallMinutes` (default 20) with nothing worth buying
- too fast / too slow: a milestone outside its `targets` window
- overflow: a balance above 1e15 (where Luau numbers stop being exact integers)
- dead content: something the player never reaches in the simulated time

Privacy: this only reads your config. Nothing about players is collected or sent anywhere.
Standard library only.
"""
from __future__ import annotations

import argparse
import json
import math
import random
import statistics
import sys
from dataclasses import dataclass, field
from pathlib import Path

MAX_EXACT = 1e15


def curve_cost(curve: dict, n: int) -> float:
    """Cost of level n (1-based). Same as RebirthLogic.curveCost in Luau."""
    kind = curve.get("kind")
    if kind == "linear":
        return math.floor(curve.get("base", 0) + curve.get("step", 0) * (n - 1))
    if kind == "exponential":
        return math.floor(curve.get("base", 0) * curve.get("growth", 1.5) ** (n - 1))
    values = curve.get("values") or []
    if not values:
        return 0
    return values[min(n, len(values)) - 1]


def validate(cfg: dict) -> list[str]:
    errors = []
    if not isinstance(cfg.get("income"), dict) or cfg["income"].get("base", 0) <= 0:
        errors.append("income.base must be > 0")
    for u in cfg.get("upgrades", []):
        if u.get("maxLevel", 0) < 1:
            errors.append(f"upgrade {u.get('name')}: maxLevel >= 1")
        if u.get("cost", {}).get("kind") not in ("linear", "exponential", "table"):
            errors.append(f"upgrade {u.get('name')}: cost.kind must be linear, exponential or table")
    r = cfg.get("rebirth")
    if r and r.get("cost", {}).get("kind") not in ("linear", "exponential", "table"):
        errors.append("rebirth.cost.kind must be linear, exponential or table")
    for egg in cfg.get("eggs", []):
        if not egg.get("entries"):
            errors.append(f"egg {egg.get('name')}: entries required")
    return errors


@dataclass
class Player:
    clicks: float
    rng: random.Random
    balance: float = 0.0
    levels: dict = field(default_factory=dict)
    worlds: int = 1
    rebirths: int = 0
    pets: list = field(default_factory=list)
    events: list = field(default_factory=list)
    idle_since: float = 0.0
    longest_idle: float = 0.0
    peak_balance: float = 0.0


def income_per_second(cfg: dict, p: Player) -> float:
    inc = cfg["income"]
    base = inc["base"] * (p.clicks if inc.get("per", "click") == "click" else 1)
    bonus = 0.0
    mult = 1.0
    for u in cfg.get("upgrades", []):
        level = p.levels.get(u["name"], 0)
        eff = u.get("effect", {})
        if eff.get("stat", "income") != "income" or level == 0:
            continue
        if eff.get("mode", "add") == "multiply":
            mult *= (1 + eff.get("perLevel", 0)) ** level
        else:
            bonus += eff.get("perLevel", 0) * level
    rebirth = cfg.get("rebirth") or {}
    rmult = 1 + p.rebirths * rebirth.get("multiplierPerRebirth", 0.5)
    worlds = cfg.get("worlds", [])
    wmult = max([w.get("multiplier", 1) for w in worlds[: p.worlds]] or [1])
    slots = cfg.get("equipSlots", 3)
    pmult = 1 + sum(sorted(p.pets, reverse=True)[:slots])
    return base * (1 + bonus) * mult * rmult * wmult * pmult


def egg_expected(egg: dict) -> float:
    total = sum(e["weight"] for e in egg["entries"])
    return sum(e["weight"] / total * e.get("multiplier", 1) for e in egg["entries"])


def roll(egg: dict, rng: random.Random) -> float:
    total = sum(e["weight"] for e in egg["entries"])
    target = rng.random() * total
    run = 0.0
    for e in egg["entries"]:
        run += e["weight"]
        if target < run:
            return e.get("multiplier", 1)
    return egg["entries"][-1].get("multiplier", 1)


def options(cfg: dict, p: Player):
    """(name, cost, gain-in-income-per-second, apply) for everything buyable now."""
    now = income_per_second(cfg, p)
    out = []
    for u in cfg.get("upgrades", []):
        level = p.levels.get(u["name"], 0)
        if level >= u["maxLevel"] or any(p.levels.get(k, 0) < v for k, v in u.get("requires", {}).items()):
            continue
        cost = curve_cost(u["cost"], level + 1)
        p.levels[u["name"]] = level + 1
        gain = income_per_second(cfg, p) - now
        p.levels[u["name"]] = level

        def apply(u=u, level=level):
            p.levels[u["name"]] = level + 1
            return f"{u['name']} {level + 1}"
        out.append((f"upgrade:{u['name']}", cost, gain, apply))
    worlds = cfg.get("worlds", [])
    if p.worlds < len(worlds):
        w = worlds[p.worlds]
        if p.rebirths >= w.get("rebirths", 0):
            cost = w.get("cost", 0)
            p.worlds += 1
            gain = income_per_second(cfg, p) - now
            p.worlds -= 1

            def apply_world(w=w):
                p.worlds += 1
                return f"world {w['name']}"
            out.append((f"world:{w['name']}", cost, max(gain, now * 0.05), apply_world))
    slots = cfg.get("equipSlots", 3)
    for i, egg in enumerate(cfg.get("eggs", [])):
        if i >= p.worlds:
            break
        best = sorted(p.pets, reverse=True)[:slots]
        expect = egg_expected(egg)
        weakest = best[-1] if len(best) >= slots else 0
        if expect <= weakest and len(p.pets) >= slots:
            continue
        gain = (expect - weakest) * income_per_second(cfg, p) / max(1 + sum(best), 1)

        def apply_egg(egg=egg):
            p.pets.append(roll(egg, p.rng))
            return f"egg {egg['name']}"
        out.append((f"egg:{egg['name']}", egg.get("cost", 0), gain, apply_egg))
    return out


def rebirth_option(cfg: dict, p: Player):
    r = cfg.get("rebirth")
    if not r or p.rebirths >= r.get("maxRebirths", 1e6):
        return None
    return curve_cost(r["cost"], p.rebirths + 1)


def simulate(cfg: dict, seconds: int, clicks: float, seed: int) -> Player:
    p = Player(clicks=clicks, rng=random.Random(seed))
    reb = cfg.get("rebirth") or {}
    for t in range(1, seconds + 1):
        p.balance += income_per_second(cfg, p)
        p.peak_balance = max(p.peak_balance, p.balance)
        bought = False
        rcost = rebirth_option(cfg, p)
        # Rebirth when it pays for itself: the next rebirth multiplier outweighs what the reset loses.
        if rcost is not None and p.balance >= rcost and p.balance >= rcost * reb.get("waitFactor", 1.0):
            p.balance = 0
            p.rebirths += 1
            if "upgrades" in reb.get("reset", ["upgrades"]):
                keep = {u["name"] for u in cfg.get("upgrades", []) if u.get("resetOnRebirth") is False}
                p.levels = {k: v for k, v in p.levels.items() if k in keep}
            p.events.append((t, f"rebirth {p.rebirths}"))
            bought = True
        for _ in range(20):
            opts = [o for o in options(cfg, p) if o[1] <= p.balance and o[2] > 0]
            if not opts:
                break
            name, cost, gain, apply = max(opts, key=lambda o: o[2] / max(o[1], 1))
            p.balance -= cost
            p.events.append((t, apply()))
            bought = True
        if bought:
            p.longest_idle = max(p.longest_idle, t - p.idle_since)
            p.idle_since = t
    p.longest_idle = max(p.longest_idle, seconds - p.idle_since)
    return p


def first(events, prefix):
    for t, name in events:
        if name.startswith(prefix):
            return t
    return None


def report(cfg: dict, hours: float, players: int, seed: int) -> dict:
    seconds = int(hours * 3600)
    inc = cfg["income"]
    cps = inc.get("clicksPerSecond", [2, 6])
    if not isinstance(cps, list):
        cps = [cps, cps]
    rng = random.Random(seed)
    runs = [simulate(cfg, seconds, rng.uniform(cps[0], cps[1]), seed + i) for i in range(players)]
    milestones = {}
    names = [f"world {w['name']}" for w in cfg.get("worlds", [])[1:]] + ["rebirth 1", "rebirth 5"]
    names += [f"{u['name']} {u['maxLevel']}" for u in cfg.get("upgrades", [])]
    names += [f"egg {e['name']}" for e in cfg.get("eggs", [])]
    for name in names:
        times = [first(r.events, name) for r in runs]
        reached = [x for x in times if x is not None]
        milestones[name] = {
            "reached": f"{len(reached)}/{len(runs)}",
            "medianMinutes": round(statistics.median(reached) / 60, 1) if reached else None,
        }
    warnings = []
    limits = cfg.get("limits", {})
    wall = limits.get("wallMinutes", 20) * 60
    walls = [r.longest_idle for r in runs]
    if statistics.median(walls) > wall:
        warnings.append(f"wall: median longest stretch with nothing to buy is {statistics.median(walls) / 60:.0f} min "
                        f"(limit {wall / 60:.0f})")
    for name, (lo, hi) in cfg.get("targets", {}).items():
        m = milestones.get(name) or {}
        med = m.get("medianMinutes")
        if med is None:
            warnings.append(f"too slow: {name} not reached by the median player in {hours} h (target {lo}-{hi} min)")
        elif med < lo:
            warnings.append(f"too fast: {name} at {med} min (target {lo}-{hi} min)")
        elif med > hi:
            warnings.append(f"too slow: {name} at {med} min (target {lo}-{hi} min)")
    if max(r.peak_balance for r in runs) > MAX_EXACT:
        warnings.append("overflow: a balance passed 1e15; Luau numbers lose integer precision past 2^53")
    for name, m in milestones.items():
        if m["reached"].startswith("0/"):
            warnings.append(f"dead content: no simulated player reached {name}")
    return {"hours": hours, "players": players, "seed": seed, "milestones": milestones,
            "medianRebirths": statistics.median(r.rebirths for r in runs),
            "medianIncomePerSecondAtEnd": round(statistics.median(income_per_second(cfg, r) for r in runs), 2),
            "warnings": warnings}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("config", type=Path)
    ap.add_argument("--hours", type=float, default=None, help="simulated play time (default config session.hours or 4)")
    ap.add_argument("--players", type=int, default=50)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--json", type=Path, help="write the report as JSON")
    ap.add_argument("--strict", action="store_true", help="exit 1 when there are warnings")
    a = ap.parse_args(argv)
    cfg = json.loads(a.config.read_text())
    errors = validate(cfg)
    if errors:
        print("\n".join("error: " + e for e in errors))
        return 2
    hours = a.hours or cfg.get("session", {}).get("hours", 4)
    rep = report(cfg, hours, a.players, a.seed)
    print(f"{a.config.name}: {a.players} simulated players, {hours} h each (seed {a.seed})")
    print(f"{'milestone':28} {'reached':>9} {'median min':>11}")
    for name, m in rep["milestones"].items():
        med = "-" if m["medianMinutes"] is None else m["medianMinutes"]
        print(f"{name:28} {m['reached']:>9} {med:>11}")
    print(f"median rebirths {rep['medianRebirths']}, median income/s at end {rep['medianIncomePerSecondAtEnd']}")
    for w in rep["warnings"]:
        print("WARNING " + w)
    if not rep["warnings"]:
        print("no warnings")
    if a.json:
        a.json.write_text(json.dumps(rep, indent=1) + "\n")
    return 1 if (a.strict and rep["warnings"]) else 0


if __name__ == "__main__":
    sys.exit(main())
