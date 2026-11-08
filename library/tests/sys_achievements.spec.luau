--!strict
local AchievementsLogic = require("../src/Systems/Achievements/AchievementsLogic")
local t = require("./lib/t")

local function defs()
	return AchievementsLogic.newDefs({
		{ id = "FirstBlood", key = "Kill", threshold = 1, name = "First Blood", badgeId = 111 },
		{ id = "Slayer", key = "Kill", threshold = 100 },
		{ id = "Veteran", kind = "stat", key = "Level", threshold = 10, description = "Reach level 10" },
		{ id = "Secret", key = "SecretDoor", threshold = 1, hidden = true, name = "Explorer" },
	})
end

return {
	["newDefs validates definitions"] = function()
		t.throws(function()
			AchievementsLogic.newDefs({ { id = "A", key = "K", threshold = 0 } })
		end)
		t.throws(function()
			AchievementsLogic.newDefs({ { id = "A", key = "", threshold = 1 } })
		end)
		local one = { id = "A", key = "K", threshold = 1 }
		t.throws(function()
			AchievementsLogic.newDefs({ one, one })
		end)
		local badKind: any = { { id = "A", kind = "timer", key = "K", threshold = 1 } }
		t.throws(function()
			AchievementsLogic.newDefs(badKind)
		end)
		t.throws(function()
			AchievementsLogic.newDefs({ { id = "A", key = "K", threshold = 1, badgeId = -5 } })
		end)
		local d = defs()
		t.equal(#d.list, 4)
		t.equal(d.byId.Slayer.name, "Slayer")
		t.equal(d.byId.Slayer.kind, "counter")
	end,

	["counters unlock at their threshold once"] = function()
		local d = defs()
		local state, unlocked = AchievementsLogic.increment(d, AchievementsLogic.new(), "Kill", 1, 50)
		t.deepEqual(unlocked, { "FirstBlood" })
		t.equal(state.unlocked.FirstBlood, 50)
		local again, more = AchievementsLogic.increment(d, state, "Kill", 1, 60)
		t.deepEqual(more, {})
		t.equal(again.unlocked.FirstBlood, 50)
		t.equal(again.counters.Kill, 2)
	end,

	["one increment can unlock several achievements"] = function()
		local d = defs()
		local _, unlocked = AchievementsLogic.increment(d, AchievementsLogic.new(), "Kill", 150, 0)
		t.deepEqual(unlocked, { "FirstBlood", "Slayer" })
	end,

	["increment ignores bad input and never modifies the input"] = function()
		local d = defs()
		local original = AchievementsLogic.new()
		local same, none = AchievementsLogic.increment(d, original, "Kill", -1, 0)
		t.equal(same, original)
		t.deepEqual(none, {})
		t.equal(select(1, AchievementsLogic.increment(d, original, "Kill", math.huge, 0)), original)
		local updated = AchievementsLogic.increment(d, original, "Kill", nil, 0)
		t.equal(updated.counters.Kill, 1)
		t.equal(original.counters.Kill, nil)
	end,

	["stats keep the highest value"] = function()
		local d = defs()
		local state, unlocked = AchievementsLogic.observe(d, AchievementsLogic.new(), "Level", 7, 0)
		t.deepEqual(unlocked, {})
		local lower = AchievementsLogic.observe(d, state, "Level", 3, 0)
		t.equal(lower, state)
		t.equal(lower.stats.Level, 7)
		local _, reached = AchievementsLogic.observe(d, state, "Level", 10, 5)
		t.deepEqual(reached, { "Veteran" })
		t.equal(select(1, AchievementsLogic.observe(d, state, "Level", math.sqrt(-1), 0)), state)
	end,

	["manual unlocks are idempotent"] = function()
		local d = defs()
		local state, isNew = AchievementsLogic.unlock(d, AchievementsLogic.new(), "Secret", 9)
		t.truthy(isNew)
		t.truthy(AchievementsLogic.isUnlocked(state, "Secret"))
		local _, again = AchievementsLogic.unlock(d, state, "Secret", 10)
		t.falsy(again)
		local _, unknown = AchievementsLogic.unlock(d, state, "Nope", 10)
		t.falsy(unknown)
	end,

	["progress reports current, target and fraction"] = function()
		local d = defs()
		local state = AchievementsLogic.increment(d, AchievementsLogic.new(), "Kill", 25, 0)
		local slayer = AchievementsLogic.progress(d, state, "Slayer")
		assert(slayer, "missing progress")
		t.equal(slayer.current, 25)
		t.equal(slayer.target, 100)
		t.equal(slayer.fraction, 0.25)
		t.falsy(slayer.unlocked)
		local first = AchievementsLogic.progress(d, state, "FirstBlood")
		assert(first, "missing progress")
		t.equal(first.fraction, 1)
		t.equal(AchievementsLogic.progress(d, state, "Nope"), nil)
	end,

	["hidden achievements stay hidden until unlocked"] = function()
		local d = defs()
		local locked = AchievementsLogic.list(d, AchievementsLogic.new())
		t.equal(locked[4].name, "???")
		t.equal(locked[4].description, "")
		t.truthy(locked[4].hidden)
		t.equal(locked[3].description, "Reach level 10")
		local state = AchievementsLogic.increment(d, AchievementsLogic.new(), "SecretDoor", 1, 0)
		local shown = AchievementsLogic.list(d, state)
		t.equal(shown[4].name, "Explorer")
		t.falsy(shown[4].hidden)
		t.truthy(shown[4].unlocked)
	end,

	["list caps progress at the threshold"] = function()
		local d = defs()
		local state = AchievementsLogic.increment(d, AchievementsLogic.new(), "Kill", 500, 0)
		t.equal(AchievementsLogic.list(d, state)[2].current, 100)
	end,

	["pending badges clear once awarded"] = function()
		local d = defs()
		local state = AchievementsLogic.increment(d, AchievementsLogic.new(), "Kill", 1, 0)
		local pending = AchievementsLogic.pendingBadges(d, state)
		t.deepEqual(pending, { { id = "FirstBlood", badgeId = 111 } })
		local awarded = AchievementsLogic.markBadgeAwarded(state, "FirstBlood")
		t.deepEqual(AchievementsLogic.pendingBadges(d, awarded), {})
		t.equal(AchievementsLogic.markBadgeAwarded(awarded, "FirstBlood"), awarded)
		t.deepEqual(AchievementsLogic.pendingBadges(d, AchievementsLogic.new()), {})
	end,

	["evaluate unlocks achievements added after progress was made"] = function()
		local old = AchievementsLogic.newDefs({ { id = "A", key = "Kill", threshold = 1 } })
		local state = AchievementsLogic.increment(old, AchievementsLogic.new(), "Kill", 5, 0)
		local newer = AchievementsLogic.newDefs({
			{ id = "A", key = "Kill", threshold = 1 },
			{ id = "B", key = "Kill", threshold = 5 },
		})
		local _, unlocked = AchievementsLogic.evaluate(newer, state, 10)
		t.deepEqual(unlocked, { "B" })
	end,

	["serialize and deserialize drop unknown and malformed entries"] = function()
		local d = defs()
		local state = AchievementsLogic.increment(d, AchievementsLogic.new(), "Kill", 1, 5)
		state = AchievementsLogic.markBadgeAwarded(state, "FirstBlood")
		local restored = AchievementsLogic.deserialize(d, AchievementsLogic.serialize(state))
		t.deepEqual(restored, state)
		local raw: any = {
			c = { Kill = 3, Bad = "x" },
			s = { Level = math.huge },
			u = { FirstBlood = 1, Removed = 2 },
			b = { FirstBlood = true, Slayer = true },
		}
		local cleaned = AchievementsLogic.deserialize(d, raw)
		t.deepEqual(cleaned.counters, { Kill = 3 })
		t.deepEqual(cleaned.stats, {})
		t.deepEqual(cleaned.unlocked, { FirstBlood = 1 })
		t.deepEqual(cleaned.badges, { FirstBlood = true })
		t.deepEqual(AchievementsLogic.deserialize(d, nil), AchievementsLogic.new())
	end,
}
