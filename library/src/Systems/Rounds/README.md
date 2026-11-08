# Rounds

A round loop for any round-based game: Intermission, Starting, InProgress, Ending, then back to Intermission. It waits for a minimum player count, runs timers, ends rounds through your win check, on time or when players run out, and runs map voting with a random tie-break. The server publishes the state as attributes so any client UI can show it.

| File | Runs on | Role |
| --- | --- | --- |
| `RoundsLogic.luau` | anywhere (pure) | phase machine, timers, results, voting |
| `RoundsServer.luau` | server | update loop, attributes on `ReplicatedStorage.UrkRounds`, Vote remote |
| `RoundsClient.luau` | client | attribute reader, `timeLeft()`, `vote(option)` |
| `RoundsConfig.luau` | anywhere | defaults |

## Phases

| Phase | Leaves when | Goes to |
| --- | --- | --- |
| Intermission | timer ends with at least `minPlayers` (the timer restarts while short of players, `Waiting = true`) | Starting (the vote is tallied into `Map`) |
| Starting | timer ends; or players drop below `minPlayers` | InProgress (`Round` + 1); or back to Intermission |
| InProgress | `checkWinner` returns non-nil (`"win"`), players below `minPlayersToContinue` (`"abandoned"`), timer ends (`"timeout"`), `forceEnd` (`"forced"`) | Ending |
| Ending | timer ends | Intermission (`Map` cleared, a new vote opens) |

## API

| Function | Returns | Notes |
| --- | --- | --- |
| `RoundsLogic.resolveConfig(overrides?)` | `Config` | |
| `RoundsLogic.new(config, now)` | `State` | |
| `RoundsLogic.update(state, config, { now, playerCount, checkWinner?, rng? })` | `Change?` | at most one phase change per call |
| `RoundsLogic.forceEnd(state, config, now, winner?)` | `Change?` | only during InProgress |
| `RoundsLogic.timeLeft(state, now)` | seconds | |
| `RoundsLogic.openVote(state, options)`, `castVote(state, voterId, option)`, `removeVoter`, `counts(vote)`, `tally(vote, rng?)` | | votes only during Intermission; one ballot per voter, replaceable |
| `RoundsServer.new({ config?, maps?, mapsPerVote?, countPlayers?, checkWinner? })` | `Service` | `service:state()`, `service:forceEnd(winner?)`, `service.phaseChanged`, `service:destroy()` |
| `RoundsClient.new(folderName?)` | `Client` | `client.changed`, `client:snapshot()`, `client:timeLeft()`, `client:vote(option)` |

## Config (`RoundsConfig.luau`)

| Key | Default | Meaning |
| --- | --- | --- |
| `minPlayers` | 2 | needed to leave Intermission |
| `intermissionTime` / `startingTime` / `roundTime` / `endingTime` | 15 / 5 / 180 / 8 | seconds |
| `minPlayersToContinue` | 1 | below this the round is abandoned |
| `folderName` | `"UrkRounds"` | ReplicatedStorage folder for attributes and the Vote remote |
| `updateInterval` | 0.2 | seconds between updates |
| `voteCapacity` / `voteRefillPerSecond` | 5 / 1 | vote rate limit per player |

## Example

```lua
local rounds = RoundsServer.new({
	config = { minPlayers = 2, roundTime = 120 },
	maps = { "Desert", "Forest", "Harbor", "Ruins" },
	mapsPerVote = 3,
	countPlayers = function() return #Teams.activePlayers() end,
	checkWinner = function(state)
		local alive = aliveTeams()
		return if #alive == 1 then alive[1].Name else nil
	end,
})
rounds.phaseChanged:Connect(function(change, state)
	if change.to == "InProgress" then MapLoader.load(state.map or "Desert") end
	if change.to == "Intermission" then MapLoader.unload() end
end)
```

Client: `RoundsClient.new().changed:Connect(function(snap) label.Text = snap.phase end)`.

## Events and attributes

- `service.phaseChanged(change, state)` with `change = { from, to, round, result?, map? }`.
- Attributes on `ReplicatedStorage.UrkRounds`: `Phase`, `PhaseEndsAt` (server time from `workspace:GetServerTimeNow()`), `Round`, `Waiting`, `Map`, `Winner` (string), `Reason`, `VoteOptions` and `VoteCounts` (JSON strings).
- `ReplicatedStorage.UrkRounds.Vote` (client to server): `(option)`, validated and rate limited.

## Persistence

None. Round state is per server.

## Limitations

- `Winner` is published with `tostring`; publish richer results yourself from `phaseChanged`.
- `checkWinner` runs every update (default 5 times a second); keep it cheap.
- Map loading, teleporting players to spawns and resetting characters are left to your `phaseChanged` handler.

## Needs a Studio playtest

The Heartbeat loop, attribute replication, JSON attributes and the Vote remote are unverified outside Studio. Lune tests cover `RoundsLogic`.
