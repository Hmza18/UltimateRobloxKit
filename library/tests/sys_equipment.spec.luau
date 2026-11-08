--!strict
local EquipmentLogic = require("../src/Systems/Equipment/EquipmentLogic")
local t = require("./lib/t")

local SLOTS = { "head", "body", "weapon", "ring1", "ring2" }

local function catalog(stacking: ("product" | "additive")?)
	local items: { EquipmentLogic.ItemInput } = {
		{ id = "Helm", slot = "head", stats = { add = { defense = 5 } } },
		{ id = "Plate", slot = "body", requirements = { level = 10 }, stats = { add = { defense = 20 } } },
		{ id = "Sword", slot = "weapon", stats = { add = { attack = 10 }, mul = { attack = 1.5 } } },
		{ id = "Staff", slot = "weapon", requirements = { tags = { "mage" } }, stats = { add = { magic = 8 } } },
		{ id = "RubyRing", slots = { "ring1", "ring2" }, stats = { mul = { attack = 1.1 } } },
		{ id = "JadeRing", slots = { "ring1", "ring2" }, stats = { mul = { attack = 1.2 } } },
	}
	return EquipmentLogic.newCatalog(SLOTS, items, stacking)
end

local function equipAll(cat, ids: { string }, context: EquipmentLogic.Context?): EquipmentLogic.Loadout
	local loadout = EquipmentLogic.new()
	for _, id in ids do
		local nextLoadout, reason = EquipmentLogic.equip(cat, loadout, id, context)
		assert(nextLoadout, reason)
		loadout = nextLoadout
	end
	return loadout
end

return {
	["newCatalog validates slots and items"] = function()
		t.throws(function()
			EquipmentLogic.newCatalog({}, {})
		end)
		t.throws(function()
			EquipmentLogic.newCatalog({ "head", "head" }, {})
		end)
		t.throws(function()
			EquipmentLogic.newCatalog({ "head" }, { { id = "Boots", slot = "feet" } })
		end)
		t.throws(function()
			EquipmentLogic.newCatalog({ "head" }, { { id = "Hat" } })
		end)
		t.throws(function()
			EquipmentLogic.newCatalog({ "head" }, { { id = "Hat", slot = "head" }, { id = "Hat", slot = "head" } })
		end)
		local badStacking: any = "max"
		t.throws(function()
			EquipmentLogic.newCatalog({ "head" }, {}, badStacking)
		end)
		local cat = catalog()
		t.equal(#cat.slots, 5)
		t.equal(cat.stacking, "product")
	end,

	["equip places an item in its slot without touching the input"] = function()
		local cat = catalog()
		local empty = EquipmentLogic.new()
		local loadout, slot, replaced = EquipmentLogic.equip(cat, empty, "Helm")
		t.truthy(loadout)
		t.equal(slot, "head")
		t.equal(replaced, nil)
		if loadout then
			t.equal(EquipmentLogic.equippedIn(loadout, "head"), "Helm")
			t.truthy(EquipmentLogic.isEquipped(loadout, "Helm"))
		end
		t.equal(EquipmentLogic.equippedIn(empty, "head"), nil)
	end,

	["equipping into an occupied slot reports the replaced item"] = function()
		local cat = catalog()
		local loadout = equipAll(cat, { "Sword" })
		local result, slot, replaced = EquipmentLogic.equip(cat, loadout, "Staff", { tags = { mage = true } })
		t.truthy(result)
		t.equal(slot, "weapon")
		t.equal(replaced, "Sword")
	end,

	["multi-slot items fill the first free slot"] = function()
		local cat = catalog()
		local loadout = equipAll(cat, { "RubyRing", "JadeRing" })
		t.equal(loadout.equipped.ring1, "RubyRing")
		t.equal(loadout.equipped.ring2, "JadeRing")
		local _, reason = EquipmentLogic.equip(cat, loadout, "RubyRing", nil, "ring2")
		t.equal(reason, "already equipped")
		local same = EquipmentLogic.equip(cat, loadout, "RubyRing", nil, "ring1")
		t.truthy(same)
	end,

	["requirements check level and tags"] = function()
		local cat = catalog()
		local empty = EquipmentLogic.new()
		t.equal(select(2, EquipmentLogic.canEquip(cat, empty, "Plate", { level = 9 })), "level too low")
		t.truthy(EquipmentLogic.canEquip(cat, empty, "Plate", { level = 10 }))
		t.equal(select(2, EquipmentLogic.canEquip(cat, empty, "Plate")), "level too low")
		t.equal(select(2, EquipmentLogic.canEquip(cat, empty, "Staff", { tags = {} })), "missing tag mage")
		t.equal(select(2, EquipmentLogic.canEquip(cat, empty, "Staff")), "missing tag mage")
		t.truthy(EquipmentLogic.canEquip(cat, empty, "Staff", { tags = { mage = true } }))
	end,

	["invalid equips are rejected"] = function()
		local cat = catalog()
		local empty = EquipmentLogic.new()
		t.equal(select(2, EquipmentLogic.equip(cat, empty, "Nope")), "unknown item")
		t.equal(select(2, EquipmentLogic.equip(cat, empty, "Helm", nil, "body")), "wrong slot")
		t.equal(select(2, EquipmentLogic.equip(cat, empty, "Helm", nil, "tail")), "unknown slot")
	end,

	["unequip empties a slot"] = function()
		local cat = catalog()
		local loadout = equipAll(cat, { "Helm" })
		local result, removed = EquipmentLogic.unequip(loadout, "head")
		t.equal(removed, "Helm")
		t.equal(result.equipped.head, nil)
		t.equal(loadout.equipped.head, "Helm")
		local _, none = EquipmentLogic.unequip(result, "head")
		t.equal(none, nil)
	end,

	["aggregate adds then multiplies (product stacking)"] = function()
		local cat = catalog()
		local loadout = equipAll(cat, { "Helm", "Sword", "RubyRing", "JadeRing" })
		local stats = EquipmentLogic.aggregate(cat, loadout, { attack = 10, defense = 1, speed = 16 })
		t.near(stats.attack, (10 + 10) * 1.5 * 1.1 * 1.2, 1e-9)
		t.equal(stats.defense, 6)
		t.equal(stats.speed, 16)
	end,

	["aggregate with additive stacking sums multiplier bonuses"] = function()
		local cat = catalog("additive")
		local loadout = equipAll(cat, { "Sword", "RubyRing", "JadeRing" })
		local stats = EquipmentLogic.aggregate(cat, loadout, { attack = 10 })
		t.near(stats.attack, 20 * (1 + 0.5 + 0.1 + 0.2), 1e-9)
	end,

	["aggregate handles missing base stats"] = function()
		local cat = catalog()
		local stats = EquipmentLogic.aggregate(cat, equipAll(cat, { "RubyRing", "Helm" }))
		t.equal(stats.defense, 5)
		t.equal(stats.attack, 0)
		t.deepEqual(EquipmentLogic.aggregate(cat, EquipmentLogic.new(), nil), {})
	end,

	["invalidSlots finds items the wearer no longer qualifies for"] = function()
		local cat = catalog()
		local loadout = equipAll(cat, { "Plate", "Helm" }, { level = 12 })
		t.deepEqual(EquipmentLogic.invalidSlots(cat, loadout, { level = 12 }), {})
		t.deepEqual(EquipmentLogic.invalidSlots(cat, loadout, { level = 3 }), { "body" })
	end,

	["serialize and deserialize drop bad entries"] = function()
		local cat = catalog()
		local loadout = equipAll(cat, { "Helm", "RubyRing" })
		local restored = EquipmentLogic.deserialize(cat, EquipmentLogic.serialize(loadout))
		t.deepEqual(restored.equipped, loadout.equipped)
		local raw: any = {
			e = { head = "Sword", body = "Ghost", ring1 = "JadeRing", ring2 = "JadeRing", tail = "Helm", weapon = 5 },
		}
		local cleaned = EquipmentLogic.deserialize(cat, raw)
		t.deepEqual(cleaned.equipped, { ring1 = "JadeRing" })
		t.deepEqual(EquipmentLogic.deserialize(cat, nil).equipped, {})
	end,
}
