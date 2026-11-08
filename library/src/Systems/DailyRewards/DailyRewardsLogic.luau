--!strict
-- Daily login rewards with streaks. Pure Luau and immutable. Days are counted from injected unix
-- time in UTC (plus a fixed, game-wide reset offset), never from the client's clock or time zone,
-- so every player shares the same day boundary.

export type ConfigInput = {
	rewards: { any }, -- reward payloads by streak day: rewards[1] on day 1, and so on
	graceDays: number?, -- missed days allowed before the streak resets (default 0)
	cycle: boolean?, -- after the last reward start again at 1 (true, default) or repeat the last
	resetOffsetSeconds: number?, -- day boundary in seconds after 00:00 UTC (default 0)
}

export type Config = { rewards: { any }, graceDays: number, cycle: boolean, resetOffsetSeconds: number }

export type State = { streak: number, lastClaimDay: number?, totalClaims: number }

export type Status = {
	canClaim: boolean, -- whether a claim would succeed now
	reason: string?, -- why not
	day: number, -- today's day index
	streak: number, -- streak after claiming now (or the current streak when already claimed)
	rewardIndex: number, -- index into rewards for that streak
	reward: any, -- the reward payload
	streakWillReset: boolean, -- claiming now starts over at 1
	secondsUntilNext: number, -- seconds until the next day starts
}

export type ClaimResult = {
	ok: boolean, -- whether the claim was accepted
	reason: string?, -- why not
	state: State, -- new state, or the input on failure
	streak: number, -- streak after the claim
	rewardIndex: number, -- index into rewards
	reward: any, -- payload to grant
}

export type Saved = { v: number, s: number, d: number?, t: number }

local DailyRewardsLogic = {}

DailyRewardsLogic.DAY = 86400
DailyRewardsLogic.SAVE_VERSION = 1

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isWhole(value: any): boolean
	return isFinite(value) and value >= 0 and value % 1 == 0
end

function DailyRewardsLogic.newConfig(input: ConfigInput): Config
	assert(type(input) == "table" and type(input.rewards) == "table", "rewards must be an array")
	assert(#input.rewards > 0, "rewards must not be empty")
	local grace = input.graceDays or 0
	assert(isWhole(grace), "graceDays must be a whole number")
	local offset = input.resetOffsetSeconds or 0
	assert(isFinite(offset) and offset > -DailyRewardsLogic.DAY and offset < DailyRewardsLogic.DAY, "invalid offset")
	return {
		rewards = table.clone(input.rewards),
		graceDays = grace,
		cycle = input.cycle ~= false,
		resetOffsetSeconds = offset,
	}
end

function DailyRewardsLogic.new(): State
	return { streak = 0, lastClaimDay = nil, totalClaims = 0 }
end

-- Whole days since the epoch for `unix`, with days starting `offset` seconds after 00:00 UTC.
function DailyRewardsLogic.dayIndex(unix: number, offset: number?): number
	return math.floor((unix - (offset or 0)) / DailyRewardsLogic.DAY)
end

-- Unix time at which the day after `unix` starts.
function DailyRewardsLogic.nextReset(unix: number, offset: number?): number
	local shift = offset or 0
	return (DailyRewardsLogic.dayIndex(unix, shift) + 1) * DailyRewardsLogic.DAY + shift
end

-- Which reward a streak earns: cycles through the table, or stays on the last entry.
function DailyRewardsLogic.rewardIndex(config: Config, streak: number): number
	local count = #config.rewards
	local day = math.max(math.floor(streak), 1)
	if config.cycle then
		return (day - 1) % count + 1
	end
	return math.min(day, count)
end

-- The streak a claim on `today` would produce, and whether it breaks the old streak.
local function nextStreak(config: Config, state: State, today: number): (number, boolean)
	local last = state.lastClaimDay
	if last == nil then
		return 1, false
	end
	local gap = today - last
	if gap <= 1 + config.graceDays then
		return state.streak + 1, false
	end
	return 1, state.streak > 0
end

function DailyRewardsLogic.status(config: Config, state: State, now: number): Status
	local offset = config.resetOffsetSeconds
	local valid = isFinite(now)
	local today = if valid then DailyRewardsLogic.dayIndex(now, offset) else 0
	local untilNext = if valid then DailyRewardsLogic.nextReset(now, offset) - now else 0
	local last = state.lastClaimDay
	local reason: string? = nil
	local streak, resets = state.streak, false
	if not valid then
		reason = "invalid time"
	elseif last ~= nil and today == last then
		reason = "already claimed"
	elseif last ~= nil and today < last then
		reason = "clock went backwards"
	else
		streak, resets = nextStreak(config, state, today)
	end
	local index = DailyRewardsLogic.rewardIndex(config, streak)
	return {
		canClaim = reason == nil,
		reason = reason,
		day = today,
		streak = streak,
		rewardIndex = index,
		reward = config.rewards[index],
		streakWillReset = resets,
		secondsUntilNext = untilNext,
	}
end

-- Claims today's reward. At most one claim per day; the caller grants `reward` and only then
-- commits `state`, so a failed grant can be retried the same day.
function DailyRewardsLogic.claim(config: Config, state: State, now: number): ClaimResult
	local status = DailyRewardsLogic.status(config, state, now)
	if not status.canClaim then
		return {
			ok = false,
			reason = status.reason,
			state = state,
			streak = state.streak,
			rewardIndex = status.rewardIndex,
			reward = nil,
		}
	end
	local nextState: State = { streak = status.streak, lastClaimDay = status.day, totalClaims = state.totalClaims + 1 }
	return {
		ok = true,
		reason = nil,
		state = nextState,
		streak = status.streak,
		rewardIndex = status.rewardIndex,
		reward = status.reward,
	}
end

function DailyRewardsLogic.serialize(state: State): Saved
	return { v = DailyRewardsLogic.SAVE_VERSION, s = state.streak, d = state.lastClaimDay, t = state.totalClaims }
end

function DailyRewardsLogic.deserialize(raw: any): State
	local state = DailyRewardsLogic.new()
	if type(raw) ~= "table" then
		return state
	end
	if isWhole(raw.s) then
		state.streak = raw.s
	end
	if isFinite(raw.d) and raw.d % 1 == 0 then
		state.lastClaimDay = raw.d
	end
	if isWhole(raw.t) then
		state.totalClaims = raw.t
	end
	return state
end

return DailyRewardsLogic
