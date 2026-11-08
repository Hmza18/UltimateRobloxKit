--!strict
local Checkpoints = require("../src/Systems/Checkpoints/CheckpointsLogic")
local t = require("./lib/t")

local CONFIG = Checkpoints.resolveConfig({ maxStage = 10 })

return {
	["resolveConfig validates values"] = function()
		local config = Checkpoints.resolveConfig({
			startStage = 0,
			maxStage = 5,
			maxSkip = 0,
			respawnAtLastTouched = 1,
		})
		t.equal(config.startStage, 0)
		t.equal(config.maxStage, 5)
		t.equal(config.maxSkip, 1)
		t.equal(config.respawnAtLastTouched, false)
		local fallback = Checkpoints.resolveConfig({ startStage = 3, maxStage = 2 })
		t.equal(fallback.maxStage, 1000, "a max below the start falls back")
		t.deepEqual(Checkpoints.new(CONFIG), { stage = 1, highest = 1 })
	end,

	["touch advances one stage at a time"] = function()
		local state = Checkpoints.new(CONFIG)
		t.equal(Checkpoints.touch(state, 2, CONFIG), "advanced")
		t.equal(Checkpoints.touch(state, 2, CONFIG), "same")
		t.equal(Checkpoints.touch(state, 1, CONFIG), "behind")
		t.deepEqual(state, { stage = 2, highest = 2 })
	end,

	["skipping ahead is refused"] = function()
		local state = Checkpoints.new(CONFIG)
		t.equal(Checkpoints.touch(state, 3, CONFIG), "skipped")
		t.equal(state.highest, 1)
		local loose = Checkpoints.resolveConfig({ maxStage = 10, maxSkip = 2 })
		t.equal(Checkpoints.touch(state, 3, loose), "advanced")
		t.equal(Checkpoints.touch(state, 6, loose), "skipped")
	end,

	["invalid stages are ignored"] = function()
		local state = Checkpoints.new(CONFIG)
		t.equal(Checkpoints.touch(state, 1.5, CONFIG), "invalid")
		t.equal(Checkpoints.touch(state, "2", CONFIG), "invalid")
		t.equal(Checkpoints.touch(state, 0, CONFIG), "invalid")
		t.equal(Checkpoints.touch(state, 11, CONFIG), "invalid")
		t.equal(Checkpoints.touch(state, math.sqrt(-1), CONFIG), "invalid")
		t.equal(Checkpoints.touch(state, math.huge, CONFIG), "invalid")
		t.deepEqual(state, { stage = 1, highest = 1 })
	end,

	["respawnAtLastTouched moves the respawn point back"] = function()
		local config = Checkpoints.resolveConfig({ maxStage = 10, respawnAtLastTouched = true })
		local state = Checkpoints.new(config)
		Checkpoints.touch(state, 2, config)
		Checkpoints.touch(state, 3, config)
		t.equal(Checkpoints.touch(state, 1, config), "moved")
		t.deepEqual(state, { stage = 1, highest = 3 })
		t.equal(Checkpoints.touch(state, 4, config), "advanced", "progress still counts from the highest")
		Checkpoints.touch(state, 2, config)
		t.equal(Checkpoints.touch(state, 4, config), "moved")
		t.equal(state.stage, 4)
	end,

	["grantSkip, completion and percent"] = function()
		local config = Checkpoints.resolveConfig({ maxStage = 3 })
		local state = Checkpoints.new(config)
		t.equal(Checkpoints.percent(state, config), 0)
		t.truthy(Checkpoints.grantSkip(state, config))
		t.equal(Checkpoints.percent(state, config), 50)
		t.truthy(Checkpoints.grantSkip(state, config))
		t.truthy(Checkpoints.isComplete(state, config))
		t.falsy(Checkpoints.grantSkip(state, config))
		t.equal(Checkpoints.percent(state, config), 100)
		local single = Checkpoints.resolveConfig({ maxStage = 1 })
		t.equal(Checkpoints.percent(Checkpoints.new(single), single), 100)
	end,

	["resolveSpawn uses the nearest checkpoint at or below"] = function()
		local parts = { [1] = "start", [2] = "two", [5] = "five" }
		local stage, part = Checkpoints.resolveSpawn(4, parts)
		t.equal(stage, 2)
		t.equal(part, "two")
		t.equal(select(2, Checkpoints.resolveSpawn(9, parts)), "five")
		t.equal(Checkpoints.resolveSpawn(0, parts), nil)
		t.equal(Checkpoints.resolveSpawn(3, {}), nil)
	end,

	["cooldownReady"] = function()
		t.truthy(Checkpoints.cooldownReady(nil, 0, 1))
		t.falsy(Checkpoints.cooldownReady(5, 5.5, 1))
		t.truthy(Checkpoints.cooldownReady(5, 6, 1))
	end,

	["serialize and deserialize sanitise saved data"] = function()
		local state = { stage = 3, highest = 4 }
		t.deepEqual(Checkpoints.deserialize(Checkpoints.serialize(state), CONFIG), state)
		t.deepEqual(Checkpoints.deserialize({ stage = 9, highest = 4 }, CONFIG), { stage = 4, highest = 4 })
		t.deepEqual(Checkpoints.deserialize({ highest = 50 }, CONFIG), { stage = 10, highest = 10 })
		t.deepEqual(Checkpoints.deserialize({ stage = "x", highest = 2.5 }, CONFIG), { stage = 1, highest = 1 })
		t.deepEqual(Checkpoints.deserialize(nil, CONFIG), { stage = 1, highest = 1 })
	end,

	["reset returns to the start"] = function()
		local state = { stage = 4, highest = 6 }
		Checkpoints.reset(state, CONFIG)
		t.deepEqual(state, { stage = 1, highest = 1 })
	end,
}
