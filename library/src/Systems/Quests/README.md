# Quests

Data-driven quests and missions. Objectives count game events, collect items or reach locations. Quests can chain, require prerequisites, repeat after a cooldown or reset daily. The server owns progress; clients can only ask to start or abandon a quest.

| File | Runs on | Role |
| --- | --- | --- |
| `QuestsLogic.luau` | anywhere (pure) | definitions, validation, progress, chains, persistence shape |
| `QuestsServer.luau` | server | per-player state, remotes, reward callback, store hooks |
| `QuestsClient.luau` | client | snapshot mirror and start/abandon requests |
| `QuestsConfig.luau` | anywhere | defaults |

## Definitions

```lua
local definitions = {
	{ id = "Slimes", next = "Gems", rewards = { coins = 50 },
		objectives = { { id = "kill", kind = "count", event = "EnemyDefeated", target = "Slime", amount = 3 } } },
	{ id = "Gems", prerequisites = { "Slimes" },
		objectives = {
			{ id = "gems", kind = "collect", target = "Gem", amount = 2 },
			{ id = "cave", kind = "reach", target = "Cave" },
		} },
	{ id = "DailyWin", daily = true, objectives = { { id = "win", kind = "count", event = "RoundWon" } } },
	{ id = "Grind", repeatable = true, cooldown = 600, objectives = { { id = "k", kind = "count", event = "EnemyDefeated" } } },
}
```

| Objective kind | Matches events | Needs |
| --- | --- | --- |
| `count` | `{ type = objective.event, target = ? }` (target filter optional) | `event` |
| `collect` | `{ type = "collect", target = itemId, amount = n }` | `target` |
| `reach` | `{ type = "reach", target = locationId }` | `target` (amount is always 1) |

Quest fields: `prerequisites`, `next`, `autoStartNext` (default true), `repeatable`, `cooldown`, `daily`, `timeLimit`, `rewards` (opaque, passed to your callback).

## API

| Function | Returns | Notes |
| --- | --- | --- |
| `QuestsLogic.validateDefinitions(defs)` | `ok, errors` | duplicate ids, bad objectives, unknown prerequisites or `next`, prerequisite cycles |
| `QuestsLogic.newCatalog(defs)` | `Catalog` | errors with every problem when invalid |
| `QuestsLogic.newState()` | `PlayerState` | |
| `QuestsLogic.canStart(catalog, state, id, now, config?)` | `ok, reason` | reasons: unknown quest, already active, too many active quests, prerequisites not met, already completed, on cooldown, already done today |
| `QuestsLogic.start(...)` / `abandon(state, id)` | `ok, reason` / `boolean` | |
| `QuestsLogic.handleEvent(catalog, state, event, now, config?)` | `{ updated, completed, started }` | completes quests and auto-starts chains |
| `QuestsLogic.expire(catalog, state, now)` | expired ids | for `timeLimit` quests |
| `QuestsLogic.available(...)`, `progressOf(...)` | ids, rows | for UI |
| `QuestsLogic.serialize(state)` / `deserialize(data, catalog)` | data / state | deserialize sanitises untrusted data |
| `QuestsServer.new(options)` | `Service` | see below |
| `service:recordEvent(player, event)` | `EventResult` | call from your combat, pickup and zone code |
| `service:start(player, id)`, `service:abandon(player, id)`, `service:getState(player)` | | |
| `QuestsClient.new(remoteFolder?)` | `Client` | `client.changed`, `client:start(id)`, `client:abandon(id)` |

## Config (`QuestsConfig.luau`)

| Key | Default | Meaning |
| --- | --- | --- |
| `dayLength` | 86400 | seconds per quest day |
| `dayOffset` | 0 | seconds after 00:00 UTC when the day rolls over |
| `maxActive` | 20 | active quest limit |
| `remoteFolder` | `"UrkQuests"` | ReplicatedStorage folder for remotes |
| `requestCapacity` / `requestRefillPerSecond` | 10 / 2 | per-player rate limit for client requests |

## Example

```lua
local QuestsServer = require(ReplicatedStorage.UltimateRobloxKit.Systems.Quests.QuestsServer)
local quests = QuestsServer.new({
	definitions = definitions,
	autoStart = { "Slimes", "DailyWin" },
	store = { load = function(player) return profiles[player].Data.quests end,
		save = function(player, data) profiles[player].Data.quests = data end },
	grantReward = function(player, questId, rewards) Economy.add(player, rewards.coins or 0) end,
})
-- in combat code:
quests:recordEvent(player, { type = "EnemyDefeated", target = enemy.Name })
```

## Events and remotes

- `service.completed(player, questId)` and `service.progressed(player, questId)` (Util/Signal).
- `ReplicatedStorage.UrkQuests.State` (server to client): `(snapshot, availableIds)`.
- `ReplicatedStorage.UrkQuests.Request` (client to server): `("start" | "abandon", questId)`, validated with `Util/Validate` and rate limited.

## Persistence shape

```lua
{ version = 1,
  active = { [questId] = { startedAt = number, progress = { [objectiveId] = number } } },
  completed = { [questId] = { count = number, lastAt = number } } }
```

## Limitations

- Times are wall-clock seconds from `os.time()` (override with `options.clock`). Daily resets use UTC plus `dayOffset`.
- `collect` objectives count pickups; they do not watch the inventory, so dropping an item does not undo progress.
- Expired timed quests stay active (and ignore events) until `QuestsLogic.expire` runs; call it from a timer if you use `timeLimit`.
- Rewards are granted once per completion through your callback. If the callback errors, the quest is still completed and a warning is printed, so make the callback reliable or idempotent.

## Needs a Studio playtest

The remotes, PlayerAdded/PlayerRemoving flow, store calls and the client mirror are only checked by Selene and StyLua. Lune tests cover `QuestsLogic`.
