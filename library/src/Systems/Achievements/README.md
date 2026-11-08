# Achievements

Achievements driven by event counters (kills, crafts, purchases) or observed stats (level, best score), with hidden achievements, progress for UI, idempotent unlocks and optional Roblox badges awarded through an adapter with pcall and retries. `AchievementsLogic` is pure and immutable. `AchievementsServer` tracks players, fires unlock events, notifies the owner and awards badges.

## AchievementsLogic API

| Function | Returns | Notes |
| --- | --- | --- |
| `newDefs(defs)` | `Defs` | def: `{ id, kind? = "counter" \| "stat", key, threshold > 0, hidden?, badgeId?, name? = id, description? }` |
| `new()` | `State` | |
| `increment(defs, state, counter, amount? = 1, now)` | `(State, newlyUnlocked)` | ignores non-positive or non-finite amounts |
| `observe(defs, state, stat, value, now)` | `(State, newlyUnlocked)` | keeps the highest value |
| `unlock(defs, state, id, now)` | `(State, isNew)` | for scripted events |
| `evaluate(defs, state, now)` | `(State, newlyUnlocked)` | unlocks anything already earned (new definitions) |
| `isUnlocked(state, id)` | `boolean` | |
| `progress(defs, state, id)` | `{ current, target, fraction, unlocked }?` | |
| `list(defs, state)` | `{ Entry }` | hidden and locked: name `"???"`, empty description |
| `pendingBadges(defs, state)` | `{ { id, badgeId } }` | unlocked but not yet awarded |
| `markBadgeAwarded(state, id)` | `State` | |
| `serialize(state)` / `deserialize(defs, raw)` | | drops unlocks for removed ids; keeps counters and stats |

Each id unlocks once; `newlyUnlocked` lists it exactly once, in definition order.

## Server config

| Key | Default | Meaning |
| --- | --- | --- |
| `defs` | required | |
| `store` | `nil` | `{ load, save }` |
| `badges` | `AchievementsServer.badgeServiceAdapter()` | `{ award(userId, badgeId) -> boolean }` |
| `badgeRetries` | `3` | waits 2 s, 4 s between attempts |
| `remoteFolderName` | `"URK_Achievements"` | RemoteEvent `Unlocked(id)` to the owner, RemoteFunction `GetList()` |
| `clock` | `os.time` | unlock timestamps |

The default adapter calls `BadgeService:UserHasBadgeAsync` before `BadgeService:AwardBadge`, so a badge the user already owns counts as awarded. Awards run in their own thread; one award per player and achievement is in flight at a time, and pending badges are retried on the next join.

Server methods: `increment(player, counter, amount?)`, `observe(player, stat, value)`, `unlock(player, id)`, `list(player)`, `get(player)`, `loadPlayer`, `savePlayer`, `destroy`.

## Events

`Unlocked(player, id)`, `BadgeAwarded(player, id, badgeId)`.

## Example

```luau
local achievements = AchievementsServer.new({
	defs = AchievementsLogic.newDefs({
		{ id = "FirstCoin", key = "CoinsCollected", threshold = 1, name = "First Coin" },
		{ id = "Rich", key = "CoinsCollected", threshold = 10000, badgeId = 0 }, -- your badge id
		{ id = "Level10", kind = "stat", key = "Level", threshold = 10 },
		{ id = "SecretRoom", key = "SecretRoom", threshold = 1, hidden = true, name = "Explorer" },
	}),
})
currency.Changed:Connect(function(player, name, _balance, delta)
	if name == "Coins" and delta > 0 then
		achievements:increment(player, "CoinsCollected", delta)
	end
end)
achievements.Unlocked:Connect(function(player, id)
	print(player.Name, "unlocked", id)
end)
```

## Persistence shape

```luau
{ v = 1, c = { CoinsCollected = 420 }, s = { Level = 7 }, u = { FirstCoin = 1767225600 }, b = { Rich = true } }
```

## Limitations

- Thresholds only; achievements that need combinations ("win without taking damage") are unlocked by your code with `unlock`.
- Badge awarding needs a published place with real badge ids. Awards made in Studio test sessions may not count.
- Counters are per player and per session save; cross-server global achievements are not supported.

## Needs a Studio playtest

Badge awarding (verify `BadgeService:AwardBadge`, `UserHasBadgeAsync` and their limits in the creator docs), the Unlocked remote and GetList. Lune covers `AchievementsLogic`.
