--!strict
-- Achievements. Pure Luau and immutable. An achievement unlocks when an event counter (kills,
-- crafts, ...) or an observed stat (level, best time, ...) reaches its threshold. Unlocking is
-- idempotent: each id unlocks once and is reported once. Optional Roblox badge ids are tracked
-- so the server can award them later and retry failures.

export type DefInput = {
	id: string, -- unique achievement id
	kind: ("counter" | "stat")?, -- counter: summed events; stat: highest observed value (default "counter")
	key: string, -- counter or stat name, such as "ZombieKilled" or "Level"
	threshold: number, -- value that unlocks it, > 0
	hidden: boolean?, -- hide name and description until unlocked (default false)
	badgeId: number?, -- Roblox badge to award on unlock
	name: string?, -- display name (default id)
	description: string?, -- display text (default "")
}

export type Def = {
	id: string, -- unique id
	kind: "counter" | "stat", -- what drives progress
	key: string, -- counter or stat name
	threshold: number, -- unlock value
	hidden: boolean, -- hidden until unlocked
	badgeId: number?, -- Roblox badge id
	name: string, -- display name
	description: string, -- display text
}

export type Defs = { list: { Def }, byId: { [string]: Def } }

export type State = {
	counters: { [string]: number }, -- summed events
	stats: { [string]: number }, -- highest observed values
	unlocked: { [string]: number }, -- id -> unlock time
	badges: { [string]: boolean }, -- ids whose badge was awarded
}

export type Progress = { current: number, target: number, fraction: number, unlocked: boolean }

export type Entry = {
	id: string, -- achievement id
	name: string, -- "???" while hidden
	description: string, -- empty while hidden
	unlocked: boolean, -- whether it is unlocked
	hidden: boolean, -- whether it is still hidden
	current: number, -- progress value
	target: number, -- threshold
}

export type PendingBadge = { id: string, badgeId: number }

export type Saved = {
	v: number, -- format version
	c: { [string]: number }, -- counters
	s: { [string]: number }, -- stats
	u: { [string]: number }, -- unlocked
	b: { [string]: boolean }, -- badges
}

local AchievementsLogic = {}

AchievementsLogic.SAVE_VERSION = 1
AchievementsLogic.HIDDEN_NAME = "???"

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function copy(state: State): State
	return {
		counters = table.clone(state.counters),
		stats = table.clone(state.stats),
		unlocked = table.clone(state.unlocked),
		badges = table.clone(state.badges),
	}
end

function AchievementsLogic.newDefs(inputs: { DefInput }): Defs
	assert(type(inputs) == "table", "inputs must be an array")
	local defs: Defs = { list = {}, byId = {} }
	for _, input in inputs do
		local id = input.id
		assert(type(id) == "string" and id ~= "", "achievement id must be a non-empty string")
		assert(defs.byId[id] == nil, "duplicate achievement id " .. id)
		local kind: "counter" | "stat" = input.kind or "counter"
		assert(kind == "counter" or kind == "stat", "kind must be counter or stat for " .. id)
		assert(type(input.key) == "string" and input.key ~= "", "key must be a non-empty string for " .. id)
		assert(isFinite(input.threshold) and input.threshold > 0, "threshold must be > 0 for " .. id)
		local badgeId = input.badgeId
		assert(badgeId == nil or isFinite(badgeId) and badgeId > 0, "invalid badgeId for " .. id)
		local def: Def = {
			id = id,
			kind = kind,
			key = input.key,
			threshold = input.threshold,
			hidden = input.hidden == true,
			badgeId = badgeId,
			name = input.name or id,
			description = input.description or "",
		}
		table.insert(defs.list, def)
		defs.byId[id] = def
	end
	return defs
end

function AchievementsLogic.new(): State
	return { counters = {}, stats = {}, unlocked = {}, badges = {} }
end

function AchievementsLogic.isUnlocked(state: State, id: string): boolean
	return state.unlocked[id] ~= nil
end

local function currentValue(def: Def, state: State): number
	if def.kind == "stat" then
		return state.stats[def.key] or 0
	end
	return state.counters[def.key] or 0
end

-- Unlocks every achievement whose threshold is met. Modifies `state` (a private copy) and
-- returns the newly unlocked ids in definition order.
local function evaluateInto(defs: Defs, state: State, now: number, key: string?): { string }
	local unlocked: { string } = {}
	for _, def in defs.list do
		local relevant = key == nil or def.key == key
		if relevant and state.unlocked[def.id] == nil and currentValue(def, state) >= def.threshold then
			state.unlocked[def.id] = now
			table.insert(unlocked, def.id)
		end
	end
	return unlocked
end

-- Adds `amount` (default 1) to an event counter. Returns the new state and newly unlocked ids.
function AchievementsLogic.increment(
	defs: Defs,
	state: State,
	counter: string,
	amount: number?,
	now: number
): (State, { string })
	local delta = amount or 1
	if type(counter) ~= "string" or not isFinite(delta) or delta <= 0 then
		return state, {}
	end
	local result = copy(state)
	result.counters[counter] = (result.counters[counter] or 0) + delta
	return result, evaluateInto(defs, result, now, counter)
end

-- Records a stat value. Only a new highest value counts (a level can drop, the record cannot).
function AchievementsLogic.observe(
	defs: Defs,
	state: State,
	stat: string,
	value: number,
	now: number
): (State, { string })
	if type(stat) ~= "string" or not isFinite(value) then
		return state, {}
	end
	local best = state.stats[stat]
	if best ~= nil and value <= best then
		return state, {}
	end
	local result = copy(state)
	result.stats[stat] = value
	return result, evaluateInto(defs, result, now, stat)
end

-- Unlocks an achievement directly (scripted events). Returns the new state and whether it was new.
function AchievementsLogic.unlock(defs: Defs, state: State, id: string, now: number): (State, boolean)
	if defs.byId[id] == nil or state.unlocked[id] ~= nil then
		return state, false
	end
	local result = copy(state)
	result.unlocked[id] = now
	return result, true
end

-- Unlocks anything already earned, for example achievements added after the player's progress.
function AchievementsLogic.evaluate(defs: Defs, state: State, now: number): (State, { string })
	local result = copy(state)
	return result, evaluateInto(defs, result, now, nil)
end

function AchievementsLogic.progress(defs: Defs, state: State, id: string): Progress?
	local def = defs.byId[id]
	if def == nil then
		return nil
	end
	local unlocked = state.unlocked[id] ~= nil
	local current = currentValue(def, state)
	local fraction = if unlocked then 1 else math.clamp(current / def.threshold, 0, 1)
	return { current = current, target = def.threshold, fraction = fraction, unlocked = unlocked }
end

-- Display list in definition order. Hidden achievements show "???" until unlocked.
function AchievementsLogic.list(defs: Defs, state: State): { Entry }
	local entries: { Entry } = {}
	for _, def in defs.list do
		local unlocked = state.unlocked[def.id] ~= nil
		local hidden = def.hidden and not unlocked
		table.insert(entries, {
			id = def.id,
			name = if hidden then AchievementsLogic.HIDDEN_NAME else def.name,
			description = if hidden then "" else def.description,
			unlocked = unlocked,
			hidden = hidden,
			current = math.min(currentValue(def, state), def.threshold),
			target = def.threshold,
		})
	end
	return entries
end

-- Unlocked achievements with a badge that has not been awarded yet.
function AchievementsLogic.pendingBadges(defs: Defs, state: State): { PendingBadge }
	local pending: { PendingBadge } = {}
	for _, def in defs.list do
		local badgeId = def.badgeId
		if badgeId ~= nil and state.unlocked[def.id] ~= nil and not state.badges[def.id] then
			table.insert(pending, { id = def.id, badgeId = badgeId })
		end
	end
	return pending
end

function AchievementsLogic.markBadgeAwarded(state: State, id: string): State
	if state.badges[id] then
		return state
	end
	local result = copy(state)
	result.badges[id] = true
	return result
end

function AchievementsLogic.serialize(state: State): Saved
	return {
		v = AchievementsLogic.SAVE_VERSION,
		c = table.clone(state.counters),
		s = table.clone(state.stats),
		u = table.clone(state.unlocked),
		b = table.clone(state.badges),
	}
end

local function numberMap(raw: any): { [string]: number }
	local result: { [string]: number } = {}
	if type(raw) == "table" then
		for key, value in raw do
			if type(key) == "string" and isFinite(value) then
				result[key] = value
			end
		end
	end
	return result
end

-- Rebuilds state from untrusted data. Unlocks and badges for ids that no longer exist are dropped;
-- counters and stats are kept so renamed achievements can still use them.
function AchievementsLogic.deserialize(defs: Defs, raw: any): State
	local state = AchievementsLogic.new()
	if type(raw) ~= "table" then
		return state
	end
	state.counters = numberMap(raw.c)
	state.stats = numberMap(raw.s)
	for id, time in numberMap(raw.u) do
		if defs.byId[id] ~= nil then
			state.unlocked[id] = time
		end
	end
	if type(raw.b) == "table" then
		for id, awarded in raw.b do
			if type(id) == "string" and awarded == true and state.unlocked[id] ~= nil then
				state.badges[id] = true
			end
		end
	end
	return state
end

return AchievementsLogic
