--!strict
-- Leveled upgrades (walk speed, backpack size, coin bonus...). Pure Luau. Each upgrade has a cost
-- curve (shared with Rebirth), a max level and an effect per level. `buy` plans one or more levels
-- against a balance; the server spends `plan.cost` and stores `plan.state`.

local RebirthLogic = require("../Rebirth/RebirthLogic")

export type Effect = {
	base: number, -- value at level 0
	perLevel: number?, -- added per level (linear effect)
	values: { number }?, -- explicit value at level N (overrides perLevel)
}

export type UpgradeDef = {
	currency: string,
	cost: RebirthLogic.Curve,
	maxLevel: number,
	effect: Effect,
	requires: { [string]: number }?, -- other upgrade levels needed first
	resetOnRebirth: boolean?, -- default true
}

export type Config = { upgrades: { [string]: UpgradeDef } }

export type State = { levels: { [string]: number } }

export type Plan = { ok: boolean, reason: string?, levels: number, cost: number, currency: string?, state: State }

local UpgradesLogic = {}

UpgradesLogic.MAX_PER_PURCHASE = 100

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function UpgradesLogic.validateConfig(config: Config): Config
	assert(type(config) == "table" and type(config.upgrades) == "table", "config.upgrades required")
	for name, def in config.upgrades do
		assert(type(def.currency) == "string", name .. ": currency required")
		RebirthLogic.validateCurve(def.cost, name)
		assert(isFinite(def.maxLevel) and def.maxLevel >= 1 and def.maxLevel % 1 == 0, name .. ": maxLevel >= 1")
		assert(type(def.effect) == "table" and isFinite(def.effect.base), name .. ": effect.base required")
		if def.effect.values then
			assert(#def.effect.values >= def.maxLevel, name .. ": effect.values needs maxLevel entries")
		end
		for other, level in def.requires or {} do
			assert(config.upgrades[other] ~= nil and other ~= name, name .. ": requires unknown upgrade " .. other)
			assert(isFinite(level) and level >= 1, name .. ": bad required level")
		end
	end
	return config
end

function UpgradesLogic.newState(): State
	return { levels = {} }
end

function UpgradesLogic.level(state: State, name: string): number
	return state.levels[name] or 0
end

function UpgradesLogic.value(config: Config, state: State, name: string): number
	local def = config.upgrades[name]
	assert(def ~= nil, "unknown upgrade " .. tostring(name))
	local level = UpgradesLogic.level(state, name)
	if level == 0 then
		return def.effect.base
	end
	if def.effect.values then
		return def.effect.values[level]
	end
	return def.effect.base + (def.effect.perLevel or 0) * level
end

-- Cost of the next level, or nil at max level.
function UpgradesLogic.nextCost(config: Config, state: State, name: string): number?
	local def = config.upgrades[name]
	assert(def ~= nil, "unknown upgrade " .. tostring(name))
	local level = UpgradesLogic.level(state, name)
	if level >= def.maxLevel then
		return nil
	end
	return RebirthLogic.curveCost(def.cost, level + 1)
end

function UpgradesLogic.isLocked(config: Config, state: State, name: string): (boolean, string?)
	local def = config.upgrades[name]
	if def == nil then
		return true, "unknown upgrade"
	end
	for other, level in def.requires or {} do
		if UpgradesLogic.level(state, other) < level then
			return true, "requires " .. other .. " " .. level
		end
	end
	return false, nil
end

-- Plans buying `count` levels (default 1, or "max") with `balance` of the upgrade's currency.
function UpgradesLogic.buy(config: Config, state: State, name: string, balance: number, count: (number | "max")?): Plan
	local def = config.upgrades[name]
	local fail = function(reason: string): Plan
		return {
			ok = false,
			reason = reason,
			levels = 0,
			cost = 0,
			currency = if def then def.currency else nil,
			state = state,
		}
	end
	if def == nil then
		return fail("unknown upgrade")
	end
	local locked, why = UpgradesLogic.isLocked(config, state, name)
	if locked then
		return fail(why or "locked")
	end
	local wanted = count or 1
	local maxCount = if wanted == "max" then UpgradesLogic.MAX_PER_PURCHASE else wanted :: number
	if not isFinite(maxCount) or maxCount < 1 or maxCount % 1 ~= 0 or maxCount > UpgradesLogic.MAX_PER_PURCHASE then
		return fail("invalid count")
	end
	local level = UpgradesLogic.level(state, name)
	if level >= def.maxLevel then
		return fail("max level")
	end
	local bought, total = 0, 0
	while bought < maxCount and level + bought < def.maxLevel do
		local cost = RebirthLogic.curveCost(def.cost, level + bought + 1)
		if total + cost > balance then
			break
		end
		total += cost
		bought += 1
	end
	if bought == 0 or (wanted ~= "max" and bought < maxCount) then
		return fail("not enough " .. def.currency)
	end
	local levels = table.clone(state.levels)
	levels[name] = level + bought
	return {
		ok = true,
		reason = nil,
		levels = bought,
		cost = total,
		currency = def.currency,
		state = { levels = levels },
	}
end

-- The state after a rebirth: upgrades with resetOnRebirth ~= false go back to level 0.
function UpgradesLogic.afterRebirth(config: Config, state: State): State
	local levels: { [string]: number } = {}
	for name, level in state.levels do
		local def = config.upgrades[name]
		if def and def.resetOnRebirth == false then
			levels[name] = level
		end
	end
	return { levels = levels }
end

function UpgradesLogic.serialize(state: State): { [string]: any }
	return { v = 1, l = table.clone(state.levels) }
end

function UpgradesLogic.deserialize(config: Config, raw: any): State
	local state = UpgradesLogic.newState()
	if type(raw) ~= "table" or type(raw.l) ~= "table" then
		return state
	end
	for name, level in raw.l do
		local def = if type(name) == "string" then config.upgrades[name] else nil
		if def and isFinite(level) and level >= 1 then
			state.levels[name] = math.min(math.floor(level), def.maxLevel)
		end
	end
	return state
end

return UpgradesLogic
