--!strict
local Quests = require("../src/Systems/Quests/QuestsLogic")
local t = require("./lib/t")

local function definitions(): { any }
	return {
		{
			id = "Slimes",
			objectives = { { id = "kill", kind = "count", event = "EnemyDefeated", target = "Slime", amount = 3 } },
			next = "Gems",
		},
		{
			id = "Gems",
			prerequisites = { "Slimes" },
			objectives = {
				{ id = "gems", kind = "collect", target = "Gem", amount = 2 },
				{ id = "cave", kind = "reach", target = "Cave" },
			},
		},
		{ id = "Daily", daily = true, objectives = { { id = "win", kind = "count", event = "RoundWon" } } },
		{
			id = "Grind",
			repeatable = true,
			cooldown = 60,
			objectives = { { id = "any", kind = "count", event = "EnemyDefeated" } },
		},
		{ id = "Timed", timeLimit = 30, objectives = { { id = "go", kind = "reach", target = "Tower" } } },
	}
end

local function catalog()
	return Quests.newCatalog(definitions() :: any)
end

return {
	["validateDefinitions accepts a valid set"] = function()
		local ok, errors = Quests.validateDefinitions(definitions() :: any)
		t.truthy(ok)
		t.equal(#errors, 0)
	end,

	["validateDefinitions reports bad objectives"] = function()
		local definitionsWithErrors: any = {
			{ id = "A", objectives = {} },
			{ id = "A", objectives = { { id = "x", kind = "count" } } },
			{ id = "B", objectives = { { id = "x", kind = "fly" }, { id = "x", kind = "collect", target = "Gem" } } },
			{ id = "C", objectives = { { id = "y", kind = "reach", target = "Top", amount = 0 } } },
		}
		local ok, errors = Quests.validateDefinitions(definitionsWithErrors)
		t.falsy(ok)
		local joined = table.concat(errors, "\n")
		t.truthy(string.find(joined, "needs at least one objective", 1, true), "empty objectives")
		t.truthy(string.find(joined, "duplicate quest id", 1, true), "duplicate quest")
		t.truthy(string.find(joined, "need an event", 1, true), "count without event")
		t.truthy(string.find(joined, "unknown kind", 1, true), "unknown kind")
		t.truthy(string.find(joined, "duplicate objective id", 1, true), "duplicate objective")
		t.truthy(string.find(joined, "positive integer", 1, true), "bad amount")
	end,

	["validateDefinitions reports missing links and cycles"] = function()
		local brokenLinks: any = {
			{ id = "A", prerequisites = { "B" }, objectives = { { id = "o", kind = "reach", target = "P" } } },
			{ id = "B", prerequisites = { "A" }, objectives = { { id = "o", kind = "reach", target = "P" } } },
			{
				id = "C",
				prerequisites = { "Nope" },
				next = "Gone",
				objectives = { { id = "o", kind = "reach", target = "P" } },
			},
		}
		local ok, errors = Quests.validateDefinitions(brokenLinks)
		t.falsy(ok)
		local joined = table.concat(errors, "\n")
		t.truthy(string.find(joined, "unknown prerequisite Nope", 1, true))
		t.truthy(string.find(joined, "unknown next quest Gone", 1, true))
		t.truthy(string.find(joined, "prerequisite cycle", 1, true))
		t.throws(function()
			Quests.newCatalog({ { id = "X" } } :: any)
		end)
	end,

	["start respects prerequisites and duplicates"] = function()
		local cat = catalog()
		local state = Quests.newState()
		local ok, reason = Quests.start(cat, state, "Gems", 0)
		t.falsy(ok)
		t.equal(reason, "prerequisites not met")
		t.truthy(Quests.start(cat, state, "Slimes", 0))
		t.equal(select(2, Quests.start(cat, state, "Slimes", 0)), "already active")
		t.equal(select(2, Quests.start(cat, state, "Missing", 0)), "unknown quest")
	end,

	["count objectives filter by target and clamp"] = function()
		local cat = catalog()
		local state = Quests.newState()
		Quests.start(cat, state, "Slimes", 0)
		local result = Quests.handleEvent(cat, state, { type = "EnemyDefeated", target = "Bat" }, 1)
		t.equal(#result.updated, 0)
		result = Quests.handleEvent(cat, state, { type = "EnemyDefeated", target = "Slime", amount = 2 }, 2)
		t.deepEqual(result.updated, { "Slimes" })
		local rows = Quests.progressOf(cat, state, "Slimes")
		t.truthy(rows)
		if rows then
			t.equal(rows[1].current, 2)
			t.equal(rows[1].required, 3)
		end
	end,

	["completion moves the quest and starts the chain"] = function()
		local cat = catalog()
		local state = Quests.newState()
		Quests.start(cat, state, "Slimes", 0)
		local result = Quests.handleEvent(cat, state, { type = "EnemyDefeated", target = "Slime", amount = 10 }, 5)
		t.deepEqual(result.completed, { "Slimes" })
		t.deepEqual(result.started, { "Gems" })
		t.equal(state.active.Slimes, nil)
		t.equal(state.completed.Slimes.count, 1)
		t.equal(state.completed.Slimes.lastAt, 5)
		t.truthy(state.active.Gems)
	end,

	["collect and reach objectives must all finish"] = function()
		local cat = catalog()
		local state = Quests.newState()
		state.completed.Slimes = { count = 1, lastAt = 0 }
		t.truthy(Quests.start(cat, state, "Gems", 0))
		Quests.handleEvent(cat, state, { type = Quests.COLLECT_EVENT, target = "Gem", amount = 2 }, 1)
		t.truthy(state.active.Gems, "still needs the cave")
		Quests.handleEvent(cat, state, { type = Quests.REACH_EVENT, target = "Mine" }, 2)
		t.truthy(state.active.Gems, "wrong location")
		local result = Quests.handleEvent(cat, state, { type = Quests.REACH_EVENT, target = "Cave" }, 3)
		t.deepEqual(result.completed, { "Gems" })
		t.equal(#result.started, 0)
	end,

	["non repeatable quests cannot restart"] = function()
		local cat = catalog()
		local state = Quests.newState()
		state.completed.Slimes = { count = 1, lastAt = 0 }
		t.equal(select(2, Quests.canStart(cat, state, "Slimes", 999999)), "already completed")
	end,

	["repeatable quests wait for the cooldown"] = function()
		local cat = catalog()
		local state = Quests.newState()
		Quests.start(cat, state, "Grind", 0)
		Quests.handleEvent(cat, state, { type = "EnemyDefeated" }, 100)
		t.equal(state.completed.Grind.count, 1)
		t.equal(select(2, Quests.canStart(cat, state, "Grind", 159)), "on cooldown")
		t.truthy(Quests.start(cat, state, "Grind", 160))
		Quests.handleEvent(cat, state, { type = "EnemyDefeated" }, 170)
		t.equal(state.completed.Grind.count, 2)
	end,

	["daily quests reset at the day boundary"] = function()
		local cat = catalog()
		local config = Quests.resolveConfig({ dayLength = 100, dayOffset = 10 })
		local state = Quests.newState()
		t.truthy(Quests.start(cat, state, "Daily", 15, config))
		Quests.handleEvent(cat, state, { type = "RoundWon" }, 20, config)
		t.equal(select(2, Quests.canStart(cat, state, "Daily", 109, config)), "already done today")
		t.truthy(Quests.canStart(cat, state, "Daily", 110, config))
		t.equal(Quests.dayIndex(109, config), 0)
		t.equal(Quests.dayIndex(110, config), 1)
	end,

	["timed quests expire"] = function()
		local cat = catalog()
		local state = Quests.newState()
		Quests.start(cat, state, "Timed", 0)
		local late = Quests.handleEvent(cat, state, { type = Quests.REACH_EVENT, target = "Tower" }, 31)
		t.equal(#late.completed, 0, "expired quests ignore events")
		t.deepEqual(Quests.expire(cat, state, 31), { "Timed" })
		t.equal(state.active.Timed, nil)
		t.deepEqual(Quests.expire(cat, state, 40), {})
	end,

	["maxActive limits active quests"] = function()
		local cat = catalog()
		local config = Quests.resolveConfig({ maxActive = 1 })
		local state = Quests.newState()
		t.truthy(Quests.start(cat, state, "Slimes", 0, config))
		t.equal(select(2, Quests.start(cat, state, "Daily", 0, config)), "too many active quests")
		t.truthy(Quests.abandon(state, "Slimes"))
		t.falsy(Quests.abandon(state, "Slimes"))
		t.truthy(Quests.start(cat, state, "Daily", 0, config))
	end,

	["invalid events change nothing"] = function()
		local cat = catalog()
		local state = Quests.newState()
		Quests.start(cat, state, "Grind", 0)
		t.equal(#Quests.handleEvent(cat, state, nil :: any, 1).updated, 0)
		t.equal(#Quests.handleEvent(cat, state, { type = "EnemyDefeated", amount = 0 }, 1).updated, 0)
		t.equal(#Quests.handleEvent(cat, state, { type = "EnemyDefeated", amount = math.sqrt(-1) }, 1).updated, 0)
		t.equal(#Quests.handleEvent(cat, state, { type = "EnemyDefeated", amount = -2 }, 1).updated, 0)
		t.truthy(state.active.Grind)
	end,

	["available lists startable quests in order"] = function()
		local cat = catalog()
		local state = Quests.newState()
		t.deepEqual(Quests.available(cat, state, 0), { "Slimes", "Daily", "Grind", "Timed" })
	end,

	["serialize and deserialize round trip and sanitise"] = function()
		local cat = catalog()
		local state = Quests.newState()
		Quests.start(cat, state, "Slimes", 4)
		Quests.handleEvent(cat, state, { type = "EnemyDefeated", target = "Slime" }, 5)
		state.completed.Daily = { count = 2, lastAt = 50 }
		local restored = Quests.deserialize(Quests.serialize(state), cat)
		t.deepEqual(restored, state)
		local saved = {
			active = {
				Slimes = { startedAt = 1, progress = { kill = 99, extra = 5 } },
				Unknown = { startedAt = 1, progress = {} },
				Gems = { startedAt = "x" },
			},
			completed = { Daily = { count = 1.5, lastAt = 1 }, Grind = { count = 1, lastAt = 3 } },
		}
		local dirty = Quests.deserialize(saved, cat)
		t.equal(dirty.active.Slimes.progress.kill, 3)
		t.equal(dirty.active.Slimes.progress.extra, nil)
		t.equal(dirty.active.Unknown, nil)
		t.equal(dirty.active.Gems, nil)
		t.equal(dirty.completed.Daily, nil)
		t.equal(dirty.completed.Grind.count, 1)
		t.deepEqual(Quests.deserialize("garbage", cat), Quests.newState())
	end,
}
