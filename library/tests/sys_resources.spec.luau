--!strict
local ResourcesLogic = require("../src/Systems/Resources/ResourcesLogic")
local t = require("./lib/t")

local function defs()
	return ResourcesLogic.newDefs({
		{
			kind = "Tree",
			maxHealth = 10,
			yield = { { id = "Log", weight = 3, min = 1, max = 3 }, { id = "Apple", weight = 1 } },
			respawnSeconds = 20,
		},
		{ kind = "IronRock", maxHealth = 30, yield = { { id = "Iron", weight = 1, min = 2 } }, minTier = 2, rolls = 2 },
		{ kind = "Bush", maxHealth = 5, yield = { { id = "Berry", weight = 1 } }, dropOnHit = true },
	})
end

-- A random source that returns the given values in order, then repeats the last one.
local function sequence(values: { number }): () -> number
	local index = 0
	local function nextValue(): number
		index = math.min(index + 1, #values)
		return values[index]
	end
	return nextValue
end

local AXE = { tier = 1, damage = 5 }

return {
	["newDefs validates definitions"] = function()
		t.throws(function()
			ResourcesLogic.newDefs({ { kind = "A", maxHealth = 0, yield = {} } })
		end)
		t.throws(function()
			ResourcesLogic.newDefs({ { kind = "A", maxHealth = 1, yield = { { id = "X", weight = 0 } } } })
		end)
		local inverted = { kind = "A", maxHealth = 1, yield = { { id = "X", weight = 1, min = 3, max = 2 } } }
		t.throws(function()
			ResourcesLogic.newDefs({ inverted })
		end)
		local plain = { kind = "A", maxHealth = 1, yield = {} }
		t.throws(function()
			ResourcesLogic.newDefs({ plain, plain })
		end)
		local d = defs()
		local tree = ResourcesLogic.getDef(d, "Tree")
		assert(tree, "missing tree")
		t.equal(tree.totalWeight, 4)
		t.equal(tree.rolls, 1)
		t.equal(tree.yield[2].max, 1)
		t.throws(function()
			ResourcesLogic.newNode(d, "Ghost")
		end)
	end,

	["hits reduce health and depletion rolls drops"] = function()
		local d = defs()
		local node = ResourcesLogic.newNode(d, "Tree")
		local first = ResourcesLogic.hit(d, node, AXE, 0, sequence({ 0 }))
		t.truthy(first.ok)
		t.equal(first.node.health, 5)
		t.falsy(first.depleted)
		t.equal(#first.drops, 0)
		t.equal(node.health, 10)
		local second = ResourcesLogic.hit(d, first.node, AXE, 1, sequence({ 0.1, 0.99 }))
		t.truthy(second.depleted)
		t.equal(second.node.health, 0)
		t.equal(second.node.respawnAt, 21)
		t.deepEqual(second.drops, { { id = "Log", count = 3 } })
	end,

	["weighted rolls pick entries by cumulative weight"] = function()
		local tree = ResourcesLogic.getDef(defs(), "Tree")
		assert(tree, "missing tree")
		t.deepEqual(ResourcesLogic.rollYield(tree, sequence({ 0.74, 0 })), { { id = "Log", count = 1 } })
		t.deepEqual(ResourcesLogic.rollYield(tree, sequence({ 0.75, 0 })), { { id = "Apple", count = 1 } })
		t.deepEqual(ResourcesLogic.rollYield(tree, sequence({ 0.5, 0.5 })), { { id = "Log", count = 2 } })
	end,

	["rolls merge drops and survive bad random values"] = function()
		local tree = ResourcesLogic.getDef(defs(), "Tree")
		assert(tree, "missing tree")
		local merged = ResourcesLogic.rollYield(tree, sequence({ 0, 0 }), 3)
		t.deepEqual(merged, { { id = "Log", count = 3 } })
		local edge = ResourcesLogic.rollYield(tree, sequence({ 1, 1 }))
		t.deepEqual(edge, { { id = "Apple", count = 1 } })
		local nan = ResourcesLogic.rollYield(tree, sequence({ math.sqrt(-1) }))
		t.deepEqual(nan, { { id = "Log", count = 1 } })
	end,

	["tool tiers gate damage and add a bonus"] = function()
		local d = defs()
		local rock = ResourcesLogic.getDef(d, "IronRock")
		assert(rock, "missing rock")
		t.equal(ResourcesLogic.damageFor(rock, { tier = 1, damage = 10 }), 0)
		t.equal(ResourcesLogic.damageFor(rock, { tier = 2, damage = 10 }), 10)
		t.equal(ResourcesLogic.damageFor(rock, { tier = 4, damage = 10 }), 15)
		t.equal(ResourcesLogic.damageFor(rock, { tier = 4, damage = 10 }, 0), 10)
		local badTool: any = { tier = "x", damage = 5 }
		t.equal(ResourcesLogic.damageFor(rock, badTool), 0)
		local result = ResourcesLogic.hit(d, ResourcesLogic.newNode(d, "IronRock"), AXE, 0, sequence({ 0 }))
		t.falsy(result.ok)
		t.equal(result.reason, "tool tier too low")
	end,

	["depleted nodes refuse hits until they respawn"] = function()
		local d = defs()
		local node: ResourcesLogic.Node = { kind = "Tree", health = 0, respawnAt = 50 }
		t.falsy(ResourcesLogic.isAvailable(node, 49))
		t.truthy(ResourcesLogic.isAvailable(node, 50))
		t.equal(ResourcesLogic.hit(d, node, AXE, 49, sequence({ 0 })).reason, "depleted")
		local refreshed = ResourcesLogic.refresh(d, node, 50)
		t.equal(refreshed.health, 10)
		t.equal(refreshed.respawnAt, nil)
		t.equal(ResourcesLogic.refresh(d, node, 10), node)
		local after = ResourcesLogic.hit(d, node, AXE, 60, sequence({ 0 }))
		t.truthy(after.ok)
		t.equal(after.node.health, 5)
	end,

	["dropOnHit nodes drop on every hit"] = function()
		local d = defs()
		local hands = { tier = 0, damage = 1 }
		local result = ResourcesLogic.hit(d, ResourcesLogic.newNode(d, "Bush"), hands, 0, sequence({ 0 }))
		t.falsy(result.depleted)
		t.deepEqual(result.drops, { { id = "Berry", count = 1 } })
	end,

	["multiple rolls come from the definition"] = function()
		local d = defs()
		local pick = { tier = 2, damage = 100 }
		local result = ResourcesLogic.hit(d, ResourcesLogic.newNode(d, "IronRock"), pick, 0, sequence({ 0 }))
		t.truthy(result.depleted)
		t.deepEqual(result.drops, { { id = "Iron", count = 4 } })
		local fresh = ResourcesLogic.newNode(d, "IronRock")
		local override = ResourcesLogic.hit(d, fresh, pick, 0, sequence({ 0 }), { rolls = 1 })
		t.deepEqual(override.drops, { { id = "Iron", count = 2 } })
	end,

	["invalid hits are rejected"] = function()
		local d = defs()
		local ghost: ResourcesLogic.Node = { kind = "Ghost", health = 5, respawnAt = nil }
		t.equal(ResourcesLogic.hit(d, ghost, AXE, 0, sequence({ 0 })).reason, "unknown kind")
		local node = ResourcesLogic.newNode(d, "Tree")
		t.equal(ResourcesLogic.hit(d, node, AXE, math.huge, sequence({ 0 })).reason, "invalid time")
		t.equal(ResourcesLogic.hit(d, node, { tier = 1, damage = 0 }, 0, sequence({ 0 })).reason, "tool tier too low")
	end,

	["cooldowns gate gathering per key"] = function()
		local cooldowns: ResourcesLogic.Cooldowns = {}
		t.truthy(ResourcesLogic.ready(cooldowns, "1", 0))
		ResourcesLogic.markCooldown(cooldowns, "1", 0, 0.5)
		t.falsy(ResourcesLogic.ready(cooldowns, "1", 0.4))
		t.truthy(ResourcesLogic.ready(cooldowns, "2", 0.4))
		t.truthy(ResourcesLogic.ready(cooldowns, "1", 0.5))
		ResourcesLogic.pruneCooldowns(cooldowns, 1)
		t.equal(cooldowns["1"], nil)
	end,

	["seededRng is deterministic and in range"] = function()
		local a = ResourcesLogic.seededRng(42)
		local b = ResourcesLogic.seededRng(42)
		for _ = 1, 100 do
			local value = a()
			t.equal(value, b())
			t.truthy(value >= 0 and value < 1)
		end
		local zero = ResourcesLogic.seededRng(0)
		t.truthy(zero() >= 0)
	end,
}
