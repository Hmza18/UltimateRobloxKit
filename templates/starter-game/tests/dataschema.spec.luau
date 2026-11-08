--!strict
local DataSchema = require("../src/shared/Logic/DataSchema")
local Inventory = require("../src/shared/Logic/Inventory")
local t = require("./lib/t")

return {
	["a new player gets default data"] = function()
		local data = DataSchema.migrate(nil)
		t.truthy(data)
		if data then
			t.equal(data.coins, 0)
			t.equal(data.rebirths, 0)
			t.equal(Inventory.usedSlots(data.inventory), 0)
		end
	end,

	["version 1 data is migrated"] = function()
		local data = DataSchema.migrate({ schemaVersion = 1, data = { cash = 50 } })
		t.truthy(data)
		if data then
			t.equal(data.coins, 50)
			t.deepEqual(data.progress, {})
		end
	end,

	["a bare table is treated as version 1"] = function()
		local data = DataSchema.migrate({ cash = 7, rebirths = 2 })
		t.truthy(data)
		if data then
			t.equal(data.coins, 7)
			t.equal(data.rebirths, 2)
		end
	end,

	["data from a newer schema is refused"] = function()
		local data, reason = DataSchema.migrate({ schemaVersion = DataSchema.VERSION + 1, data = {} })
		t.equal(data, nil)
		t.truthy(reason)
	end,

	["reconcile drops invalid fields"] = function()
		local data = DataSchema.reconcile({ coins = -5, rebirths = 1.7, progress = { ok = 3, bad = "x" } })
		t.equal(data.coins, 0)
		t.equal(data.rebirths, 1)
		t.equal(data.progress.ok, 3)
		t.equal(data.progress.bad, nil)
	end,

	["lock states"] = function()
		t.equal(DataSchema.lockState(nil, "job-a", 100, 300), "free")
		t.equal(DataSchema.lockState({ jobId = "job-a", time = 90 }, "job-a", 100, 300), "own")
		t.equal(DataSchema.lockState({ jobId = "job-b", time = 90 }, "job-a", 100, 300), "held")
		t.equal(DataSchema.lockState({ jobId = "job-b", time = 90 }, "job-a", 500, 300), "stale")
	end,

	["newRecord copies data and sets or clears the lock"] = function()
		local data = DataSchema.default()
		local held = DataSchema.newRecord(data, "job-a", 10, false)
		t.equal(held.schemaVersion, DataSchema.VERSION)
		t.truthy(held.lock)
		data.coins = 99
		t.equal(held.data.coins, 0, "record is a snapshot")
		t.equal(DataSchema.newRecord(data, "job-a", 10, true).lock, nil)
	end,
}
