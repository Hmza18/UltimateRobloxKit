# Leaderboards

Global and in-server leaderboards. `LeaderboardsLogic` is pure: sorting and ranks with three tie modes, top-N, a write queue that throttles OrderedDataStore writes per player and per request budget, integer and log score encoding, and parsing of OrderedDataStore pages. `LeaderboardsServer` runs the OrderedDataStore loop, ranks players in the current server and builds the `leaderstats` folder shown in the player list.

## LeaderboardsLogic API

| Function | Returns | Notes |
| --- | --- | --- |
| `rank(entries, options?)` | `{ RankedEntry }` | entries `{ key, score, name? }`; options `{ descending? = true, ties? = "competition" }`; drops non-finite scores |
| `top(entries, n, options?)` | `{ RankedEntry }` | |
| `find(ranked, key)` | `RankedEntry?` | |
| `newQueue(minInterval)` | `WriteQueue` | seconds between writes for one key |
| `queueScore(queue, key, score)` | `boolean` | keeps the newest score per key |
| `takeBatch(queue, now, budget)` | `{ { key, score } }` | due and changed scores only, at most `budget`, sorted by key |
| `requeue(queue, write)` / `forget(queue, key)` | | retry a failed write / drop a key |
| `encode(score, decimals?)` / `decode(stored, decimals?)` | | whole numbers clamped to +/- 2^53 |
| `encodeLog(score, precision?)` / `decodeLog(stored, precision?)` | | order-preserving, approximate (about 0.01% with precision 10000) |
| `fromPage(items, keyPrefix?, decimals?)` | `{ Entry }` | items from `DataStorePages:GetCurrentPage()` |

Tie modes for scores 100, 50, 50, 30: `"competition"` 1, 2, 2, 4; `"dense"` 1, 2, 2, 3; `"ordinal"` 1, 2, 3, 4. Equal scores are ordered by key, so results are deterministic. The queue functions modify the queue you pass.

## Server config

| Key | Default | Meaning |
| --- | --- | --- |
| `storeName`, `scope?` | required | OrderedDataStore |
| `getScore(player)` | required | number, or nil to skip |
| `keyPrefix` | `""` | key = prefix .. UserId |
| `decimals` | `0` | digits kept by integer encoding |
| `useLog` | `false` | log encoding for scores past 2^53 |
| `ascending` | `false` | lowest first (speedruns) |
| `topN` | `50` | 1..100 entries read |
| `writeInterval` | `60` | seconds between writes per player |
| `flushInterval` | `30` | seconds between write batches |
| `refreshInterval` | `120` | seconds between top-N reads |
| `budgetReserve` | `5` | `SetIncrementSortedAsync` budget left for other code |
| `remoteFolderName` | `"URK_Leaderboard_<storeName>"` | RemoteEvent `Updated(top)`, RemoteFunction `GetTop()` |

Server methods: `flush() -> written`, `refresh() -> ok`, `getTop()`, `serverRanking()`, `destroy()`. Helpers: `LeaderboardsServer.leaderstats(player, { { name, kind? = "IntValue", value? } })` and `LeaderboardsServer.setStat(player, name, value)`. Display names come from `Players:GetNameFromUserIdAsync` and are cached per server.

## Events

`Updated(top)` where each entry is `{ key, score, name, rank }`.

## Example

```luau
local board = LeaderboardsServer.new({
	storeName = "TopCoins",
	getScore = function(player)
		return currency:balance(player, "Coins")
	end,
	useLog = true, -- idle-game numbers
})
Players.PlayerAdded:Connect(function(player)
	LeaderboardsServer.leaderstats(player, { { name = "Coins", kind = "NumberValue" } })
end)
board.Updated:Connect(function(top)
	-- Draw top[1..n] on a SurfaceGui.
end)
```

## Persistence

The OrderedDataStore itself: one whole number per key.

## Limitations

- OrderedDataStore values are integers; fractional scores need `decimals` or `useLog`, and log-encoded scores are approximate.
- Writes are throttled, so the global board lags behind live scores by up to `writeInterval + flushInterval` seconds.
- Only the first page (at most 100 entries) is read. A player's own global rank outside the top N is not available from OrderedDataStore without paging.
- Name lookups yield; the first refresh after start can take a few seconds.

## Needs a Studio playtest

OrderedDataStore reads and writes (enable Studio Access to API Services), budget behaviour under load, the leaderstats folder in the player list, and the remotes. Verify `GetSortedAsync`, `GetCurrentPage`, `GetRequestBudgetForRequestType` and `Enum.DataStoreRequestType.SetIncrementSortedAsync` in the creator docs. Lune covers `LeaderboardsLogic`.
