--!strict
-- Stage progression for obbies, races and levels. Pure Luau.
-- Progress is monotonic: `highest` only goes up, and a checkpoint more than `maxSkip` stages ahead
-- is refused, so touching a far checkpoint (by teleport exploit or a gap in the course) does not count.
-- `stage` is where the player respawns; it equals `highest` unless respawnAtLastTouched is on.

export type Config = {
	startStage: number, -- first stage (default 1)
	maxStage: number, -- last stage (default 1000)
	maxSkip: number, -- how far ahead a touch may be (default 1: only the next stage)
	respawnAtLastTouched: boolean, -- touching an earlier reached checkpoint moves the respawn point there
}

export type State = { stage: number, highest: number }

export type Result = "advanced" | "moved" | "same" | "behind" | "skipped" | "invalid"

local Checkpoints = {}

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and math.abs(value) ~= math.huge
end

function Checkpoints.resolveConfig(overrides: { [string]: any }?): Config
	local source: { [string]: any } = overrides or {}
	local startStage = if isInteger(source.startStage) then source.startStage else 1
	local maxStage = if isInteger(source.maxStage) and source.maxStage >= startStage then source.maxStage else 1000
	local maxSkip = if isInteger(source.maxSkip) and source.maxSkip >= 1 then source.maxSkip else 1
	return {
		startStage = startStage,
		maxStage = math.max(maxStage, startStage),
		maxSkip = maxSkip,
		respawnAtLastTouched = source.respawnAtLastTouched == true,
	}
end

function Checkpoints.new(config: Config): State
	return { stage = config.startStage, highest = config.startStage }
end

function Checkpoints.isValidStage(stage: any, config: Config): boolean
	return isInteger(stage) and stage >= config.startStage and stage <= config.maxStage
end

-- Applies a checkpoint touch and returns what happened. Changes `state` only for "advanced" and "moved".
function Checkpoints.touch(state: State, stage: any, config: Config): Result
	if not Checkpoints.isValidStage(stage, config) then
		return "invalid"
	end
	if stage > state.highest then
		if stage - state.highest > config.maxSkip then
			return "skipped"
		end
		state.highest = stage
		state.stage = stage
		return "advanced"
	end
	if stage == state.stage then
		return "same"
	end
	if config.respawnAtLastTouched or stage == state.highest then
		state.stage = stage
		return "moved"
	end
	return "behind"
end

-- Advances one stage without touching a checkpoint, for example after buying a skip.
-- Returns false at the last stage.
function Checkpoints.grantSkip(state: State, config: Config): boolean
	if state.highest >= config.maxStage then
		return false
	end
	state.highest += 1
	state.stage = state.highest
	return true
end

function Checkpoints.reset(state: State, config: Config)
	state.stage = config.startStage
	state.highest = config.startStage
end

function Checkpoints.isComplete(state: State, config: Config): boolean
	return state.highest >= config.maxStage
end

-- Whole-number percentage of the course reached (start = 0, last stage = 100).
function Checkpoints.percent(state: State, config: Config): number
	local span = config.maxStage - config.startStage
	if span <= 0 then
		return 100
	end
	return math.floor((state.highest - config.startStage) / span * 100 + 0.5)
end

-- Finds the spawn for `stage`: the checkpoint with the largest stage number at or below it.
-- `available` maps stage numbers to anything (for example parts). Returns the stage used and its value.
function Checkpoints.resolveSpawn(stage: number, available: { [number]: any }): (number?, any)
	local best: number? = nil
	for candidate in available do
		if type(candidate) == "number" and candidate <= stage and (best == nil or candidate > best) then
			best = candidate
		end
	end
	if best == nil then
		return nil, nil
	end
	return best, available[best]
end

-- True when enough time has passed since `lastAt` (nil means never) to trigger again.
function Checkpoints.cooldownReady(lastAt: number?, now: number, cooldown: number): boolean
	return lastAt == nil or now - lastAt >= cooldown
end

function Checkpoints.serialize(state: State): { [string]: number }
	return { stage = state.stage, highest = state.highest }
end

-- Rebuilds state from untrusted saved data: invalid values fall back to the start, values past
-- maxStage are capped, and the respawn stage never exceeds the highest stage.
function Checkpoints.deserialize(data: any, config: Config): State
	local state = Checkpoints.new(config)
	if type(data) ~= "table" then
		return state
	end
	local highest = data.highest
	if isInteger(highest) and highest >= config.startStage then
		state.highest = math.min(highest, config.maxStage)
	end
	local stage = data.stage
	if isInteger(stage) and stage >= config.startStage then
		state.stage = math.min(stage, state.highest)
	else
		state.stage = state.highest
	end
	return state
end

return Checkpoints
