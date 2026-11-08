# Teams

Team assignment and balancing (by player count, optionally by skill), friendly-fire and self-damage rules, team scores and standings. The server adapter drives Roblox's `Teams` service so the default leaderboard and team colours work.

| File | Runs on | Role |
| --- | --- | --- |
| `TeamsLogic.luau` | anywhere (pure) | assignment, join rules, snake-draft balance, rebalance moves, damage rules, scores |
| `TeamsServer.luau` | server | Team instances, auto-assign, `canDamage`, scores as attributes, optional SwitchTeam remote |

## API

| Function | Returns | Notes |
| --- | --- | --- |
| `TeamsLogic.new({ "Red", { name = "Blue", maxSize = 8 } })` | `State` | |
| `assign(state, playerId, skill?, useSkill?)` | team or nil | smallest team with room; ties by lower total skill (with `useSkill`) or list order |
| `pickTeam(state, useSkill?)` | team or nil | nil when every team is full |
| `join(state, playerId, team, skill?, maxImbalance?)` | `ok, reason` | reasons: unknown team, already on that team, team is full, teams would be unbalanced |
| `remove(state, playerId)` | old team | |
| `balance(players, teamNames, useSkill?)` | `{ [playerId] = team }` | snake draft by skill, or round robin by id |
| `rebalance(state, maxImbalance?)` | `{ { playerId, from, to } }` | moves the player that best evens total skill |
| `canDamage(rules, attackerId, victimId, attackerTeam?, victimTeam?)` | boolean | `rules = { friendlyFire?, selfDamage? }`; players without a team can always be hit by others |
| `addScore(state, team, amount)`, `resetScores`, `standings`, `leader` | | `leader` is nil on a tie |
| `size`, `totalSkill`, `teamOf`, `membersOf` | | |
| `TeamsServer.new(options)` | `Service` | `teamOf`, `setTeam` (ignores balance), `canDamage(attacker, victim)`, `addScore`, `leader`, `shuffle`, `rebalance`, `state`, `changed`, `destroy` |

## Config (TeamsServer options)

| Key | Default | Meaning |
| --- | --- | --- |
| `teams` | required | `{ { name, color = BrickColor.new("Bright red"), maxSize? } }` |
| `autoAssign` | true | assign on join |
| `useSkill` / `skillOf` | false / nil | skill-aware ties and shuffles |
| `friendlyFire` / `selfDamage` | false / false | damage rules |
| `allowSwitching` | false | create `ReplicatedStorage.UrkTeams.SwitchTeam` |
| `maxImbalance` | 1 | for client switches and `rebalance` |

## Example

```lua
local teams = TeamsServer.new({
	teams = { { name = "Red", color = BrickColor.new("Bright red") }, { name = "Blue", color = BrickColor.new("Bright blue") } },
	useSkill = true,
	skillOf = function(player) return PlayerData.get(player).rating end,
	allowSwitching = true,
})
-- in damage code:
if teams:canDamage(attacker, victim) then humanoid:TakeDamage(damage) end
-- on a capture:
teams:addScore(teams:teamOf(player), 1)
```

## Events and remotes

- `service.changed(player, teamName?)` after any assignment change.
- `ReplicatedStorage.UrkTeams.SwitchTeam` (client to server, only with `allowSwitching`): `(teamName)`, validated against the team list and rate limited (3 burst, one every 2 seconds).
- Each `Team` instance carries a `Score` attribute.

## Persistence

None. Teams are per server; save scores yourself if they matter across sessions.

## Limitations

- Team colours must be unique in Roblox; give each team its own `color` (a random colour is used otherwise).
- `shuffle` ignores `maxSize` during the draft and falls back to `assign` for players whose drafted team is full.
- Damage rules only answer the question; your weapons must call `canDamage`.

## Needs a Studio playtest

Team instances, `player.Team` assignment, the leaderboard, attributes and the SwitchTeam remote are unverified outside Studio. Lune tests cover `TeamsLogic`.
