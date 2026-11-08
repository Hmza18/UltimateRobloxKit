--!strict
local Economy = require("../src/shared/Logic/Economy")
local t = require("./lib/t")

local NAN = math.sqrt(-1)

return {
	["round goes half away from zero and handles binary error"] = function()
		t.equal(Economy.round(2.5), 3)
		t.equal(Economy.round(-2.5), -3)
		t.equal(Economy.round(2.4), 2)
		t.equal(Economy.round(1.005, 2), 1.01)
		t.equal(Economy.round(NAN), 0)
		t.equal(Economy.round(math.huge), 0)
	end,

	["clamp keeps whole numbers inside the currency range"] = function()
		t.equal(Economy.clamp(-5), 0)
		t.equal(Economy.clamp(12.9), 12)
		t.equal(Economy.clamp(NAN), 0)
		t.equal(Economy.clamp(1e300), Economy.MAX_CURRENCY)
	end,

	["price grows geometrically"] = function()
		t.equal(Economy.price(10, 1.5, 0), 10)
		t.equal(Economy.price(10, 1.5, 1), 15)
		t.equal(Economy.price(10, 1.5, 2), 23)
	end,

	["bulk price equals buying one at a time"] = function()
		local oneByOne = 0
		for owned = 3, 7 do
			oneByOne += Economy.price(25, 1.15, owned)
		end
		t.equal(Economy.bulkPrice(25, 1.15, 3, 5), oneByOne)
	end,

	["maxAffordable stops before the balance runs out"] = function()
		local count, total = Economy.maxAffordable(50, 10, 1.5, 0)
		t.equal(count, 3)
		t.equal(total, 48)
		t.equal(Economy.maxAffordable(5, 10, 1.5, 0), 0)
	end,

	["canAfford rejects bad numbers"] = function()
		t.truthy(Economy.canAfford(10, 10))
		t.falsy(Economy.canAfford(9, 10))
		t.falsy(Economy.canAfford(10, -1))
		t.falsy(Economy.canAfford(NAN, 1))
	end,

	["rebirth multiplier and cost"] = function()
		t.equal(Economy.rebirthMultiplier(0, 0.5), 1)
		t.equal(Economy.rebirthMultiplier(2, 0.5), 2)
		t.equal(Economy.rebirthCost(1000, 2.5, 0), 1000)
		t.equal(Economy.rebirthCost(1000, 2.5, 2), 6250)
		t.equal(Economy.applyMultiplier(7, 1.5), 10)
	end,

	["abbreviate formats large numbers"] = function()
		t.equal(Economy.abbreviate(999), "999")
		t.equal(Economy.abbreviate(1000), "1K")
		t.equal(Economy.abbreviate(1500), "1.5K")
		t.equal(Economy.abbreviate(1234567), "1.23M")
		t.equal(Economy.abbreviate(-2500), "-2.5K")
		t.equal(Economy.abbreviate(NAN), "0")
	end,
}
