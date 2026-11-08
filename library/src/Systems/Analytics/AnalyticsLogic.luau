--!strict
-- Analytics event pipeline. Pure Luau: no Roblox globals, no clock and no random source.
-- Validates events against the documented AnalyticsService limits, keeps funnel steps in order
-- per player, samples players, rate-limits, drops duplicates and batches events for a sink.
-- The sink is any table with `write(events)`, so tests use `memorySink()` and the server adapter
-- maps events to AnalyticsService.

local RateLimiter = require("../../Util/RateLimiter")

export type Kind = "economy" | "funnel" | "onboarding" | "progression" | "custom"
export type Flow = "Source" | "Sink"
export type ProgressionStatus = "Start" | "Complete" | "Fail"

-- Keys are "CustomField01", "CustomField02" and "CustomField03"; values are strings.
export type Fields = { [string]: string }

export type Event = {
	kind: Kind,
	userId: number,
	time: number, -- the `now` passed to track
	-- economy
	flow: Flow?,
	currency: string?,
	amount: number?,
	balance: number?,
	transaction: string?,
	sku: string?,
	-- funnel and onboarding
	funnel: string?,
	sessionId: string?,
	step: number?,
	stepName: string?,
	-- progression
	path: string?,
	status: ProgressionStatus?,
	level: number?,
	levelName: string?,
	-- custom
	name: string?,
	value: number?,
	fields: Fields?,
}

export type Sink = { write: (events: { Event }) -> () }
export type MemorySink = { events: { Event }, batches: number, write: (events: { Event }) -> () }

export type Config = {
	maxNameLength: number?, -- characters in any name or label (default 50)
	maxFieldLength: number?, -- characters in a custom field value (default 50)
	maxAmount: number?, -- largest economy amount, balance or custom value (default 1e12)
	maxLevel: number?, -- largest progression level (default 10000)
	maxSteps: number?, -- steps per funnel (default 100, the documented limit)
	maxCustomNames: number?, -- distinct custom event names (default 100, documented)
	maxFunnels: number?, -- distinct funnel names (default 10, documented)
	maxCurrencies: number?, -- distinct economy currencies (default 10, documented)
	maxPaths: number?, -- distinct progression paths (default 10, a kit choice)
	batchSize: number?, -- flush when this many events are queued (default 20)
	flushInterval: number?, -- seconds before a partial batch is flushed (default 5)
	maxQueue: number?, -- events kept before new ones are dropped (default 1000)
	dedupeWindow: number?, -- seconds an identical event is ignored (default 1, 0 disables)
	coalesceCustom: boolean?, -- sum identical queued custom events into one (default false)
	rejectLongNumbers: boolean?, -- reject text with 7+ digits in a row, likely ids (default true)
	rate: RateLimiter.Options?, -- per player (default capacity 30, refill 0.5 per second)
	sampleRates: { [string]: number }?, -- per kind, 0 to 1 (default 1); decided once per player
	sessionPrefix: string?, -- start of generated funnel session ids (default "s")
}

export type Settings = {
	maxNameLength: number,
	maxFieldLength: number,
	maxAmount: number,
	maxLevel: number,
	maxSteps: number,
	maxCustomNames: number,
	maxFunnels: number,
	maxCurrencies: number,
	maxPaths: number,
	batchSize: number,
	flushInterval: number,
	maxQueue: number,
	dedupeWindow: number,
	coalesceCustom: boolean,
	rejectLongNumbers: boolean,
	rate: RateLimiter.Options,
	sampleRates: { [string]: number },
	sessionPrefix: string,
}

export type Progress = { sessionId: string, step: number }

export type Stats = { accepted: number, coalesced: number, sinkErrors: number, dropped: { [string]: number } }

export type State = {
	settings: Settings,
	queue: { Event },
	lastFlush: number,
	recent: { [string]: number },
	coalesce: { [string]: number },
	funnels: { [string]: Progress },
	sampled: { [string]: boolean },
	seen: { [string]: { [string]: boolean } },
	seenCount: { [string]: number },
	sessionCounter: number,
	limiter: RateLimiter.Limiter,
	stats: Stats,
}

local AnalyticsLogic = {}

AnalyticsLogic.FIELD_KEYS = { "CustomField01", "CustomField02", "CustomField03" }
AnalyticsLogic.KINDS = { "economy", "funnel", "onboarding", "progression", "custom" }

local NAME_PATTERN = "^[%w][%w _%-%.:]*$"
local FIELD_PATTERN = "^[%w%-][%w _%-%.:]*$"
local LONG_NUMBER = "%d%d%d%d%d%d%d"
local SEP = "\31"
local ONBOARDING = "\0onboarding"

local VALID_FIELD_KEY: { [string]: boolean } = { CustomField01 = true, CustomField02 = true, CustomField03 = true }

local VALID_KIND: { [string]: boolean } = {
	economy = true,
	funnel = true,
	onboarding = true,
	progression = true,
	custom = true,
}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isInteger(value: any): boolean
	return isFinite(value) and value % 1 == 0
end

local function positiveNumber(value: any, fallback: number, label: string): number
	if value == nil then
		return fallback
	end
	assert(isFinite(value) and value > 0, label .. " must be a positive number")
	return value
end

local function nonNegative(value: any, fallback: number, label: string): number
	if value == nil then
		return fallback
	end
	assert(isFinite(value) and value >= 0, label .. " must be a number >= 0")
	return value
end

function AnalyticsLogic.validateConfig(config: Config?): Settings
	local cfg: Config = config or {}
	local rates: { [string]: number } = {}
	if cfg.sampleRates ~= nil then
		assert(type(cfg.sampleRates) == "table", "sampleRates must be a table")
		for kind, rate in cfg.sampleRates do
			assert(VALID_KIND[kind] == true, "unknown sample kind " .. tostring(kind))
			assert(isFinite(rate) and rate >= 0 and rate <= 1, "sample rates must be between 0 and 1")
			rates[kind] = rate
		end
	end
	local rate: RateLimiter.Options = cfg.rate or { capacity = 30, refillPerSecond = 0.5 }
	assert(type(rate) == "table", "rate must be a table")
	assert(isFinite(rate.capacity) and rate.capacity > 0, "rate.capacity must be positive")
	assert(isFinite(rate.refillPerSecond) and rate.refillPerSecond >= 0, "rate.refillPerSecond must be >= 0")
	local prefix = cfg.sessionPrefix or "s"
	assert(type(prefix) == "string" and #prefix <= 20, "sessionPrefix must be a short string")
	local settings: Settings = {
		maxNameLength = positiveNumber(cfg.maxNameLength, 50, "maxNameLength"),
		maxFieldLength = positiveNumber(cfg.maxFieldLength, 50, "maxFieldLength"),
		maxAmount = positiveNumber(cfg.maxAmount, 1e12, "maxAmount"),
		maxLevel = positiveNumber(cfg.maxLevel, 10000, "maxLevel"),
		maxSteps = positiveNumber(cfg.maxSteps, 100, "maxSteps"),
		maxCustomNames = positiveNumber(cfg.maxCustomNames, 100, "maxCustomNames"),
		maxFunnels = positiveNumber(cfg.maxFunnels, 10, "maxFunnels"),
		maxCurrencies = positiveNumber(cfg.maxCurrencies, 10, "maxCurrencies"),
		maxPaths = positiveNumber(cfg.maxPaths, 10, "maxPaths"),
		batchSize = positiveNumber(cfg.batchSize, 20, "batchSize"),
		flushInterval = nonNegative(cfg.flushInterval, 5, "flushInterval"),
		maxQueue = positiveNumber(cfg.maxQueue, 1000, "maxQueue"),
		dedupeWindow = nonNegative(cfg.dedupeWindow, 1, "dedupeWindow"),
		coalesceCustom = cfg.coalesceCustom == true,
		rejectLongNumbers = cfg.rejectLongNumbers ~= false,
		rate = { capacity = rate.capacity, refillPerSecond = rate.refillPerSecond },
		sampleRates = rates,
		sessionPrefix = prefix,
	}
	return settings
end

function AnalyticsLogic.new(config: Config?, now: number?): State
	local settings = AnalyticsLogic.validateConfig(config)
	return {
		settings = settings,
		queue = {},
		lastFlush = now or 0,
		recent = {},
		coalesce = {},
		funnels = {},
		sampled = {},
		seen = { custom = {}, funnel = {}, currency = {}, path = {} },
		seenCount = { custom = 0, funnel = 0, currency = 0, path = 0 },
		sessionCounter = 0,
		limiter = RateLimiter.new(settings.rate),
		stats = { accepted = 0, coalesced = 0, sinkErrors = 0, dropped = {} },
	}
end

-- The documented global AnalyticsService budget: 120 + 20 * CCU requests per minute.
function AnalyticsLogic.serverBudgetPerMinute(playerCount: number): number
	assert(isFinite(playerCount) and playerCount >= 0, "playerCount must be a number >= 0")
	return 120 + 20 * math.floor(playerCount)
end

-- Returns nil when `value` is a valid name, or the reason it is not.
local function checkText(settings: Settings, value: any, pattern: string, maxLength: number, label: string): string?
	if type(value) ~= "string" or #value == 0 or #value > maxLength then
		return "invalid " .. label
	end
	if not string.find(value, pattern) or string.sub(value, -1) == " " then
		return "invalid " .. label
	end
	if settings.rejectLongNumbers and string.find(value, LONG_NUMBER) then
		return "possible personal data"
	end
	return nil
end

function AnalyticsLogic.checkName(settings: Settings, value: any, label: string?): string?
	return checkText(settings, value, NAME_PATTERN, settings.maxNameLength, label or "name")
end

local function checkOptionalName(settings: Settings, value: any, label: string): string?
	if value == nil then
		return nil
	end
	return checkText(settings, value, NAME_PATTERN, settings.maxNameLength, label)
end

-- Accepts { "a", "b" } (up to three values) or { CustomField01 = "a", ... }.
-- Numbers and booleans become strings. Returns the normalized fields (nil when empty) or a reason.
function AnalyticsLogic.normalizeFields(settings: Settings, raw: any): (Fields?, string?)
	if raw == nil then
		return nil, nil
	end
	if type(raw) ~= "table" then
		return nil, "invalid fields"
	end
	local out: Fields = {}
	local count = 0
	for key, value in raw do
		local fieldKey: string? = nil
		if type(key) == "number" then
			fieldKey = AnalyticsLogic.FIELD_KEYS[key]
		elseif type(key) == "string" and VALID_FIELD_KEY[key] then
			fieldKey = key
		end
		if fieldKey == nil or out[fieldKey] ~= nil then
			return nil, "invalid fields"
		end
		local text: string
		if type(value) == "string" then
			text = value
		elseif type(value) == "boolean" or isFinite(value) then
			text = tostring(value)
		else
			return nil, "invalid fields"
		end
		local reason = checkText(settings, text, FIELD_PATTERN, settings.maxFieldLength, "fields")
		if reason then
			return nil, reason
		end
		out[fieldKey] = text
		count += 1
	end
	if count == 0 then
		return nil, nil
	end
	return out, nil
end

local function inRange(value: any, maximum: number): boolean
	return isInteger(value) and value >= 1 and value <= maximum
end

local function validateEconomy(settings: Settings, input: { [string]: any }, event: Event): string?
	if input.flow ~= "Source" and input.flow ~= "Sink" then
		return "invalid flow"
	end
	event.flow = input.flow
	local reason = AnalyticsLogic.checkName(settings, input.currency, "currency")
	if reason == nil then
		reason = AnalyticsLogic.checkName(settings, input.transaction, "transaction")
	end
	if reason == nil then
		reason = checkOptionalName(settings, input.sku, "sku")
	end
	if reason then
		return reason
	end
	if not isFinite(input.amount) or input.amount <= 0 or input.amount > settings.maxAmount then
		return "invalid amount"
	end
	if not isFinite(input.balance) or input.balance < 0 or input.balance > settings.maxAmount then
		return "invalid balance"
	end
	event.currency = input.currency
	event.transaction = input.transaction
	event.sku = input.sku
	event.amount = input.amount
	event.balance = input.balance
	return nil
end

local function validateFunnel(settings: Settings, input: { [string]: any }, event: Event): string?
	if input.kind == "funnel" then
		local reason = AnalyticsLogic.checkName(settings, input.funnel, "funnel")
		if reason == nil then
			reason = checkOptionalName(settings, input.sessionId, "sessionId")
		end
		if reason then
			return reason
		end
		event.funnel = input.funnel
		event.sessionId = input.sessionId
	end
	if not inRange(input.step, settings.maxSteps) then
		return "invalid step"
	end
	local reason = checkOptionalName(settings, input.stepName, "stepName")
	if reason then
		return reason
	end
	event.step = input.step
	event.stepName = input.stepName
	return nil
end

local function validateProgression(settings: Settings, input: { [string]: any }, event: Event): string?
	local status = input.status
	if status ~= "Start" and status ~= "Complete" and status ~= "Fail" then
		return "invalid status"
	end
	event.status = status
	local reason = AnalyticsLogic.checkName(settings, input.path, "path")
	if reason == nil then
		reason = checkOptionalName(settings, input.levelName, "levelName")
	end
	if reason then
		return reason
	end
	if not inRange(input.level, settings.maxLevel) then
		return "invalid level"
	end
	event.path = input.path
	event.level = input.level
	event.levelName = input.levelName
	return nil
end

local function validateCustom(settings: Settings, input: { [string]: any }, event: Event): string?
	local reason = AnalyticsLogic.checkName(settings, input.name, "name")
	if reason then
		return reason
	end
	local value = input.value
	if value == nil then
		value = 1
	end
	if not isFinite(value) or math.abs(value) > settings.maxAmount then
		return "invalid value"
	end
	event.name = input.name
	event.value = value
	return nil
end

-- Checks an untrusted event table and returns a clean copy, or nil and a reason.
function AnalyticsLogic.validate(settings: Settings, input: any, now: number): (Event?, string?)
	if type(input) ~= "table" then
		return nil, "invalid event"
	end
	local kind = input.kind
	if type(kind) ~= "string" or not VALID_KIND[kind] then
		return nil, "invalid kind"
	end
	if not isInteger(input.userId) or input.userId == 0 then
		return nil, "invalid user"
	end
	local fields, fieldReason = AnalyticsLogic.normalizeFields(settings, input.fields)
	if fieldReason then
		return nil, fieldReason
	end
	local event: Event = { kind = kind :: Kind, userId = input.userId, time = now, fields = fields }
	local reason: string?
	if kind == "economy" then
		reason = validateEconomy(settings, input, event)
	elseif kind == "funnel" or kind == "onboarding" then
		reason = validateFunnel(settings, input, event)
	elseif kind == "progression" then
		reason = validateProgression(settings, input, event)
	else
		reason = validateCustom(settings, input, event)
	end
	if reason then
		return nil, reason
	end
	return event, nil
end

local function funnelKey(userId: number, funnel: string): string
	return tostring(userId) .. SEP .. funnel
end

-- Works out the funnel progress this step would produce, without changing the state.
local function checkOrder(state: State, event: Event): (string?, Progress?, string?)
	if event.kind ~= "funnel" and event.kind ~= "onboarding" then
		return nil, nil, nil
	end
	local onboarding = event.kind == "onboarding"
	local key = funnelKey(event.userId, if onboarding then ONBOARDING else event.funnel :: string)
	local step = event.step :: number
	local current = state.funnels[key]
	if step == 1 then
		if current and (onboarding or current.step == 1) then
			if onboarding or event.sessionId == nil or event.sessionId == current.sessionId then
				return nil, nil, "duplicate step"
			end
		end
		local sessionId = event.sessionId
		if sessionId == nil then
			sessionId = if onboarding then "onboarding" else ""
		end
		return key, { sessionId = sessionId :: string, step = 1 }, nil
	end
	if current == nil then
		return nil, nil, "funnel not started"
	end
	if event.sessionId ~= nil and event.sessionId ~= current.sessionId then
		return nil, nil, "wrong session"
	end
	if step <= current.step then
		return nil, nil, "duplicate step"
	end
	if step > current.step + 1 then
		return nil, nil, "skipped step"
	end
	return key, { sessionId = current.sessionId, step = step }, nil
end

local function commitOrder(state: State, key: string?, progress: Progress?, event: Event)
	if key == nil or progress == nil then
		return
	end
	if progress.sessionId == "" then
		state.sessionCounter += 1
		progress.sessionId = state.settings.sessionPrefix .. tostring(state.sessionCounter)
	end
	state.funnels[key] = progress
	event.sessionId = progress.sessionId
end

local function cardinalitySlot(event: Event): (string?, string?, string?)
	if event.kind == "custom" then
		return "custom", event.name, "maxCustomNames"
	elseif event.kind == "funnel" then
		return "funnel", event.funnel, "maxFunnels"
	elseif event.kind == "economy" then
		return "currency", event.currency, "maxCurrencies"
	elseif event.kind == "progression" then
		return "path", event.path, "maxPaths"
	end
	return nil, nil, nil
end

local function checkCardinality(state: State, event: Event): string?
	local slot, value, limitKey = cardinalitySlot(event)
	if slot == nil or value == nil or limitKey == nil then
		return nil
	end
	if state.seen[slot][value] then
		return nil
	end
	local limit = (state.settings :: any)[limitKey] :: number
	if state.seenCount[slot] >= limit then
		return "too many names"
	end
	return nil
end

local function commitCardinality(state: State, event: Event)
	local slot, value = cardinalitySlot(event)
	if slot == nil or value == nil or state.seen[slot][value] then
		return
	end
	state.seen[slot][value] = true
	state.seenCount[slot] += 1
end

local function fieldsKey(fields: Fields?): string
	if fields == nil then
		return ""
	end
	local a = fields.CustomField01 or ""
	local b = fields.CustomField02 or ""
	local c = fields.CustomField03 or ""
	return a .. SEP .. b .. SEP .. c
end

local function part(value: any): string
	return if value == nil then "" else tostring(value)
end

-- Identifies an event for duplicate detection. Two events with the same key are the same event.
function AnalyticsLogic.dedupeKey(event: Event): string
	local parts = {
		event.kind,
		tostring(event.userId),
		part(event.flow),
		part(event.currency),
		part(event.amount),
		part(event.balance),
		part(event.transaction),
		part(event.sku),
		part(event.funnel),
		part(event.sessionId),
		part(event.step),
		part(event.stepName),
		part(event.path),
		part(event.status),
		part(event.level),
		part(event.levelName),
		part(event.name),
		part(event.value),
		fieldsKey(event.fields),
	}
	return table.concat(parts, SEP)
end

local function coalesceKey(event: Event): string
	return table.concat({ tostring(event.userId), event.name or "", fieldsKey(event.fields) }, SEP)
end

local function isSampled(state: State, event: Event, rng: (() -> number)?): boolean
	local rate = state.settings.sampleRates[event.kind]
	if rate == nil or rate >= 1 then
		return true
	end
	local key = tostring(event.userId) .. SEP .. event.kind
	local decided = state.sampled[key]
	if decided ~= nil then
		return decided
	end
	local included = false
	if rate > 0 then
		if rng == nil then
			error("an rng is needed when a sample rate is between 0 and 1")
		end
		included = rng() < rate
	end
	state.sampled[key] = included
	return included
end

local function drop(state: State, reason: string): (boolean, string?)
	state.stats.dropped[reason] = (state.stats.dropped[reason] or 0) + 1
	return false, reason
end

-- Validates, orders, samples, dedupes, rate-limits and queues one event.
-- `rng` returns a number in [0, 1); it is only needed when a sample rate is between 0 and 1.
-- Returns true, or false and the reason the event was dropped.
function AnalyticsLogic.track(state: State, input: any, now: number, rng: (() -> number)?): (boolean, string?)
	assert(isFinite(now), "now must be a finite number")
	local event, reason = AnalyticsLogic.validate(state.settings, input, now)
	if event == nil then
		return drop(state, reason or "invalid event")
	end
	if not isSampled(state, event, rng) then
		return drop(state, "sampled out")
	end
	local key, progress, orderReason = checkOrder(state, event)
	if orderReason then
		return drop(state, orderReason)
	end
	local cardinalityReason = checkCardinality(state, event)
	if cardinalityReason then
		return drop(state, cardinalityReason)
	end
	local settings = state.settings
	local dedupe = AnalyticsLogic.dedupeKey(event)
	if settings.dedupeWindow > 0 then
		local seenAt = state.recent[dedupe]
		if seenAt ~= nil and now - seenAt < settings.dedupeWindow and now >= seenAt then
			return drop(state, "duplicate")
		end
	end

	local capacityReason: string? = nil
	local coalesceIndex: number? = nil
	if settings.coalesceCustom and event.kind == "custom" then
		coalesceIndex = state.coalesce[coalesceKey(event)]
	end
	if coalesceIndex == nil and #state.queue >= settings.maxQueue then
		capacityReason = "queue full"
	elseif not state.limiter:allow(tostring(event.userId), now) then
		capacityReason = "rate limited"
	end

	-- A capacity drop still means the step happened in game, so funnel progress advances and
	-- the next step stays valid.
	commitOrder(state, key, progress, event)
	if capacityReason then
		return drop(state, capacityReason)
	end
	commitCardinality(state, event)
	if settings.dedupeWindow > 0 then
		state.recent[dedupe] = now
	end
	state.stats.accepted += 1
	if coalesceIndex ~= nil then
		local queued = state.queue[coalesceIndex]
		queued.value = (queued.value or 0) + (event.value or 0)
		state.stats.coalesced += 1
		return true, nil
	end
	table.insert(state.queue, event)
	if settings.coalesceCustom and event.kind == "custom" then
		state.coalesce[coalesceKey(event)] = #state.queue
	end
	return true, nil
end

function AnalyticsLogic.shouldFlush(state: State, now: number): boolean
	local count = #state.queue
	if count == 0 then
		return false
	end
	return count >= state.settings.batchSize or now - state.lastFlush >= state.settings.flushInterval
end

-- Sends every queued event to the sink in one batch and empties the queue.
-- Returns how many events were handed over, and the sink error if it raised one.
-- A failed batch is not retried, so a broken sink cannot grow the queue forever.
function AnalyticsLogic.flush(state: State, sink: Sink, now: number): (number, string?)
	state.lastFlush = now
	local batch = state.queue
	if #batch == 0 then
		return 0, nil
	end
	state.queue = {}
	state.coalesce = {}
	local ok, err = pcall(sink.write, batch)
	if not ok then
		state.stats.sinkErrors += 1
		return #batch, tostring(err)
	end
	return #batch, nil
end

-- Forgets dedupe entries older than the window.
function AnalyticsLogic.prune(state: State, now: number)
	local window = state.settings.dedupeWindow
	for key, seenAt in state.recent do
		if now - seenAt >= window or seenAt > now then
			state.recent[key] = nil
		end
	end
end

-- Call regularly (the adapter does it on Heartbeat). Prunes and flushes when a batch is due.
function AnalyticsLogic.tick(state: State, sink: Sink, now: number): (number, string?)
	AnalyticsLogic.prune(state, now)
	if AnalyticsLogic.shouldFlush(state, now) then
		return AnalyticsLogic.flush(state, sink, now)
	end
	return 0, nil
end

-- The session id and last step of a player's funnel, or nil when the funnel has not started.
function AnalyticsLogic.funnelProgress(state: State, userId: number, funnel: string?): Progress?
	return state.funnels[funnelKey(userId, funnel or ONBOARDING)]
end

-- Ends a funnel so the next step 1 starts a fresh session.
function AnalyticsLogic.endFunnel(state: State, userId: number, funnel: string)
	state.funnels[funnelKey(userId, funnel)] = nil
end

-- Drops all per-player state (funnels, sampling decisions, rate bucket). Queued events stay queued,
-- so flush first when the player is leaving.
function AnalyticsLogic.forgetPlayer(state: State, userId: number)
	local prefix = tostring(userId) .. SEP
	for key in state.funnels do
		if string.sub(key, 1, #prefix) == prefix then
			state.funnels[key] = nil
		end
	end
	for key in state.sampled do
		if string.sub(key, 1, #prefix) == prefix then
			state.sampled[key] = nil
		end
	end
	state.limiter:forget(tostring(userId))
end

function AnalyticsLogic.memorySink(): MemorySink
	local events: { Event } = {}
	local sink: MemorySink
	sink = {
		events = events,
		batches = 0,
		write = function(batch: { Event })
			for _, event in batch do
				table.insert(events, event)
			end
			sink.batches += 1
		end,
	}
	return sink
end

return AnalyticsLogic
