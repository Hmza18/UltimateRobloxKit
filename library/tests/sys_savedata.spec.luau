--!strict
local SaveDataLogic = require("../src/Systems/SaveData/SaveDataLogic")
local t = require("./lib/t")

local function schema()
	return SaveDataLogic.newSchema({
		version = 3,
		defaults = { coins = 0, settings = { music = true, volume = 0.5 }, items = {} },
		migrations = {
			-- v1 stored gold; v2 renamed it to coins.
			[1] = function(data)
				data.coins = data.gold
				data.gold = nil
				return data
			end,
			-- v3 moved the music flag into settings.
			[2] = function(data)
				data.settings = { music = data.music ~= false }
				data.music = nil
				return data
			end,
		},
	})
end

return {
	["newSchema requires a migration for every older version"] = function()
		t.throws(function()
			SaveDataLogic.newSchema({ version = 2, defaults = {} })
		end)
		t.throws(function()
			SaveDataLogic.newSchema({ version = 0, defaults = {} })
		end)
		local noDefaults: any = { version = 1 }
		t.throws(function()
			SaveDataLogic.newSchema(noDefaults)
		end)
		t.equal(SaveDataLogic.newSchema({ version = 1, defaults = {} }).version, 1)
	end,

	["defaults are deep copies"] = function()
		local s = schema()
		local first = SaveDataLogic.defaults(s)
		first.settings.music = false
		table.insert(first.items, "x")
		local second = SaveDataLogic.defaults(s)
		t.equal(second.settings.music, true)
		t.equal(#second.items, 0)
	end,

	["reconcile fills missing keys and fixes wrong types"] = function()
		local defaults = { coins = 0, settings = { music = true, volume = 0.5 }, items = {} }
		local data = { coins = "lots", settings = { music = false }, items = { "Sword" }, extra = 7 }
		local result = SaveDataLogic.reconcile(data, defaults)
		t.equal(result.coins, 0)
		t.equal(result.settings.music, false)
		t.equal(result.settings.volume, 0.5)
		t.equal(result.items[1], "Sword")
		t.equal(result.extra, 7)
		t.equal(data.settings.volume, nil)
		t.equal(SaveDataLogic.reconcile(nil, defaults).coins, 0)
	end,

	["migrate runs the chain in order"] = function()
		local s = schema()
		local data, reason = SaveDataLogic.migrate(s, { gold = 40, music = false }, 1)
		t.equal(reason, nil)
		t.equal(data.coins, 40)
		t.equal(data.gold, nil)
		t.equal(data.settings.music, false)
		local fromTwo = SaveDataLogic.migrate(s, { coins = 5 }, 2)
		t.equal(fromTwo.settings.music, true)
		local same = SaveDataLogic.migrate(s, { coins = 9 }, 3)
		t.equal(same.coins, 9)
	end,

	["migrate refuses newer data and reports failures"] = function()
		local s = schema()
		t.equal(select(2, SaveDataLogic.migrate(s, {}, 4)), "data is from a newer version")
		t.equal(select(2, SaveDataLogic.migrate(s, {}, 0)), "invalid version")
		local broken = SaveDataLogic.newSchema({
			version = 2,
			defaults = {},
			migrations = {
				[1] = function(_data)
					error("bad")
				end,
			},
		})
		t.equal(select(2, SaveDataLogic.migrate(broken, {}, 1)), "migration from version 1 failed")
	end,

	["migrations get a copy of the input"] = function()
		local s = schema()
		local original = { gold = 3 }
		SaveDataLogic.migrate(s, original, 1)
		t.equal(original.gold, 3)
	end,

	["load handles new players, records and legacy data"] = function()
		local s = schema()
		local fresh = SaveDataLogic.load(s, nil)
		t.equal(fresh.coins, 0)
		local record = SaveDataLogic.load(s, { schemaVersion = 2, data = { coins = 12, music = true } })
		t.equal(record.coins, 12)
		t.equal(record.settings.volume, 0.5)
		local legacy = SaveDataLogic.load(s, { gold = 8 })
		t.equal(legacy.coins, 8)
		t.equal(select(2, SaveDataLogic.load(s, "garbage")), "corrupt record")
		t.equal(select(2, SaveDataLogic.load(s, { schemaVersion = 9, data = {} })), "data is from a newer version")
	end,

	["lockState classifies sessions"] = function()
		local own = { session = { jobId = "A", lockedAt = 0, heartbeatAt = 100 } }
		t.equal(SaveDataLogic.lockState(nil, "A", 0), "free")
		t.equal(SaveDataLogic.lockState({ data = {} }, "A", 0), "free")
		t.equal(SaveDataLogic.lockState(own, "A", 150), "own")
		t.equal(SaveDataLogic.lockState(own, "B", 150, 60), "held")
		t.equal(SaveDataLogic.lockState(own, "B", 161, 60), "stale")
		local broken = { session = { jobId = "A" } }
		t.equal(SaveDataLogic.lockState(broken, "B", 10, 60), "held")
		t.equal(SaveDataLogic.lockState(broken, "B", 61, 60), "stale")
	end,

	["planLoad takes free, own and stale sessions but not held ones"] = function()
		local s = schema()
		local plan = SaveDataLogic.planLoad(s, nil, "A", 1000)
		t.truthy(plan.ok)
		local record = plan.record
		assert(record, "missing record")
		t.equal(record.schemaVersion, 3)
		local session = record.session
		assert(session, "missing session")
		t.equal(session.jobId, "A")
		t.equal(session.heartbeatAt, 1000)
		t.equal(plan.data.coins, 0)
		local held = SaveDataLogic.planLoad(s, record, "B", 1010, 60)
		t.falsy(held.ok)
		t.equal(held.reason, "locked by another server")
		t.equal(held.record, nil)
		local stolen = SaveDataLogic.planLoad(s, record, "B", 1100, 60)
		t.truthy(stolen.ok)
		local corrupt = SaveDataLogic.planLoad(s, 42, "A", 0)
		t.falsy(corrupt.ok)
		t.equal(corrupt.reason, "corrupt record")
	end,

	["planSave keeps the session, releases it, or refuses when lost"] = function()
		local s = schema()
		local loaded = SaveDataLogic.planLoad(s, nil, "A", 100).record
		local saved = SaveDataLogic.planSave(s, loaded, "A", { coins = 5 }, 200)
		t.truthy(saved.ok)
		local record = saved.record
		assert(record, "missing record")
		t.equal(record.data.coins, 5)
		local session = record.session
		assert(session, "missing session")
		t.equal(session.lockedAt, 100)
		t.equal(session.heartbeatAt, 200)
		local released = SaveDataLogic.planSave(s, record, "A", { coins = 6 }, 300, true)
		t.truthy(released.ok)
		t.equal(released.record and released.record.session, nil)
		local lost = SaveDataLogic.planSave(s, record, "B", { coins = 1 }, 1e9)
		t.falsy(lost.ok)
		t.equal(lost.reason, "session lock lost")
		t.truthy(SaveDataLogic.planSave(s, nil, "A", {}, 0).ok)
	end,

	["backoff doubles up to the cap and applies jitter"] = function()
		t.equal(SaveDataLogic.backoff(1), 1)
		t.equal(SaveDataLogic.backoff(2), 2)
		t.equal(SaveDataLogic.backoff(4), 8)
		t.equal(SaveDataLogic.backoff(10), 16)
		t.equal(SaveDataLogic.backoff(3, 0.5, 100), 2)
		local function low(): number
			return 0
		end
		local function high(): number
			return 1
		end
		t.equal(SaveDataLogic.backoff(3, 1, 16, low), 2)
		t.equal(SaveDataLogic.backoff(3, 1, 16, high), 4)
	end,

	["retry sleeps between failures and stops on success"] = function()
		local sleeps: { number } = {}
		local calls = 0
		local function flaky(): any
			calls += 1
			if calls < 3 then
				error("busy")
			end
			return "done"
		end
		local options = {
			attempts = 5,
			sleep = function(seconds: number)
				table.insert(sleeps, seconds)
			end,
		}
		local ok, result, attempts = SaveDataLogic.retry(flaky, options)
		t.truthy(ok)
		t.equal(result, "done")
		t.equal(attempts, 3)
		t.deepEqual(sleeps, { 1, 2 })
	end,

	["retry gives up after the last attempt without sleeping again"] = function()
		local sleeps = 0
		local function failing(): any
			error("down", 0)
		end
		local options = {
			attempts = 3,
			sleep = function(_seconds: number)
				sleeps += 1
			end,
		}
		local ok, err, attempts = SaveDataLogic.retry(failing, options)
		t.falsy(ok)
		t.equal(err, "down")
		t.equal(attempts, 3)
		t.equal(sleeps, 2)
	end,

	["waitForBudget waits for budget or gives up"] = function()
		local budget = 0
		local slept = 0
		local function getBudget(): number
			return budget
		end
		local function sleep(_seconds: number)
			slept += 1
			if slept == 2 then
				budget = 5
			end
		end
		t.truthy(SaveDataLogic.waitForBudget(getBudget, 1, sleep, 10))
		t.equal(slept, 2)
		budget = 0
		slept = 10
		t.falsy(SaveDataLogic.waitForBudget(getBudget, 1, sleep, 3))
	end,
}
