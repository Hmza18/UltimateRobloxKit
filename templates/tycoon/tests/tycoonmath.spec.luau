--!strict
local TycoonMath = require("../src/shared/Logic/TycoonMath")
local t = require("./lib/t")

return {
	["next free plot is the lowest untaken index"] = function()
		t.equal(TycoonMath.nextFreePlot({}, 3), 1)
		t.equal(TycoonMath.nextFreePlot({ [1] = true }, 3), 2)
		t.equal(TycoonMath.nextFreePlot({ [1] = true, [3] = true }, 3), 2)
		t.equal(TycoonMath.nextFreePlot({ [1] = true, [2] = true }, 2), nil)
		t.equal(TycoonMath.nextFreePlot({}, 0), nil)
	end,

	["parseList trims and skips empty items"] = function()
		t.deepEqual(TycoonMath.parseList(" Dropper1 ,Wall,, "), { "Dropper1", "Wall" })
		t.deepEqual(TycoonMath.parseList(nil), {})
		t.deepEqual(TycoonMath.parseList(42), {})
	end,

	["requirements unlock buttons"] = function()
		local purchased: { [string]: boolean } = { Dropper1 = true }
		t.truthy(TycoonMath.isUnlocked(purchased, {}))
		t.truthy(TycoonMath.isUnlocked(purchased, { "Dropper1" }))
		t.falsy(TycoonMath.isUnlocked(purchased, { "Dropper1", "Wall" }))
		t.equal(TycoonMath.buttonState(purchased, "Dropper1", {}), "Purchased")
		t.equal(TycoonMath.buttonState(purchased, "Dropper2", { "Dropper1" }), "Available")
		t.equal(TycoonMath.buttonState(purchased, "Dropper3", { "Dropper2" }), "Locked")
	end,

	["drop value applies the multiplier"] = function()
		t.equal(TycoonMath.dropValue(3, 1), 3)
		t.equal(TycoonMath.dropValue(3, 1.5), 4)
		t.equal(TycoonMath.dropValue(1, 0.1), 1)
		t.equal(TycoonMath.dropValue(0, 2), 0)
		t.equal(TycoonMath.dropValue(math.sqrt(-1), 2), 0)
	end,

	["income per second sums droppers"] = function()
		t.equal(TycoonMath.incomePerSecond({ { value = 2, interval = 2 }, { value = 6, interval = 3 } }), 3)
		t.equal(TycoonMath.incomePerSecond({ { value = 5, interval = 0 } }), 0)
	end,
}
