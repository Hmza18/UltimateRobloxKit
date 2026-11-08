# Progression patterns

## Weekly reset

```lua
--!strict
-- Week index starting Monday 00:00 UTC. 1970-01-01 was a Thursday, so shift by 3 days.
local function weekIndex(unix: number): number
	return (unix // 86400 + 3) // 7
end
return weekIndex
```

On load, if `profile.weekly.week ~= weekIndex(os.time())`, clear weekly quest state and assign new ones from a seeded pick: `Random.new(weekIndex(os.time()) * 7919)` so every server offers the same weekly set.

## Quest chains

Give each definition `requires = { "QuestA" }`. The quest giver offers a quest only when every required quest has `done = true`. Keep chains as data so designers can reorder without code changes.

## Claiming rewards safely

Separate `done` (objectives met) from `claimed` (reward granted). The claim remote:

1. Checks `done and not claimed` on the server.
2. Sets `claimed = true` **before** granting, then grants via the economy service.
3. Saves. If the server crashes between steps, the worst case is a lost reward, never a duplicated one; support can re-grant.

## Streak with a grace day

```lua
--!strict
local function nextStreak(lastDay: number, streak: number, today: number, graceUsed: boolean): (number, boolean)
	if today == lastDay + 1 then
		return streak + 1, graceUsed
	elseif today == lastDay + 2 and not graceUsed then
		return streak + 1, true -- one missed day forgiven per streak
	end
	return 1, false
end
return nextStreak
```

## Daily reward table

Make the reward table a list indexed by `((streak - 1) % #table) + 1` so it loops after the last day. Show the whole table in UI so players know what is coming; do not hide that missing a day resets the streak.

## Ethics

Daily rewards and streaks should reward play, not punish absence. Avoid streak-loss messaging designed to pressure, and never sell "streak protection" aimed at anxiety. See `monetization-economy-design`.
