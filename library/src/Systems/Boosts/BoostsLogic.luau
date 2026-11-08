--!strict
-- Timed boosts (2x coins for 15 minutes, luck potions, server-wide events). Pure Luau: `now` is
-- injected. Boosts multiply a stat; several boosts on one stat multiply together. Stacking per boost
-- kind: "extend" adds duration, "refresh" restarts it, "stack" adds another instance (up to
-- maxStacks). Time can run on the wall clock (default) or only while the player is online.

export type BoostDef = {
	stat: string, -- e.g. "coins", "luck", "speed"
	multiplier: number, -- > 0
	duration: number, -- seconds
	stacking: ("extend" | "refresh" | "stack")?, -- default "extend"
	maxDuration: number?, -- cap for "extend" (default 24 h)
	maxStacks: number?, -- cap for "stack" (default 5)
}

export type Config = { boosts: { [string]: BoostDef }, clock: ("wall" | "online")? }

export type Active = { kind: string, expiresAt: number }

export type State = { active: { Active } }

export type Result = { ok: boolean, reason: string?, state: State }

local BoostsLogic = {}

local DAY = 24 * 60 * 60

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function BoostsLogic.validateConfig(config: Config): Config
	assert(type(config) == "table" and type(config.boosts) == "table", "config.boosts required")
	for name, def in config.boosts do
		assert(type(def.stat) == "string", name .. ": stat required")
		assert(isFinite(def.multiplier) and def.multiplier > 0, name .. ": multiplier must be > 0")
		assert(isFinite(def.duration) and def.duration > 0, name .. ": duration must be > 0")
		local s = def.stacking
		assert(s == nil or s == "extend" or s == "refresh" or s == "stack", name .. ": bad stacking")
	end
	assert(config.clock == nil or config.clock == "wall" or config.clock == "online", "clock must be wall or online")
	return config
end

function BoostsLogic.newState(): State
	return { active = {} }
end

-- Drops expired boosts.
function BoostsLogic.prune(state: State, now: number): State
	local active: { Active } = {}
	for _, boost in state.active do
		if boost.expiresAt > now then
			table.insert(active, boost)
		end
	end
	return { active = active }
end

function BoostsLogic.activate(config: Config, state: State, kind: string, now: number, count: number?): Result
	local def = config.boosts[kind]
	if def == nil then
		return { ok = false, reason = "unknown boost", state = state }
	end
	local n = count or 1
	if not isFinite(n) or n < 1 or n > 100 or n % 1 ~= 0 then
		return { ok = false, reason = "invalid count", state = state }
	end
	local nextState = BoostsLogic.prune(state, now)
	local stacking = def.stacking or "extend"
	local existing: Active? = nil
	local instances = 0
	for _, boost in nextState.active do
		if boost.kind == kind then
			existing = existing or boost
			instances += 1
		end
	end
	if stacking == "stack" then
		if instances + n > (def.maxStacks or 5) then
			return { ok = false, reason = "max stacks", state = state }
		end
		for _ = 1, n do
			table.insert(nextState.active, { kind = kind, expiresAt = now + def.duration })
		end
	elseif existing == nil then
		local duration = if stacking == "extend" then def.duration * n else def.duration
		local cap = def.maxDuration or DAY
		table.insert(nextState.active, { kind = kind, expiresAt = now + math.min(duration, cap) })
	else
		local current = existing :: Active
		local index = table.find(nextState.active, current) :: number
		local expiresAt
		if stacking == "refresh" then
			expiresAt = now + def.duration
		else
			local cap = def.maxDuration or DAY
			expiresAt = math.min(current.expiresAt + def.duration * n, now + cap)
			if expiresAt <= current.expiresAt then
				return { ok = false, reason = "max duration", state = state }
			end
		end
		nextState.active[index] = { kind = kind, expiresAt = expiresAt }
	end
	return { ok = true, reason = nil, state = nextState }
end

-- Product of all active multipliers for a stat (1 when none).
function BoostsLogic.multiplier(config: Config, state: State, stat: string, now: number): number
	local total = 1
	for _, boost in state.active do
		local def = config.boosts[boost.kind]
		if def and def.stat == stat and boost.expiresAt > now then
			total *= def.multiplier
		end
	end
	return total
end

-- Seconds left per boost kind (the longest instance), for HUD timers.
function BoostsLogic.remaining(state: State, now: number): { [string]: number }
	local result: { [string]: number } = {}
	for _, boost in state.active do
		local left = boost.expiresAt - now
		if left > 0 then
			result[boost.kind] = math.max(result[boost.kind] or 0, left)
		end
	end
	return result
end

-- Saved as remaining seconds when the clock is "online" (time pauses offline), else as absolute
-- expiry times.
function BoostsLogic.serialize(config: Config, state: State, now: number): { [string]: any }
	local rows = {}
	local online = config.clock == "online"
	for _, boost in BoostsLogic.prune(state, now).active do
		table.insert(rows, { boost.kind, if online then boost.expiresAt - now else boost.expiresAt })
	end
	return { v = 1, c = if online then "o" else "w", a = rows }
end

function BoostsLogic.deserialize(config: Config, raw: any, now: number): State
	local state = BoostsLogic.newState()
	if type(raw) ~= "table" or type(raw.a) ~= "table" then
		return state
	end
	local relative = raw.c == "o"
	for _, row in raw.a do
		if type(row) == "table" and type(row[1]) == "string" and config.boosts[row[1]] and isFinite(row[2]) then
			local def = config.boosts[row[1]]
			local expiresAt = if relative then now + row[2] else row[2]
			local cap = now + math.max(def.maxDuration or DAY, def.duration)
			expiresAt = math.min(expiresAt, cap)
			if expiresAt > now then
				table.insert(state.active, { kind = row[1], expiresAt = expiresAt })
			end
		end
	end
	return state
end

return BoostsLogic
