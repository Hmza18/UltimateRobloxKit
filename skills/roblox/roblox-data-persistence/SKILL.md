---
name: roblox-data-persistence
description: Saving player data in Roblox - DataStoreService with UpdateAsync, session locking, retries with backoff, request budgets, BindToClose, schema versions and migrations, ProfileStore (MadStudioRoblox) as the recommended library, OrderedDataStore leaderboards, right-to-erasure handling and Studio API access for testing. Use when adding saved data, fixing data loss or duplication, building a leaderboard or migrating a save format.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [datastore, profilestore, updateasync, session lock, bindtoclose, ordereddatastore, leaderboard, data loss, save data, migration, lose data, lose their data, player data, data not saving]
  depends: [luau-language, roblox-architecture]
---

# Roblox data persistence

## When to use

- A player's progress, currency, inventory or settings must survive leaving the game.
- Players report lost progress, duplicated items, or "data not loading".
- Building a global leaderboard, or changing the shape of saved data.

When not to use: cross-server live state such as matchmaking queues (MemoryStoreService, see `roblox-teleport-matchmaking`), purchase receipts logic (see `roblox-inventory-economy`, which builds on this skill).

## Inputs

- The saved data shape (a template table) and its current schema version.
- Whether the place is published and Studio API access is enabled (required to test DataStores in Studio).

## Workflow

1. **Enable Studio access**: Home > Game Settings > Security > "Enable Studio Access to API Services". Studio writes go to the real live DataStores of that experience; use a separate test place or a key prefix such as `STUDIO_` for experiments.
2. **Use ProfileStore** for player data (recommended). It handles session locking, auto-save, BindToClose and retries. Install from its GitHub releases (MadStudioRoblox/ProfileStore) or via Wally; verify the current Wally package name and version on wally.run before adding it to `wally.toml`. Copy [templates/DataService.luau](templates/DataService.luau).
3. **Define a template with a version field** and write migrations as pure functions `vN -> vN+1`. Run them after load, before `Reconcile`.
4. **Expose data through the data service only.** Other services call `DataService.get(player)` and mutate the returned table; no other module touches DataStores.
5. **Mirror display values** to attributes for the client (see `roblox-networking`).
6. **Leaderboards** use a separate OrderedDataStore updated at intervals, never on every change.

### Without a library: UpdateAsync with retries

If you cannot use ProfileStore, write every save with `UpdateAsync`, check the budget and retry with backoff. `SetAsync` overwrites blindly and loses data written by another server.

```luau
--!strict
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("PlayerData_v1")

local MAX_ATTEMPTS = 5

local function waitForBudget(requestType: Enum.DataStoreRequestType)
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 do
		task.wait(1)
	end
end

-- transform receives the current stored value (or nil) and returns the new value,
-- or nil to cancel the write. It may run more than once, so it must not yield or
-- have side effects.
local function update(key: string, transform: (any) -> any): (boolean, any)
	local delay = 1
	for attempt = 1, MAX_ATTEMPTS do
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(old: any, _keyInfo: DataStoreKeyInfo?)
				return transform(old)
			end)
		end)
		if ok then
			return true, result
		end
		warn(`UpdateAsync {key} attempt {attempt} failed: {result}`)
		if attempt < MAX_ATTEMPTS then
			task.wait(delay + math.random())  -- jitter avoids synchronized retries
			delay = math.min(delay * 2, 30)
		end
	end
	return false, nil
end

return { update = update }
```

A hand-rolled system also needs session locking: store `{ lockedBy = game.JobId, lockedAt = os.time() }` inside the value, refuse to load if another live JobId holds a recent lock, and clear it on release. This is exactly what ProfileStore already does; prefer it.

### Schema versioning

```luau
--!strict
local CURRENT_VERSION = 3

local migrations: { [number]: (any) -> any } = {
	[1] = function(d) d.coins = d.money or 0; d.money = nil; return d end,     -- v1 -> v2
	[2] = function(d) d.inventory = d.inventory or {}; return d end,           -- v2 -> v3
}

local function migrate(data: any): any
	local v = data.version or 1
	while v < CURRENT_VERSION do
		data = migrations[v](data)
		v += 1
	end
	data.version = CURRENT_VERSION
	return data
end
```

Never delete a migration once shipped; old saves may still be at v1. A server running older code must not save a newer version over it: if `data.version > CURRENT_VERSION`, load read-only and do not save.

### OrderedDataStore leaderboard

```luau
--!strict
local DataStoreService = game:GetService("DataStoreService")
local wins = DataStoreService:GetOrderedDataStore("Wins_v1")

local function submit(userId: number, value: number)
	pcall(function()
		wins:SetAsync(tostring(userId), math.floor(value)) -- integers only
	end)
end

local function top(n: number): { { key: string, value: number } }
	local ok, pages = pcall(function()
		return wins:GetSortedAsync(false, math.clamp(n, 1, 100))
	end)
	if not ok then
		return {}
	end
	return (pages :: DataStorePages):GetCurrentPage() :: any
end
```

Refresh the board every 60 seconds or more, and submit on leave or at intervals.

### Right-to-erasure (GDPR/CCPA) requests

Roblox notifies experience owners when a user asks for their data to be deleted. You must remove every key holding that user's data (main store, ordered stores, backups). Store keys by UserId, call `profile:AddUserId(userId)` (ProfileStore) or pass user ids in `SetAsync`/`UpdateAsync` options, and keep a short runbook script that deletes a given UserId from each store with `RemoveAsync`. Check the current notification channel and Open Cloud deletion options in creator docs.

## Outputs

- `src/server/Services/DataService.luau` (from the template), a template table with `version`, a migrations table and, if needed, a leaderboard module.

## Validation

1. In Studio with API access on, play, change data, stop, play again: the change persists.
2. Run two Studio test servers (or a live server and Studio) with the same account; the second waits for or steals the session cleanly and no data is duplicated.
3. Stop the server during play (Studio stop button or shut down all servers): Output shows the profile released before close.
4. Load an old save shape through `migrate` in a unit test; the result matches the current template.
5. Watch for "DataStore request was added to queue" warnings in Output; they mean you exceed the budget.

## Pitfalls

- **Saving on every change** exhausts the budget. Mutate in memory; the library or a 60 to 300 second interval saves.
- **SetAsync after GetAsync** races with other servers and loses items. Use UpdateAsync or ProfileStore.
- **Yielding or side effects inside the UpdateAsync callback**. It can run several times; keep it pure.
- **Missing BindToClose**: without it, shutdown loses the last minutes of data. ProfileStore binds it for you; hand-rolled code must save all players in parallel there (about 30 seconds are available).
- **Non-serializable values**: Instances, Vector3, CFrame, functions and mixed tables cannot be saved. Store plain numbers, strings, booleans and tables; convert vectors to `{x, y, z}`.
- **Key size and value size limits** exist (values about 4 MB). Do not save logs in the profile.
- **Kicking a player whose profile failed to load** is correct; letting them play on a blank profile and saving it erases their real data.

## Limitations

- DataStore limits and budget formulas change; verify current numbers in creator docs (Data stores > Limits).
- This skill cannot test against live production data safely; use a separate test experience for destructive tests.
- ProfileStore's API is summarized from its public docs; check its README for the version you install.
