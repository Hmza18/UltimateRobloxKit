--!strict
-- Round loop state machine: Intermission -> Starting -> InProgress -> Ending -> Intermission.
-- Pure Luau: the caller passes `now`, the player count, a winner check and a random source.
-- Map voting runs during Intermission and is tallied when the round starts (ties broken by `rng`).

local RoundsConfig = require("./RoundsConfig")

export type Phase = "Intermission" | "Starting" | "InProgress" | "Ending"

export type Config = {
	minPlayers: number,
	intermissionTime: number,
	startingTime: number,
	roundTime: number,
	endingTime: number,
	minPlayersToContinue: number,
}

export type Result = { winner: any?, reason: string } -- reason: "win" | "timeout" | "abandoned" | "forced"
export type Vote = { options: { string }, ballots: { [string]: string } }

export type State = {
	phase: Phase,
	phaseStartedAt: number,
	phaseEndsAt: number,
	round: number,
	waiting: boolean, -- Intermission is holding for more players
	result: Result?,
	vote: Vote?,
	map: string?,
}

export type Input = {
	now: number,
	playerCount: number,
	checkWinner: (() -> any?)?, -- called during InProgress; a non-nil return ends the round
	rng: (() -> number)?, -- returns [0, 1); used for vote tie-breaks
}

export type Change = { from: Phase, to: Phase, round: number, result: Result?, map: string? }

local Rounds = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Rounds.resolveConfig(overrides: { [string]: any }?): Config
	local source: { [string]: any } = overrides or {}
	local function pick(key: string): number
		local value = source[key]
		if isFinite(value) and value >= 0 then
			return value
		end
		return (RoundsConfig :: any)[key]
	end
	return {
		minPlayers = pick("minPlayers"),
		intermissionTime = pick("intermissionTime"),
		startingTime = pick("startingTime"),
		roundTime = pick("roundTime"),
		endingTime = pick("endingTime"),
		minPlayersToContinue = pick("minPlayersToContinue"),
	}
end

local function durationOf(config: Config, phase: Phase): number
	if phase == "Intermission" then
		return config.intermissionTime
	elseif phase == "Starting" then
		return config.startingTime
	elseif phase == "InProgress" then
		return config.roundTime
	end
	return config.endingTime
end

function Rounds.new(config: Config, now: number): State
	local state: State = {
		phase = "Intermission",
		phaseStartedAt = now,
		phaseEndsAt = now + config.intermissionTime,
		round = 0,
		waiting = false,
		result = nil,
		vote = nil,
		map = nil,
	}
	return state
end

local function enter(state: State, config: Config, phase: Phase, now: number): Change
	local change: Change = { from = state.phase, to = phase, round = state.round, result = nil, map = nil }
	state.phase = phase
	state.phaseStartedAt = now
	state.phaseEndsAt = now + durationOf(config, phase)
	state.waiting = false
	return change
end

-- Map voting -----------------------------------------------------------------------------------------

-- Opens a vote with the given options (duplicates and non-strings are dropped). Replaces any open vote.
function Rounds.openVote(state: State, options: { string }): Vote
	local unique: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, option in options do
		if type(option) == "string" and not seen[option] then
			seen[option] = true
			table.insert(unique, option)
		end
	end
	local vote: Vote = { options = unique, ballots = {} }
	state.vote = vote
	return vote
end

-- Records or replaces a voter's ballot. Voting is only open during Intermission.
function Rounds.castVote(state: State, voterId: string, option: string): (boolean, string?)
	local vote = state.vote
	if vote == nil or state.phase ~= "Intermission" then
		return false, "no vote open"
	end
	if table.find(vote.options, option) == nil then
		return false, "unknown option"
	end
	vote.ballots[voterId] = option
	return true, nil
end

function Rounds.removeVoter(state: State, voterId: string)
	local vote = state.vote
	if vote then
		vote.ballots[voterId] = nil
	end
end

function Rounds.counts(vote: Vote): { [string]: number }
	local counts: { [string]: number } = {}
	for _, option in vote.options do
		counts[option] = 0
	end
	for _, option in vote.ballots do
		if counts[option] ~= nil then
			counts[option] += 1
		end
	end
	return counts
end

-- The option with the most ballots. Ties (including no ballots) are broken with `rng`,
-- or by option order when no rng is given. Returns nil when there are no options.
function Rounds.tally(vote: Vote, rng: (() -> number)?): string?
	local counts = Rounds.counts(vote)
	local best = -1
	local tied: { string } = {}
	for _, option in vote.options do
		local count = counts[option]
		if count > best then
			best = count
			tied = { option }
		elseif count == best then
			table.insert(tied, option)
		end
	end
	if #tied == 0 then
		return nil
	end
	local index = 1
	if rng then
		index = math.clamp(math.floor(rng() * #tied) + 1, 1, #tied)
	end
	return tied[index]
end

-- Round loop -----------------------------------------------------------------------------------------

function Rounds.timeLeft(state: State, now: number): number
	return math.max(0, state.phaseEndsAt - now)
end

-- Advances the loop by at most one phase. Returns a Change when the phase changed, otherwise nil.
function Rounds.update(state: State, config: Config, input: Input): Change?
	local now = input.now
	local enough = input.playerCount >= config.minPlayers
	if state.phase == "Intermission" then
		if not enough then
			-- Hold the timer until enough players are present.
			state.waiting = true
			state.phaseEndsAt = now + config.intermissionTime
			return nil
		end
		state.waiting = false
		if now < state.phaseEndsAt then
			return nil
		end
		local vote = state.vote
		if vote then
			state.map = Rounds.tally(vote, input.rng)
			state.vote = nil
		end
		local change = enter(state, config, "Starting", now)
		change.map = state.map
		return change
	elseif state.phase == "Starting" then
		if not enough then
			return enter(state, config, "Intermission", now)
		end
		if now < state.phaseEndsAt then
			return nil
		end
		state.round += 1
		state.result = nil
		local change = enter(state, config, "InProgress", now)
		change.round = state.round
		change.map = state.map
		return change
	elseif state.phase == "InProgress" then
		local check = input.checkWinner
		local winner = if check then check() else nil
		local result: Result? = nil
		if winner ~= nil then
			result = { winner = winner, reason = "win" }
		elseif input.playerCount < config.minPlayersToContinue then
			result = { winner = nil, reason = "abandoned" }
		elseif now >= state.phaseEndsAt then
			result = { winner = nil, reason = "timeout" }
		end
		if result == nil then
			return nil
		end
		state.result = result
		local change = enter(state, config, "Ending", now)
		change.result = result
		return change
	end
	if now < state.phaseEndsAt then
		return nil
	end
	state.map = nil
	return enter(state, config, "Intermission", now)
end

-- Ends a running round at once, for example from an admin command.
function Rounds.forceEnd(state: State, config: Config, now: number, winner: any?): Change?
	if state.phase ~= "InProgress" then
		return nil
	end
	local result: Result = { winner = winner, reason = "forced" }
	state.result = result
	local change = enter(state, config, "Ending", now)
	change.result = result
	return change
end

return Rounds
