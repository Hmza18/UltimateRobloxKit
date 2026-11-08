---
name: economy-balancing
description: Balance simulator and incremental economies before launch with the kit's economy simulator - write the economy as JSON (income, upgrade and rebirth cost curves, worlds, eggs, targets), simulate many seeded players, read milestone times, find walls, too-fast or too-slow progress, dead content and number overflow, then tune curves and repeat. Curves use the same formulas as the Luau Rebirth and Upgrades systems. Use when tuning prices, rebirth costs, world unlocks or egg odds, or when asked how long progression takes.
license: MIT
metadata:
  category: gameplay
  version: 1.0.0
  triggers: [balance the economy, economy simulation, tune prices, progression speed, rebirth cost, time to unlock, economy curve, too grindy, inflation]
  depends: [monetization-economy-design]
---

# Economy balancing

## Purpose

Catch grind walls and runaway inflation in minutes, before players do.

## Workflow

1. **Write the economy** as JSON (start from `$URK/tools/economy/examples/pet-sim.json`): `income`, `upgrades`, `rebirth`, `worlds`, `eggs`, `equipSlots`, `session.hours`, `limits.wallMinutes` and `targets` (milestone name to `[min, max]` minutes, e.g. `"rebirth 1": [15, 60]`).
2. **Simulate**: `python3 $URK/urk.py economy sim economy.json --players 50 --json report.json`.
3. **Read the table**: how many simulated players reached each milestone and the median minutes.
4. **Fix warnings one at a time**:
   - `wall`: add something to buy in the gap, or lower the next cost.
   - `too fast` / `too slow`: change the base or growth of that curve. Growth controls the late game, base controls the start.
   - `dead content`: nobody reached it in the session; lower its cost or move it to a longer session target.
   - `overflow`: balances past 1e15 lose integer precision in Luau; flatten growth or add a currency tier.
5. **Copy the final numbers** into `GameConfig.Progression` (same curve kinds: `linear`, `exponential`, `table`), then run the Lune specs.
6. `--strict` makes warnings fail a CI step once the economy is tuned.

## Rules

- Simulated players are greedy and tireless. Treat results as relative ("rebirth 1 moved from 12 to 25 minutes"), and confirm with live analytics after launch.
- Never tune paid items to create walls that only Robux removes. Roblox's rules and players both punish it.

## Limitations

- Pets are modelled by expected multiplier per egg, not individual rarity chases.
- Offline earnings, events and trading are not simulated.
