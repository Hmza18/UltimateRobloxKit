--!strict
-- Simulator maths: click value, upgrade prices and the collect cooldown. Pure Luau.

local Economy = require("./Economy")

export type ClickInput = {
	base: number, -- coins per click before upgrades
	powerLevel: number, -- flat bonus upgrade level
	powerBonus: number, -- coins added per power level
	multiplierLevel: number, -- percentage upgrade level
	multiplierBonus: number, -- fraction added per multiplier level, for example 0.1 for +10%
	rebirthMultiplier: number, -- from Economy.rebirthMultiplier
}

local SimFormulas = {}

-- Coins for one click: (base + power) * (1 + multiplier) * rebirth, rounded down, at least 1.
function SimFormulas.clickValue(input: ClickInput): number
	local flat = input.base + math.max(input.powerLevel, 0) * input.powerBonus
	local percent = 1 + math.max(input.multiplierLevel, 0) * input.multiplierBonus
	local value = Economy.clamp(flat * percent * math.max(input.rebirthMultiplier, 1))
	return math.max(value, 1)
end

-- Price of buying level `level + 1` of an upgrade.
function SimFormulas.upgradeCost(baseCost: number, growth: number, level: number): number
	return Economy.price(baseCost, growth, level)
end

-- True when at least `cooldown` seconds have passed since `lastAt` (nil means never collected).
function SimFormulas.canCollect(lastAt: number?, now: number, cooldown: number): boolean
	if lastAt == nil then
		return true
	end
	return now - lastAt >= cooldown
end

-- How many levels `coins` buys starting at `level`, without passing `maxLevel`, and the total cost.
function SimFormulas.affordableLevels(coins: number, baseCost: number, growth: number, level: number, maxLevel: number)
	local room = math.max(maxLevel - level, 0)
	return Economy.maxAffordable(coins, baseCost, growth, level, room)
end

return SimFormulas
