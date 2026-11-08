# Upgrades

Leveled upgrades with cost curves, max levels, effects and prerequisites. Pure `UpgradesLogic`; use it through `Systems/Progression/ProgressionServer`.

```luau
upgrades = {
	Speed = { currency = "Coins", cost = { kind = "linear", base = 10, step = 10 }, maxLevel = 5, effect = { base = 16, perLevel = 2 } },
	Bag = { currency = "Coins", cost = { kind = "table", values = { 50, 100, 400 } }, maxLevel = 3,
		effect = { base = 10, values = { 20, 40, 80 } }, requires = { Speed = 2 }, resetOnRebirth = false },
}
```

| Function | Notes |
| --- | --- |
| `buy(config, state, name, balance, count? \| "max")` | `{ ok, reason?, levels, cost, currency, state }` |
| `value(config, state, name)` | effect at the current level |
| `nextCost`, `level`, `isLocked` | `nextCost` is nil at max level |
| `afterRebirth(config, state)` | keeps only `resetOnRebirth = false` upgrades |
| `serialize`, `deserialize` | unknown names dropped, levels clamped to `maxLevel` |
