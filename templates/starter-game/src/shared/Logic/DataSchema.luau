--!strict
-- Player save format, migrations and session-lock rules. Pure Luau, so Lune can test it.
-- PlayerDataService does the DataStore calls; this module only decides what the data should be.

local Inventory = require("./Inventory")

export type PlayerData = {
	coins: number,
	rebirths: number,
	inventory: Inventory.Inventory,
	-- Genre counters keyed by name, such as "upgrade:Power", "obby:stage" or "tycoon:Dropper2".
	progress: { [string]: number },
}

export type Lock = { jobId: string, time: number }

export type Record = { schemaVersion: number, data: PlayerData, lock: Lock? }

-- free: nobody holds the lock. own: this server does. stale: another server did but stopped refreshing it.
-- held: another server holds it right now.
export type LockState = "free" | "own" | "stale" | "held"

local DataSchema = {}

DataSchema.VERSION = 2
DataSchema.INVENTORY_CAPACITY = 24
DataSchema.MAX_STACK = 99
DataSchema.MAX_PROGRESS_KEYS = 500

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function DataSchema.default(): PlayerData
	return {
		coins = 0,
		rebirths = 0,
		inventory = Inventory.new(DataSchema.INVENTORY_CAPACITY, DataSchema.MAX_STACK),
		progress = {},
	}
end

-- Deep copy for JSON-like data. Saves write copies, so later edits cannot change a snapshot mid-write.
function DataSchema.copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value do
		result[key] = DataSchema.copy(item)
	end
	return result
end

-- Builds valid PlayerData from anything, keeping each field that passes its check.
function DataSchema.reconcile(raw: any): PlayerData
	local data = DataSchema.default()
	if type(raw) ~= "table" then
		return data
	end
	if isFinite(raw.coins) and raw.coins >= 0 then
		data.coins = math.floor(raw.coins)
	end
	if isFinite(raw.rebirths) and raw.rebirths >= 0 then
		data.rebirths = math.floor(raw.rebirths)
	end
	data.inventory = Inventory.sanitize(raw.inventory, DataSchema.INVENTORY_CAPACITY, DataSchema.MAX_STACK)
	if type(raw.progress) == "table" then
		local count = 0
		for key, value in raw.progress do
			if type(key) == "string" and isFinite(value) and count < DataSchema.MAX_PROGRESS_KEYS then
				data.progress[key] = value
				count += 1
			end
		end
	end
	return data
end

-- migrations[n] turns version n data into version n + 1. Add a step whenever VERSION goes up.
local migrations: { [number]: (any) -> any } = {
	-- Version 1 called the currency `cash` and had no progress table.
	[1] = function(data: any): any
		data.coins = data.coins or data.cash
		data.cash = nil
		data.progress = data.progress or {}
		return data
	end,
}

-- Takes a stored record (nil for a new player) and returns current-version data.
-- Returns nil and a reason when a newer schema wrote the record, so it is never downgraded.
function DataSchema.migrate(record: any): (PlayerData?, string?)
	if type(record) ~= "table" then
		return DataSchema.default(), nil
	end
	local version: number = 1
	local data: any = record
	if record.schemaVersion ~= nil then
		if isFinite(record.schemaVersion) and record.schemaVersion >= 1 then
			version = math.floor(record.schemaVersion)
		else
			-- Unreadable version number: salvage the data as if it were current.
			version = DataSchema.VERSION
		end
		if version > DataSchema.VERSION then
			return nil, "This save comes from a newer version of the game. Please rejoin in a moment."
		end
		data = record.data
	end
	data = DataSchema.copy(data)
	for step = version, DataSchema.VERSION - 1 do
		local upgrade = migrations[step]
		if upgrade and type(data) == "table" then
			data = upgrade(data)
		end
	end
	return DataSchema.reconcile(data), nil
end

-- Decides who owns a session lock. `timeout` is how long, in seconds, an unrefreshed lock stays valid.
function DataSchema.lockState(lock: any, jobId: string, now: number, timeout: number): LockState
	if type(lock) ~= "table" or type(lock.jobId) ~= "string" or not isFinite(lock.time) then
		return "free"
	end
	if lock.jobId == jobId then
		return "own"
	end
	if now - lock.time >= timeout then
		return "stale"
	end
	return "held"
end

-- The record to write. `release` clears the lock so the next server can load at once.
function DataSchema.newRecord(data: PlayerData, jobId: string, now: number, release: boolean): Record
	local lock: Lock? = if release then nil else { jobId = jobId, time = now }
	return { schemaVersion = DataSchema.VERSION, data = DataSchema.copy(data), lock = lock }
end

return DataSchema
