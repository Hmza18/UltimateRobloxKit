--!strict
local StageProgress = require("../src/shared/Logic/StageProgress")
local t = require("./lib/t")

return {
	["clamp sanitises saved stages"] = function()
		t.equal(StageProgress.clamp(nil, 10), 1)
		t.equal(StageProgress.clamp("3", 10), 1)
		t.equal(StageProgress.clamp(0, 10), 1)
		t.equal(StageProgress.clamp(math.sqrt(-1), 10), 1)
		t.equal(StageProgress.clamp(4.7, 10), 4)
		t.equal(StageProgress.clamp(25, 10), 10)
	end,

	["advance moves forward one stage at a time"] = function()
		local stage, result = StageProgress.advance(3, 4, 10)
		t.equal(stage, 4)
		t.equal(result, "advanced")
	end,

	["advance ignores the same and earlier stages"] = function()
		t.equal(select(2, StageProgress.advance(3, 3, 10)), "same")
		local stage, result = StageProgress.advance(3, 1, 10)
		t.equal(stage, 3)
		t.equal(result, "behind")
	end,

	["advance refuses skipped and invalid stages"] = function()
		local stage, result = StageProgress.advance(3, 7, 10)
		t.equal(stage, 3)
		t.equal(result, "skipped")
		t.equal(select(2, StageProgress.advance(3, 11, 10)), "invalid")
		t.equal(select(2, StageProgress.advance(3, 4.5, 10)), "invalid")
		t.equal(select(2, StageProgress.advance(3, "4", 10)), "invalid")
	end,

	["percent and completion"] = function()
		t.equal(StageProgress.percent(1, 11), 0)
		t.equal(StageProgress.percent(6, 11), 50)
		t.equal(StageProgress.percent(11, 11), 100)
		t.equal(StageProgress.percent(1, 1), 100)
		t.truthy(StageProgress.isComplete(11, 11))
		t.falsy(StageProgress.isComplete(10, 11))
	end,
}
