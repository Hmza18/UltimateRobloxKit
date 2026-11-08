---
name: roblox-simulator-systems
description: Use the kit's tested Luau systems for simulator games instead of writing new ones - Pets (eggs, weighted rarity, pity, luck, equip, fuse, lock), Rebirth, Upgrades, Worlds (unlock requirements), Boosts (timed multipliers with stacking modes), Trading (versioned offers, countdown, re-check, atomic swap), Progression (one server for rebirth, upgrades, worlds and boosts), VFX presets with quality tiers, WorldGen layouts, plus the ProfileStore and Fusion integrations. Use when adding pets, eggs, hatching, rebirths, upgrades, world unlocks, boosts, trading or simulator VFX to a game.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [pets and eggs, hatch, rarity, pity, rebirth system, upgrades system, world unlock, boosts, potion, trading system, trade pets, simulator systems, vfx preset, world layout]
  depends: [roblox-architecture, roblox-security-anti-exploit]
---

# Roblox simulator systems

## Purpose

Simulator features are where exploits and dupes happen. The kit's versions are pure, tested Luau with thin server adapters; use them and spend your time on what makes the game different.

## Add them

```bash
python3 $URK/urk.py add Systems/Pets Systems/Progression Systems/Trading Systems/VFX Systems/WorldGen --project <dir>
```

Each module's README has the full API: `library/src/Systems/<Name>/README.md`.

## Wiring (server)

1. `CurrencyServer.new(...)` first; everything else spends through `currency:spendMany(player, costs, sink)`.
2. `ProgressionServer.new({ currency, rebirth, upgrades, worlds, boosts, store, onRebirthReset })`.
3. `PetsServer.new({ pets, currency, store, getLuck = function(p) return progression:multiplier(p, "luck") end, canUseEgg = ... })`.
4. `TradingServer.new({ trading = { currencies = { Gems = true } }, pets, petsConfig, currency, currencyConfig })`.
5. Income: `base * progression:multiplier(player, "income") * pets:multiplier(player)`, computed on the server.
6. Persistence: one ProfileStore session per player, split into sections: `ProfileStoreAdapter.new({ ProfileStore = ..., name = "PlayerData_v1" }).section("pets")`.

## Rules

- Clients send ids and counts, never prices, amounts or results. The adapters already validate and rate-limit.
- Roll on the server with its own `Random`. Charge after a successful roll, commit last.
- Show odds for every egg (Roblox requires it for paid random items): `PetsLogic.odds(config, egg, luck)`.
- Mark rare or event pets `tradeable = false` when they must not move between players.
- VFX are cosmetic: play them on the client with `VFXClient`; never gate gameplay on them.

## Limitations

- Server adapters are exercised in Studio, not in CI: CI runs the pure Logic modules' Lune specs and a Rojo build.
- Trading covers pets and chosen currencies. Other item types need their own `verify` and swap step.
