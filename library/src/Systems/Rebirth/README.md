# Rebirth

Prestige resets with a growing cost and a permanent multiplier. Pure `RebirthLogic`; use it through `Systems/Progression/ProgressionServer`.

| Function | Notes |
| --- | --- |
| `curveCost(curve, n)` | `linear` base + step(n-1), `exponential` base x growth^(n-1), `table` values[n] (last repeats). Shared with Upgrades |
| `plan(config, state, balance, count? \| "max")` | `{ ok, reason?, count, cost, tokens, state, reset }`; the server spends `cost`, resets `reset`, grants `tokens` |
| `multiplier(config, state)` | `1 + rebirths x multiplierPerRebirth` (default 0.5) |
| `costOf`, `serialize`, `deserialize` | deserialize clamps to `[0, maxRebirths]` |

Config: `currency`, `cost` (curve), `multiplierPerRebirth?`, `maxRebirths?`, `reset?` (keys your `onRebirthReset` handles; `"upgrades"` is handled for you), `tokensPerRebirth?`, `tokenCurrency?`.
