--!strict
-- Inventory slot logic for drag-and-drop and grid selection. Pure Luau.
--
-- The UI never changes inventory state. resolveDrop turns a drag from one slot to another into an
-- Intent ("move", "swap", "merge" or "reject") that the game sends to the server, which validates
-- and applies it. applyIntent exists for previews and for servers that want the same rules.

export type Slot = {
	itemId: string?,
	count: number?,
	category: string?, -- the item's category, for example "Weapon"
	accepts: { string }?, -- categories this slot accepts; nil accepts everything
	locked: boolean?,
	maxStack: number?, -- per-item stack limit; falls back to options.maxStack
}

export type Intent = {
	kind: string, -- "move" | "swap" | "merge" | "reject"
	from: number,
	to: number,
	itemId: string?,
	amount: number?,
	reason: string?,
}

export type DropOptions = {
	maxStack: number?, -- default stack limit (default 99)
	allowSwap: boolean?, -- default true
	split: number?, -- move only this many (for a split-drag); nil moves the whole stack
}

local SlotLogic = {}

local function reject(from: number, to: number, reason: string): Intent
	return { kind = "reject", from = from, to = to, reason = reason }
end

local function accepts(slot: Slot, category: string?): boolean
	local list = slot.accepts
	if list == nil then
		return true
	end
	return category ~= nil and table.find(list, category) ~= nil
end

local function isEmpty(slot: Slot): boolean
	return slot.itemId == nil or (slot.count or 1) <= 0
end

function SlotLogic.resolveDrop(slots: { Slot }, from: number, to: number, options: DropOptions?): Intent
	local opts: DropOptions = options or {}
	local source = slots[from]
	local target = slots[to]
	if source == nil or target == nil then
		return reject(from, to, "out of range")
	end
	if from == to then
		return reject(from, to, "same slot")
	end
	if isEmpty(source) then
		return reject(from, to, "empty source")
	end
	if source.locked or target.locked then
		return reject(from, to, "locked")
	end
	if not accepts(target, source.category) then
		return reject(from, to, "not accepted")
	end
	local sourceCount = source.count or 1
	local amount = math.clamp(math.floor(opts.split or sourceCount), 1, sourceCount)

	if isEmpty(target) then
		return { kind = "move", from = from, to = to, itemId = source.itemId, amount = amount }
	end

	if target.itemId == source.itemId then
		local limit = target.maxStack or source.maxStack or opts.maxStack or 99
		local space = limit - (target.count or 1)
		if space <= 0 then
			return reject(from, to, "stack full")
		end
		return { kind = "merge", from = from, to = to, itemId = source.itemId, amount = math.min(space, amount) }
	end

	if opts.allowSwap == false then
		return reject(from, to, "occupied")
	end
	if amount < sourceCount then
		return reject(from, to, "cannot split onto another item")
	end
	if not accepts(source, target.category) then
		return reject(from, to, "swap not accepted")
	end
	return { kind = "swap", from = from, to = to, itemId = source.itemId, amount = sourceCount }
end

local function copySlot(slot: Slot): Slot
	return table.clone(slot)
end

-- Returns new slots with the intent applied (rejects return a copy unchanged). Slot settings
-- such as accepts, locked and maxStack stay with the slot; item fields move with the item.
function SlotLogic.applyIntent(slots: { Slot }, intent: Intent): { Slot }
	local result: { Slot } = {}
	for index, slot in slots do
		result[index] = copySlot(slot)
	end
	if intent.kind == "reject" then
		return result
	end
	local source = result[intent.from]
	local target = result[intent.to]
	if source == nil or target == nil then
		return result
	end
	local amount = intent.amount or (source.count or 1)
	local sourceCount = source.count or 1
	if intent.kind == "move" then
		target.itemId = source.itemId
		target.category = source.category
		target.count = amount
		if amount >= sourceCount then
			source.itemId = nil
			source.category = nil
			source.count = nil
		else
			source.count = sourceCount - amount
		end
	elseif intent.kind == "merge" then
		target.count = (target.count or 1) + amount
		if amount >= sourceCount then
			source.itemId = nil
			source.category = nil
			source.count = nil
		else
			source.count = sourceCount - amount
		end
	elseif intent.kind == "swap" then
		local itemId, category, count = target.itemId, target.category, target.count
		target.itemId, target.category, target.count = source.itemId, source.category, source.count
		source.itemId, source.category, source.count = itemId, category, count
	end
	return result
end

-- Moves a selection index around a grid of `columns`, clamped to 1..count. No wrap by default.
function SlotLogic.moveSelection(index: number, direction: string, columns: number, count: number, wrap: boolean?)
	if count <= 0 then
		return 0
	end
	local cols = math.max(1, math.floor(columns))
	local current = math.clamp(index, 1, count)
	local nextIndex = current
	if direction == "left" then
		nextIndex = current - 1
	elseif direction == "right" then
		nextIndex = current + 1
	elseif direction == "up" then
		nextIndex = current - cols
	elseif direction == "down" then
		nextIndex = current + cols
	end
	if nextIndex < 1 or nextIndex > count then
		if wrap then
			return ((nextIndex - 1) % count) + 1
		end
		return current
	end
	return nextIndex
end

export type Rect = { x: number, y: number, w: number, h: number }

-- Index of the slot whose rectangle contains `point`, or nil.
function SlotLogic.hitTest(point: { x: number, y: number }, rects: { Rect }): number?
	for index, rect in rects do
		local insideX = point.x >= rect.x and point.x < rect.x + rect.w
		local insideY = point.y >= rect.y and point.y < rect.y + rect.h
		if insideX and insideY then
			return index
		end
	end
	return nil
end

return SlotLogic
