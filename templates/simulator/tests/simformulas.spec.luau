--!strict
local SimFormulas = require("../src/shared/Logic/SimFormulas")
local t = require("./lib/t")

local function input(powerLevel: number, multiplierLevel: number, rebirthMultiplier: number): SimFormulas.ClickInput
	return {
		base = 1,
		powerLevel = powerLevel,
		powerBonus = 1,
		multiplierLevel = multiplierLevel,
		multiplierBonus = 0.1,
		rebirthMultiplier = rebirthMultiplier,
	}
end

return {
	["click value combines upgrades and rebirths"] = function()
		t.equal(SimFormulas.clickValue(input(0, 0, 1)), 1)
		t.equal(SimFormulas.clickValue(input(4, 0, 1)), 5)
		t.equal(SimFormulas.clickValue(input(4, 5, 1)), 7)
		t.equal(SimFormulas.clickValue(input(4, 5, 2)), 15)
	end,

	["click value is at least 1"] = function()
		t.equal(SimFormulas.clickValue(input(-10, -10, 0)), 1)
	end,

	["upgrade cost grows each level"] = function()
		t.equal(SimFormulas.upgradeCost(25, 1.15, 0), 25)
		t.truthy(SimFormulas.upgradeCost(25, 1.15, 10) > SimFormulas.upgradeCost(25, 1.15, 9))
	end,

	["cooldown"] = function()
		t.truthy(SimFormulas.canCollect(nil, 0, 0.15))
		t.falsy(SimFormulas.canCollect(1, 1.1, 0.15))
		t.truthy(SimFormulas.canCollect(1, 1.2, 0.15))
	end,

	["affordable levels stop at max level"] = function()
		local levels = SimFormulas.affordableLevels(1e9, 10, 1.1, 8, 10)
		t.equal(levels, 2)
		local none, cost = SimFormulas.affordableLevels(5, 10, 1.1, 0, 10)
		t.equal(none, 0)
		t.equal(cost, 0)
	end,
}
