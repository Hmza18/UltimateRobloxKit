--!strict
-- Slot inventory with an item registry, stacking, a slot capacity and a hotbar. Pure Luau.
-- Every function returns new tables and never modifies its inputs, so a caller can try an
-- operation and commit the result only when the rest of a transaction also succeeds.

export type ItemDefInput = {
	id: string, -- unique item id
	maxStack: number?, -- most items one slot holds (default 1)
	category: string?, -- free-form group used by filters and sorting (default "misc")
	tags: { string }?, -- free-form labels such as "tool" or "food"
}

export type ItemDef = {
	id: string, -- unique item id
	maxStack: number, -- most items one slot holds
	category: string, -- group used by filters and sorting
	tags: { string }, -- labels in the order they were declared
	tagSet: { [string]: boolean }, -- the same labels as a set for fast checks
}

export type Registry = { items: { [string]: ItemDef }, order: { string } }

export type Stack = { id: string, count: number }

export type Inventory = {
	capacity: number, -- number of slots, indexed 1..capacity
	slots: { [number]: Stack }, -- sparse: an empty slot has no entry
	hotbar: { number }, -- hotbar position -> inventory slot index
	selected: number?, -- selected hotbar position, or nil when nothing is selected
}

export type Filter = { category: string?, tag: string?, id: string? }

export type Entry = { index: number, id: string, count: number, category: string }

export type SortKey = "category" | "id" | "count"

export type SavedStack = { i: number, id: string, n: number }

export type Saved = { v: number, slots: { SavedStack }, hotbar: { number }, sel: number? }

local InventoryLogic = {}

InventoryLogic.SAVE_VERSION = 1
InventoryLogic.MAX_CAPACITY = 1000
InventoryLogic.DEFAULT_CATEGORY = "misc"

local function isCount(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value >= 1 and value % 1 == 0
end

local function isIndex(inventory: Inventory, index: any): boolean
	return isCount(index) and index <= inventory.capacity
end

local function copy(inventory: Inventory): Inventory
	local slots: { [number]: Stack } = {}
	for index, stack in inventory.slots do
		slots[index] = { id = stack.id, count = stack.count }
	end
	return {
		capacity = inventory.capacity,
		slots = slots,
		hotbar = table.clone(inventory.hotbar),
		selected = inventory.selected,
	}
end

-- Builds the item registry. Raises an error for duplicate ids or invalid definitions,
-- because a broken registry is a programming mistake, not a runtime condition.
function InventoryLogic.newRegistry(defs: { ItemDefInput }): Registry
	assert(type(defs) == "table", "defs must be an array")
	local items: { [string]: ItemDef } = {}
	local order: { string } = {}
	for _, input in defs do
		assert(type(input) == "table", "each definition must be a table")
		local id = input.id
		assert(type(id) == "string" and id ~= "", "item id must be a non-empty string")
		assert(items[id] == nil, "duplicate item id " .. id)
		local maxStack = input.maxStack or 1
		assert(isCount(maxStack), "maxStack must be a positive integer for " .. id)
		local category = input.category or InventoryLogic.DEFAULT_CATEGORY
		assert(type(category) == "string", "category must be a string for " .. id)
		local tags: { string } = {}
		local tagSet: { [string]: boolean } = {}
		for _, tag in ipairs(input.tags or {}) do
			assert(type(tag) == "string", "tags must be strings for " .. id)
			table.insert(tags, tag)
			tagSet[tag] = true
		end
		items[id] = { id = id, maxStack = maxStack, category = category, tags = tags, tagSet = tagSet }
		table.insert(order, id)
	end
	return { items = items, order = order }
end

function InventoryLogic.getDef(registry: Registry, id: string): ItemDef?
	return registry.items[id]
end

function InventoryLogic.hasTag(registry: Registry, id: string, tag: string): boolean
	local def = registry.items[id]
	return def ~= nil and def.tagSet[tag] == true
end

-- `capacity` is the number of slots. The hotbar starts mapped to slots 1..hotbarSize.
function InventoryLogic.new(capacity: number, hotbarSize: number?): Inventory
	assert(isCount(capacity) and capacity <= InventoryLogic.MAX_CAPACITY, "capacity must be an integer in 1..1000")
	local size = hotbarSize or 0
	local validSize = size == 0 or isCount(size) and size <= capacity
	assert(validSize, "hotbarSize must be an integer in 0..capacity")
	local hotbar: { number } = {}
	for position = 1, size do
		hotbar[position] = position
	end
	return { capacity = capacity, slots = {}, hotbar = hotbar, selected = nil }
end

function InventoryLogic.slot(inventory: Inventory, index: number): Stack?
	return inventory.slots[index]
end

function InventoryLogic.count(inventory: Inventory, id: string): number
	local total = 0
	for _, stack in inventory.slots do
		if stack.id == id then
			total += stack.count
		end
	end
	return total
end

function InventoryLogic.usedSlots(inventory: Inventory): number
	local used = 0
	for _ in inventory.slots do
		used += 1
	end
	return used
end

function InventoryLogic.freeSlots(inventory: Inventory): number
	return inventory.capacity - InventoryLogic.usedSlots(inventory)
end

-- How many more of `id` fit, counting free slots and room left in existing stacks.
-- Unknown items never fit.
function InventoryLogic.spaceFor(inventory: Inventory, registry: Registry, id: string): number
	local def = registry.items[id]
	if def == nil then
		return 0
	end
	local space = InventoryLogic.freeSlots(inventory) * def.maxStack
	for _, stack in inventory.slots do
		if stack.id == id then
			space += math.max(def.maxStack - stack.count, 0)
		end
	end
	return space
end

function InventoryLogic.canAdd(inventory: Inventory, registry: Registry, id: string, amount: number): boolean
	return isCount(amount) and InventoryLogic.spaceFor(inventory, registry, id) >= amount
end

-- Adds up to `amount`, topping up existing stacks in slot order before using empty slots.
-- Returns the new inventory and how many items did not fit (all of them for an unknown id).
function InventoryLogic.add(inventory: Inventory, registry: Registry, id: string, amount: number): (Inventory, number)
	assert(isCount(amount), "amount must be a positive integer")
	local result = copy(inventory)
	local def = registry.items[id]
	if def == nil then
		return result, amount
	end
	local maxStack = def.maxStack
	local remaining = amount
	for index = 1, result.capacity do
		local stack = result.slots[index]
		if remaining > 0 and stack ~= nil and stack.id == id and stack.count < maxStack then
			local moved = math.min(maxStack - stack.count, remaining)
			stack.count += moved
			remaining -= moved
		end
	end
	for index = 1, result.capacity do
		if remaining <= 0 then
			break
		end
		if result.slots[index] == nil then
			local moved = math.min(maxStack, remaining)
			result.slots[index] = { id = id, count = moved }
			remaining -= moved
		end
	end
	return result, remaining
end

-- Removes exactly `amount`, taking from the highest slots first. All or nothing:
-- returns nil and a reason when the amount is invalid or there are too few items.
function InventoryLogic.remove(inventory: Inventory, id: string, amount: number): (Inventory?, string?)
	if not isCount(amount) then
		return nil, "invalid amount"
	end
	if InventoryLogic.count(inventory, id) < amount then
		return nil, "not enough items"
	end
	local result = copy(inventory)
	local remaining = amount
	for index = result.capacity, 1, -1 do
		local stack = result.slots[index]
		if remaining > 0 and stack ~= nil and stack.id == id then
			local taken = math.min(stack.count, remaining)
			stack.count -= taken
			remaining -= taken
			if stack.count == 0 then
				result.slots[index] = nil
			end
		end
	end
	return result, nil
end

-- Removes `amount` (default: the whole stack) from one slot, for drops and uses.
-- Returns the new inventory and the removed stack, or nil and a reason.
function InventoryLogic.removeAt(inventory: Inventory, index: number, amount: number?): (Inventory?, Stack?, string?)
	if not isIndex(inventory, index) then
		return nil, nil, "invalid slot"
	end
	local existing = inventory.slots[index]
	if existing == nil then
		return nil, nil, "empty slot"
	end
	local taken = amount or existing.count
	if not isCount(taken) or taken > existing.count then
		return nil, nil, "invalid amount"
	end
	local result = copy(inventory)
	if taken == existing.count then
		result.slots[index] = nil
	else
		result.slots[index] = { id = existing.id, count = existing.count - taken }
	end
	return result, { id = existing.id, count = taken }, nil
end

-- Moves `amount` (default: the whole stack) from slot `from` to slot `to`.
-- Empty target: moves or splits. Same item: merges up to maxStack. Other item: swaps whole stacks.
function InventoryLogic.move(
	inventory: Inventory,
	registry: Registry,
	from: number,
	to: number,
	amount: number?
): (Inventory?, string?)
	if not isIndex(inventory, from) or not isIndex(inventory, to) then
		return nil, "invalid slot"
	end
	if from == to then
		return nil, "same slot"
	end
	local result = copy(inventory)
	local source = result.slots[from]
	if source == nil then
		return nil, "empty slot"
	end
	local moving = amount or source.count
	if not isCount(moving) or moving > source.count then
		return nil, "invalid amount"
	end
	local target = result.slots[to]
	if target == nil then
		if moving == source.count then
			result.slots[to] = source
			result.slots[from] = nil
		else
			result.slots[to] = { id = source.id, count = moving }
			source.count -= moving
		end
		return result, nil
	end
	if target.id == source.id then
		local def = registry.items[source.id]
		local maxStack = if def then def.maxStack else target.count
		local room = math.max(maxStack - target.count, 0)
		if room == 0 then
			return nil, "stack full"
		end
		local moved = math.min(room, moving)
		target.count += moved
		source.count -= moved
		if source.count == 0 then
			result.slots[from] = nil
		end
		return result, nil
	end
	if moving ~= source.count then
		return nil, "cannot split onto another item"
	end
	result.slots[from] = target
	result.slots[to] = source
	return result, nil
end

function InventoryLogic.hotbarSize(inventory: Inventory): number
	return #inventory.hotbar
end

function InventoryLogic.hotbarStack(inventory: Inventory, position: number): Stack?
	local index = inventory.hotbar[position]
	if index == nil then
		return nil
	end
	return inventory.slots[index]
end

-- Selects a hotbar position, or clears the selection when `position` is nil.
function InventoryLogic.selectHotbar(inventory: Inventory, position: number?): (Inventory?, string?)
	if position ~= nil and not (isCount(position) and position <= #inventory.hotbar) then
		return nil, "invalid hotbar position"
	end
	local result = copy(inventory)
	result.selected = position
	return result, nil
end

function InventoryLogic.selectedStack(inventory: Inventory): Stack?
	local position = inventory.selected
	if position == nil then
		return nil
	end
	return InventoryLogic.hotbarStack(inventory, position)
end

-- Points a hotbar position at an inventory slot. If another position already shows that slot,
-- the two positions swap targets so every slot appears on the hotbar at most once.
function InventoryLogic.assignHotbar(inventory: Inventory, position: number, index: number): (Inventory?, string?)
	if not (isCount(position) and position <= #inventory.hotbar) then
		return nil, "invalid hotbar position"
	end
	if not isIndex(inventory, index) then
		return nil, "invalid slot"
	end
	local result = copy(inventory)
	local previous = result.hotbar[position]
	for other, target in result.hotbar do
		if target == index and other ~= position then
			result.hotbar[other] = previous
		end
	end
	result.hotbar[position] = index
	return result, nil
end

function InventoryLogic.swapHotbar(inventory: Inventory, a: number, b: number): (Inventory?, string?)
	local size = #inventory.hotbar
	if not (isCount(a) and a <= size and isCount(b) and b <= size) then
		return nil, "invalid hotbar position"
	end
	local result = copy(inventory)
	result.hotbar[a], result.hotbar[b] = inventory.hotbar[b], inventory.hotbar[a]
	if inventory.selected == a then
		result.selected = b
	elseif inventory.selected == b then
		result.selected = a
	end
	return result, nil
end

-- Lists stacks in slot order. Every filter field that is set must match.
function InventoryLogic.list(inventory: Inventory, registry: Registry, filter: Filter?): { Entry }
	local entries: { Entry } = {}
	for index = 1, inventory.capacity do
		local stack = inventory.slots[index]
		if stack ~= nil then
			local def = registry.items[stack.id]
			local category = if def then def.category else InventoryLogic.DEFAULT_CATEGORY
			local keep = true
			if filter then
				local wantId, wantCategory, wantTag = filter.id, filter.category, filter.tag
				if wantId ~= nil and wantId ~= stack.id then
					keep = false
				end
				if wantCategory ~= nil and wantCategory ~= category then
					keep = false
				end
				if wantTag ~= nil and not (def ~= nil and def.tagSet[wantTag] == true) then
					keep = false
				end
			end
			if keep then
				table.insert(entries, { index = index, id = stack.id, count = stack.count, category = category })
			end
		end
	end
	return entries
end

-- Merges partial stacks and packs them into slots 1..n in the chosen order (default "category").
-- Items missing from the registry keep their stacks and go after the known ones.
-- The hotbar keeps pointing at slot indices, so what it shows can change after a sort.
function InventoryLogic.sort(inventory: Inventory, registry: Registry, by: SortKey?): Inventory
	local key: SortKey = by or "category"
	local totals: { [string]: number } = {}
	local ids: { string } = {}
	local unknown: { Stack } = {}
	for index = 1, inventory.capacity do
		local stack = inventory.slots[index]
		if stack ~= nil then
			if registry.items[stack.id] == nil then
				table.insert(unknown, { id = stack.id, count = stack.count })
			else
				if totals[stack.id] == nil then
					table.insert(ids, stack.id)
					totals[stack.id] = 0
				end
				totals[stack.id] += stack.count
			end
		end
	end
	table.sort(ids, function(a: string, b: string): boolean
		if key == "count" and totals[a] ~= totals[b] then
			return totals[a] > totals[b]
		end
		if key == "category" then
			local categoryA = registry.items[a].category
			local categoryB = registry.items[b].category
			if categoryA ~= categoryB then
				return categoryA < categoryB
			end
		end
		return a < b
	end)
	local result = copy(inventory)
	result.slots = {}
	local nextIndex = 1
	for _, id in ids do
		local remaining = totals[id]
		local maxStack = registry.items[id].maxStack
		while remaining > 0 do
			local placed = math.min(maxStack, remaining)
			result.slots[nextIndex] = { id = id, count = placed }
			nextIndex += 1
			remaining -= placed
		end
	end
	for _, stack in unknown do
		result.slots[nextIndex] = stack
		nextIndex += 1
	end
	return result
end

-- Plain data for a store or for replication: slots as { i, id, n } in slot order.
function InventoryLogic.serialize(inventory: Inventory): Saved
	local slots: { SavedStack } = {}
	for index = 1, inventory.capacity do
		local stack = inventory.slots[index]
		if stack ~= nil then
			table.insert(slots, { i = index, id = stack.id, n = stack.count })
		end
	end
	return {
		v = InventoryLogic.SAVE_VERSION,
		slots = slots,
		hotbar = table.clone(inventory.hotbar),
		sel = inventory.selected,
	}
end

-- The compact view sent to the owning client. Same shape as serialize.
function InventoryLogic.view(inventory: Inventory): Saved
	return InventoryLogic.serialize(inventory)
end

-- Rebuilds an inventory from untrusted saved data. Drops unknown items, malformed entries,
-- out-of-range or duplicate slots, and clamps counts to the item's maxStack.
function InventoryLogic.deserialize(raw: any, registry: Registry, capacity: number, hotbarSize: number?): Inventory
	local result = InventoryLogic.new(capacity, hotbarSize)
	if type(raw) ~= "table" then
		return result
	end
	if type(raw.slots) == "table" then
		for _, entry in raw.slots do
			if type(entry) == "table" and isIndex(result, entry.i) and result.slots[entry.i] == nil then
				local def = if type(entry.id) == "string" then registry.items[entry.id] else nil
				if def ~= nil and isCount(entry.n) then
					result.slots[entry.i] = { id = def.id, count = math.min(entry.n, def.maxStack) }
				end
			end
		end
	end
	if type(raw.hotbar) == "table" then
		for position = 1, #result.hotbar do
			local index = raw.hotbar[position]
			if isIndex(result, index) then
				result.hotbar[position] = index
			end
		end
	end
	if isCount(raw.sel) and raw.sel <= #result.hotbar then
		result.selected = raw.sel
	end
	return result
end

return InventoryLogic
