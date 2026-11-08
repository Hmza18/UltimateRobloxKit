#!/usr/bin/env python3
"""Generate a playable game project from one sentence, assembled from the kit's existing parts.

  python3 scripts/automation/generate_game.py "supermarket simulator with 50 products" --name MegaMart --out ~/games/MegaMart
  python3 scripts/automation/generate_game.py "pet simulator with 3 worlds and 24 pets" --name PetLand --out build/petland
  python3 scripts/automation/generate_game.py "obby with 30 stages" --name SkyObby --out build/skyobby --dry-run

Genres: simulator, pet, collection, incremental, tycoon, obby. Counts are read from the sentence
("50 products", "24 pets", "3 worlds", "6 eggs", "30 stages"); missing counts get defaults.

What it writes (nothing is published or uploaded):
- the base template (new_project.py) plus library systems for the genre (add_module.py)
- src/shared/GameConfig.luau        products, currencies, pets and eggs, worlds, upgrades, rebirths, passes
- src/server/Services/UrkGameService.luau  wires CurrencyServer, PetsServer, ProgressionServer and Shop
- src/shared/UrkScreens/*.json      screen specs (shop, HUD, upgrades, inventory...) with client scripts
- tests/gameconfig.spec.luau        Lune spec: the generated config passes every system's validator
- assets/asset-plan.json            3D asset batch for scripts/export/asset_batch.py (one entry per product)
- economy.json + economy-report.json  balance check with tools/economy/economy_sim.py
- GAME_PLAN.md                      what was generated, what to fill in (game pass ids), next steps
Game pass and developer product ids are 0 placeholders: create them on the Creator Dashboard and fill them in.
Standard library only.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PY = sys.executable

GENRES = {
    "supermarket": "simulator", "store": "simulator", "shop": "simulator", "simulator": "simulator",
    "pet": "pet", "pets": "pet", "collection": "collection", "collect": "collection", "incremental": "incremental",
    "idle": "incremental", "clicker": "incremental", "tycoon": "tycoon", "obby": "obby", "parkour": "obby",
}
TEMPLATE_FOR = {"simulator": "simulator", "pet": "simulator", "collection": "simulator", "incremental": "simulator",
                "tycoon": "tycoon", "obby": "obby"}
SYSTEMS_FOR = {
    "simulator": ["Systems/Currency", "Systems/Shop", "Systems/Inventory", "Systems/Progression", "Systems/Pets",
                  "Systems/Quests", "Systems/DailyRewards", "Systems/Leaderboards", "Systems/Notifications", "UI", "Icons"],
    "pet": ["Systems/Currency", "Systems/Shop", "Systems/Progression", "Systems/Pets", "Systems/Trading",
            "Systems/Quests", "Systems/DailyRewards", "Systems/Leaderboards", "Systems/Notifications", "UI", "Icons"],
    "collection": ["Systems/Currency", "Systems/Shop", "Systems/Inventory", "Systems/Progression", "Systems/Pets",
                   "Systems/Achievements", "Systems/Leaderboards", "UI", "Icons"],
    "incremental": ["Systems/Currency", "Systems/Shop", "Systems/Progression", "Systems/Leaderboards", "UI", "Icons"],
    "tycoon": ["Systems/Currency", "Systems/Shop", "Systems/Placement", "Systems/Progression", "UI", "Icons"],
    "obby": ["Systems/Checkpoints", "Systems/Currency", "Systems/Shop", "Systems/Progression", "Systems/Leaderboards", "UI", "Icons"],
}
SCREENS_FOR = {
    "simulator": ["MainHud", "PetSimShop", "Upgrades", "Inventory", "DailyRewards"],
    "pet": ["MainHud", "PetSimShop", "PetHatch", "Trading", "Upgrades"],
    "collection": ["MainHud", "Inventory", "Achievements", "PetSimShop"],
    "incremental": ["MainHud", "Upgrades", "GamepassStore"],
    "tycoon": ["MainHud", "Upgrades", "GamepassStore"],
    "obby": ["MainHud", "GamepassStore", "Leaderboard"],
}
COUNT_WORDS = {"products": "products", "items": "products", "goods": "products", "pets": "pets", "worlds": "worlds",
               "areas": "worlds", "zones": "worlds", "eggs": "eggs", "stages": "stages", "levels": "stages",
               "upgrades": "upgrades"}
DEFAULTS = {"products": 12, "pets": 12, "worlds": 3, "eggs": 0, "stages": 20, "upgrades": 3}

# Generic product nouns grouped by shape, each with a mesh generator from tools/rbxasset/generators.
PRODUCT_SHAPES = [
    ("carton_box", ["Cereal", "Crackers", "Oat Flakes", "Tea Box", "Rice Pops", "Cookies", "Granola", "Pasta"]),
    ("bottle", ["Juice", "Water", "Ketchup", "Olive Oil", "Shampoo", "Vinegar", "Syrup", "Lemonade"]),
    ("soda_can", ["Cola", "Orange Soda", "Energy Drink", "Iced Tea", "Ginger Ale", "Sparkling Water"]),
    ("food_can", ["Beans", "Soup", "Tomatoes", "Corn", "Peaches", "Tuna"]),
    ("jar", ["Jam", "Honey", "Pickles", "Peanut Butter", "Salsa", "Olives"]),
    ("gable_carton", ["Milk", "Orange Juice", "Cream", "Oat Milk"]),
    ("bread_loaf", ["Bread", "Rye Loaf", "Brioche"]),
    ("cheese_block", ["Cheddar", "Gouda", "Butter"]),
    ("pillow_bag", ["Chips", "Pretzels", "Popcorn", "Candy Mix"]),
    ("wrapped_bar", ["Chocolate Bar", "Protein Bar", "Toffee"]),
    ("egg_carton", ["Eggs"]),
    ("paper_rolls", ["Paper Towels", "Toilet Paper"]),
    ("bleach_jug", ["Bleach", "Detergent", "Fabric Softener"]),
    ("cup_tub", ["Yogurt", "Ice Cream", "Pudding"]),
]
PET_NAMES = ["Dog", "Cat", "Bunny", "Fox", "Owl", "Panda", "Penguin", "Tiger", "Wolf", "Bear", "Deer", "Frog", "Koala",
             "Lion", "Monkey", "Otter", "Parrot", "Raccoon", "Seal", "Shark", "Turtle", "Unicorn", "Dragon", "Phoenix"]
WORLD_NAMES = ["Spawn", "Forest", "Desert", "Snow", "Volcano", "Ocean", "Candy", "Space", "Crystal", "Shadow"]
RARITIES = [("Common", 1, 60), ("Uncommon", 2, 25), ("Rare", 3, 10), ("Epic", 4, 4), ("Legendary", 5, 1)]
COLOURS = ["#E63946", "#F4A261", "#2A9D8F", "#457B9D", "#8E44AD", "#F1C40F", "#27AE60", "#E67E22", "#1ABC9C", "#D35400"]


def parse(text: str) -> dict:
    t = text.lower()
    genre = next((GENRES[w] for w in re.findall(r"[a-z]+", t) if w in GENRES), "simulator")
    counts = dict(DEFAULTS)
    for n, word in re.findall(r"(\d+)\s+([a-z]+)", t):
        if word in COUNT_WORDS:
            counts[COUNT_WORDS[word]] = max(1, min(int(n), 500))
    theme = "supermarket" if re.search(r"supermarket|grocery|store|market|shop", t) else (
        "pets" if genre == "pet" else genre)
    if genre == "pet" and counts["eggs"] == 0:
        counts["eggs"] = counts["worlds"]
    return {"genre": genre, "theme": theme, "counts": counts, "prompt": text}


def products(n: int) -> list[dict]:
    flat = [(gen, name) for gen, names in PRODUCT_SHAPES for name in names]
    out = []
    for i in range(n):
        gen, name = flat[i % len(flat)]
        if i >= len(flat):
            name = f"{name} {i // len(flat) + 1}"
        tier = i * 5 // max(n, 1)  # five price tiers across the list
        price = round(5 * (2.2 ** tier) * (1 + (i % 5) * 0.15))
        out.append({"id": re.sub(r"[^A-Za-z0-9]", "", name.title()), "name": name, "generator": gen, "tier": tier + 1,
                    "buyPrice": price, "sellPrice": round(price * 1.6), "colour": COLOURS[i % len(COLOURS)]})
    return out


def pets(n: int, eggs: int, worlds: list[str]) -> tuple[list[dict], list[dict]]:
    names = [PET_NAMES[i % len(PET_NAMES)] + (f" {i // len(PET_NAMES) + 1}" if i >= len(PET_NAMES) else "") for i in range(n)]
    egg_count = max(1, eggs)
    per = max(1, n // egg_count)
    pet_list, egg_list = [], []
    for e in range(egg_count):
        group = names[e * per: (e + 1) * per] if e < egg_count - 1 else names[e * per:]
        if not group:
            group = names[-1:]
        entries = []
        for j, name in enumerate(group):
            rarity = RARITIES[min(j * len(RARITIES) // max(len(group), 1), len(RARITIES) - 1)]
            mult = round((1 + e * 2) * (0.5 + rarity[1] ** 2 * 0.25), 2)
            pet_list.append({"name": name, "rarity": rarity[0], "multiplier": mult})
            entries.append({"pet": name, "weight": rarity[2]})
        egg_list.append({"name": f"{worlds[min(e, len(worlds) - 1)]} Egg", "world": worlds[min(e, len(worlds) - 1)],
                         "cost": round(100 * (12 ** e)), "entries": entries,
                         "pity": {"rarity": "Legendary", "after": 150} if any(
                             p["rarity"] == "Legendary" for p in pet_list[-len(group):]) else None})
    return pet_list, egg_list


def plan(spec: dict, name: str) -> dict:
    c = spec["counts"]
    genre = spec["genre"]
    worlds = [WORLD_NAMES[i % len(WORLD_NAMES)] + (f" {i // len(WORLD_NAMES) + 1}" if i >= len(WORLD_NAMES) else "")
              for i in range(max(1, c["worlds"]))]
    currency = "Cash" if spec["theme"] == "supermarket" else "Coins"
    p = {"name": name, "genre": genre, "theme": spec["theme"], "prompt": spec["prompt"], "currency": currency,
         "template": TEMPLATE_FOR[genre], "systems": SYSTEMS_FOR[genre], "screens": SCREENS_FOR[genre],
         "worlds": [{"name": w, "cost": 0 if i == 0 else round(2500 * (8 ** (i - 1))), "multiplier": round(1 + i * 0.75, 2),
                     "rebirths": max(0, i - 1)} for i, w in enumerate(worlds)],
         "upgrades": [
             {"name": "Income", "base": 25, "growth": 1.45, "maxLevel": 35, "perLevel": 0.5},
             {"name": "Speed", "base": 100, "growth": 1.6, "maxLevel": 10, "perLevel": 2},
             {"name": "Capacity", "base": 250, "growth": 1.8, "maxLevel": 15, "perLevel": 5},
         ][: max(1, c["upgrades"])],
         "rebirth": {"base": 300000, "growth": 3, "multiplierPerRebirth": 0.5},
         "passes": [{"name": "2x " + currency, "price": 199}, {"name": "VIP", "price": 299}],
         "products": [], "pets": [], "eggs": [], "stages": c["stages"] if genre == "obby" else 0}
    if spec["theme"] == "supermarket" or genre in ("collection", "simulator"):
        p["products"] = products(c["products"])
    if genre in ("pet", "collection") or "Systems/Pets" in p["systems"] and c["pets"] and genre != "incremental":
        p["pets"], p["eggs"] = pets(c["pets"], c["eggs"] or len(worlds), worlds)
    return p


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def game_config_luau(p: dict) -> str:
    cur = p["currency"]
    L = ["--!strict", f"-- Generated by urk generate for {p['name']} ({p['genre']}). Safe to edit: re-running the",
         "-- generator never overwrites this file. Clients can read it, so keep secrets out.", "",
         "local GameConfig = {}", "", f"GameConfig.Currency = {lua_str(cur)}", ""]
    L += ["GameConfig.CurrencyConfig = {", "\tcurrencies = {", f"\t\t{cur} = {{ initial = 0 }},", "\t\tGems = { initial = 0 },",
          "\t},", "}", ""]
    L.append("-- Products: buyPrice to stock, sellPrice per sale. `generator` and `colour` drive assets/asset-plan.json.")
    L.append("GameConfig.Products = {")
    for pr in p["products"]:
        L.append(f"\t{{ id = {lua_str(pr['id'])}, name = {lua_str(pr['name'])}, tier = {pr['tier']}, "
                 f"buyPrice = {pr['buyPrice']}, sellPrice = {pr['sellPrice']} }},")
    L += ["}", ""]
    if p["pets"]:
        L += ["GameConfig.Pets = {", "\trarities = {"]
        for rname, rank, _ in RARITIES:
            L.append(f"\t\t{{ name = {lua_str(rname)}, rank = {rank} }},")
        L += ["\t},", "\tpets = {"]
        for pet in p["pets"]:
            L.append(f"\t\t[{lua_str(pet['name'])}] = {{ rarity = {lua_str(pet['rarity'])}, multiplier = {pet['multiplier']} }},")
        L += ["\t},", "\teggs = {"]
        for egg in p["eggs"]:
            entries = ", ".join(f"{{ pet = {lua_str(e['pet'])}, weight = {e['weight']} }}" for e in egg["entries"])
            pity = (f", pity = {{ rarity = {lua_str(egg['pity']['rarity'])}, after = {egg['pity']['after']} }}"
                    if egg.get("pity") else "")
            L.append(f"\t\t[{lua_str(egg['name'])}] = {{ cost = {{ {cur} = {egg['cost']} }}, world = {lua_str(egg['world'])}, "
                     f"entries = {{ {entries} }}{pity} }},")
        L += ["\t},", "\tcapacity = 100,", "\tequipSlots = 3,", "}", ""]
    else:
        L += ["GameConfig.Pets = nil :: any", ""]
    L += ["GameConfig.Progression = {", "\trebirth = {", f"\t\tcurrency = {lua_str(cur)},",
          f"\t\tcost = {{ kind = \"exponential\", base = {p['rebirth']['base']}, growth = {p['rebirth']['growth']} }},",
          f"\t\tmultiplierPerRebirth = {p['rebirth']['multiplierPerRebirth']},", f"\t\treset = {{ {lua_str(cur)}, \"upgrades\" }},",
          "\t},", "\tupgrades = {", "\t\tupgrades = {"]
    for u in p["upgrades"]:
        L.append(f"\t\t\t{u['name']} = {{ currency = {lua_str(cur)}, cost = {{ kind = \"exponential\", base = {u['base']}, "
                 f"growth = {u['growth']} }}, maxLevel = {u['maxLevel']}, effect = {{ base = 0, perLevel = {u['perLevel']} }} }},")
    L += ["\t\t},", "\t},", "\tworlds = {", "\t\tworlds = {"]
    for i, w in enumerate(p["worlds"]):
        if i == 0:
            L.append(f"\t\t\t{{ name = {lua_str(w['name'])} }},")
        else:
            req = f"cost = {{ {cur} = {w['cost']} }}" + (f", rebirths = {w['rebirths']}" if w["rebirths"] else "")
            L.append(f"\t\t\t{{ name = {lua_str(w['name'])}, requires = {{ {req} }}, multiplier = {w['multiplier']} }},")
    L += ["\t\t},", "\t},", "\tboosts = {", "\t\tboosts = {",
          f"\t\t\tDouble{cur} = {{ stat = \"income\", multiplier = 2, duration = 900 }},",
          "\t\t\tLuck = { stat = \"luck\", multiplier = 1.5, duration = 600, stacking = \"stack\", maxStacks = 3 },",
          "\t\t},", "\t},", "}", ""]
    L.append("-- Fill in real ids from the Creator Dashboard before publishing. 0 means not created yet.")
    L.append("GameConfig.GamePasses = {")
    for gp in p["passes"]:
        L.append(f"\t{{ name = {lua_str(gp['name'])}, id = 0, robux = {gp['price']} }},")
    L += ["}", ""]
    if p["stages"]:
        L += [f"GameConfig.Stages = {p['stages']}", ""]
    L += ["return GameConfig", ""]
    return "\n".join(L)


SERVICE = '''--!strict
-- Generated by urk generate. Wires the kit's systems with GameConfig. One ProfileStore session is not
-- assumed: pass a store (ProfileStoreAdapter or SaveDataServer.dataStoreStore) to persist; without one,
-- data lives for the session only, which is fine in Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Urk = Shared:WaitForChild("Urk")
local Systems = Urk:WaitForChild("Systems")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local CurrencyServer = require(Systems:WaitForChild("Currency"):WaitForChild("CurrencyServer"))
local ProgressionServer = require(Systems:WaitForChild("Progression"):WaitForChild("ProgressionServer"))
__PETS_REQUIRE__
local UrkGameService = { Name = "UrkGameService", Priority = 5 }

function UrkGameService:Init()
	self.currency = CurrencyServer.new({
		currency = GameConfig.CurrencyConfig,
		leaderstats = { GameConfig.Currency },
	})
	self.progression = ProgressionServer.new({
		currency = self.currency,
		rebirth = GameConfig.Progression.rebirth,
		upgrades = GameConfig.Progression.upgrades,
		worlds = GameConfig.Progression.worlds,
		boosts = GameConfig.Progression.boosts,
	})
__PETS_INIT__end

-- Income from any source goes through here, so every multiplier applies in one place.
function UrkGameService:Grant(player: Player, base: number, source: string)
	local multiplier = self.progression:multiplier(player, "income")__PETS_MULT__
	self.currency:add(player, GameConfig.Currency, math.max(1, math.floor(base * multiplier)), source)
end

return UrkGameService
'''


def service_luau(p: dict) -> str:
    has_pets = bool(p["pets"])
    s = SERVICE.replace("__PETS_REQUIRE__", 'local PetsServer = require(Systems:WaitForChild("Pets"):WaitForChild("PetsServer"))\n'
                        if has_pets else "")
    s = s.replace("__PETS_INIT__", '''	self.pets = PetsServer.new({
		pets = GameConfig.Pets,
		currency = self.currency,
		canUseEgg = function(player: Player, egg: string): boolean
			local def = GameConfig.Pets.eggs[egg]
			return def ~= nil and (def.world == nil or self.progression:isWorldUnlocked(player, def.world))
		end,
	})
''' if has_pets else "")
    return s.replace("__PETS_MULT__", " * self.pets:multiplier(player)" if has_pets else "")


def spec_luau(p: dict) -> str:
    pets = '''	["pets config is valid"] = function()
		PetsLogic.validateConfig(GameConfig.Pets)
	end,
''' if p["pets"] else ""
    pets_req = 'local PetsLogic = require("../src/shared/Urk/Systems/Pets/PetsLogic")\n' if p["pets"] else ""
    return f'''--!strict
-- Generated by urk generate: the generated GameConfig passes every system's validator.
local BoostsLogic = require("../src/shared/Urk/Systems/Boosts/BoostsLogic")
local CurrencyLogic = require("../src/shared/Urk/Systems/Currency/CurrencyLogic")
local GameConfig = require("../src/shared/GameConfig")
{pets_req}local RebirthLogic = require("../src/shared/Urk/Systems/Rebirth/RebirthLogic")
local UpgradesLogic = require("../src/shared/Urk/Systems/Upgrades/UpgradesLogic")
local WorldsLogic = require("../src/shared/Urk/Systems/Worlds/WorldsLogic")

return {{
	["currency and progression configs are valid"] = function()
		CurrencyLogic.validateConfig(GameConfig.CurrencyConfig)
		RebirthLogic.validateConfig(GameConfig.Progression.rebirth)
		UpgradesLogic.validateConfig(GameConfig.Progression.upgrades)
		WorldsLogic.validateConfig(GameConfig.Progression.worlds)
		BoostsLogic.validateConfig(GameConfig.Progression.boosts)
	end,
{pets}	["every product has a positive margin"] = function()
		for _, product in GameConfig.Products do
			assert(product.sellPrice > product.buyPrice, product.id .. " sells below cost")
		end
	end,
}}
'''


def asset_plan(p: dict) -> dict:
    sizes = {"carton_box": [0.8, 0.3, 1.1], "bottle": [0.35, 0.35, 1.0], "soda_can": [0.3, 0.3, 0.45],
             "food_can": [0.35, 0.35, 0.45], "jar": [0.4, 0.4, 0.5], "gable_carton": [0.4, 0.4, 0.9],
             "bread_loaf": [0.9, 0.45, 0.4], "cheese_block": [0.6, 0.4, 0.3], "pillow_bag": [0.7, 0.25, 0.9],
             "wrapped_bar": [0.6, 0.15, 0.2], "egg_carton": [0.9, 0.4, 0.3], "paper_rolls": [0.8, 0.4, 0.6],
             "bleach_jug": [0.5, 0.35, 0.9], "cup_tub": [0.4, 0.4, 0.35]}
    return {"batch": f"{p['name'].lower()}-products", "assets": [
        {"name": pr["id"], "generator": pr["generator"], "size": sizes.get(pr["generator"], [1, 1, 1]),
         "colors": {"body": pr["colour"]}} for pr in p["products"]]}


def economy_json(p: dict) -> dict:
    return {
        "currency": p["currency"],
        "income": {"base": 1, "per": "click", "clicksPerSecond": [2, 6]},
        "upgrades": [{"name": u["name"], "cost": {"kind": "exponential", "base": u["base"], "growth": u["growth"]},
                      "maxLevel": u["maxLevel"], "effect": {"stat": "income", "perLevel": u["perLevel"] / 2}}
                     for u in p["upgrades"]],
        "rebirth": {"cost": {"kind": "exponential", "base": p["rebirth"]["base"], "growth": p["rebirth"]["growth"]},
                    "multiplierPerRebirth": p["rebirth"]["multiplierPerRebirth"], "reset": ["upgrades"], "maxRebirths": 30},
        "worlds": [{"name": w["name"], "cost": w["cost"], "multiplier": w["multiplier"], "rebirths": w["rebirths"]}
                   for w in p["worlds"]],
        "eggs": [{"name": e["name"], "cost": e["cost"], "entries": [
            {"pet": en["pet"], "weight": en["weight"],
             "multiplier": next(x["multiplier"] for x in p["pets"] if x["name"] == en["pet"]) / 10}
            for en in e["entries"]]} for e in p["eggs"]],
        "equipSlots": 3, "session": {"hours": 1.5}, "limits": {"wallMinutes": 20},
    }


def write_new(path: Path, text: str) -> bool:
    if path.exists():
        print(f"kept existing {path}")
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return True


def run(args: list, check=True) -> int:
    print("$ " + " ".join(str(a) for a in args[1:]), flush=True)
    code = subprocess.run(args).returncode
    if check and code != 0:
        sys.exit(code)
    return code


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("prompt")
    ap.add_argument("--name", required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--dry-run", action="store_true", help="print the plan only")
    ap.add_argument("--no-economy", action="store_true", help="skip the economy simulation")
    a = ap.parse_args(argv)
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]{1,40}", a.name):
        ap.error("--name must be letters and digits, starting with a letter")
    p = plan(parse(a.prompt), a.name)
    if a.dry_run:
        print(json.dumps(p, indent=1))
        return 0
    out = a.out.expanduser().resolve()
    if not out.exists():
        run([PY, ROOT / "scripts/automation/new_project.py", "--template", p["template"], "--name", a.name, "--out", out])
    run([PY, ROOT / "scripts/automation/add_module.py", *p["systems"], "--project", out])
    written = [path for path, text in [
        (out / "src/shared/GameConfig.luau", game_config_luau(p)),
        (out / "src/server/Services/UrkGameService.luau", service_luau(p)),
        (out / "tests/gameconfig.spec.luau", spec_luau(p)),
    ] if write_new(path, text)]
    stylua = shutil.which("stylua")
    if written and stylua:
        subprocess.run([stylua, *map(str, written)], cwd=out)
    elif written:
        print("StyLua not found: run `rokit install` then `stylua src tests` to format the generated Luau.")
    for screen in p["screens"]:
        if not (out / "src/shared/UrkScreens" / f"{screen}.json").exists():
            run([PY, ROOT / "tools/ui/ui_cli.py", "new", screen, "--name", screen, "--project", out], check=False)
    if p["products"]:
        write_new(out / "assets/asset-plan.json", json.dumps(asset_plan(p), indent=1) + "\n")
    report = None
    if p["eggs"] or p["upgrades"]:
        write_new(out / "economy.json", json.dumps(economy_json(p), indent=1) + "\n")
        if not a.no_economy:
            run([PY, ROOT / "tools/economy/economy_sim.py", out / "economy.json", "--players", "20",
                 "--json", out / "economy-report.json"], check=False)
            if (out / "economy-report.json").exists():
                report = json.loads((out / "economy-report.json").read_text())
    doc = [f"# {a.name}", "", f"Generated by `urk generate` from: \"{a.prompt}\"", "",
           f"- Genre: {p['genre']} (template `{p['template']}`), theme: {p['theme']}, currency: {p['currency']}",
           f"- Systems: {', '.join(p['systems'])}",
           f"- Screens: {', '.join(p['screens'])} (src/shared/UrkScreens, edit the JSON, preview with `urk ui preview`)",
           f"- Products: {len(p['products'])}, pets: {len(p['pets'])}, eggs: {len(p['eggs'])}, worlds: {len(p['worlds'])}",
           "", "## Before you publish", "",
           "- [ ] Create the game passes and developer products, then put their ids in `GameConfig.GamePasses` (all 0 now).",
           "- [ ] Choose persistence: pass a store to the servers in `UrkGameService` (see `Integrations/README.md`).",
           "- [ ] Build the 3D products: `python3 urk.py assets assets/asset-plan.json --out build/products`, review "
           "the contact sheets, then approve each asset.",
           "- [ ] Publish the odds of every egg in game (Roblox rule for paid random items).",
           "- [ ] Test on phone, tablet and console sizes in Studio's device emulator.",
           "- [ ] `python3 urk.py release check --project .` and only then publish, yourself, from Studio.", ""]
    if report:
        doc += ["## Economy check (simulated, not real players)", "", "| Milestone | Reached | Median minutes |",
                "|---|---|---|"]
        doc += [f"| {k} | {v['reached']} | {v['medianMinutes'] if v['medianMinutes'] is not None else '-'} |"
                for k, v in report["milestones"].items()]
        doc += [""] + [f"- WARNING {w}" for w in report["warnings"]] + ([""] if report["warnings"] else ["No warnings.", ""])
    write_new(out / "GAME_PLAN.md", "\n".join(doc))
    print(f"\n{a.name} generated in {out}. Next: read GAME_PLAN.md, then `lune run tests/run` and `rojo serve`.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
