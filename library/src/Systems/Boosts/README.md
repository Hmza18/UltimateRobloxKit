# Boosts

Timed multipliers (2x coins, luck potions, events). Pure `BoostsLogic` with injected `now`; granted by server code through `ProgressionServer:grantBoost(player, kind, count?)`.

| Stacking | Effect of another activation |
| --- | --- |
| `extend` (default) | adds `duration`, capped at `maxDuration` (default 24 h) |
| `refresh` | restarts at `duration` |
| `stack` | adds another instance, up to `maxStacks` (default 5); instances multiply |

`clock = "wall"` (default) keeps counting offline. `clock = "online"` saves remaining seconds, so time only runs while the player is in game.

Functions: `activate(config, state, kind, now, count?)`, `multiplier(config, state, stat, now)` (product of active boosts on that stat), `remaining(state, now)` (seconds per kind, for HUD timers), `prune`, `serialize(config, state, now)`, `deserialize(config, raw, now)` (clamps hostile expiry times).
