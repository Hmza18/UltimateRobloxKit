# Worlds

Ordered worlds or areas with requirements: the previous world (default), currency costs, rebirths and any stat. Pure `WorldsLogic`; use it through `ProgressionServer:unlockWorld` and gate zones with `ProgressionServer:isWorldUnlocked`.

```luau
worlds = {
	{ name = "Spawn" },
	{ name = "Forest", requires = { cost = { Coins = 500 } }, multiplier = 1.5 },
	{ name = "Volcano", requires = { cost = { Coins = 5000 }, rebirths = 1, stats = { hatched = 50 } }, multiplier = 3 },
}
```

Functions: `canUnlock(config, state, name, context)` returns `{ ok, reason?, cost }`, `unlock` (returns check and new state; the server charges `cost`), `isUnlocked`, `nextLocked` (for a "next area" arrow), `multiplier` (best unlocked world), `serialize`, `deserialize` (unknown names dropped). The first world is always unlocked.
