---
name: component-library
description: Picks, installs and wires the kit's 27 reusable Luau game systems - inventory and hotbar, pickup, equipment, crafting, resources, shop, currency, save data, settings, quests, achievements, daily rewards, leaderboards, NPC behaviour, dialogue, zones, checkpoints, vehicles, placement, binder, rounds, teams, matchmaking, notifications, loading, input and analytics - into a Rojo project, with server authority and tests. Use when a game needs any of these systems, before writing one from scratch.
license: MIT
metadata:
  category: gameplay
  version: 1.0.0
  triggers: [game system, reusable module, hotbar, crafting system, quest system, dialogue system, round system, placement system, daily rewards, matchmaking system, add module]
  depends: [roblox-architecture, roblox-security-anti-exploit]
---

# Component library

The systems live in `$URK/library/src/Systems/`. `$URK/library/README.md` is the index, and each system's README has its API, configuration, persistence shape, example and Studio checklist. Read only the READMEs of the systems you are wiring.

## Workflow

1. **Check before building.** `python3 $URK/urk.py add --list`. If a system covers 80% of the need, use it and configure it rather than writing a new one.
2. **Install**: `python3 $URK/urk.py add Systems/Inventory Systems/Shop --project .`. Dependencies (Util, Currency for Shop, Inventory for Crafting) and specs come with it, into `src/shared/Urk/` and `tests/urk/`.
3. **Wire on the server** in one service per system (templates: `src/server/Services/`). Typical shape:
   ```lua
   local InventoryServer = require(ReplicatedStorage.Shared.Urk.Systems.Inventory.InventoryServer)
   local inventory = InventoryServer.new({ items = ItemDefinitions, capacity = 30, store = playerStore })
   ```
   Check each README for the exact constructor and config table. Server adapters create their remotes, validate and rate-limit arguments, and fire Signals for your game code.
4. **Persistence**: systems expose `serialize`/`deserialize` and accept a `{ load, save }` store. Use `Systems/SaveData` (session lock, migrations, retries), or wrap ProfileStore as its README shows. Keep one store per player, not one per system.
5. **Client**: use `<Name>Client` adapters or UrkUI (`urk-ui-framework`) for display. The client sends intents only.
6. **Configure, don't fork.** Change behaviour through config tables and callbacks. If you must edit a kit file, `urk.py add --update` will keep your edit and report it.
7. **Test**: `lune run tests/urk/run tests/urk` for the rules, then the README's Studio checklist for adapters.

## Choosing systems by genre

| Genre | Start with |
|---|---|
| Simulator | Currency, Resources, Inventory, Shop, Equipment, DailyRewards, Achievements, Leaderboards, SaveData |
| Tycoon | Currency, Placement, Shop, SaveData, Zones, Notifications |
| Obby | Checkpoints, Leaderboards, DailyRewards, Settings |
| RPG or adventure | Inventory, Equipment, Quests, Dialogue, NPC, Crafting, Pickup, Zones |
| Round-based PvP | Rounds, Teams, Matchmaking, Leaderboards, Analytics |
| Racing | Vehicles, Checkpoints, Rounds, Leaderboards |
| Building or sandbox | Placement, Inventory, SaveData, Binder |

Every game also wants Settings, Input, Loading, Notifications and Analytics.

## Validation

`python3 $URK/urk.py check .` shows the library lock as OK, Lune specs pass, and Selene and StyLua are clean on `src`. Then the Studio checklist from each README.

## Limitations

The adapters were written without a Studio run, so treat their first playtest as part of integration. Shop stock is per server, the SaveData lock has no MessagingService handoff (ProfileStore has one), and Matchmaking and teleports cannot be tested in Studio.
