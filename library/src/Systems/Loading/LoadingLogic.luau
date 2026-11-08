--!strict
-- Loading screen rules. Pure Luau: `now` and `dt` are passed in.
-- Splits assets into preload batches, tracks loaded and failed counts, smooths the displayed bar,
-- and decides when the screen may close: once loading is done (or timed out) and the minimum display
-- time has passed, or as soon as the player skips (allowed after `skipAfter` seconds).

local LoadingConfig = require("./LoadingConfig")

export type Config = {
	batchSize: number,
	minDisplayTime: number,
	allowSkip: boolean,
	skipAfter: number,
	maxWait: number,
	displaySpeed: number,
}

export type Tracker = {
	total: number,
	loaded: number,
	failed: number,
	startedAt: number,
	finishedAt: number?,
	skipped: boolean,
}

export type Status = "loading" | "ready" | "done" | "skipped" | "timeout"
export type Stage = { weight: number, progress: number }

local Loading = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Loading.resolveConfig(overrides: { [string]: any }?): Config
	local source: { [string]: any } = overrides or {}
	local function numberOr(key: string, minimum: number): number
		local value = source[key]
		if isFinite(value) and value >= minimum then
			return value
		end
		return (LoadingConfig :: any)[key]
	end
	local allowSkip = if type(source.allowSkip) == "boolean" then source.allowSkip else LoadingConfig.allowSkip
	return {
		batchSize = math.floor(numberOr("batchSize", 1)),
		minDisplayTime = numberOr("minDisplayTime", 0),
		allowSkip = allowSkip,
		skipAfter = numberOr("skipAfter", 0),
		maxWait = numberOr("maxWait", 0),
		displaySpeed = numberOr("displaySpeed", 0.01),
	}
end

-- Splits `items` into arrays of at most `batchSize`, keeping order.
function Loading.batches(items: { any }, batchSize: number): { { any } }
	local size = math.max(1, math.floor(batchSize))
	local result: { { any } } = {}
	local current: { any } = {}
	for _, item in items do
		table.insert(current, item)
		if #current >= size then
			table.insert(result, current)
			current = {}
		end
	end
	if #current > 0 then
		table.insert(result, current)
	end
	return result
end

function Loading.newTracker(total: number, now: number): Tracker
	local count = if isFinite(total) then math.max(0, math.floor(total)) else 0
	return {
		total = count,
		loaded = 0,
		failed = 0,
		startedAt = now,
		finishedAt = if count == 0 then now else nil,
		skipped = false,
	}
end

local function record(tracker: Tracker, loaded: number, failed: number, now: number)
	local room = tracker.total - tracker.loaded - tracker.failed
	local addLoaded = math.clamp(math.floor(loaded), 0, room)
	local addFailed = math.clamp(math.floor(failed), 0, room - addLoaded)
	tracker.loaded += addLoaded
	tracker.failed += addFailed
	if tracker.finishedAt == nil and tracker.loaded + tracker.failed >= tracker.total then
		tracker.finishedAt = now
	end
end

function Loading.markLoaded(tracker: Tracker, count: number, now: number)
	record(tracker, if isFinite(count) then count else 0, 0, now)
end

function Loading.markFailed(tracker: Tracker, count: number, now: number)
	record(tracker, 0, if isFinite(count) then count else 0, now)
end

-- Finished share from 0 to 1. Failed assets count as finished so a broken asset cannot stall the bar.
function Loading.progress(tracker: Tracker): number
	if tracker.total == 0 then
		return 1
	end
	return (tracker.loaded + tracker.failed) / tracker.total
end

function Loading.isLoaded(tracker: Tracker): boolean
	return tracker.finishedAt ~= nil
end

-- Combines stages such as { weight = 1, progress = gameLoaded } and { weight = 4, progress = preload }.
function Loading.weighted(stages: { Stage }): number
	local totalWeight, sum = 0, 0
	for _, stage in stages do
		if isFinite(stage.weight) and stage.weight > 0 then
			totalWeight += stage.weight
			sum += stage.weight * math.clamp(stage.progress, 0, 1)
		end
	end
	if totalWeight == 0 then
		return 1
	end
	return sum / totalWeight
end

-- Moves the shown bar toward `target` at `speed` per second. The bar never moves backwards.
function Loading.displayProgress(shown: number, target: number, dt: number, speed: number): number
	local goal = math.clamp(target, 0, 1)
	if goal <= shown then
		return shown
	end
	return math.min(goal, shown + speed * math.max(0, dt))
end

function Loading.timedOut(tracker: Tracker, now: number, config: Config): boolean
	return config.maxWait > 0 and now - tracker.startedAt >= config.maxWait
end

function Loading.canSkip(tracker: Tracker, now: number, config: Config): boolean
	if not config.allowSkip or tracker.skipped then
		return false
	end
	return now - tracker.startedAt >= config.skipAfter
end

function Loading.skip(tracker: Tracker, now: number, config: Config): boolean
	if not Loading.canSkip(tracker, now, config) then
		return false
	end
	tracker.skipped = true
	return true
end

-- "loading", "ready" (loaded but inside the minimum display time), "done", "skipped" or "timeout".
function Loading.status(tracker: Tracker, now: number, config: Config): Status
	if tracker.skipped then
		return "skipped"
	end
	local waitedLongEnough = now - tracker.startedAt >= config.minDisplayTime
	if Loading.isLoaded(tracker) then
		if waitedLongEnough then
			return "done"
		end
		return "ready"
	end
	if Loading.timedOut(tracker, now, config) and waitedLongEnough then
		return "timeout"
	end
	return "loading"
end

-- True when the loading screen should close.
function Loading.shouldDismiss(tracker: Tracker, now: number, config: Config): boolean
	local status = Loading.status(tracker, now, config)
	return status == "done" or status == "skipped" or status == "timeout"
end

function Loading.formatPercent(progress: number): string
	local value = if isFinite(progress) then math.clamp(progress, 0, 1) else 0
	return tostring(math.floor(value * 100)) .. "%"
end

return Loading
