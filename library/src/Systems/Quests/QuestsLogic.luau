--!strict
-- Quest and mission rules. Pure Luau: callers pass `now` in seconds and the module never reads a clock.
-- Definitions are data. Progress comes from events such as { type = "EnemyDefeated", target = "Slime" }.
-- Functions that change progress modify the PlayerState passed in and return what happened.

local QuestsConfig = require("./QuestsConfig")

export type ObjectiveKind = "count" | "collect" | "reach"

export type ObjectiveDef = {
	id: string, -- unique inside its quest
	kind: ObjectiveKind,
	event: string?, -- "count" only: the event type to count, for example "EnemyDefeated"
	target: string?, -- "count": optional filter; "collect": the item id; "reach": the location id
	amount: number?, -- how many are needed (default 1); "reach" always needs 1
}

export type QuestDef = {
	id: string,
	objectives: { ObjectiveDef },
	prerequisites: { string }?, -- quests that must be completed before this one can start
	next: string?, -- the next quest in a chain
	autoStartNext: boolean?, -- start `next` as soon as this quest completes (default true)
	repeatable: boolean?, -- can be done again once `cooldown` seconds have passed
	cooldown: number?, -- seconds between completions of a repeatable quest (default 0)
	daily: boolean?, -- can be done once per quest day
	timeLimit: number?, -- seconds allowed after starting; nil means no limit
	rewards: any?, -- handed untouched to the reward callback
}

export type Event = { type: string, target: string?, amount: number? }
export type ActiveQuest = { startedAt: number, progress: { [string]: number } }
export type CompletedRecord = { count: number, lastAt: number }
export type PlayerState = { active: { [string]: ActiveQuest }, completed: { [string]: CompletedRecord } }
export type Catalog = { byId: { [string]: QuestDef }, order: { string } }
export type Config = { dayLength: number, dayOffset: number, maxActive: number }
export type EventResult = { updated: { string }, completed: { string }, started: { string } }
export type ObjectiveProgress = { id: string, current: number, required: number }

local COLLECT_EVENT = "collect"
local REACH_EVENT = "reach"
local SAVE_VERSION = 1

local Quests = {}

Quests.COLLECT_EVENT = COLLECT_EVENT
Quests.REACH_EVENT = REACH_EVENT

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isCount(value: any): boolean
	return isFinite(value) and value >= 1 and value % 1 == 0
end

local function isName(value: any): boolean
	return type(value) == "string" and value ~= ""
end

-- Fills missing keys from QuestsConfig. Unknown keys are ignored.
function Quests.resolveConfig(overrides: { [string]: any }?): Config
	local source: { [string]: any } = overrides or {}
	local dayLength = source.dayLength
	local dayOffset = source.dayOffset
	local maxActive = source.maxActive
	return {
		dayLength = if isFinite(dayLength) and dayLength > 0 then dayLength else QuestsConfig.dayLength,
		dayOffset = if isFinite(dayOffset) then dayOffset else QuestsConfig.dayOffset,
		maxActive = if isCount(maxActive) then maxActive else QuestsConfig.maxActive,
	}
end

local DEFAULT_CONFIG = Quests.resolveConfig(nil)

function Quests.dayIndex(now: number, config: Config?): number
	local cfg = config or DEFAULT_CONFIG
	return math.floor((now - cfg.dayOffset) / cfg.dayLength)
end

-- How many of an objective are needed.
function Quests.required(objective: ObjectiveDef): number
	if objective.kind == "reach" then
		return 1
	end
	local amount = objective.amount
	return if amount and isCount(amount) then amount else 1
end

local function validateObjective(questId: string, raw: any, seen: { [string]: boolean }, errors: { string })
	if type(raw) ~= "table" or not isName(raw.id) then
		table.insert(errors, questId .. ": objective without an id")
		return
	end
	local label = questId .. "." .. raw.id
	if seen[raw.id] then
		table.insert(errors, label .. ": duplicate objective id")
	end
	seen[raw.id] = true
	if raw.kind == "count" then
		if not isName(raw.event) then
			table.insert(errors, label .. ": count objectives need an event")
		end
	elseif raw.kind == "collect" or raw.kind == "reach" then
		if not isName(raw.target) then
			table.insert(errors, label .. ": " .. raw.kind .. " objectives need a target")
		end
	else
		table.insert(errors, label .. ": unknown kind " .. tostring(raw.kind))
	end
	if raw.amount ~= nil and not isCount(raw.amount) then
		table.insert(errors, label .. ": amount must be a positive integer")
	end
end

-- Checks a list of quest definitions. Returns whether they are valid and every problem found.
function Quests.validateDefinitions(definitions: { QuestDef }): (boolean, { string })
	local errors: { string } = {}
	if type(definitions) ~= "table" then
		return false, { "definitions must be an array" }
	end
	local list: { any } = definitions :: any
	local byId: { [string]: any } = {}
	for index, raw in list do
		if type(raw) ~= "table" or not isName(raw.id) then
			table.insert(errors, "quest #" .. tostring(index) .. ": missing id")
			continue
		end
		if byId[raw.id] then
			table.insert(errors, raw.id .. ": duplicate quest id")
		end
		byId[raw.id] = raw
		if type(raw.objectives) ~= "table" or #raw.objectives == 0 then
			table.insert(errors, raw.id .. ": needs at least one objective")
		else
			local seen: { [string]: boolean } = {}
			for _, objective in raw.objectives do
				validateObjective(raw.id, objective, seen, errors)
			end
		end
		if raw.cooldown ~= nil and not (isFinite(raw.cooldown) and raw.cooldown >= 0) then
			table.insert(errors, raw.id .. ": cooldown must be >= 0")
		end
		if raw.timeLimit ~= nil and not (isFinite(raw.timeLimit) and raw.timeLimit > 0) then
			table.insert(errors, raw.id .. ": timeLimit must be > 0")
		end
	end
	for id, raw in byId do
		if raw.prerequisites ~= nil then
			if type(raw.prerequisites) ~= "table" then
				table.insert(errors, id .. ": prerequisites must be an array")
			else
				for _, prerequisite in raw.prerequisites do
					if byId[prerequisite] == nil then
						table.insert(errors, id .. ": unknown prerequisite " .. tostring(prerequisite))
					end
				end
			end
		end
		if raw.next ~= nil and byId[raw.next] == nil then
			table.insert(errors, id .. ": unknown next quest " .. tostring(raw.next))
		end
	end
	-- Prerequisite cycles would make quests impossible to start.
	local marks: { [string]: number } = {}
	local function hasCycle(id: string): boolean
		local mark = marks[id]
		if mark == 1 then
			return true
		elseif mark == 2 then
			return false
		end
		marks[id] = 1
		local raw = byId[id]
		if raw and type(raw.prerequisites) == "table" then
			for _, prerequisite in raw.prerequisites do
				if type(prerequisite) == "string" and byId[prerequisite] and hasCycle(prerequisite) then
					return true
				end
			end
		end
		marks[id] = 2
		return false
	end
	local ids: { string } = {}
	for id in byId do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		if hasCycle(id) then
			table.insert(errors, id .. ": prerequisite cycle")
			break
		end
	end
	return #errors == 0, errors
end

-- Builds a lookup from definitions. Raises an error listing every problem when they are invalid.
function Quests.newCatalog(definitions: { QuestDef }): Catalog
	local ok, errors = Quests.validateDefinitions(definitions)
	if not ok then
		error("invalid quest definitions: " .. table.concat(errors, "; "), 2)
	end
	local byId: { [string]: QuestDef } = {}
	local order: { string } = {}
	for _, definition in definitions do
		byId[definition.id] = definition
		table.insert(order, definition.id)
	end
	return { byId = byId, order = order }
end

function Quests.newState(): PlayerState
	return { active = {}, completed = {} }
end

local function countActive(state: PlayerState): number
	local count = 0
	for _ in state.active do
		count += 1
	end
	return count
end

-- Whether the player may start `questId` now. Returns false and a reason when not.
function Quests.canStart(
	catalog: Catalog,
	state: PlayerState,
	questId: string,
	now: number,
	config: Config?
): (boolean, string?)
	local cfg = config or DEFAULT_CONFIG
	local definition = catalog.byId[questId]
	if not definition then
		return false, "unknown quest"
	end
	if state.active[questId] then
		return false, "already active"
	end
	if countActive(state) >= cfg.maxActive then
		return false, "too many active quests"
	end
	local prerequisites = definition.prerequisites
	if prerequisites then
		for _, prerequisite in prerequisites do
			if not state.completed[prerequisite] then
				return false, "prerequisites not met"
			end
		end
	end
	local record = state.completed[questId]
	if record then
		if definition.daily then
			if Quests.dayIndex(record.lastAt, cfg) >= Quests.dayIndex(now, cfg) then
				return false, "already done today"
			end
		elseif definition.repeatable then
			if now - record.lastAt < (definition.cooldown or 0) then
				return false, "on cooldown"
			end
		else
			return false, "already completed"
		end
	end
	return true, nil
end

function Quests.start(
	catalog: Catalog,
	state: PlayerState,
	questId: string,
	now: number,
	config: Config?
): (boolean, string?)
	local ok, reason = Quests.canStart(catalog, state, questId, now, config)
	local definition = catalog.byId[questId]
	if not ok or not definition then
		return false, reason
	end
	local progress: { [string]: number } = {}
	for _, objective in definition.objectives do
		progress[objective.id] = 0
	end
	state.active[questId] = { startedAt = now, progress = progress }
	return true, nil
end

function Quests.abandon(state: PlayerState, questId: string): boolean
	if state.active[questId] == nil then
		return false
	end
	state.active[questId] = nil
	return true
end

function Quests.matches(objective: ObjectiveDef, event: Event): boolean
	if objective.kind == "count" then
		return event.type == objective.event and (objective.target == nil or objective.target == event.target)
	elseif objective.kind == "collect" then
		return event.type == COLLECT_EVENT and event.target == objective.target
	elseif objective.kind == "reach" then
		return event.type == REACH_EVENT and event.target == objective.target
	end
	return false
end

function Quests.isComplete(definition: QuestDef, active: ActiveQuest): boolean
	for _, objective in definition.objectives do
		if (active.progress[objective.id] or 0) < Quests.required(objective) then
			return false
		end
	end
	return true
end

local function isExpired(definition: QuestDef, active: ActiveQuest, now: number): boolean
	local limit = definition.timeLimit
	return limit ~= nil and now - active.startedAt > limit
end

local function markCompleted(state: PlayerState, questId: string, now: number)
	state.active[questId] = nil
	local record = state.completed[questId]
	local count = if record then record.count + 1 else 1
	state.completed[questId] = { count = count, lastAt = now }
end

-- Applies one game event to every active quest, in definition order.
-- Completed quests move to `completed`, and chained quests with autoStartNext start straight away.
function Quests.handleEvent(
	catalog: Catalog,
	state: PlayerState,
	event: Event,
	now: number,
	config: Config?
): EventResult
	local result: EventResult = { updated = {}, completed = {}, started = {} }
	if type(event) ~= "table" or type(event.type) ~= "string" then
		return result
	end
	local amount: number = event.amount or 1
	if not isFinite(amount) or amount <= 0 then
		return result
	end
	for _, questId in catalog.order do
		local active = state.active[questId]
		local definition = catalog.byId[questId]
		if active and definition and not isExpired(definition, active, now) then
			local changed = false
			for _, objective in definition.objectives do
				local current = active.progress[objective.id] or 0
				local needed = Quests.required(objective)
				if current < needed and Quests.matches(objective, event) then
					active.progress[objective.id] = math.min(needed, current + amount)
					changed = true
				end
			end
			if changed then
				table.insert(result.updated, questId)
				if Quests.isComplete(definition, active) then
					markCompleted(state, questId, now)
					table.insert(result.completed, questId)
				end
			end
		end
	end
	for _, questId in result.completed do
		local definition = catalog.byId[questId]
		local nextId = if definition then definition.next else nil
		local autoStart = if definition then definition.autoStartNext ~= false else false
		if nextId and autoStart and Quests.start(catalog, state, nextId, now, config) then
			table.insert(result.started, nextId)
		end
	end
	return result
end

-- Removes active quests whose time limit has run out and returns their ids.
function Quests.expire(catalog: Catalog, state: PlayerState, now: number): { string }
	local expired: { string } = {}
	for _, questId in catalog.order do
		local active = state.active[questId]
		local definition = catalog.byId[questId]
		if active and definition and isExpired(definition, active, now) then
			state.active[questId] = nil
			table.insert(expired, questId)
		end
	end
	return expired
end

-- Quests the player could start right now, in definition order.
function Quests.available(catalog: Catalog, state: PlayerState, now: number, config: Config?): { string }
	local ids: { string } = {}
	for _, questId in catalog.order do
		if Quests.canStart(catalog, state, questId, now, config) then
			table.insert(ids, questId)
		end
	end
	return ids
end

-- Per-objective progress of an active quest, or nil when it is not active.
function Quests.progressOf(catalog: Catalog, state: PlayerState, questId: string): { ObjectiveProgress }?
	local active = state.active[questId]
	local definition = catalog.byId[questId]
	if not active or not definition then
		return nil
	end
	local rows: { ObjectiveProgress } = {}
	for _, objective in definition.objectives do
		local current = active.progress[objective.id] or 0
		table.insert(rows, { id = objective.id, current = current, required = Quests.required(objective) })
	end
	return rows
end

-- Plain data for a DataStore. Shape: { version, active = { [id] = { startedAt, progress } }, completed }.
function Quests.serialize(state: PlayerState): { [string]: any }
	local active: { [string]: any } = {}
	for questId, quest in state.active do
		active[questId] = { startedAt = quest.startedAt, progress = table.clone(quest.progress) }
	end
	local completed: { [string]: any } = {}
	for questId, record in state.completed do
		completed[questId] = { count = record.count, lastAt = record.lastAt }
	end
	return { version = SAVE_VERSION, active = active, completed = completed }
end

-- Rebuilds state from untrusted saved data. Unknown quests and objectives are dropped,
-- and progress is clamped to what each objective needs.
function Quests.deserialize(data: any, catalog: Catalog): PlayerState
	local state = Quests.newState()
	if type(data) ~= "table" then
		return state
	end
	if type(data.completed) == "table" then
		for questId, record in data.completed do
			local known = type(questId) == "string" and catalog.byId[questId] ~= nil
			if known and type(record) == "table" and isCount(record.count) and isFinite(record.lastAt) then
				state.completed[questId] = { count = record.count, lastAt = record.lastAt }
			end
		end
	end
	if type(data.active) == "table" then
		for questId, raw in data.active do
			local definition = if type(questId) == "string" then catalog.byId[questId] else nil
			if definition and type(raw) == "table" and isFinite(raw.startedAt) then
				local savedProgress: { [any]: any } = if type(raw.progress) == "table" then raw.progress else {}
				local progress: { [string]: number } = {}
				for _, objective in definition.objectives do
					local value = savedProgress[objective.id]
					local current = if isFinite(value) then value else 0
					progress[objective.id] = math.clamp(math.floor(current), 0, Quests.required(objective))
				end
				state.active[questId] = { startedAt = raw.startedAt, progress = progress }
			end
		end
	end
	return state
end

return Quests
