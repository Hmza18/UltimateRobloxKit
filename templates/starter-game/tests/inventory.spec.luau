--!strict
local Inventory = require("../src/shared/Logic/Inventory")
local t = require("./lib/t")

return {
	["a new inventory is empty"] = function()
		local inventory = Inventory.new(4, 10)
		t.equal(Inventory.usedSlots(inventory), 0)
		t.equal(Inventory.count(inventory, "Apple"), 0)
		t.equal(Inventory.spaceFor(inventory, "Apple"), 40)
	end,

	["add fills existing stacks before opening slots"] = function()
		local inventory = Inventory.add(Inventory.new(4, 10), "Apple", 7)
		local nextInventory, leftover = Inventory.add(inventory, "Apple", 5)
		t.equal(leftover, 0)
		t.equal(Inventory.usedSlots(nextInventory), 2)
		t.equal(nextInventory.slots[1].count, 10)
		t.equal(nextInventory.slots[2].count, 2)
	end,

	["add returns the leftover when capacity is reached"] = function()
		local inventory, leftover = Inventory.add(Inventory.new(2, 10), "Gem", 25)
		t.equal(leftover, 5)
		t.equal(Inventory.count(inventory, "Gem"), 20)
		t.falsy(Inventory.canAdd(inventory, "Gem", 1))
	end,

	["add and remove never modify their input"] = function()
		local original = Inventory.add(Inventory.new(2, 10), "Wood", 3)
		Inventory.add(original, "Wood", 4)
		Inventory.remove(original, "Wood", 2)
		t.equal(Inventory.count(original, "Wood"), 3)
	end,

	["remove is all or nothing"] = function()
		local inventory = Inventory.add(Inventory.new(3, 10), "Apple", 12)
		local result, reason = Inventory.remove(inventory, "Apple", 13)
		t.equal(result, nil)
		t.equal(reason, "not enough items")
		local removed = Inventory.remove(inventory, "Apple", 12)
		t.truthy(removed)
		if removed then
			t.equal(Inventory.usedSlots(removed), 0)
		end
	end,

	["remove rejects invalid amounts"] = function()
		local inventory = Inventory.add(Inventory.new(3, 10), "Apple", 5)
		t.equal(Inventory.remove(inventory, "Apple", 0), nil)
		t.equal(Inventory.remove(inventory, "Apple", 1.5), nil)
		t.equal(Inventory.remove(inventory, "Apple", math.sqrt(-1)), nil)
	end,

	["compact merges partial stacks"] = function()
		local inventory: Inventory.Inventory = {
			capacity = 4,
			maxStack = 10,
			slots = { { id = "Apple", count = 4 }, { id = "Gem", count = 1 }, { id = "Apple", count = 3 } },
		}
		local compacted = Inventory.compact(inventory)
		t.equal(Inventory.usedSlots(compacted), 2)
		t.equal(compacted.slots[1].id, "Apple")
		t.equal(compacted.slots[1].count, 7)
	end,

	["sanitize drops malformed saved stacks"] = function()
		local raw: any = {
			slots = { { id = "Apple", count = 2 }, { id = 5, count = 1 }, { id = "Gem", count = -3 }, "bad" },
		}
		local inventory = Inventory.sanitize(raw, 4, 10)
		t.equal(Inventory.usedSlots(inventory), 1)
		t.equal(Inventory.count(inventory, "Apple"), 2)
		t.equal(Inventory.usedSlots(Inventory.sanitize(nil, 4, 10)), 0)
	end,

	["invalid add amounts raise errors"] = function()
		t.throws(function()
			Inventory.add(Inventory.new(1, 1), "Apple", 0)
		end)
	end,
}
