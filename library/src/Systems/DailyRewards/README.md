# DailyRewards

Daily login rewards with streaks. Days come from server unix time in UTC plus one fixed, game-wide reset offset, so the client's clock and time zone never matter and every player shares the same day boundary. Supports grace days, cycling or capped reward tables, and refuses double claims and clocks that move backwards. `DailyRewardsLogic` is pure and immutable; `DailyRewardsServer` grants through a callback and commits the streak only after the grant succeeds.

## DailyRewardsLogic API

| Function | Returns | Notes |
| --- | --- | --- |
| `newConfig({ rewards, graceDays?, cycle?, resetOffsetSeconds? })` | `Config` | errors on an empty reward list or bad values |
| `new()` | `State` | `{ streak = 0, lastClaimDay = nil, totalClaims = 0 }` |
| `dayIndex(unix, offset?)` | `number` | `floor((unix - offset) / 86400)` |
| `nextReset(unix, offset?)` | `number` | unix time the next day starts |
| `rewardIndex(config, streak)` | `number` | cycles, or stays on the last reward when `cycle = false` |
| `status(config, state, now)` | `Status` | `{ canClaim, reason?, day, streak, rewardIndex, reward, streakWillReset, secondsUntilNext }` |
| `claim(config, state, now)` | `ClaimResult` | `{ ok, reason?, state, streak, rewardIndex, reward }` |
| `serialize(state)` / `deserialize(raw)` | | |

Streak rule: with `gap = today - lastClaimDay`, a gap of `0` is `"already claimed"`, a negative gap is `"clock went backwards"`, `1 + graceDays` or less continues the streak, and anything longer starts again at 1. A non-finite `now` is `"invalid time"`.

## Config

| Key | Default | Meaning |
| --- | --- | --- |
| `rewards` | required | any payloads, for example `{ { currency = "Coins", amount = 100 }, ... }` |
| `graceDays` | `0` | missed days allowed before the streak resets |
| `cycle` | `true` | after the last reward, start again at the first |
| `resetOffsetSeconds` | `0` | day boundary after 00:00 UTC, between -86400 and 86400 exclusive |

Server config: `config`, `grant(player, reward, streak) -> boolean` (required), `store?`, `clock = os.time`, `remoteFolderName = "URK_DailyRewards"` (RemoteFunctions `Claim()` and `GetStatus()`), `saveAfterClaim = true`.

Server methods: `status(player)`, `claim(player)`, `loadPlayer(player)`, `destroy()`. A player whose data failed to load cannot claim, so a DataStore outage never hands out a second reward.

## Events

`Claimed(player, reward, streak)`.

## Example

```luau
local daily = DailyRewardsServer.new({
	config = DailyRewardsLogic.newConfig({
		rewards = { 50, 75, 100, 150, 200, 300, 500 }, -- coins for days 1..7
		graceDays = 1,
	}),
	grant = function(player, coins, streak)
		local result = currency:add(player, "Coins", coins, "daily:" .. streak)
		return result ~= nil and result.ok
	end,
})
```

Client: `local result = ReplicatedStorage.URK_DailyRewards.Claim:InvokeServer()`; show `GetStatus().secondsUntilNext` as a countdown.

## Persistence shape

```luau
{ v = 1, s = 4, d = 20454, t = 12 } -- streak, last claim day index, total claims
```

## Limitations

- One reward per day; no "claim missed days" or premium tracks.
- The grant and the save are separate steps. If the server crashes between them, the claim can repeat once that day. Storing this state in the same record as the reward (SaveData) avoids it.
- Changing `resetOffsetSeconds` after launch shifts every player's day once.

## Needs a Studio playtest

RemoteFunction calls, the save after a claim and the client countdown. Lune covers `DailyRewardsLogic`, including day boundaries.
