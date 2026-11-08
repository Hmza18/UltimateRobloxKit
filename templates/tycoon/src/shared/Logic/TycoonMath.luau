--!strict
-- Tycoon rules: plot assignment, purchase prerequisites and dropper income. Pure Luau.

local Economy = require("./Economy")

export type ButtonState = "Purchased" | "Available" | "Locked"
export type DropperInfo = { value: number, interval: number }

local TycoonMath = {}

-- Lowest plot index (1..plotCount) that is not taken, or nil when every plot is in use.
function TycoonMath.nextFreePlot(taken: { [number]: boolean }, plotCount: number): number?
	for index = 1, plotCount do
		if not taken[index] then
			return index
		end
	end
	return nil
end

-- Splits "Dropper1, Wall" into { "Dropper1", "Wall" }. Anything that is not a string gives {}.
function TycoonMath.parseList(text: any): { string }
	local items: { string } = {}
	if type(text) ~= "string" then
		return items
	end
	for item in string.gmatch(text, "[^,]+") do
		local trimmed = string.match(item, "^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" then
			table.insert(items, trimmed)
		end
	end
	return items
end

-- True when every id in `requires` has been purchased.
function TycoonMath.isUnlocked(purchased: { [string]: boolean }, requires: { string }): boolean
	for _, id in requires do
		if not purchased[id] then
			return false
		end
	end
	return true
end

function TycoonMath.buttonState(purchased: { [string]: boolean }, id: string, requires: { string }): ButtonState
	if purchased[id] then
		return "Purchased"
	end
	return if TycoonMath.isUnlocked(purchased, requires) then "Available" else "Locked"
end

-- Coins one drop is worth: base value times the owner's multiplier, rounded down, at least 1.
function TycoonMath.dropValue(baseValue: number, multiplier: number): number
	if not Economy.isFinite(baseValue) or baseValue <= 0 then
		return 0
	end
	return math.max(Economy.applyMultiplier(baseValue, multiplier), 1)
end

-- Steady income in coins per second from a set of droppers, before the multiplier.
function TycoonMath.incomePerSecond(droppers: { DropperInfo }): number
	local total = 0
	for _, dropper in droppers do
		if dropper.interval > 0 and dropper.value > 0 then
			total += dropper.value / dropper.interval
		end
	end
	return total
end

return TycoonMath
