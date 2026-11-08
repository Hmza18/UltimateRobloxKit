# Progression

`ProgressionServer` runs the simulator loop on top of `CurrencyServer`: Rebirth, Upgrades, Worlds and Boosts share one saved record per player. Each part is optional.

```luau
local progression = ProgressionServer.new({
	currency = currencyServer,
	rebirth = { currency = "Coins", cost = { kind = "exponential", base = 1e4, growth = 2.2 }, reset = { "Coins", "upgrades" } },
	upgrades = { upgrades = { ... } },
	worlds = { worlds = { ... } },
	boosts = { boosts = { Coins2x = { stat = "coins", multiplier = 2, duration = 900 } } },
	store = profileStoreAdapter.section("progression"),
	onRebirthReset = function(player, keys) -- reset what lives in other systems
		if table.find(keys, "Coins") then currencyServer:setWallet(player, CurrencyLogic.newWallet(currencyConfig)) end
	end,
})
local earned = math.floor(base * progression:multiplier(player, "coins") * pets:multiplier(player))
```

Remotes in `URK_Progression`: `Rebirth(count? | "max")`, `BuyUpgrade(name, count? | "max")`, `UnlockWorld(name)`, server to client `Sync`. Server-only: `grantBoost(player, kind, count?)`. Queries: `multiplier(player, stat)`, `upgradeValue(player, name)`, `isWorldUnlocked(player, world)`, `getState(player)`. Signals: `Rebirthed`, `Upgraded`, `WorldUnlocked`. The player attribute `Rebirths` is kept current for leaderboards and UI.

Tune costs before launch with `python3 urk.py economy sim` (see `tools/economy`).
