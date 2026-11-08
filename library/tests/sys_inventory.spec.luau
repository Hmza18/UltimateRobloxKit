--!strict
local InventoryLogic = require("../src/Systems/Inventory/InventoryLogic")
local t = require("./lib/t")

local function registry()
	return InventoryLogic.newRegistry({
		{ id = "Apple", maxStack = 10, category = "food", tags = { "edible" } },
		{ id = "Sword", category = "weapon", tags = { "tool", "melee" } },
		{ id = "Wood", maxStack = 50, category = "material" },
	})
end

local function filled(capacity: number, hotbarSize: number?)
	local reg = registry()
	local inventory = InventoryLogic.new(capacity, hotbarSize)
	return reg, inventory
end

return {
	["registry applies defaults and indexes tags"] = function()
		local reg = registry()
		local sword = InventoryLogic.getDef(reg, "Sword")
		t.truthy(sword)
		if sword then
			t.equal(sword.maxStack, 1)
			t.equal(sword.category, "weapon")
		end
		t.truthy(InventoryLogic.hasTag(reg, "Sword", "melee"))
		t.falsy(InventoryLogic.hasTag(reg, "Apple", "melee"))
		t.falsy(InventoryLogic.hasTag(reg, "Missing", "melee"))
		t.equal(#reg.order, 3)
	end,

	["registry rejects duplicates and bad definitions"] = function()
		t.throws(function()
			InventoryLogic.newRegistry({ { id = "A" }, { id = "A" } })
		end)
		t.throws(function()
			InventoryLogic.newRegistry({ { id = "A", maxStack = 0 } })
		end)
		t.throws(function()
			InventoryLogic.newRegistry({ { id = "" } })
		end)
		local bad: any = { { id = "A", tags = { 5 } } }
		t.throws(function()
			InventoryLogic.newRegistry(bad)
		end)
	end,

	["new validates capacity and hotbar size"] = function()
		t.throws(function()
			InventoryLogic.new(0)
		end)
		t.throws(function()
			InventoryLogic.new(4, 5)
		end)
		t.throws(function()
			InventoryLogic.new(1.5)
		end)
		local inventory = InventoryLogic.new(4, 3)
		t.equal(InventoryLogic.hotbarSize(inventory), 3)
		t.equal(inventory.hotbar[3], 3)
		t.equal(InventoryLogic.freeSlots(inventory), 4)
	end,

	["add tops up stacks before using empty slots"] = function()
		local reg, inventory = filled(4)
		local first = InventoryLogic.add(inventory, reg, "Apple", 7)
		local second, leftover = InventoryLogic.add(first, reg, "Apple", 5)
		t.equal(leftover, 0)
		t.equal(InventoryLogic.usedSlots(second), 2)
		t.equal(second.slots[1].count, 10)
		t.equal(second.slots[2].count, 2)
		t.equal(InventoryLogic.count(second, "Apple"), 12)
	end,

	["add returns leftover at capacity and for unknown items"] = function()
		local reg, inventory = filled(2)
		local full, leftover = InventoryLogic.add(inventory, reg, "Apple", 25)
		t.equal(leftover, 5)
		t.equal(InventoryLogic.spaceFor(full, reg, "Apple"), 0)
		t.falsy(InventoryLogic.canAdd(full, reg, "Apple", 1))
		local _, unknownLeftover = InventoryLogic.add(inventory, reg, "Ghost", 3)
		t.equal(unknownLeftover, 3)
		t.equal(InventoryLogic.spaceFor(inventory, reg, "Ghost"), 0)
		t.throws(function()
			InventoryLogic.add(inventory, reg, "Apple", 0)
		end)
	end,

	["unstackable items take one slot each"] = function()
		local reg, inventory = filled(3)
		local result, leftover = InventoryLogic.add(inventory, reg, "Sword", 4)
		t.equal(leftover, 1)
		t.equal(InventoryLogic.usedSlots(result), 3)
	end,

	["functions never modify their input"] = function()
		local reg, inventory = filled(3, 2)
		local original = InventoryLogic.add(inventory, reg, "Wood", 30)
		InventoryLogic.add(original, reg, "Wood", 5)
		InventoryLogic.remove(original, "Wood", 10)
		InventoryLogic.move(original, reg, 1, 2, 5)
		InventoryLogic.selectHotbar(original, 1)
		t.equal(InventoryLogic.count(original, "Wood"), 30)
		t.equal(original.slots[2], nil)
		t.equal(original.selected, nil)
	end,

	["remove is all or nothing and takes from the last slots"] = function()
		local reg, inventory = filled(3)
		local stocked = InventoryLogic.add(inventory, reg, "Apple", 15)
		local failed, reason = InventoryLogic.remove(stocked, "Apple", 16)
		t.equal(failed, nil)
		t.equal(reason, "not enough items")
		local result = InventoryLogic.remove(stocked, "Apple", 5)
		t.truthy(result)
		if result then
			t.equal(result.slots[1].count, 10)
			t.equal(result.slots[2], nil)
		end
		t.equal(InventoryLogic.remove(stocked, "Apple", 0), nil)
		t.equal(InventoryLogic.remove(stocked, "Apple", math.sqrt(-1)), nil)
	end,

	["removeAt drops part or all of one slot"] = function()
		local reg, inventory = filled(3)
		local stocked = InventoryLogic.add(inventory, reg, "Wood", 20)
		local partial, stack = InventoryLogic.removeAt(stocked, 1, 5)
		t.truthy(partial)
		t.deepEqual(stack, { id = "Wood", count = 5 })
		if partial then
			t.equal(partial.slots[1].count, 15)
		end
		local whole, all = InventoryLogic.removeAt(stocked, 1)
		t.truthy(whole)
		t.deepEqual(all, { id = "Wood", count = 20 })
		local _, _, emptyReason = InventoryLogic.removeAt(stocked, 2)
		t.equal(emptyReason, "empty slot")
		local _, _, badReason = InventoryLogic.removeAt(stocked, 1, 21)
		t.equal(badReason, "invalid amount")
		local _, _, slotReason = InventoryLogic.removeAt(stocked, 9)
		t.equal(slotReason, "invalid slot")
	end,

	["move to an empty slot moves or splits"] = function()
		local reg, inventory = filled(4)
		local stocked = InventoryLogic.add(inventory, reg, "Wood", 20)
		local moved = InventoryLogic.move(stocked, reg, 1, 4)
		t.truthy(moved)
		if moved then
			t.equal(moved.slots[1], nil)
			t.equal(moved.slots[4].count, 20)
		end
		local split = InventoryLogic.move(stocked, reg, 1, 3, 8)
		t.truthy(split)
		if split then
			t.equal(split.slots[1].count, 12)
			t.equal(split.slots[3].count, 8)
		end
	end,

	["move merges same items up to maxStack"] = function()
		local reg, inventory = filled(4)
		local stocked = InventoryLogic.add(inventory, reg, "Apple", 10)
		local split = InventoryLogic.move(stocked, reg, 1, 2, 4)
		t.truthy(split)
		if split then
			local merged = InventoryLogic.move(split, reg, 2, 1)
			t.truthy(merged)
			if merged then
				t.equal(merged.slots[1].count, 10)
				t.equal(merged.slots[2], nil)
			end
			local topped = InventoryLogic.move(split, reg, 1, 2, 3)
			t.truthy(topped)
			if topped then
				t.equal(topped.slots[1].count, 3)
				t.equal(topped.slots[2].count, 7)
			end
		end
		local full = InventoryLogic.add(stocked, reg, "Apple", 10)
		local _, reason = InventoryLogic.move(full, reg, 1, 2)
		t.equal(reason, "stack full")
	end,

	["move swaps different items and rejects bad input"] = function()
		local reg, inventory = filled(4)
		local a = InventoryLogic.add(inventory, reg, "Apple", 5)
		local b = InventoryLogic.add(a, reg, "Sword", 1)
		local swapped = InventoryLogic.move(b, reg, 1, 2)
		t.truthy(swapped)
		if swapped then
			t.equal(swapped.slots[1].id, "Sword")
			t.equal(swapped.slots[2].id, "Apple")
		end
		local _, splitReason = InventoryLogic.move(b, reg, 1, 2, 2)
		t.equal(splitReason, "cannot split onto another item")
		t.equal(select(2, InventoryLogic.move(b, reg, 1, 1)), "same slot")
		t.equal(select(2, InventoryLogic.move(b, reg, 3, 1)), "empty slot")
		t.equal(select(2, InventoryLogic.move(b, reg, 0, 1)), "invalid slot")
		t.equal(select(2, InventoryLogic.move(b, reg, 1, 5)), "invalid slot")
		t.equal(select(2, InventoryLogic.move(b, reg, 1, 3, 6)), "invalid amount")
	end,

	["hotbar selection and stacks"] = function()
		local reg, inventory = filled(6, 3)
		local stocked = InventoryLogic.add(inventory, reg, "Sword", 1)
		local selected = InventoryLogic.selectHotbar(stocked, 1)
		t.truthy(selected)
		if selected then
			t.equal(selected.selected, 1)
			local stack = InventoryLogic.selectedStack(selected)
			t.truthy(stack)
			if stack then
				t.equal(stack.id, "Sword")
			end
			local cleared = InventoryLogic.selectHotbar(selected, nil)
			t.truthy(cleared)
			if cleared then
				t.equal(cleared.selected, nil)
				t.equal(InventoryLogic.selectedStack(cleared), nil)
			end
		end
		t.equal(select(2, InventoryLogic.selectHotbar(stocked, 4)), "invalid hotbar position")
		t.equal(select(2, InventoryLogic.selectHotbar(stocked, 0)), "invalid hotbar position")
		t.equal(InventoryLogic.hotbarStack(stocked, 2), nil)
	end,

	["assignHotbar keeps slots unique and swapHotbar follows the selection"] = function()
		local _, inventory = filled(6, 3)
		local assigned = InventoryLogic.assignHotbar(inventory, 1, 3)
		t.truthy(assigned)
		if assigned then
			t.equal(assigned.hotbar[1], 3)
			t.equal(assigned.hotbar[3], 1)
		end
		local selected = InventoryLogic.selectHotbar(inventory, 2)
		t.truthy(selected)
		if selected then
			local swapped = InventoryLogic.swapHotbar(selected, 2, 3)
			t.truthy(swapped)
			if swapped then
				t.equal(swapped.hotbar[2], 3)
				t.equal(swapped.hotbar[3], 2)
				t.equal(swapped.selected, 3)
			end
		end
		t.equal(select(2, InventoryLogic.assignHotbar(inventory, 1, 7)), "invalid slot")
		t.equal(select(2, InventoryLogic.assignHotbar(inventory, 4, 1)), "invalid hotbar position")
		t.equal(select(2, InventoryLogic.swapHotbar(inventory, 1, 9)), "invalid hotbar position")
	end,

	["list filters by category, tag and id"] = function()
		local reg, inventory = filled(6)
		local a = InventoryLogic.add(inventory, reg, "Apple", 3)
		local b = InventoryLogic.add(a, reg, "Sword", 1)
		local c = InventoryLogic.add(b, reg, "Wood", 9)
		t.equal(#InventoryLogic.list(c, reg), 3)
		local food = InventoryLogic.list(c, reg, { category = "food" })
		t.equal(#food, 1)
		t.equal(food[1].id, "Apple")
		local tools = InventoryLogic.list(c, reg, { tag = "tool" })
		t.equal(#tools, 1)
		t.equal(tools[1].index, 2)
		t.equal(#InventoryLogic.list(c, reg, { id = "Wood", category = "food" }), 0)
	end,

	["sort compacts and orders stacks"] = function()
		local reg = registry()
		local inventory: InventoryLogic.Inventory = {
			capacity = 6,
			slots = {
				[2] = { id = "Wood", count = 5 },
				[3] = { id = "Apple", count = 4 },
				[5] = { id = "Wood", count = 7 },
				[6] = { id = "Apple", count = 3 },
			},
			hotbar = {},
			selected = nil,
		}
		local byCategory = InventoryLogic.sort(inventory, reg)
		t.equal(byCategory.slots[1].id, "Apple")
		t.equal(byCategory.slots[1].count, 7)
		t.equal(byCategory.slots[2].id, "Wood")
		t.equal(byCategory.slots[2].count, 12)
		t.equal(InventoryLogic.usedSlots(byCategory), 2)
		local byCount = InventoryLogic.sort(inventory, reg, "count")
		t.equal(byCount.slots[1].id, "Wood")
		local unknown: InventoryLogic.Inventory = {
			capacity = 3,
			slots = { [1] = { id = "Ghost", count = 2 }, [3] = { id = "Apple", count = 1 } },
			hotbar = {},
			selected = nil,
		}
		local kept = InventoryLogic.sort(unknown, reg, "id")
		t.equal(kept.slots[1].id, "Apple")
		t.equal(kept.slots[2].id, "Ghost")
	end,

	["serialize and deserialize round-trip"] = function()
		local reg, inventory = filled(5, 2)
		local stocked = InventoryLogic.add(inventory, reg, "Wood", 60)
		local assigned = InventoryLogic.assignHotbar(stocked, 2, 5)
		assert(assigned, "assign failed")
		local selected = InventoryLogic.selectHotbar(assigned, 2)
		assert(selected, "select failed")
		local saved = InventoryLogic.serialize(selected)
		t.equal(saved.v, InventoryLogic.SAVE_VERSION)
		t.equal(#saved.slots, 2)
		local restored = InventoryLogic.deserialize(saved, reg, 5, 2)
		t.equal(InventoryLogic.count(restored, "Wood"), 60)
		t.equal(restored.hotbar[2], 5)
		t.equal(restored.selected, 2)
		t.deepEqual(InventoryLogic.view(restored), saved)
	end,

	["deserialize sanitizes untrusted data"] = function()
		local reg = registry()
		local raw: any = {
			slots = {
				{ i = 1, id = "Apple", n = 99 },
				{ i = 1, id = "Wood", n = 5 },
				{ i = 2, id = "Ghost", n = 1 },
				{ i = 9, id = "Wood", n = 1 },
				{ i = 3, id = "Wood", n = -2 },
				{ i = 4, id = 7, n = 1 },
				"garbage",
			},
			hotbar = { 99, 2 },
			sel = 5,
		}
		local inventory = InventoryLogic.deserialize(raw, reg, 4, 2)
		t.equal(InventoryLogic.usedSlots(inventory), 1)
		t.equal(inventory.slots[1].count, 10)
		t.equal(inventory.hotbar[1], 1)
		t.equal(inventory.hotbar[2], 2)
		t.equal(inventory.selected, nil)
		t.equal(InventoryLogic.usedSlots(InventoryLogic.deserialize(nil, reg, 4)), 0)
		t.equal(InventoryLogic.usedSlots(InventoryLogic.deserialize("x", reg, 4)), 0)
	end,
}
