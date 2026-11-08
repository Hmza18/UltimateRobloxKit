--!strict
-- Save data rules. Pure Luau: schema versions and a migration chain, reconciling defaults,
-- session-lock decisions for UpdateAsync transforms, and retry with exponential backoff using
-- injected `sleep` and random functions. SaveDataServer does the DataStore calls.

export type Migration = (data: any) -> any

export type SchemaInput = {
	version: number, -- current schema version, a positive integer
	defaults: { [string]: any }, -- data for a brand-new player
	migrations: { [number]: Migration }?, -- migrations[n] turns version n data into version n + 1
}

export type Schema = { version: number, defaults: { [string]: any }, migrations: { [number]: Migration } }

export type Session = { jobId: string, lockedAt: number, heartbeatAt: number }

export type Record = {
	schemaVersion: number, -- version of `data`
	data: any, -- the player's data
	session: Session?, -- which server holds the session lock
	updatedAt: number?, -- unix time of the last write
}

export type LockState = "free" | "own" | "stale" | "held"

export type LoadPlan = {
	ok: boolean, -- whether this server may take the session
	reason: string?, -- why not
	record: Record?, -- value to write back (nil means do not write)
	data: any, -- migrated and reconciled data when ok
}

export type SavePlan = { ok: boolean, reason: string?, record: Record? }

export type RetryOptions = {
	attempts: number?, -- total tries (default 5)
	base: number?, -- first delay in seconds (default 1)
	max: number?, -- longest delay in seconds (default 16)
	sleep: (seconds: number) -> (), -- task.wait on Roblox
	rng: (() -> number)?, -- adds jitter when given (multiplies the delay by 0.5..1)
}

local SaveDataLogic = {}

-- A lock whose heartbeat is older than this is treated as abandoned (server crashed).
SaveDataLogic.DEFAULT_LOCK_TIMEOUT = 1800

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isCount(value: any): boolean
	return isFinite(value) and value >= 1 and value % 1 == 0
end

function SaveDataLogic.deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result: { [any]: any } = {}
	for key, item in value do
		result[SaveDataLogic.deepCopy(key)] = SaveDataLogic.deepCopy(item)
	end
	return result
end

function SaveDataLogic.newSchema(input: SchemaInput): Schema
	assert(type(input) == "table", "schema must be a table")
	assert(isCount(input.version), "version must be a positive integer")
	assert(type(input.defaults) == "table", "defaults must be a table")
	local migrations = input.migrations or {}
	for from = 1, input.version - 1 do
		assert(type(migrations[from]) == "function", "missing migration from version " .. tostring(from))
	end
	return { version = input.version, defaults = SaveDataLogic.deepCopy(input.defaults), migrations = migrations }
end

function SaveDataLogic.defaults(schema: Schema): { [string]: any }
	return SaveDataLogic.deepCopy(schema.defaults)
end

-- Returns a copy of `data` with every key from `defaults` present. Missing keys and keys whose
-- type differs from the default get the default; nested tables are reconciled recursively;
-- keys that are not in `defaults` are kept.
function SaveDataLogic.reconcile(data: any, defaults: { [string]: any }): { [string]: any }
	if type(data) ~= "table" then
		return SaveDataLogic.deepCopy(defaults)
	end
	local result = SaveDataLogic.deepCopy(data)
	for key, default in defaults do
		local current = result[key]
		if current == nil or type(current) ~= type(default) then
			result[key] = SaveDataLogic.deepCopy(default)
		elseif type(default) == "table" and next(default) ~= nil then
			result[key] = SaveDataLogic.reconcile(current, default)
		end
	end
	return result
end

-- Runs migrations from `fromVersion` up to the schema version. Each migration gets a copy.
function SaveDataLogic.migrate(schema: Schema, data: any, fromVersion: number): (any, string?)
	if not isCount(fromVersion) then
		return nil, "invalid version"
	end
	if fromVersion > schema.version then
		return nil, "data is from a newer version"
	end
	local current = data
	for version = fromVersion, schema.version - 1 do
		local migration = schema.migrations[version]
		if migration == nil then
			return nil, "missing migration from version " .. tostring(version)
		end
		local ok, migrated = pcall(migration, SaveDataLogic.deepCopy(current))
		if not ok then
			return nil, "migration from version " .. tostring(version) .. " failed"
		end
		current = migrated
	end
	return current, nil
end

-- Turns a stored value into current data. nil becomes the defaults. A table without
-- `schemaVersion` is treated as version 1 data stored before records were used.
function SaveDataLogic.load(schema: Schema, raw: any): (any, string?)
	if raw == nil then
		return SaveDataLogic.defaults(schema), nil
	end
	if type(raw) ~= "table" then
		return nil, "corrupt record"
	end
	local version = 1
	local data = raw
	if raw.schemaVersion ~= nil then
		version = raw.schemaVersion
		data = raw.data
	end
	local migrated, reason = SaveDataLogic.migrate(schema, data, version)
	if reason ~= nil then
		return nil, reason
	end
	return SaveDataLogic.reconcile(migrated, schema.defaults), nil
end

function SaveDataLogic.lockState(record: any, jobId: string, now: number, timeout: number?): LockState
	local session = if type(record) == "table" then record.session else nil
	if type(session) ~= "table" or type(session.jobId) ~= "string" then
		return "free"
	end
	if session.jobId == jobId then
		return "own"
	end
	local heartbeat = if isFinite(session.heartbeatAt) then session.heartbeatAt else 0
	if now - heartbeat > (timeout or SaveDataLogic.DEFAULT_LOCK_TIMEOUT) then
		return "stale"
	end
	return "held"
end

-- Decides the UpdateAsync transform for a session start. When ok, write `record` and use `data`.
function SaveDataLogic.planLoad(schema: Schema, old: any, jobId: string, now: number, timeout: number?): LoadPlan
	local state = SaveDataLogic.lockState(old, jobId, now, timeout)
	if state == "held" then
		return { ok = false, reason = "locked by another server", record = nil, data = nil }
	end
	local data, reason = SaveDataLogic.load(schema, old)
	if reason ~= nil then
		return { ok = false, reason = reason, record = nil, data = nil }
	end
	local record: Record = {
		schemaVersion = schema.version,
		data = data,
		session = { jobId = jobId, lockedAt = now, heartbeatAt = now },
		updatedAt = now,
	}
	return { ok = true, reason = nil, record = record, data = data }
end

-- Decides the UpdateAsync transform for a save. Refuses when another server took the lock.
-- `release = true` ends the session (player leaving); otherwise the heartbeat is refreshed.
function SaveDataLogic.planSave(
	schema: Schema,
	old: any,
	jobId: string,
	data: any,
	now: number,
	release: boolean?
): SavePlan
	local state = SaveDataLogic.lockState(old, jobId, now, math.huge)
	if state == "held" then
		return { ok = false, reason = "session lock lost", record = nil }
	end
	local lockedAt = now
	if state == "own" and type(old.session.lockedAt) == "number" then
		lockedAt = old.session.lockedAt
	end
	local session: Session? = if release then nil else { jobId = jobId, lockedAt = lockedAt, heartbeatAt = now }
	local record: Record = { schemaVersion = schema.version, data = data, session = session, updatedAt = now }
	return { ok = true, reason = nil, record = record }
end

-- Delay before retry number `attempt` (1-based): base * 2^(attempt - 1), capped at `max`.
function SaveDataLogic.backoff(attempt: number, base: number?, max: number?, rng: (() -> number)?): number
	local first = base or 1
	local cap = max or 16
	local delay = math.min(cap, first * 2 ^ math.max(attempt - 1, 0))
	if rng then
		local jitter = rng()
		if isFinite(jitter) then
			delay *= 0.5 + 0.5 * math.clamp(jitter, 0, 1)
		end
	end
	return delay
end

-- Calls `callback` until it succeeds or the attempts run out, sleeping between tries.
-- Returns success, the callback's result or last error, and the number of attempts made.
function SaveDataLogic.retry(callback: () -> any, options: RetryOptions): (boolean, any, number)
	local attempts = options.attempts or 5
	assert(isCount(attempts), "attempts must be a positive integer")
	local lastError: any = nil
	for attempt = 1, attempts do
		local ok, result = pcall(callback)
		if ok then
			return true, result, attempt
		end
		lastError = result
		if attempt < attempts then
			options.sleep(SaveDataLogic.backoff(attempt, options.base, options.max, options.rng))
		end
	end
	return false, lastError, attempts
end

-- Waits until `getBudget()` reaches `needed` or `maxWait` seconds pass. Returns whether it did.
function SaveDataLogic.waitForBudget(
	getBudget: () -> number,
	needed: number,
	sleep: (number) -> (),
	maxWait: number
): boolean
	local waited = 0
	while getBudget() < needed do
		if waited >= maxWait then
			return false
		end
		sleep(1)
		waited += 1
	end
	return true
end

return SaveDataLogic
