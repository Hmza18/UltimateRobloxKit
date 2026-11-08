--!strict
-- Equipment slots, equip rules and stat aggregation. Pure Luau and immutable: every call returns
-- a new loadout. Slot names, items, requirements and stats are all supplied by the game.

export type Requirements = {
	level: number?, -- minimum level
	tags: { string }?, -- the wearer needs every one of these tags (class, quest flags, ...)
}

export type Modifiers = {
	add: { [string]: number }?, -- flat bonuses, summed
	mul: { [string]: number }?, -- multipliers such as 1.1 for +10%
}

export type ItemInput = {
	id: string, -- unique item id
	slot: string?, -- the one slot this item fits
	slots: { string }?, -- or several slots it can fit (for example two ring slots)
	requirements: Requirements?, -- who may equip it
	stats: Modifiers?, -- what it changes
}

export type Item = {
	id: string, -- unique item id
	slots: { string }, -- slots it fits, in preference order
	level: number, -- minimum level (0 when none)
	tags: { string }, -- required tags
	add: { [string]: number }, -- flat bonuses
	mul: { [string]: number }, -- multipliers
}

export type Catalog = {
	slots: { string }, -- every slot name in display order
	slotSet: { [string]: boolean }, -- the same names as a set
	items: { [string]: Item }, -- id -> item
	stacking: "product" | "additive", -- how multipliers combine
}

export type Loadout = { equipped: { [string]: string } }

export type Context = { level: number?, tags: { [string]: boolean }? }

export type Saved = { v: number, e: { [string]: string } }

local EquipmentLogic = {}

EquipmentLogic.SAVE_VERSION = 1

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function copyNumbers(source: { [string]: number }?, label: string): { [string]: number }
	local result: { [string]: number } = {}
	for key, value in pairs(source or {}) do
		assert(type(key) == "string" and isFinite(value), "invalid " .. label .. " stat")
		result[key] = value
	end
	return result
end

-- `stacking` decides how multipliers combine: "product" multiplies them (1.1 * 1.2 = 1.32),
-- "additive" sums their bonuses (1 + 0.1 + 0.2 = 1.3).
function EquipmentLogic.newCatalog(
	slots: { string },
	items: { ItemInput },
	stacking: ("product" | "additive")?
): Catalog
	assert(type(slots) == "table" and #slots > 0, "slots must be a non-empty array")
	local slotSet: { [string]: boolean } = {}
	for _, slot in slots do
		assert(type(slot) == "string" and slot ~= "", "slot names must be non-empty strings")
		assert(not slotSet[slot], "duplicate slot " .. slot)
		slotSet[slot] = true
	end
	local mode: "product" | "additive" = stacking or "product"
	assert(mode == "product" or mode == "additive", "stacking must be product or additive")
	local catalog: Catalog = { slots = table.clone(slots), slotSet = slotSet, items = {}, stacking = mode }
	for _, input in items do
		local id = input.id
		assert(type(id) == "string" and id ~= "", "item id must be a non-empty string")
		assert(catalog.items[id] == nil, "duplicate item id " .. id)
		local fits: { string } = {}
		local single = input.slot
		if single ~= nil then
			table.insert(fits, single)
		end
		for _, slot in ipairs(input.slots or {}) do
			table.insert(fits, slot)
		end
		assert(#fits > 0, "item " .. id .. " needs a slot")
		for _, slot in fits do
			assert(slotSet[slot], "unknown slot " .. tostring(slot) .. " for " .. id)
		end
		local requirements: Requirements = input.requirements or {}
		local level = requirements.level or 0
		assert(isFinite(level), "invalid level requirement for " .. id)
		local stats: Modifiers = input.stats or {}
		catalog.items[id] = {
			id = id,
			slots = fits,
			level = level,
			tags = table.clone(requirements.tags or {}),
			add = copyNumbers(stats.add, "add"),
			mul = copyNumbers(stats.mul, "mul"),
		}
	end
	return catalog
end

function EquipmentLogic.new(): Loadout
	return { equipped = {} }
end

function EquipmentLogic.equippedIn(loadout: Loadout, slot: string): string?
	return loadout.equipped[slot]
end

function EquipmentLogic.isEquipped(loadout: Loadout, itemId: string): boolean
	for _, equippedId in loadout.equipped do
		if equippedId == itemId then
			return true
		end
	end
	return false
end

-- Whether the wearer described by `context` meets the item's requirements.
function EquipmentLogic.meetsRequirements(item: Item, context: Context?): (boolean, string?)
	local level = if context then context.level or 0 else 0
	if level < item.level then
		return false, "level too low"
	end
	local tags = if context then context.tags else nil
	for _, tag in item.tags do
		if tags == nil or tags[tag] ~= true then
			return false, "missing tag " .. tag
		end
	end
	return true, nil
end

-- Picks the slot an item goes to: the requested slot, else its first free slot, else its first slot.
local function chooseSlot(catalog: Catalog, loadout: Loadout, item: Item, slot: string?): (string?, string?)
	if slot ~= nil then
		if not catalog.slotSet[slot] then
			return nil, "unknown slot"
		end
		if not table.find(item.slots, slot) then
			return nil, "wrong slot"
		end
		return slot, nil
	end
	for _, candidate in item.slots do
		if loadout.equipped[candidate] == nil then
			return candidate, nil
		end
	end
	return item.slots[1], nil
end

function EquipmentLogic.canEquip(
	catalog: Catalog,
	loadout: Loadout,
	itemId: string,
	context: Context?,
	slot: string?
): (boolean, string?)
	local item = catalog.items[itemId]
	if item == nil then
		return false, "unknown item"
	end
	local target, slotReason = chooseSlot(catalog, loadout, item, slot)
	if target == nil then
		return false, slotReason
	end
	if loadout.equipped[target] ~= itemId and EquipmentLogic.isEquipped(loadout, itemId) then
		return false, "already equipped"
	end
	return EquipmentLogic.meetsRequirements(item, context)
end

-- Equips an item. Returns the new loadout, the slot used and the item it replaced (if any),
-- or nil and a reason.
function EquipmentLogic.equip(
	catalog: Catalog,
	loadout: Loadout,
	itemId: string,
	context: Context?,
	slot: string?
): (Loadout?, string?, string?)
	local allowed, reason = EquipmentLogic.canEquip(catalog, loadout, itemId, context, slot)
	if not allowed then
		return nil, reason, nil
	end
	local item = catalog.items[itemId]
	local target = chooseSlot(catalog, loadout, item, slot)
	if target == nil then
		return nil, "wrong slot", nil
	end
	local replaced = loadout.equipped[target]
	local equipped = table.clone(loadout.equipped)
	equipped[target] = itemId
	return { equipped = equipped }, target, replaced
end

-- Empties a slot. Returns the new loadout and the removed item id (nil when the slot was empty).
function EquipmentLogic.unequip(loadout: Loadout, slot: string): (Loadout, string?)
	local removed = loadout.equipped[slot]
	local equipped = table.clone(loadout.equipped)
	equipped[slot] = nil
	return { equipped = equipped }, removed
end

-- Final stats: (base + every add) * multiplier, per stat. Stats missing from `base` start at 0.
function EquipmentLogic.aggregate(catalog: Catalog, loadout: Loadout, base: { [string]: number }?): { [string]: number }
	local flat: { [string]: number } = table.clone(base or {})
	local factor: { [string]: number } = {}
	for _, itemId in loadout.equipped do
		local item = catalog.items[itemId]
		if item ~= nil then
			for stat, value in item.add do
				flat[stat] = (flat[stat] or 0) + value
			end
			for stat, value in item.mul do
				local current = factor[stat] or 1
				if catalog.stacking == "additive" then
					factor[stat] = current + (value - 1)
				else
					factor[stat] = current * value
				end
			end
		end
	end
	local result: { [string]: number } = {}
	for stat, value in flat do
		result[stat] = value * (factor[stat] or 1)
	end
	for stat in factor do
		if result[stat] == nil then
			result[stat] = 0
		end
	end
	return result
end

-- Slots whose items the wearer no longer qualifies for (for example after losing a level).
function EquipmentLogic.invalidSlots(catalog: Catalog, loadout: Loadout, context: Context?): { string }
	local invalid: { string } = {}
	for _, slot in catalog.slots do
		local itemId = loadout.equipped[slot]
		if itemId ~= nil then
			local item = catalog.items[itemId]
			if item == nil or not EquipmentLogic.meetsRequirements(item, context) then
				table.insert(invalid, slot)
			end
		end
	end
	return invalid
end

function EquipmentLogic.serialize(loadout: Loadout): Saved
	return { v = EquipmentLogic.SAVE_VERSION, e = table.clone(loadout.equipped) }
end

-- Rebuilds a loadout from untrusted data, dropping unknown slots, unknown items, items in slots
-- they do not fit and duplicates. Requirements are not checked here: use invalidSlots.
function EquipmentLogic.deserialize(catalog: Catalog, raw: any): Loadout
	local loadout = EquipmentLogic.new()
	if type(raw) ~= "table" or type(raw.e) ~= "table" then
		return loadout
	end
	local used: { [string]: boolean } = {}
	for _, slot in catalog.slots do
		local itemId = raw.e[slot]
		local item = if type(itemId) == "string" then catalog.items[itemId] else nil
		if item ~= nil and not used[item.id] and table.find(item.slots, slot) then
			loadout.equipped[slot] = item.id
			used[item.id] = true
		end
	end
	return loadout
end

return EquipmentLogic
