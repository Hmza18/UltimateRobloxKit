--!strict
-- Obby stage rules. Pure Luau. Stages are whole numbers from 1 (the start) to maxStage.
-- A checkpoint only advances the player one stage at a time, so teleporting ahead does not count.

export type Result = "advanced" | "same" | "behind" | "skipped" | "invalid"

local StageProgress = {}

local function isStage(value: any, maxStage: number): boolean
	return type(value) == "number" and value % 1 == 0 and value >= 1 and value <= maxStage
end

-- Turns a saved value into a valid stage: anything invalid becomes 1, and values above maxStage are capped.
function StageProgress.clamp(saved: any, maxStage: number): number
	if type(saved) ~= "number" or saved ~= saved or saved < 1 then
		return 1
	end
	return math.min(math.floor(saved), math.max(maxStage, 1))
end

-- The player at `current` touched the checkpoint for stage `touched`.
-- Returns the new stage and what happened. Only touched == current + 1 moves the player forward.
function StageProgress.advance(current: number, touched: any, maxStage: number): (number, Result)
	if not isStage(touched, maxStage) then
		return current, "invalid"
	end
	if touched == current + 1 then
		return touched, "advanced"
	elseif touched == current then
		return current, "same"
	elseif touched < current then
		return current, "behind"
	end
	return current, "skipped"
end

function StageProgress.isComplete(current: number, maxStage: number): boolean
	return maxStage >= 1 and current >= maxStage
end

-- Whole-number percentage of the course finished. Stage 1 is 0% and the last stage is 100%.
function StageProgress.percent(current: number, maxStage: number): number
	if maxStage <= 1 then
		return 100
	end
	local fraction = (math.clamp(current, 1, maxStage) - 1) / (maxStage - 1)
	return math.floor(fraction * 100 + 0.5)
end

return StageProgress
