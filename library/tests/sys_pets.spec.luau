--!strict
local PetsLogic = require("../src/Systems/Pets/PetsLogic")
local t = require("./lib/t")

local function config(): PetsLogic.Config
	return PetsLogic.validateConfig({
		rarities = {
			{ name = "Common", rank = 1 },
			{ name = "Rare", rank = 2 },
			{ name = "Legendary", rank = 3 },
		},
		pets = {
			Dog = { rarity = "Common", multiplier = 1 },
			Cat = { rarity = "Rare", multiplier = 3 },
			Dragon = { rarity = "Legendary", multiplier = 10, tradeable = false },
		},
		eggs = {
			Basic = {
				cost = { Coins = 100 },
				entries = { { pet = "Dog", weight = 90 }, { pet = "Cat", weight = 9 }, { pet = "Dragon", weight = 1 } },
				pity = { rarity = "Legendary", after = 5 },
			},
		},
		capacity = 12,
		equipSlots = 2,
	})
end

local function fixed(value: number): () -> number
	return function()
		return value
	end
end

return {
	["validateConfig rejects unknown pets and rarities"] = function()
		t.throws(function()
			PetsLogic.validateConfig({
				rarities = { { name = "Common", rank = 1 } },
				pets = { Dog = { rarity = "Mythic", multiplier = 1 } },
				eggs = {},
			})
		end)
		t.throws(function()
			PetsLogic.validateConfig({
				rarities = { { name = "Common", rank = 1 } },
				pets = { Dog = { rarity = "Common", multiplier = 1 } },
				eggs = { E = { entries = { { pet = "Ghost", weight = 1 } } } },
			})
		end)
	end,

	["hatch picks by weight and assigns increasing ids"] = function()
		local cfg = config()
		local low = PetsLogic.hatch(cfg, PetsLogic.newState(), "Basic", 1, fixed(0.0))
		t.truthy(low.ok)
		t.equal(low.pets[1].kind, "Dog")
		t.equal(low.pets[1].id, "1")
		local high = PetsLogic.hatch(cfg, low.state, "Basic", 1, fixed(0.995))
		t.equal(high.pets[1].kind, "Dragon")
		t.equal(high.pets[1].id, "2")
		local mid = PetsLogic.hatch(cfg, high.state, "Basic", 1, fixed(0.92))
		t.equal(mid.pets[1].kind, "Cat")
		t.equal(PetsLogic.count(mid.state), 3)
	end,

	["pity guarantees the rarity after N misses and then resets"] = function()
		local cfg = config()
		local result = PetsLogic.hatch(cfg, PetsLogic.newState(), "Basic", 5, fixed(0))
		t.truthy(result.ok)
		for i = 1, 4 do
			t.equal(result.pets[i].kind, "Dog")
		end
		t.equal(result.pets[5].kind, "Dragon", "fifth hatch is the pity pull")
		t.equal(result.state.pity.Basic, 0)
		local again = PetsLogic.hatch(cfg, result.state, "Basic", 1, fixed(0))
		t.equal(again.state.pity.Basic, 1)
	end,

	["luck raises rare odds and odds sum to one"] = function()
		local cfg = config()
		local normal = PetsLogic.odds(cfg, "Basic")
		local lucky = PetsLogic.odds(cfg, "Basic", 3)
		local sum = 0
		for _, row in lucky do
			sum += row.chance
		end
		t.near(sum, 1, 1e-9)
		t.near(normal[3].chance, 0.01, 1e-9)
		t.truthy(lucky[3].chance > normal[3].chance)
		t.truthy(lucky[1].chance < normal[1].chance)
	end,

	["hatch rejects bad amounts, unknown eggs and full inventories"] = function()
		local cfg = config()
		local state = PetsLogic.newState()
		t.equal(PetsLogic.hatch(cfg, state, "Nope", 1, fixed(0)).reason, "unknown egg")
		t.equal(PetsLogic.hatch(cfg, state, "Basic", 0, fixed(0)).reason, "invalid amount")
		t.equal(PetsLogic.hatch(cfg, state, "Basic", 1.5, fixed(0)).reason, "invalid amount")
		t.equal(PetsLogic.hatch(cfg, state, "Basic", 11, fixed(0)).reason, "invalid amount")
		local full = PetsLogic.hatch(cfg, state, "Basic", 10, fixed(0)).state
		t.equal(PetsLogic.hatch(cfg, full, "Basic", 3, fixed(0)).reason, "inventory full")
	end,

	["equip respects slots, equipBest picks the strongest"] = function()
		local cfg = config()
		local s = PetsLogic.hatch(cfg, PetsLogic.newState(), "Basic", 1, fixed(0)).state -- 1 Dog
		s = PetsLogic.hatch(cfg, s, "Basic", 1, fixed(0.92)).state -- 2 Cat
		s = PetsLogic.hatch(cfg, s, "Basic", 1, fixed(0.995)).state -- 3 Dragon
		s = PetsLogic.equip(cfg, s, "1").state
		s = PetsLogic.equip(cfg, s, "2").state
		t.equal(PetsLogic.equip(cfg, s, "3").reason, "no free slot")
		t.equal(PetsLogic.equip(cfg, s, "1").reason, "already equipped")
		t.equal(PetsLogic.totalMultiplier(cfg, s), 1 + 1 + 3)
		local best = PetsLogic.equipBest(cfg, s).state
		t.deepEqual(best.equipped, { "3", "2" })
		t.equal(PetsLogic.totalMultiplier(cfg, best), 1 + 10 + 3)
		t.deepEqual(PetsLogic.unequip(best, "3").state.equipped, { "2" })
	end,

	["delete refuses locked pets and unequips"] = function()
		local cfg = config()
		local s = PetsLogic.hatch(cfg, PetsLogic.newState(), "Basic", 2, fixed(0)).state
		s = PetsLogic.equip(cfg, s, "1").state
		local locked = PetsLogic.setLocked(s, "2", true).state
		t.equal(PetsLogic.delete(locked, { "1", "2" }).reason, "pet is locked")
		local deleted = PetsLogic.delete(locked, { "1" }).state
		t.equal(PetsLogic.count(deleted), 1)
		t.equal(#deleted.equipped, 0)
	end,

	["fuse turns five matching pets into one golden"] = function()
		local cfg = config()
		local s = PetsLogic.hatch(cfg, PetsLogic.newState(), "Basic", 4, fixed(0)).state
		t.equal(PetsLogic.fuse(cfg, s, { "1", "2", "3", "4" }).reason, "need 5 pets")
		s = PetsLogic.give(cfg, s, "Dog").state
		s = PetsLogic.equip(cfg, s, "3").state
		local fused = PetsLogic.fuse(cfg, s, { "1", "2", "3", "4", "5" })
		t.truthy(fused.ok, fused.reason)
		t.equal(PetsLogic.count(fused.state), 1)
		t.equal(fused.pets[1].tier, 2)
		t.deepEqual(fused.state.equipped, { "1" })
		t.equal(PetsLogic.multiplierOf(cfg, fused.pets[1]), 2.5)
		local cat = PetsLogic.give(cfg, fused.state, "Cat").state
		t.equal(PetsLogic.fuse(cfg, cat, { "1", "6", "1", "1", "1" }).reason, "pets must match")
	end,

	["tradeable respects definitions and locks"] = function()
		local cfg = config()
		t.falsy(PetsLogic.isTradeable(cfg, { id = "1", kind = "Dragon", tier = 1 }))
		t.truthy(PetsLogic.isTradeable(cfg, { id = "1", kind = "Dog", tier = 1 }))
		t.falsy(PetsLogic.isTradeable(cfg, { id = "1", kind = "Dog", tier = 1, locked = true }))
	end,

	["exchange swaps pets with fresh ids"] = function()
		local cfg = config()
		local s = PetsLogic.hatch(cfg, PetsLogic.newState(), "Basic", 2, fixed(0)).state
		local r = PetsLogic.exchange(cfg, s, { "1" }, { { id = "99", kind = "Cat", tier = 2 } })
		t.truthy(r.ok)
		t.equal(r.pets[1].id, "3")
		t.equal(r.state.pets["3"].kind, "Cat")
		t.equal(r.state.pets["1"], nil)
		t.equal(PetsLogic.exchange(cfg, s, { "7" }, {}).reason, "unknown pet")
	end,

	["serialize round trip and hostile data"] = function()
		local cfg = config()
		local s = PetsLogic.hatch(cfg, PetsLogic.newState(), "Basic", 3, fixed(0)).state
		s = PetsLogic.equip(cfg, s, "2").state
		s = PetsLogic.setLocked(s, "3", true).state
		local back = PetsLogic.deserialize(cfg, PetsLogic.serialize(s))
		t.deepEqual(back, s)
		local hostile: any = {
			p = { { "1", "Dog", 1 }, { "1", "Dog", 1 }, { "x", "Dog", 1 }, { "5", "Ghost", 1 }, { "6", "Dog", 9 } },
			e = { "1", "1", "6" },
			n = -4,
			y = { Basic = -2, Fake = 3 },
			h = "lots",
		}
		local clean = PetsLogic.deserialize(cfg, hostile)
		t.equal(PetsLogic.count(clean), 1)
		t.deepEqual(clean.equipped, { "1" })
		t.equal(clean.nextId, 2)
		t.deepEqual(clean.pity, {})
		t.equal(clean.hatched, 0)
		t.deepEqual(PetsLogic.deserialize(cfg, nil), PetsLogic.newState())
	end,
}
