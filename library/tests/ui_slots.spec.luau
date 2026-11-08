--!strict
-- SlotLogic: drag-and-drop intents between inventory slots, previews and grid selection.

local t = require("./lib/t")
local SlotLogic = require("../src/UI/Core/SlotLogic")

local function slots(): { SlotLogic.Slot }
	return {
		{ itemId = "sword", count = 1, category = "Weapon" },
		{},
		{ itemId = "apple", count = 5, category = "Food", maxStack = 10 },
		{ itemId = "apple", count = 8, category = "Food", maxStack = 10 },
		{ accepts = { "Weapon" } },
		{ itemId = "potion", count = 2, category = "Food", locked = true },
		{ itemId = "apple", count = 10, category = "Food", maxStack = 10 },
	}
end

return {
	["dropping on an empty slot moves the stack"] = function()
		local intent = SlotLogic.resolveDrop(slots(), 1, 2)
		t.deepEqual(intent, { kind = "move", from = 1, to = 2, itemId = "sword", amount = 1 })
	end,

	["dropping on the same item merges up to the stack limit"] = function()
		local intent = SlotLogic.resolveDrop(slots(), 3, 4)
		t.equal(intent.kind, "merge")
		t.equal(intent.amount, 2, "only two fit")
		t.equal(SlotLogic.resolveDrop(slots(), 4, 3).amount, 5)
		t.equal(SlotLogic.resolveDrop(slots(), 3, 7).reason, "stack full")
	end,

	["dropping on a different item swaps"] = function()
		local intent = SlotLogic.resolveDrop(slots(), 1, 3)
		t.equal(intent.kind, "swap")
		t.equal(SlotLogic.resolveDrop(slots(), 1, 3, { allowSwap = false }).reason, "occupied")
	end,

	["category filters apply both ways"] = function()
		t.equal(SlotLogic.resolveDrop(slots(), 3, 5).reason, "not accepted")
		t.equal(SlotLogic.resolveDrop(slots(), 1, 5).kind, "move")
		local custom = slots()
		custom[5] = { accepts = { "Weapon" }, itemId = "axe", count = 1, category = "Weapon" }
		t.equal(SlotLogic.resolveDrop(custom, 3, 5).reason, "not accepted")
		custom[1] = { accepts = { "Weapon" }, itemId = "sword", count = 1, category = "Weapon" }
		custom[3] = { itemId = "apple", count = 1, category = "Food" }
		t.equal(SlotLogic.resolveDrop(custom, 3, 1).reason, "not accepted", "the dragged item must fit the target")
	end,

	["invalid drops are rejected with a reason"] = function()
		t.equal(SlotLogic.resolveDrop(slots(), 6, 2).reason, "locked")
		t.equal(SlotLogic.resolveDrop(slots(), 2, 1).reason, "empty source")
		t.equal(SlotLogic.resolveDrop(slots(), 1, 1).reason, "same slot")
		t.equal(SlotLogic.resolveDrop(slots(), 1, 99).reason, "out of range")
		t.equal(SlotLogic.resolveDrop(slots(), 1, 99).kind, "reject")
	end,

	["split drags move part of a stack"] = function()
		local intent = SlotLogic.resolveDrop(slots(), 3, 2, { split = 2 })
		t.equal(intent.kind, "move")
		t.equal(intent.amount, 2)
		local preview = SlotLogic.applyIntent(slots(), intent)
		t.equal(preview[2].count, 2)
		t.equal(preview[3].count, 3)
		t.equal(SlotLogic.resolveDrop(slots(), 3, 1, { split = 2 }).reason, "cannot split onto another item")
	end,

	["applyIntent previews without mutating the input"] = function()
		local original = slots()
		local swapped = SlotLogic.applyIntent(original, SlotLogic.resolveDrop(original, 1, 3))
		t.equal(swapped[1].itemId, "apple")
		t.equal(swapped[1].count, 5)
		t.equal(swapped[3].itemId, "sword")
		t.equal(swapped[3].maxStack, 10, "slot settings stay with the slot")
		t.equal(original[1].itemId, "sword", "input untouched")
		local merged = SlotLogic.applyIntent(original, SlotLogic.resolveDrop(original, 3, 4))
		t.equal(merged[4].count, 10)
		t.equal(merged[3].count, 3)
		local moved = SlotLogic.applyIntent(original, SlotLogic.resolveDrop(original, 1, 2))
		t.equal(moved[1].itemId, nil)
		t.equal(moved[2].itemId, "sword")
		local rejected = SlotLogic.applyIntent(original, SlotLogic.resolveDrop(original, 6, 2))
		t.equal(rejected[6].itemId, "potion")
	end,

	["moveSelection walks the grid and clamps or wraps"] = function()
		t.equal(SlotLogic.moveSelection(5, "right", 4, 10), 6)
		t.equal(SlotLogic.moveSelection(6, "up", 4, 10), 2)
		t.equal(SlotLogic.moveSelection(2, "up", 4, 10), 2, "top row stays")
		t.equal(SlotLogic.moveSelection(9, "down", 4, 10), 9, "no slot below")
		t.equal(SlotLogic.moveSelection(10, "right", 4, 10, true), 1, "wraps")
		t.equal(SlotLogic.moveSelection(1, "left", 4, 0), 0, "empty grid")
	end,

	["hitTest finds the slot under a point"] = function()
		local rects = { { x = 0, y = 0, w = 50, h = 50 }, { x = 60, y = 0, w = 50, h = 50 } }
		t.equal(SlotLogic.hitTest({ x = 70, y = 10 }, rects), 2)
		t.equal(SlotLogic.hitTest({ x = 55, y = 10 }, rects), nil, "the gap between slots")
		t.equal(SlotLogic.hitTest({ x = 50, y = 10 }, rects), nil, "right edge is exclusive")
	end,
}
