---
name: roblox-quests-progression
description: Player progression in Roblox - quests and objectives defined as data and tracked through server events, XP and level curves with formulas, achievements awarded through BadgeService, daily rewards and streaks computed from server time (os.time, DateTime), and save hooks for persistence. Use when adding quests, missions, XP, levels, achievements, badges, daily login rewards or streaks.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [quest, objective, xp, level curve, achievement, badge, badgeservice, daily reward, streak, progression]
  depends: [roblox-data-persistence, roblox-networking, game-design-core]
---

# Roblox quests and progression

## When to use

- Quest chains, daily/weekly tasks, tutorials with steps.
- XP, levels, prestige curves; achievements and Roblox badges.
- Daily login rewards and streaks.

When not to use: currencies and item grants go through `roblox-inventory-economy`; how data is saved is `roblox-data-persistence`; HUD and quest log UI are `roblox-ui-systems`; pacing decisions are `game-design-core`.

## Inputs

- Quest list (id, objectives, rewards, prerequisites, repeatability).
- XP sources and the target time to reach key levels (for example level 10 in 1 hour of play).
- Badge ids (created in Creator Hub; creating badges may cost Robux beyond a free daily allowance, verify in creator docs).
- The player data module that loads and saves a profile.

## Workflow

1. **Quests are data.** One `QuestDefinitions` ModuleScript in `ReplicatedStorage` (clients read it for UI), no logic inside. Each objective has a `kind` matching a gameplay event (`"Collect"`, `"Defeat"`, `"Visit"`) plus a `target` and `count`.
2. **Gameplay emits events, quests listen.** Gameplay code calls `Progress.record(player, "Defeat", "Slime", 1)` on the server after it has validated the action. The quest service is the only code that changes quest progress. Clients never report progress.
3. **Store progress compactly** in the profile: `quests = { [questId] = { counts = { [objectiveIndex] = n }, done = bool, claimedAt = number? } }`. Store ids, not definitions, so definitions can change.
4. **XP curve.** Pick a formula and keep it in one module (examples below). Award XP on the server, loop level-ups while XP exceeds the requirement, and fire one remote for UI.
5. **Badges.** Call `BadgeService:AwardBadge(userId, badgeId)` on the server in `pcall`, only after checking `UserHasBadgeAsync` (or your own saved flag) to avoid repeated calls. Record in your save that the achievement was earned even if the badge call fails, and retry the badge later.
6. **Daily rewards.** Use server time only: `os.time()` or `DateTime.now().UnixTimestamp` (UTC). Compute the day index as `os.time() // 86400`. Claimable when `today > lastClaimDay`; the streak continues when `today == lastClaimDay + 1`, else resets to 1.
7. **Persistence hooks.** The quest service reads and mutates the profile table handed to it by the data module and marks it dirty; it never calls DataStore itself.

### XP curves

| Curve | XP to go from level L to L+1 | Feel |
|---|---|---|
| Linear | `100 * L` | Steady, gets slow late |
| Polynomial | `floor(50 * L^1.5)` | Common default |
| Exponential | `floor(100 * 1.15^(L-1))` | Fast early, steep wall; cap or add prestige |
| Piecewise | polynomial to 50, then flat `5000` | Predictable endgame |

### Quest and level service

```lua
--!strict
-- ServerScriptService/Progression/Progress.luau (ModuleScript)
local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Definitions = require(ReplicatedStorage.Shared.QuestDefinitions)
local remote = ReplicatedStorage.Remotes.ProgressChanged :: RemoteEvent

export type QuestState = { counts: { [number]: number }, done: boolean }
export type Profile = {
	xp: number,
	level: number,
	quests: { [string]: QuestState },
	badges: { [string]: boolean },
	daily: { lastDay: number, streak: number },
}

local Progress = {}
local profiles: { [Player]: Profile } = {} -- filled by the data module via Progress.attach

function Progress.xpForLevel(level: number): number
	return math.floor(50 * level ^ 1.5)
end

function Progress.attach(player: Player, profile: Profile)
	profiles[player] = profile
end

function Progress.detach(player: Player)
	profiles[player] = nil
end

function Progress.awardBadge(player: Player, key: string, badgeId: number)
	local profile = profiles[player]
	if not profile or profile.badges[key] then
		return
	end
	profile.badges[key] = true -- record the achievement even if the badge call fails
	task.spawn(function()
		local okHas, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, badgeId)
		if okHas and has then
			return
		end
		local ok, err = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, badgeId)
		if not ok then
			warn("AwardBadge failed", key, err) -- retried on next join by re-checking profile.badges
		end
	end)
end

function Progress.addXp(player: Player, amount: number)
	local profile = profiles[player]
	if not profile or amount <= 0 or amount ~= amount then
		return
	end
	profile.xp += amount
	while profile.xp >= Progress.xpForLevel(profile.level) do
		profile.xp -= Progress.xpForLevel(profile.level)
		profile.level += 1
	end
	remote:FireClient(player, "Level", profile.level, profile.xp)
end

-- Called by trusted server gameplay code only.
function Progress.record(player: Player, kind: string, target: string, amount: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	for questId, def in Definitions do
		local state = profile.quests[questId]
		if state and not state.done then
			local allDone = true
			for i, objective in def.objectives do
				local have = state.counts[i] or 0
				if objective.kind == kind and objective.target == target then
					have = math.min(have + amount, objective.count)
					state.counts[i] = have
				end
				allDone = allDone and have >= objective.count
			end
			if allDone then
				state.done = true
				Progress.addXp(player, def.rewardXp)
				if def.badgeId then
					Progress.awardBadge(player, questId, def.badgeId)
				end
			end
			remote:FireClient(player, "Quest", questId, state)
		end
	end
end

function Progress.claimDaily(player: Player): (boolean, number)
	local profile = profiles[player]
	if not profile then
		return false, 0
	end
	local today = os.time() // 86400 -- UTC day index from server time
	local daily = profile.daily
	if today <= daily.lastDay then
		return false, daily.streak
	end
	daily.streak = if today == daily.lastDay + 1 then daily.streak + 1 else 1
	daily.lastDay = today
	return true, daily.streak
end

return Progress
```

Example definition entry: `FirstHunt = { objectives = { { kind = "Defeat", target = "Slime", count = 5 } }, rewardXp = 200, badgeId = nil }`. Quests start when your quest giver sets `profile.quests[id] = { counts = {}, done = false }` after checking prerequisites.

More: weekly resets, quest chains, offline-safe reward claiming, and a streak grace-day variant in [references/progression-patterns.md](references/progression-patterns.md).

## Outputs

- `QuestDefinitions` data module, `Progress` service, a `ProgressChanged` remote, profile schema fields.

## Validation

1. Lune unit tests for `xpForLevel`, level-up loop (huge XP grant crosses several levels), daily streak edges (same day, next day, skipped day, clock going backward).
2. Studio play: complete a quest, rejoin, progress persists (requires Studio API access enabled for DataStores).
3. Badges cannot be awarded in Studio for most setups; verify on a published test place and check the badge appears on the profile.

## Pitfalls

- **Client-reported progress** (`QuestProgress:FireServer("Defeat", "Boss")`): instant completion by exploiters. Record only from server-validated actions.
- **Client clock for dailies**: players change their device time. Use `os.time()` on the server.
- **Level-up uses `if` instead of `while`**: big XP grants lose levels.
- **Hard-coded definitions in saves**: changing a quest breaks old saves. Save ids and counts.
- **AwardBadge every kill**: wasteful and throttled. Gate with the saved flag.
- **Midnight-UTC surprise**: rewards reset at 00:00 UTC, not local midnight. Tell players in UI, or offset with a documented fixed timezone.

## Limitations

- XP curves need tuning with real playtime data; formulas here are starting points.
- BadgeService quotas and costs change; verify current limits in creator docs.
- This skill does not include the DataStore save layer; it assumes the profile is loaded and saved by `roblox-data-persistence`.
