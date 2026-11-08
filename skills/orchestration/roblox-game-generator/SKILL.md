---
name: roblox-game-generator
description: Generates a complete, working Roblox game project from one sentence with `urk generate` - picks the template and library systems for the genre (simulator, pet, collection, incremental, tycoon, obby), writes GameConfig (products, currencies, pets, eggs, worlds, upgrades, rebirths, passes), the server wiring, screen specs, a 3D asset plan, a Lune spec that validates the config and an economy report, then guides the follow-up work. Use when the user asks for a whole game, a game from a description, or a starting point like "supermarket simulator with 50 products".
license: MIT
metadata:
  category: orchestration
  version: 1.0.0
  triggers: [generate a game, whole game, complete game, game from a description, urk generate, start a new game, make me a simulator, supermarket simulator, pet simulator game]
  depends: [roblox-project-planner, roblox-simulator-systems]
---

# Roblox game generator

## Purpose

Get from an idea to a project that builds, tests and runs in Studio in one step, assembled from the kit's tested systems instead of new code.

## Workflow

1. **Confirm the sentence**: genre, theme and counts. Example: "supermarket simulator with 50 products and 3 worlds".
2. **Dry run** to show the plan: `python3 $URK/urk.py generate "<sentence>" --name MegaMart --out ~/games/MegaMart --dry-run`.
3. **Generate**: the same command without `--dry-run`. It never overwrites existing files.
4. **Verify** in the project: `python3 $URK/urk.py build --project ~/games/MegaMart` (Selene, StyLua, Lune incl. `tests/gameconfig.spec.luau`, Rojo build). Report PASS, FAIL or MISSING TOOL as printed.
5. **Read `GAME_PLAN.md` with the user** and work through it. Product art: `python3 $URK/urk.py assets assets/asset-plan.json --out build/products` (`batch-asset-production`). Balance: `economy-balancing`. Screens: `roblox-ui-generator` or `roblox-visual-ui-loop`. Data: `python3 $URK/urk.py packages --project .` and `Integrations/ProfileStoreAdapter`.
6. **Record decisions** in project memory: `python3 $URK/urk.py memory add decision "..." --project .`.

## What each genre gets

| Genre | Template | Systems |
|---|---|---|
| simulator, supermarket | simulator | Currency, Shop, Inventory, Progression, Pets, Quests, DailyRewards, Leaderboards, Notifications |
| pet | simulator | Currency, Shop, Progression, Pets, Trading, Quests, DailyRewards, Leaderboards |
| collection | simulator | Currency, Shop, Inventory, Progression, Pets, Achievements, Leaderboards |
| incremental | simulator | Currency, Shop, Progression, Leaderboards |
| tycoon | tycoon | Currency, Shop, Placement, Progression |
| obby | obby | Checkpoints, Currency, Shop, Progression, Leaderboards |

UI, Icons and the matching screen specs come with every genre.

## Limitations

- The generator writes data and wiring. Gameplay unique to an idea (how a register works, what an obstacle does) is still yours to design and build.
- Game pass and product ids are 0 placeholders until created on the Creator Dashboard; `urk release check` fails until they are filled in.
- Product names are generic nouns. Brand them with `original-brand` art direction; never use real brands.
- The economy report simulates greedy players. Real players differ, so check it again with live data.
