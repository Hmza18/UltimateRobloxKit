--!strict
-- World / area unlocking. Pure Luau. Worlds form an ordered list; each has requirements (previous
-- world, currency cost, rebirths, any custom stat). The server checks `canUnlock`, charges the cost
-- and stores the new state; zone gates and teleport pads read `isUnlocked`.

export type Requirement = {
	previous: boolean?, -- the world before it in the list must be unlocked (default true)
	cost: { [string]: number }?, -- currency costs
	rebirths: number?, -- minimum rebirths
	stats: { [string]: number }?, -- any other minimum stat (pets hatched, level...)
}

export type WorldDef = { name: string, requires: Requirement?, multiplier: number? }

export type Config = { worlds: { WorldDef } } -- the first world is always unlocked

export type State = { unlocked: { [string]: boolean } }

export type Context = { balances: { [string]: number }?, rebirths: number?, stats: { [string]: number }? }

export type Check = { ok: boolean, reason: string?, cost: { [string]: number } }

local WorldsLogic = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function WorldsLogic.validateConfig(config: Config): Config
	assert(type(config) == "table" and type(config.worlds) == "table" and #config.worlds > 0, "worlds required")
	local seen: { [string]: boolean } = {}
	for i, world in config.worlds do
		assert(type(world.name) == "string" and world.name ~= "", "world " .. i .. " needs a name")
		assert(not seen[world.name], "duplicate world " .. world.name)
		seen[world.name] = true
		for currency, amount in (world.requires and world.requires.cost) or {} do
			assert(type(currency) == "string" and isFinite(amount) and amount >= 0, world.name .. ": bad cost")
		end
		assert(
			world.multiplier == nil or isFinite(world.multiplier) and world.multiplier > 0,
			world.name .. ": bad multiplier"
		)
	end
	return config
end

local function indexOf(config: Config, name: string): number?
	for i, world in config.worlds do
		if world.name == name then
			return i
		end
	end
	return nil
end

function WorldsLogic.newState(config: Config): State
	return { unlocked = { [config.worlds[1].name] = true } }
end

function WorldsLogic.isUnlocked(config: Config, state: State, name: string): boolean
	return config.worlds[1].name == name or state.unlocked[name] == true
end

function WorldsLogic.canUnlock(config: Config, state: State, name: string, context: Context): Check
	local index = indexOf(config, name)
	if index == nil then
		return { ok = false, reason = "unknown world", cost = {} }
	end
	if WorldsLogic.isUnlocked(config, state, name) then
		return { ok = false, reason = "already unlocked", cost = {} }
	end
	local world = config.worlds[index]
	local req: Requirement = world.requires or {}
	if
		req.previous ~= false
		and index > 1
		and not WorldsLogic.isUnlocked(config, state, config.worlds[index - 1].name)
	then
		return { ok = false, reason = "unlock " .. config.worlds[index - 1].name .. " first", cost = {} }
	end
	if (context.rebirths or 0) < (req.rebirths or 0) then
		return { ok = false, reason = "needs " .. tostring(req.rebirths) .. " rebirths", cost = {} }
	end
	for stat, minimum in req.stats or {} do
		if ((context.stats or {})[stat] or 0) < minimum then
			return { ok = false, reason = "needs " .. stat .. " " .. tostring(minimum), cost = {} }
		end
	end
	local balances = context.balances or {}
	for currency, amount in req.cost or {} do
		if (balances[currency] or 0) < amount then
			return { ok = false, reason = "not enough " .. currency, cost = table.clone(req.cost or {}) }
		end
	end
	return { ok = true, reason = nil, cost = table.clone(req.cost or {}) }
end

function WorldsLogic.unlock(config: Config, state: State, name: string, context: Context): (Check, State)
	local check = WorldsLogic.canUnlock(config, state, name, context)
	if not check.ok then
		return check, state
	end
	local unlocked = table.clone(state.unlocked)
	unlocked[name] = true
	return check, { unlocked = unlocked }
end

-- The next locked world in order, for the "next area" HUD arrow.
function WorldsLogic.nextLocked(config: Config, state: State): string?
	for _, world in config.worlds do
		if not WorldsLogic.isUnlocked(config, state, world.name) then
			return world.name
		end
	end
	return nil
end

-- The highest multiplier among unlocked worlds (default 1).
function WorldsLogic.multiplier(config: Config, state: State): number
	local best = 1
	for _, world in config.worlds do
		if world.multiplier and WorldsLogic.isUnlocked(config, state, world.name) then
			best = math.max(best, world.multiplier)
		end
	end
	return best
end

function WorldsLogic.serialize(config: Config, state: State): { [string]: any }
	local names = {}
	for _, world in config.worlds do
		if state.unlocked[world.name] then
			table.insert(names, world.name)
		end
	end
	return { v = 1, u = names }
end

function WorldsLogic.deserialize(config: Config, raw: any): State
	local state = WorldsLogic.newState(config)
	if type(raw) == "table" and type(raw.u) == "table" then
		for _, name in raw.u do
			if type(name) == "string" and indexOf(config, name) then
				state.unlocked[name] = true
			end
		end
	end
	return state
end

return WorldsLogic
