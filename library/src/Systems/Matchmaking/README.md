# Matchmaking

Queue players (solo or as parties) across servers and send each assembled match to a reserved server. The rules are pure and tested: skill buckets, a skill window that widens with waiting time, party integrity (parties never split across teams), mode or region buckets, partial matches after a wait, expiry and retry backoff. The server adapter uses MemoryStoreService and TeleportService.

| File | Runs on | Role |
| --- | --- | --- |
| `MatchmakingLogic.luau` | anywhere (pure) | tickets, validation, skill windows, team filling, match assembly, encoding, backoff |
| `MatchmakingServer.luau` | server (lobby place) | MemoryStore queue, matchmaker lock, ReserveServer, TeleportAsync with retries |
| `MatchmakingConfig.luau` | anywhere | defaults |

## How matching works

1. Tickets are taken oldest first. Each one in turn is the anchor.
2. A ticket is compatible with the anchor when it is in the same bucket and the skill gap is within the larger of the two tickets' windows: `min(maxSkillWindow, baseSkillWindow + waited * widenPerSecond)`.
3. Teams are filled with the anchor first, then larger parties, then older tickets. A party always lands in one team; a party bigger than `teamSize` is refused at enqueue.
4. A match forms when every team is full. If `minPlayers > 0`, a partly filled match may also form once the anchor has waited `fillAfter` seconds and at least `minPlayers` players are available.

## API

| Function | Returns | Notes |
| --- | --- | --- |
| `MatchmakingLogic.newQueue(config?)` / `resolveConfig(config?)` | `Queue` / `Config` | |
| `enqueue(queue, { id, players = { userIdString }, skill, bucket? }, now)` | `ok, reason` | reasons: ticket needs an id, duplicate ticket, skill must be a finite number, ticket needs players, party is larger than a team, player listed twice, player already queued |
| `dequeue(queue, ticketId)` / `dequeuePlayer(queue, playerId)` | ok / ticketId | removing one member removes the party |
| `skillWindow(config, waited)`, `compatible(config, a, b, now)` | | |
| `assemble(queue, now)` | `{ Match }` | removes matched tickets; `Match = { bucket, teams, ticketIds, players, averageSkill, full, createdAt }` |
| `expire(queue, now)` | removed ids | older than `maxWait` |
| `encodeTicket(ticket)` / `decodeTicket(raw)` / `restore(queue, ticket)` | | storage round trip; decode rejects malformed data |
| `backoff(attempt, base, maxDelay, random)` | seconds | exponential with 50 to 100 percent jitter |
| `MatchmakingServer.new({ placeId, config?, skillOf?, teleportData? })` | `Service` | `service:queue(players, bucket?)`, `cancel(player)`, `isQueued(player)`, `matched`, `failed`, `destroy()` |

## Config (`MatchmakingConfig.luau`)

| Key | Default | Meaning |
| --- | --- | --- |
| `teamCount` / `teamSize` | 2 / 4 | match shape |
| `baseSkillWindow` / `widenPerSecond` / `maxSkillWindow` | 100 / 10 / 1000 | skill window |
| `fillAfter` / `minPlayers` | 60 / 0 | partial matches (0 = full only) |
| `maxWait` | 300 | seconds before a ticket is dropped |
| `mapName` | `"UrkMatchmaking"` | MemoryStore maps `<mapName>Tickets`, `<mapName>Assignments`, `<mapName>Lock` |
| `pollInterval` | 2 | seconds between polls |
| `ticketTtl` / `lockTtl` | 360 / 10 | MemoryStore expirations |
| `teleportRetries` / `retryBaseDelay` / `retryMaxDelay` | 4 / 1 / 15 | ReserveServer and teleport retries |

## Example

```lua
local matchmaking = MatchmakingServer.new({
	placeId = 1234567890, -- the arena place in the same experience
	config = { teamCount = 2, teamSize = 3, minPlayers = 4, fillAfter = 45 },
	skillOf = function(player) return PlayerData.get(player).rating end,
	teleportData = function(match) return { teams = match.teams } end,
})
queueRemote.OnServerEvent:Connect(function(player)
	matchmaking:queue(Party.membersOf(player), "ranked") -- validate who may queue a party first
end)
matchmaking.failed:Connect(function(player, reason) warn(player.Name, reason) end)
```

In the match place, read `player:GetJoinData().TeleportData` and treat it as untrusted (verify team membership server-side if it matters).

## Events

`service.matched(players, assignment)` fires just before this server teleports a ticket's players. `service.failed(player, reason)` fires when a teleport gives up.

## Persistence shape

Tickets live only in MemoryStore: `{ id, players = { "userId" }, skill, bucket, enqueuedAt }` with `ticketTtl` expiry. Assignments: `{ placeId, accessCode, teams, data }` with a 120 second expiry.

## Limitations

- The matchmaker reads one page of 200 tickets per poll; larger queues need paging or sharding by bucket.
- Times use `os.time()`; server clocks can differ by a second or two, which only shifts the skill window slightly.
- Team filling is greedy, so an exotic mix of party sizes can wait for another poll even when a perfect packing exists.
- Party membership comes from your code; the adapter trusts the `players` list you pass to `queue`.

## Verify in the Roblox docs before shipping

- MemoryStore limits and quotas (request units per minute, item size, sorted map `GetRangeAsync` count limit of 200).
- `MemoryStoreSortedMap:UpdateAsync` semantics when the transform returns nil (we rely on it leaving the lock unchanged).
- `TeleportService:ReserveServer` and `TeleportAsync` with `TeleportOptions.ReservedServerAccessCode`, and the `TeleportInitFailed` retry pattern.
- Teleports and `ReserveServer` do not work in Studio play tests; test in a published experience with two places.

## Needs a Studio playtest

Everything in `MatchmakingServer.luau` (MemoryStore calls, locking, teleports) is unverified outside a live game. Lune tests cover `MatchmakingLogic`.
