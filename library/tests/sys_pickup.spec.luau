--!strict
local PickupLogic = require("../src/Systems/Pickup/PickupLogic")
local t = require("./lib/t")

local ORIGIN = { x = 0, y = 0, z = 0 }

local function giveAll(_itemId: string, _count: number): number
	return 0
end

local function spawned(overrides: { [string]: any }?, ownerId: number?)
	local state = PickupLogic.new(overrides)
	local uid = PickupLogic.spawn(state, "Apple", 5, ORIGIN, 0, ownerId)
	assert(uid, "spawn failed")
	return state, uid
end

return {
	["new applies defaults and validates overrides"] = function()
		local state = PickupLogic.new()
		t.equal(state.config.maxDistance, 12)
		t.equal(state.config.despawnSeconds, 120)
		t.equal(PickupLogic.new({ maxDistance = 4 }).config.maxDistance, 4)
		t.throws(function()
			PickupLogic.new({ cooldown = -1 })
		end)
		t.throws(function()
			PickupLogic.new({ maxDistance = math.huge })
		end)
	end,

	["spawn validates input and assigns uids"] = function()
		local state = PickupLogic.new({ maxCount = 10 })
		local first = PickupLogic.spawn(state, "Apple", 1, ORIGIN, 0)
		local second = PickupLogic.spawn(state, "Apple", 1, ORIGIN, 0)
		t.equal(first, 1)
		t.equal(second, 2)
		t.equal(select(2, PickupLogic.spawn(state, "", 1, ORIGIN, 0)), "invalid item")
		t.equal(select(2, PickupLogic.spawn(state, "Apple", 0, ORIGIN, 0)), "invalid count")
		t.equal(select(2, PickupLogic.spawn(state, "Apple", 11, ORIGIN, 0)), "invalid count")
		local badPosition: any = { x = 0, y = math.sqrt(-1), z = 0 }
		t.equal(select(2, PickupLogic.spawn(state, "Apple", 1, badPosition, 0)), "invalid input")
	end,

	["spawn copies the position"] = function()
		local position = { x = 1, y = 2, z = 3 }
		local state = PickupLogic.new()
		local uid = PickupLogic.spawn(state, "Apple", 1, position, 0)
		position.x = 99
		local item = PickupLogic.get(state, uid or 0)
		assert(item, "missing item")
		t.equal(item.position.x, 1)
	end,

	["pickup within range gives everything and removes the item"] = function()
		local state, uid = spawned()
		local given = 0
		local result = PickupLogic.pickup(state, uid, 1, { x = 3, y = 0, z = 4 }, 1, function(itemId, count)
			t.equal(itemId, "Apple")
			given += count
			return 0
		end)
		t.truthy(result.ok)
		t.equal(result.taken, 5)
		t.truthy(result.removed)
		t.equal(given, 5)
		t.equal(PickupLogic.get(state, uid), nil)
	end,

	["pickup is refused when too far"] = function()
		local state, uid = spawned({ maxDistance = 5 })
		local result = PickupLogic.pickup(state, uid, 1, { x = 5.1, y = 0, z = 0 }, 1, giveAll)
		t.falsy(result.ok)
		t.equal(result.reason, "too far")
		t.equal(result.remaining, 5)
		t.truthy(PickupLogic.canPickup(state, uid, 1, { x = 5, y = 0, z = 0 }, 1))
	end,

	["partial pickups leave the rest on the ground"] = function()
		local state, uid = spawned()
		local result = PickupLogic.pickup(state, uid, 1, ORIGIN, 1, function(_itemId, _count)
			return 3
		end)
		t.truthy(result.ok)
		t.equal(result.taken, 2)
		t.equal(result.remaining, 3)
		t.falsy(result.removed)
		local item = PickupLogic.get(state, uid)
		assert(item, "item should remain")
		t.equal(item.count, 3)
	end,

	["a full inventory takes nothing and starts no cooldown"] = function()
		local state, uid = spawned()
		local result = PickupLogic.pickup(state, uid, 1, ORIGIN, 1, function(_itemId, count)
			return count
		end)
		t.falsy(result.ok)
		t.equal(result.reason, "inventory full")
		t.equal(state.cooldowns[1], nil)
	end,

	["bad give results are treated as nothing taken"] = function()
		local state, uid = spawned()
		local result = PickupLogic.pickup(state, uid, 1, ORIGIN, 1, function(_itemId, _count)
			return -4
		end)
		t.equal(result.reason, "inventory full")
		local nanResult = PickupLogic.pickup(state, uid, 1, ORIGIN, 1, function(_itemId, _count)
			return math.sqrt(-1)
		end)
		t.equal(nanResult.reason, "inventory full")
		t.equal(nanResult.remaining, 5)
	end,

	["the owner has priority during the ownership window"] = function()
		local state, uid = spawned({ ownershipSeconds = 10 }, 7)
		t.equal(select(2, PickupLogic.canPickup(state, uid, 8, ORIGIN, 5)), "owned by another player")
		t.truthy(PickupLogic.canPickup(state, uid, 7, ORIGIN, 5))
		t.truthy(PickupLogic.canPickup(state, uid, 8, ORIGIN, 10))
	end,

	["cooldown blocks rapid pickups per player"] = function()
		local state = PickupLogic.new({ cooldown = 1 })
		local a = PickupLogic.spawn(state, "Apple", 1, ORIGIN, 0)
		local b = PickupLogic.spawn(state, "Apple", 1, ORIGIN, 0)
		assert(a and b, "spawn failed")
		t.truthy(PickupLogic.pickup(state, a, 1, ORIGIN, 10, giveAll).ok)
		t.equal(PickupLogic.pickup(state, b, 1, ORIGIN, 10.5, giveAll).reason, "cooldown")
		t.truthy(PickupLogic.pickup(state, b, 2, ORIGIN, 10.5, giveAll).ok)
		PickupLogic.pruneCooldowns(state, 11)
		t.equal(state.cooldowns[1], nil)
	end,

	["items despawn and expire returns their uids"] = function()
		local state = PickupLogic.new({ despawnSeconds = 30 })
		local early = PickupLogic.spawn(state, "Apple", 1, ORIGIN, 0)
		local late = PickupLogic.spawn(state, "Apple", 1, ORIGIN, 20)
		assert(early and late, "spawn failed")
		t.equal(select(2, PickupLogic.canPickup(state, early, 1, ORIGIN, 30)), "despawned")
		t.deepEqual(PickupLogic.expire(state, 30), { early })
		t.equal(PickupLogic.get(state, early), nil)
		t.truthy(PickupLogic.get(state, late))
		t.deepEqual(PickupLogic.expire(state, 100), { late })
	end,

	["despawnSeconds zero keeps items forever"] = function()
		local state = PickupLogic.new({ despawnSeconds = 0 })
		local uid = PickupLogic.spawn(state, "Apple", 1, ORIGIN, 0)
		t.equal(#PickupLogic.expire(state, 1e9), 0)
		t.truthy(PickupLogic.get(state, uid or 0))
	end,

	["missing items and bad input are rejected"] = function()
		local state, uid = spawned()
		t.equal(PickupLogic.pickup(state, 999, 1, ORIGIN, 1, giveAll).reason, "no such item")
		local badPosition: any = { x = "0", y = 0, z = 0 }
		t.equal(select(2, PickupLogic.canPickup(state, uid, 1, badPosition, 1)), "invalid input")
		t.truthy(PickupLogic.remove(state, uid))
		t.falsy(PickupLogic.remove(state, uid))
	end,

	["nearby sorts by distance"] = function()
		local state = PickupLogic.new()
		PickupLogic.spawn(state, "Far", 1, { x = 9, y = 0, z = 0 }, 0)
		PickupLogic.spawn(state, "Near", 1, { x = 1, y = 0, z = 0 }, 0)
		PickupLogic.spawn(state, "Out", 1, { x = 50, y = 0, z = 0 }, 0)
		local found = PickupLogic.nearby(state, ORIGIN, 10)
		t.equal(#found, 2)
		t.equal(found[1].itemId, "Near")
		t.equal(found[2].itemId, "Far")
		t.near(PickupLogic.distance(ORIGIN, { x = 3, y = 4, z = 0 }), 5)
	end,
}
