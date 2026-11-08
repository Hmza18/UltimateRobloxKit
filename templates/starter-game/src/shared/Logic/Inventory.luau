--!strict
-- Slot-based inventory with stacking and a slot capacity. Pure Luau.
-- Every function returns new tables and never modifies its input, so callers can compare before and after.

export type Stack = { id: string, count: number }
export type Inventory = { capacity: number, maxStack: number, slots: { Stack } }

local Inventory = {}

local function isCount(value: any): boolean
	return type(value) == "number" and value == value and value >= 1 and value % 1 == 0 and value ~= math.huge
end

local function copy(inventory: Inventory): Inventory
	local slots: { Stack } = {}
	for index, stack in inventory.slots do
		slots[index] = { id = stack.id, count = stack.count }
	end
	return { capacity = inventory.capacity, maxStack = inventory.maxStack, slots = slots }
end

-- `capacity` is the number of slots and `maxStack` the most items one slot holds.
function Inventory.new(capacity: number, maxStack: number): Inventory
	assert(isCount(capacity), "capacity must be a positive integer")
	assert(isCount(maxStack), "maxStack must be a positive integer")
	return { capacity = capacity, maxStack = maxStack, slots = {} }
end

function Inventory.count(inventory: Inventory, id: string): number
	local total = 0
	for _, stack in inventory.slots do
		if stack.id == id then
			total += stack.count
		end
	end
	return total
end

function Inventory.usedSlots(inventory: Inventory): number
	return #inventory.slots
end

-- How many more of `id` fit, counting free slots and room left in existing stacks.
function Inventory.spaceFor(inventory: Inventory, id: string): number
	local space = (inventory.capacity - #inventory.slots) * inventory.maxStack
	for _, stack in inventory.slots do
		if stack.id == id then
			space += inventory.maxStack - stack.count
		end
	end
	return math.max(space, 0)
end

function Inventory.canAdd(inventory: Inventory, id: string, amount: number): boolean
	return isCount(amount) and Inventory.spaceFor(inventory, id) >= amount
end

-- Adds up to `amount`, filling existing stacks before opening new slots.
-- Returns the new inventory and how many items did not fit (0 when everything fit).
function Inventory.add(inventory: Inventory, id: string, amount: number): (Inventory, number)
	assert(isCount(amount), "amount must be a positive integer")
	local result = copy(inventory)
	local remaining = amount
	for _, stack in result.slots do
		if remaining == 0 then
			break
		end
		if stack.id == id and stack.count < result.maxStack then
			local moved = math.min(result.maxStack - stack.count, remaining)
			stack.count += moved
			remaining -= moved
		end
	end
	while remaining > 0 and #result.slots < result.capacity do
		local moved = math.min(result.maxStack, remaining)
		table.insert(result.slots, { id = id, count = moved })
		remaining -= moved
	end
	return result, remaining
end

-- Removes exactly `amount`, taking from the last stacks first. All or nothing:
-- returns nil and a reason when the amount is invalid or the inventory holds too few.
function Inventory.remove(inventory: Inventory, id: string, amount: number): (Inventory?, string?)
	if not isCount(amount) then
		return nil, "invalid amount"
	end
	if Inventory.count(inventory, id) < amount then
		return nil, "not enough items"
	end
	local result = copy(inventory)
	local remaining = amount
	for index = #result.slots, 1, -1 do
		local stack = result.slots[index]
		if stack.id == id then
			local taken = math.min(stack.count, remaining)
			stack.count -= taken
			remaining -= taken
			if stack.count == 0 then
				table.remove(result.slots, index)
			end
			if remaining == 0 then
				break
			end
		end
	end
	return result, nil
end

-- Merges partial stacks of the same item, keeping the order in which items first appear.
function Inventory.compact(inventory: Inventory): Inventory
	local totals: { [string]: number } = {}
	local order: { string } = {}
	for _, stack in inventory.slots do
		local current = totals[stack.id]
		if current == nil then
			table.insert(order, stack.id)
			current = 0
		end
		totals[stack.id] = current + stack.count
	end
	local result = Inventory.new(inventory.capacity, inventory.maxStack)
	for _, id in order do
		result = Inventory.add(result, id, totals[id])
	end
	return result
end

-- Rebuilds an inventory from untrusted saved data, dropping malformed stacks and anything that no longer fits.
function Inventory.sanitize(raw: any, capacity: number, maxStack: number): Inventory
	local result = Inventory.new(capacity, maxStack)
	if type(raw) ~= "table" or type(raw.slots) ~= "table" then
		return result
	end
	for _, stack in raw.slots do
		if type(stack) == "table" and type(stack.id) == "string" and isCount(stack.count) then
			result = Inventory.add(result, stack.id, math.min(stack.count, maxStack))
		end
	end
	return result
end

return Inventory
