# SaveData

Player data persistence: schema versions with a migration chain, reconciling defaults, session-lock decisions, retries with exponential backoff, request-budget awareness, autosave and a BindToClose flush. `SaveDataLogic` is pure (the clock, sleep and random source are injected) and decides what each UpdateAsync transform writes. `SaveDataServer.dataStoreStore` is a DataStore adapter that implements the kit's store interface; `SaveDataServer.new` manages player sessions on top of any store.

**For production games we recommend [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore)** (Apache-2.0, by loleris; Wally `lm-loleris/profilestore@1.0.3`). It has years of live use behind its session locking, auto-saving and edge cases (MessagingService session handoff, DataStore outages). This module is small, readable and tested, and is a good default for prototypes and smaller games; it also documents below how to plug ProfileStore in as the store, so the rest of the kit does not change.

## SaveDataLogic API

| Function | Returns | Notes |
| --- | --- | --- |
| `newSchema({ version, defaults, migrations? })` | `Schema` | errors unless `migrations[n]` exists for every `n < version` |
| `defaults(schema)` | table | deep copy |
| `deepCopy(value)` | any | |
| `reconcile(data, defaults)` | table | adds missing keys, replaces wrong types, recurses into non-empty default tables, keeps extra keys |
| `migrate(schema, data, fromVersion)` | `(data?, reason?)` | each migration gets a copy; refuses data from a newer version |
| `load(schema, raw)` | `(data?, reason?)` | `nil` gives defaults; a table without `schemaVersion` is legacy version 1 data |
| `lockState(record, jobId, now, timeout?)` | `"free" \| "own" \| "stale" \| "held"` | stale = heartbeat older than `timeout` (default 1800 s) |
| `planLoad(schema, old, jobId, now, timeout?)` | `LoadPlan` | `{ ok, reason?, record?, data }`; refuses `"held"` |
| `planSave(schema, old, jobId, data, now, release?)` | `SavePlan` | refuses when another server holds the lock; `release` clears the session |
| `backoff(attempt, base? = 1, max? = 16, rng?)` | seconds | `base * 2^(attempt-1)`, capped; jitter multiplies by 0.5..1 |
| `retry(callback, { attempts? = 5, base?, max?, sleep, rng? })` | `(ok, resultOrError, attempts)` | |
| `waitForBudget(getBudget, needed, sleep, maxWait)` | `boolean` | |

Reasons: `"corrupt record"`, `"invalid version"`, `"data is from a newer version"` (an old server must never overwrite newer data), `"missing migration from version N"`, `"migration from version N failed"`, `"locked by another server"`, `"session lock lost"`.

## Stored record

```luau
{
	schemaVersion = 3,
	data = { coins = 120, settings = { music = true } },
	session = { jobId = "<game.JobId>", lockedAt = 1767225600, heartbeatAt = 1767225720 }, -- nil when released
	updatedAt = 1767225720,
}
```

## Server API

`SaveDataServer.dataStoreStore(options) -> { load(userId), save(userId, data), release(userId, data) }`

| Option | Default | Meaning |
| --- | --- | --- |
| `name`, `scope?` | required | DataStore name and scope |
| `schema` | required | |
| `keyPrefix` | `"Player_"` | |
| `lockTimeout` | `1800` | seconds before a lock counts as abandoned |
| `lockRetries` | `5` | tries (6 s apart) to take a lock another server holds |
| `attempts` | `5` | retries per UpdateAsync with backoff 1, 2, 4, 8 s plus jitter |
| `sleep` | `task.wait` | |
| `jobId` | `game.JobId` (`"studio"` when empty) | |

`load` raises an error when the data cannot be read (outage, held lock, newer version), so callers never mistake a failure for a new player. Before each UpdateAsync it waits up to 30 s for `GetRequestBudgetForRequestType(UpdateAsync)`.

`SaveDataServer.new({ store, schema, autosaveSeconds? = 120, kickOnLoadFailure? = true })` returns a manager with `get(player)`, `update(player, fn)`, `save(player)`, `destroy()` and the events `Loaded(player, data)`, `LoadFailed(player, reason)`, `Saved(player, ok)`. Autosave also refreshes the session heartbeat. On leave and on BindToClose it calls `store.release` (or `save`).

## Example

```luau
local SaveDataLogic = require(Kit.Systems.SaveData.SaveDataLogic)
local SaveDataServer = require(Kit.Systems.SaveData.SaveDataServer)

local schema = SaveDataLogic.newSchema({
	version = 2,
	defaults = { wallet = { v = 1, b = {} }, inventory = {}, daily = {} },
	migrations = {
		[1] = function(data) -- v1 kept coins at the top level
			data.wallet = { v = 1, b = { Coins = data.coins or 0 } }
			data.coins = nil
			return data
		end,
	},
})

local saves = SaveDataServer.new({
	store = SaveDataServer.dataStoreStore({ name = "PlayerData", schema = schema }),
	schema = schema,
})
saves.Loaded:Connect(function(player, data)
	-- Hand each system its part, e.g. CurrencyLogic.deserialize(config, data.wallet).
end)
```

Other systems accept a `store`; to keep one record per player, give them nothing and store their `serialize(...)` output inside this record instead.

## Plugging in ProfileStore

Wrap ProfileStore in the same `{ load, save, release }` shape (verify the method names against the ProfileStore docs for your version):

```luau
local ProfileStore = require(path.to.ProfileStore)
local PlayerStore = ProfileStore.New("PlayerData", SaveDataLogic.defaults(schema))
local profiles = {}

local store = {
	load = function(userId)
		local player = game:GetService("Players"):GetPlayerByUserId(userId)
		local profile = PlayerStore:StartSessionAsync(tostring(userId), {
			Cancel = function() return player == nil or player.Parent == nil end,
		})
		if profile == nil then
			error("profile not loaded")
		end
		profile:AddUserId(userId)
		profile:Reconcile()
		profiles[userId] = profile
		local data, reason = SaveDataLogic.load(schema, { schemaVersion = profile.Data.schemaVersion or 1, data = profile.Data })
		if data == nil then error(reason) end
		return data
	end,
	save = function(userId, data)
		local profile = profiles[userId]
		if profile == nil or not profile:IsActive() then return false end
		profile.Data = data -- ProfileStore saves on its own schedule
		profile.Data.schemaVersion = schema.version
		return true
	end,
	release = function(userId, data)
		local profile = profiles[userId]
		profiles[userId] = nil
		if profile == nil then return false end
		profile.Data = data
		profile:EndSession()
		return true
	end,
}
local saves = SaveDataServer.new({ store = store, schema = schema })
```

ProfileStore then owns session locking and auto-saving; this module only supplies migrations and defaults.

## Limitations

- Session locking relies on UpdateAsync and the heartbeat; there is no MessagingService handoff, so a player who rejoins a new server quickly may wait for up to `lockRetries * 6` seconds while the old server releases.
- One key per player. Values must stay under the DataStore value size limit (verify the current limit in the creator docs).
- No automatic backups or version restore (DataStore versioning APIs can do this).
- `os.time()` is used for lock times; servers with skewed clocks shorten or lengthen the stale timeout.

## Needs a Studio playtest

Everything in `SaveDataServer`: UpdateAsync behaviour, budget waits, kicks on load failure, autosave and BindToClose (enable Studio Access to API Services). Lune covers `SaveDataLogic`.
