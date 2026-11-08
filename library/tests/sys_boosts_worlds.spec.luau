--!strict
local BoostsLogic = require("../src/Systems/Boosts/BoostsLogic")
local WorldsLogic = require("../src/Systems/Worlds/WorldsLogic")
local t = require("./lib/t")

local function boosts(clock: ("wall" | "online")?): BoostsLogic.Config
	return BoostsLogic.validateConfig({
		boosts = {
			Coins2x = { stat = "coins", multiplier = 2, duration = 600, maxDuration = 1800 },
			Luck = { stat = "luck", multiplier = 1.5, duration = 300, stacking = "stack", maxStacks = 2 },
			Event = { stat = "coins", multiplier = 3, duration = 100, stacking = "refresh" },
		},
		clock = clock,
	})
end

local function worlds(): WorldsLogic.Config
	return WorldsLogic.validateConfig({
		worlds = {
			{ name = "Spawn" },
			{ name = "Forest", requires = { cost = { Coins = 500 } }, multiplier = 1.5 },
			{ name = "Volcano", requires = { cost = { Coins = 5000 }, rebirths = 1 }, multiplier = 3 },
		},
	})
end

return {
	["extend adds time up to the cap"] = function()
		local cfg = boosts()
		local s = BoostsLogic.activate(cfg, BoostsLogic.newState(), "Coins2x", 0).state
		s = BoostsLogic.activate(cfg, s, "Coins2x", 100).state
		t.equal(BoostsLogic.remaining(s, 100).Coins2x, 1100)
		s = BoostsLogic.activate(cfg, s, "Coins2x", 100, 5).state
		t.equal(BoostsLogic.remaining(s, 100).Coins2x, 1800)
		t.equal(BoostsLogic.activate(cfg, s, "Coins2x", 100).reason, "max duration")
	end,

	["multipliers multiply and expire"] = function()
		local cfg = boosts()
		local s = BoostsLogic.activate(cfg, BoostsLogic.newState(), "Coins2x", 0).state
		s = BoostsLogic.activate(cfg, s, "Event", 0).state
		t.equal(BoostsLogic.multiplier(cfg, s, "coins", 50), 6)
		t.equal(BoostsLogic.multiplier(cfg, s, "coins", 200), 2)
		t.equal(BoostsLogic.multiplier(cfg, s, "coins", 700), 1)
		t.equal(#BoostsLogic.prune(s, 700).active, 0)
	end,

	["stack and refresh modes"] = function()
		local cfg = boosts()
		local s = BoostsLogic.activate(cfg, BoostsLogic.newState(), "Luck", 0, 2).state
		t.near(BoostsLogic.multiplier(cfg, s, "luck", 1), 2.25, 1e-9)
		t.equal(BoostsLogic.activate(cfg, s, "Luck", 1).reason, "max stacks")
		local e = BoostsLogic.activate(cfg, BoostsLogic.newState(), "Event", 0).state
		e = BoostsLogic.activate(cfg, e, "Event", 90).state
		t.equal(BoostsLogic.remaining(e, 90).Event, 100)
	end,

	["online clock pauses while offline, wall clock does not"] = function()
		local online = boosts("online")
		local s = BoostsLogic.activate(online, BoostsLogic.newState(), "Coins2x", 1000).state
		local saved = BoostsLogic.serialize(online, s, 1100)
		local back = BoostsLogic.deserialize(online, saved, 99999)
		t.equal(BoostsLogic.remaining(back, 99999).Coins2x, 500)
		local wall = boosts("wall")
		local w = BoostsLogic.activate(wall, BoostsLogic.newState(), "Coins2x", 1000).state
		t.equal(#BoostsLogic.deserialize(wall, BoostsLogic.serialize(wall, w, 1100), 99999).active, 0)
		local hostile: any = { c = "o", a = { { "Coins2x", 1e12 }, { "Fake", 10 }, "x" } }
		t.equal(BoostsLogic.remaining(BoostsLogic.deserialize(online, hostile, 0), 0).Coins2x, 1800)
	end,

	["worlds unlock in order with requirements"] = function()
		local cfg = worlds()
		local s = WorldsLogic.newState(cfg)
		t.truthy(WorldsLogic.isUnlocked(cfg, s, "Spawn"))
		t.equal(
			WorldsLogic.canUnlock(cfg, s, "Volcano", { balances = { Coins = 1e9 }, rebirths = 5 }).reason,
			"unlock Forest first"
		)
		t.equal(WorldsLogic.canUnlock(cfg, s, "Forest", { balances = { Coins = 10 } }).reason, "not enough Coins")
		local check, s2 = WorldsLogic.unlock(cfg, s, "Forest", { balances = { Coins = 500 } })
		t.truthy(check.ok)
		t.deepEqual(check.cost, { Coins = 500 })
		t.equal(WorldsLogic.nextLocked(cfg, s2), "Volcano")
		t.equal(WorldsLogic.canUnlock(cfg, s2, "Volcano", { balances = { Coins = 1e9 } }).reason, "needs 1 rebirths")
		t.equal(WorldsLogic.multiplier(cfg, s2), 1.5)
		t.equal(WorldsLogic.canUnlock(cfg, s2, "Forest", {}).reason, "already unlocked")
		local back = WorldsLogic.deserialize(cfg, { u = { "Forest", "Moon", 4 } })
		t.deepEqual(back, s2)
	end,
}
