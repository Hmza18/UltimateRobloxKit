--!strict
local CraftingLogic = require("../src/Systems/Crafting/CraftingLogic")
local InventoryLogic = require("../src/Systems/Inventory/InventoryLogic")
local t = require("./lib/t")

local bag = CraftingLogic.bagOps

local function book()
	return CraftingLogic.newBook({
		{ id = "Planks", inputs = { { id = "Log", count = 1 } }, outputs = { { id = "Plank", count = 4 } } },
		{
			id = "Sword",
			inputs = { { id = "Plank", count = 2 }, { id = "Iron", count = 3 } },
			outputs = { { id = "Sword", count = 1 } },
			time = 10,
			station = "Anvil",
		},
		{ id = "Torch", inputs = { { id = "Plank", count = 1 } }, outputs = { { id = "Torch", count = 2 } }, time = 5 },
	})
end

local ANVIL = { stations = { Anvil = true } }

return {
	["newBook validates recipes"] = function()
		t.throws(function()
			CraftingLogic.newBook({ { id = "A", inputs = {}, outputs = {} } })
		end)
		local zeroInput = { id = "A", inputs = { { id = "X", count = 0 } }, outputs = { { id = "Y", count = 1 } } }
		t.throws(function()
			CraftingLogic.newBook({ zeroInput })
		end)
		t.throws(function()
			CraftingLogic.newBook({ { id = "A", inputs = {}, outputs = { { id = "Y", count = 1 } }, time = -1 } })
		end)
		local dup = { id = "A", inputs = {}, outputs = { { id = "Y", count = 1 } } }
		t.throws(function()
			CraftingLogic.newBook({ dup, dup })
		end)
		local b = book()
		t.equal(#b.order, 3)
		local sword = CraftingLogic.getRecipe(b, "Sword")
		assert(sword, "missing sword")
		t.equal(sword.time, 10)
		local planks = CraftingLogic.getRecipe(b, "Planks")
		assert(planks, "missing planks")
		t.equal(planks.time, 0)
		t.equal(CraftingLogic.getRecipe(b, "Nope"), nil)
	end,

	["craft consumes inputs and adds outputs"] = function()
		local result = CraftingLogic.craft(book(), "Planks", { Log = 2 }, bag)
		t.truthy(result.ok)
		t.deepEqual(result.inventory, { Log = 1, Plank = 4 })
		local twice = CraftingLogic.craft(book(), "Planks", { Log = 2 }, bag, nil, 2)
		t.deepEqual(twice.inventory, { Plank = 8 })
	end,

	["craft is all or nothing when inputs are missing"] = function()
		local inventory = { Plank = 2, Iron = 2 }
		local result = CraftingLogic.craft(book(), "Sword", inventory, bag, ANVIL)
		t.falsy(result.ok)
		t.equal(result.reason, "missing items")
		t.equal(result.inventory, inventory)
		local missing = CraftingLogic.missing(book().recipes.Sword, inventory, bag)
		t.deepEqual(missing, { { id = "Iron", count = 1 } })
	end,

	["stations are required when a recipe names one"] = function()
		local inventory = { Plank = 2, Iron = 3 }
		t.equal(select(2, CraftingLogic.canCraft(book(), "Sword", inventory, bag)), "station required")
		local nowhere = { stations = {} }
		t.equal(select(2, CraftingLogic.canCraft(book(), "Sword", inventory, bag, nowhere)), "station required")
		t.truthy(CraftingLogic.canCraft(book(), "Sword", inventory, bag, ANVIL))
	end,

	["invalid recipes and times are rejected"] = function()
		t.equal(CraftingLogic.craft(book(), "Nope", {}, bag).reason, "unknown recipe")
		t.equal(CraftingLogic.craft(book(), "Planks", { Log = 5 }, bag, nil, 0).reason, "invalid times")
		t.equal(CraftingLogic.craft(book(), "Planks", { Log = 5 }, bag, nil, 1.5).reason, "invalid times")
		t.equal(CraftingLogic.craft(book(), "Planks", { Log = 5 }, bag, nil, 5000).reason, "invalid times")
	end,

	["craft against InventoryLogic fails cleanly when outputs do not fit"] = function()
		local registry = InventoryLogic.newRegistry({ { id = "Log", maxStack = 10 }, { id = "Plank", maxStack = 3 } })
		local ops = CraftingLogic.inventoryOps(registry)
		local inventory = InventoryLogic.add(InventoryLogic.new(1), registry, "Log", 1)
		local result = CraftingLogic.craft(book(), "Planks", inventory, ops)
		t.falsy(result.ok)
		t.equal(result.reason, "no space")
		t.equal(InventoryLogic.count(result.inventory, "Log"), 1)
		local roomy = InventoryLogic.add(InventoryLogic.new(3), registry, "Log", 1)
		local ok = CraftingLogic.craft(book(), "Planks", roomy, ops)
		t.truthy(ok.ok)
		t.equal(InventoryLogic.count(ok.inventory, "Plank"), 4)
		t.equal(InventoryLogic.count(ok.inventory, "Log"), 0)
	end,

	["enqueue takes inputs and schedules jobs back to back"] = function()
		local b = book()
		local queue = CraftingLogic.newQueue(3)
		local first = CraftingLogic.enqueue(b, queue, "Torch", { Plank = 2 }, bag, nil, 100)
		t.truthy(first.ok)
		t.deepEqual(first.inventory, { Plank = 1 })
		local firstJob = first.job
		assert(firstJob, "missing job")
		t.equal(firstJob.startAt, 100)
		t.equal(firstJob.finishAt, 105)
		local second = CraftingLogic.enqueue(b, first.queue, "Torch", first.inventory, bag, nil, 101)
		local secondJob = second.job
		assert(secondJob, "missing job")
		t.equal(secondJob.startAt, 105)
		t.equal(secondJob.finishAt, 110)
		t.equal(#queue.jobs, 0)
	end,

	["enqueue respects queue size and input checks"] = function()
		local b = book()
		local queue = CraftingLogic.newQueue(1)
		local first = CraftingLogic.enqueue(b, queue, "Torch", { Plank = 5 }, bag, nil, 0)
		t.equal(CraftingLogic.enqueue(b, first.queue, "Torch", first.inventory, bag, nil, 0).reason, "queue full")
		t.equal(CraftingLogic.enqueue(b, queue, "Torch", {}, bag, nil, 0).reason, "missing items")
		t.equal(CraftingLogic.enqueue(b, queue, "Torch", { Plank = 1 }, bag, nil, math.huge).reason, "invalid time")
		t.throws(function()
			CraftingLogic.newQueue(0)
		end)
	end,

	["collect delivers finished jobs in order"] = function()
		local b = book()
		local a = CraftingLogic.enqueue(b, CraftingLogic.newQueue(), "Torch", { Plank = 2 }, bag, nil, 0)
		local c = CraftingLogic.enqueue(b, a.queue, "Torch", a.inventory, bag, nil, 0)
		local early = CraftingLogic.collect(b, c.queue, c.inventory, bag, 4)
		t.equal(#early.completed, 0)
		local mid = CraftingLogic.collect(b, c.queue, c.inventory, bag, 5)
		t.equal(#mid.completed, 1)
		t.deepEqual(mid.inventory, { Torch = 2 })
		t.equal(#mid.queue.jobs, 1)
		local done = CraftingLogic.collect(b, mid.queue, mid.inventory, bag, 10)
		t.equal(#done.completed, 1)
		t.deepEqual(done.inventory, { Torch = 4 })
		t.equal(#done.queue.jobs, 0)
		t.falsy(done.blocked)
	end,

	["collect blocks when outputs do not fit"] = function()
		local registry = InventoryLogic.newRegistry({ { id = "Plank", maxStack = 10 }, { id = "Torch", maxStack = 1 } })
		local ops = CraftingLogic.inventoryOps(registry)
		local inventory = InventoryLogic.add(InventoryLogic.new(1), registry, "Plank", 1)
		local queued = CraftingLogic.enqueue(book(), CraftingLogic.newQueue(), "Torch", inventory, ops, nil, 0)
		t.truthy(queued.ok)
		local result = CraftingLogic.collect(book(), queued.queue, queued.inventory, ops, 100)
		t.truthy(result.blocked)
		t.equal(#result.completed, 0)
		t.equal(#result.queue.jobs, 1)
	end,

	["cancel refunds inputs and moves later jobs up"] = function()
		local b = book()
		local a = CraftingLogic.enqueue(b, CraftingLogic.newQueue(), "Torch", { Plank = 3 }, bag, nil, 0)
		local c = CraftingLogic.enqueue(b, a.queue, "Torch", a.inventory, bag, nil, 0)
		local d = CraftingLogic.enqueue(b, c.queue, "Torch", c.inventory, bag, nil, 0)
		t.deepEqual(d.inventory, {})
		local firstJob = a.job
		assert(firstJob, "missing job")
		local cancelled = CraftingLogic.cancel(b, d.queue, firstJob.id, d.inventory, bag, 2)
		t.truthy(cancelled.ok)
		t.deepEqual(cancelled.inventory, { Plank = 1 })
		t.equal(#cancelled.queue.jobs, 2)
		t.equal(cancelled.queue.jobs[1].startAt, 2)
		t.equal(cancelled.queue.jobs[1].finishAt, 7)
		t.equal(cancelled.queue.jobs[2].startAt, 7)
		t.equal(d.queue.jobs[2].startAt, 5)
		t.equal(CraftingLogic.cancel(b, d.queue, 999, d.inventory, bag, 2).reason, "no such job")
	end,

	["progress runs from 0 to 1"] = function()
		local job: CraftingLogic.Job = { id = 1, recipeId = "Torch", startAt = 10, finishAt = 20, duration = 10 }
		t.equal(CraftingLogic.progress(job, 5), 0)
		t.equal(CraftingLogic.progress(job, 15), 0.5)
		t.equal(CraftingLogic.progress(job, 25), 1)
		local instant: CraftingLogic.Job = { id = 2, recipeId = "Planks", startAt = 10, finishAt = 10, duration = 0 }
		t.equal(CraftingLogic.progress(instant, 9), 0)
		t.equal(CraftingLogic.progress(instant, 10), 1)
	end,

	["queues serialize and deserialize safely"] = function()
		local b = book()
		local a = CraftingLogic.enqueue(b, CraftingLogic.newQueue(), "Torch", { Plank = 2 }, bag, nil, 50)
		local c = CraftingLogic.enqueue(b, a.queue, "Torch", a.inventory, bag, nil, 50)
		local saved = CraftingLogic.serializeQueue(c.queue)
		t.equal(saved.n, 3)
		local restored = CraftingLogic.deserializeQueue(b, saved)
		t.equal(#restored.jobs, 2)
		t.equal(restored.jobs[2].finishAt, 60)
		t.equal(restored.jobs[2].duration, 5)
		t.equal(restored.nextId, 3)
		local raw: any = {
			n = "x",
			jobs = {
				{ id = 4, r = "Torch", s = 10, f = 15 },
				{ id = 5, r = "Ghost", s = 0, f = 1 },
				{ id = 6, r = "Torch", s = 20, f = 10 },
				{ id = 1.5, r = "Torch", s = 0, f = 1 },
				"bad",
			},
		}
		local cleaned = CraftingLogic.deserializeQueue(b, raw)
		t.equal(#cleaned.jobs, 1)
		t.equal(cleaned.nextId, 5)
		t.equal(#CraftingLogic.deserializeQueue(b, nil).jobs, 0)
	end,
}
