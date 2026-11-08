--!strict
-- Tag-to-object registry. Pure Luau: the adapter feeds it tag and filter events for keys
-- (Instances on Roblox, anything in tests) and it decides when to construct and destroy the
-- bound object through injected callbacks. It handles duplicate adds, removes before adds,
-- construct errors, filters (such as "only in Workspace") and re-entrant calls made from
-- inside construct or destroy.

export type Hooks = {
	construct: (key: any) -> any, -- returns the bound object; an error or nil means "failed"
	destroy: ((object: any, key: any) -> ())?, -- default: object:Destroy() when it exists
	added: ((key: any, object: any) -> ())?, -- after an object is bound
	removing: ((key: any, object: any) -> ())?, -- before an object is destroyed
}

-- "bound": an object exists. "waiting": tagged but filtered out or construct failed.
-- "constructing": construct is running for this key.
export type Phase = "waiting" | "constructing" | "bound"

export type Entry = {
	phase: Phase,
	passes: boolean, -- the filter result last reported for this key
	object: any?,
	cancelled: boolean, -- untagged or filtered out while constructing
	error: string?, -- the last construct error
}

-- Results of tag, untag and setFilter.
export type BindStatus = "bound" | "duplicate" | "filtered" | "failed"
export type UnbindStatus = "unbound" | "untagged" | "unknown" | "unchanged" | "deferred"
export type Status = BindStatus | UnbindStatus

export type Result = { status: Status, object: any?, error: string? }

export type Stats = { constructed: number, destroyed: number, failed: number, duplicates: number }

export type State = {
	hooks: Hooks,
	entries: { [any]: Entry },
	order: { any }, -- keys in the order they were bound, for getAll
	stats: Stats,
	destroying: boolean,
}

local BinderLogic = {}

local function result(status: Status, object: any?, err: string?): Result
	return { status = status, object = object, error = err }
end

function BinderLogic.new(hooks: Hooks): State
	assert(type(hooks) == "table", "hooks must be a table")
	assert(type(hooks.construct) == "function", "hooks.construct must be a function")
	assert(hooks.destroy == nil or type(hooks.destroy) == "function", "hooks.destroy must be a function")
	assert(hooks.added == nil or type(hooks.added) == "function", "hooks.added must be a function")
	assert(hooks.removing == nil or type(hooks.removing) == "function", "hooks.removing must be a function")
	return {
		hooks = hooks,
		entries = {},
		order = {},
		stats = { constructed = 0, destroyed = 0, failed = 0, duplicates = 0 },
		destroying = false,
	}
end

local function removeFromOrder(state: State, key: any)
	local index = table.find(state.order, key)
	if index then
		table.remove(state.order, index)
	end
end

local function defaultDestroy(object: any, _key: any)
	-- typeof works for Roblox Instances without naming the Instance type, which Lune and luau-analyze lack.
	local kind = typeof(object)
	local destroyable = (kind == "table" and type(object.Destroy) == "function") or kind == "Instance"
	if destroyable then
		object:Destroy()
	end
end

-- Runs removing (only for objects that were announced with added) and destroy.
-- Errors are caught and the first one is returned.
local function teardown(state: State, key: any, object: any, announced: boolean): string?
	local hooks = state.hooks
	local firstError: string? = nil
	if announced and hooks.removing then
		local ok, err = pcall(hooks.removing, key, object)
		if not ok then
			firstError = tostring(err)
		end
	end
	local destroy: (any, any) -> () = hooks.destroy or defaultDestroy
	local ok, err = pcall(destroy, object, key)
	if not ok and firstError == nil then
		firstError = tostring(err)
	end
	state.stats.destroyed += 1
	return firstError
end

-- Constructs the object for a tagged key whose filter passes.
local function bind(state: State, key: any, entry: Entry): Result
	entry.phase = "constructing"
	entry.cancelled = false
	local ok, object = pcall(state.hooks.construct, key)
	if not ok or object == nil then
		entry.phase = "waiting"
		entry.error = if ok then "construct returned nil" else tostring(object)
		entry.cancelled = false
		state.stats.failed += 1
		return result("failed", nil, entry.error)
	end
	state.stats.constructed += 1
	if entry.cancelled or state.entries[key] ~= entry or state.destroying then
		-- Untagged, filtered out or the registry was destroyed while constructing.
		entry.phase = "waiting"
		entry.cancelled = false
		local err = teardown(state, key, object, false)
		return result("unbound", nil, err)
	end
	entry.phase = "bound"
	entry.object = object
	entry.error = nil
	table.insert(state.order, key)
	if state.hooks.added then
		local addedOk, err = pcall(state.hooks.added, key, object)
		if not addedOk then
			return result("bound", object, tostring(err))
		end
	end
	return result("bound", object, nil)
end

local function unbind(state: State, key: any, entry: Entry): Result
	local object = entry.object
	entry.object = nil
	entry.phase = "waiting"
	removeFromOrder(state, key)
	local err = teardown(state, key, object, true)
	return result("unbound", nil, err)
end

-- The key gained the tag. `passes` is the filter result (default true).
function BinderLogic.tag(state: State, key: any, passes: boolean?): Result
	assert(key ~= nil, "key must not be nil")
	if state.destroying then
		return result("unchanged")
	end
	local existing = state.entries[key]
	if existing then
		state.stats.duplicates += 1
		return result("duplicate", existing.object)
	end
	local entry: Entry = { phase = "waiting", passes = passes ~= false, object = nil, cancelled = false, error = nil }
	state.entries[key] = entry
	if not entry.passes then
		return result("filtered")
	end
	return bind(state, key, entry)
end

-- The key lost the tag (untagged, destroyed or streamed out). Unknown keys are ignored, which
-- covers a remove that arrives before its add.
function BinderLogic.untag(state: State, key: any): Result
	local entry = state.entries[key]
	if entry == nil then
		return result("unknown")
	end
	state.entries[key] = nil
	if entry.phase == "constructing" then
		entry.cancelled = true
		return result("deferred")
	elseif entry.phase == "bound" then
		return unbind(state, key, entry)
	end
	return result("untagged")
end

-- The key's filter result changed (for example it moved into or out of Workspace).
function BinderLogic.setFilter(state: State, key: any, passes: boolean): Result
	local entry = state.entries[key]
	if entry == nil then
		return result("unknown")
	end
	if entry.passes == passes then
		return result("unchanged", entry.object)
	end
	entry.passes = passes
	if passes then
		if entry.phase == "waiting" then
			return bind(state, key, entry)
		end
		-- Constructing: a filter flip back to true cancels an earlier cancel.
		entry.cancelled = false
		return result("unchanged", entry.object)
	end
	if entry.phase == "constructing" then
		entry.cancelled = true
		return result("deferred")
	elseif entry.phase == "bound" then
		return unbind(state, key, entry)
	end
	return result("unchanged")
end

-- Tries construct again for a tagged key whose last construct failed.
function BinderLogic.retry(state: State, key: any): Result
	local entry = state.entries[key]
	if entry == nil then
		return result("unknown")
	end
	if entry.phase ~= "waiting" or not entry.passes or state.destroying then
		return result("unchanged", entry.object)
	end
	return bind(state, key, entry)
end

function BinderLogic.get(state: State, key: any): any?
	local entry = state.entries[key]
	if entry and entry.phase == "bound" then
		return entry.object
	end
	return nil
end

function BinderLogic.isTagged(state: State, key: any): boolean
	return state.entries[key] ~= nil
end

function BinderLogic.phase(state: State, key: any): Phase?
	local entry = state.entries[key]
	return if entry then entry.phase else nil
end

-- Every bound object, in the order they were bound.
function BinderLogic.getAll(state: State): { any }
	local objects: { any } = {}
	for _, key in state.order do
		local entry = state.entries[key]
		if entry and entry.phase == "bound" then
			table.insert(objects, entry.object)
		end
	end
	return objects
end

function BinderLogic.keys(state: State): { any }
	return table.clone(state.order)
end

function BinderLogic.count(state: State): number
	return #state.order
end

-- Destroys every bound object (newest first) and refuses further tags. Returns how many.
function BinderLogic.destroyAll(state: State): number
	state.destroying = true
	local count = 0
	for index = #state.order, 1, -1 do
		local key = state.order[index]
		local entry = state.entries[key]
		state.entries[key] = nil
		if entry and entry.phase == "bound" then
			unbind(state, key, entry)
			count += 1
		end
	end
	for key, entry in state.entries do
		if entry.phase == "constructing" then
			entry.cancelled = true
		end
		state.entries[key] = nil
	end
	table.clear(state.order)
	return count
end

return BinderLogic
