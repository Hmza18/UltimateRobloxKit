--!strict
-- World item pickup rules. Pure Luau: positions are plain { x, y, z } tables and time is passed in.
-- A State tracks every item lying in the world, who may take it and when it despawns, plus a
-- per-player cooldown. Functions modify the State you pass and return explicit results.

export type Vec3 = { x: number, y: number, z: number }

export type Config = {
	maxDistance: number, -- studs between the player and the item (default 12)
	cooldown: number, -- seconds between pickups by one player (default 0.2)
	ownershipSeconds: number, -- only the owner may take a dropped item for this long (default 10)
	despawnSeconds: number, -- items vanish after this long; 0 keeps them forever (default 120)
	maxCount: number, -- largest stack one world item can hold (default 1000)
}

export type WorldItem = {
	uid: number, -- unique id within this State
	itemId: string, -- item definition id
	count: number, -- items left in the pile
	position: Vec3, -- where it lies
	ownerId: number?, -- userId with priority, if any
	ownerUntil: number?, -- end of the ownership window
	despawnAt: number?, -- when the item disappears, nil for never
}

export type State = {
	config: Config, -- resolved configuration
	items: { [number]: WorldItem }, -- uid -> item
	nextUid: number, -- next uid to hand out
	cooldowns: { [number]: number }, -- userId -> time the next pickup is allowed
}

export type PickupResult = {
	ok: boolean, -- whether anything was picked up
	reason: string?, -- why not
	taken: number, -- items moved into the inventory
	remaining: number, -- items still on the ground (0 means the world item is gone)
	removed: boolean, -- true when the world item no longer exists
}

-- Gives `count` of `itemId` to the player and returns how many did not fit.
export type Give = (itemId: string, count: number) -> number

local PickupLogic = {}

local DEFAULTS: Config = {
	maxDistance = 12,
	cooldown = 0.2,
	ownershipSeconds = 10,
	despawnSeconds = 120,
	maxCount = 1000,
}

PickupLogic.DEFAULTS = table.freeze(table.clone(DEFAULTS))

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isCount(value: any): boolean
	return isFinite(value) and value >= 1 and value % 1 == 0
end

local function isVec3(value: any): boolean
	return type(value) == "table" and isFinite(value.x) and isFinite(value.y) and isFinite(value.z)
end

local function option(overrides: { [string]: any }, key: string, default: number): number
	local value = overrides[key]
	if value == nil then
		return default
	end
	assert(isFinite(value) and value >= 0, key .. " must be a number >= 0")
	return value
end

function PickupLogic.new(overrides: { [string]: any }?): State
	local given = overrides or {}
	local config: Config = {
		maxDistance = option(given, "maxDistance", DEFAULTS.maxDistance),
		cooldown = option(given, "cooldown", DEFAULTS.cooldown),
		ownershipSeconds = option(given, "ownershipSeconds", DEFAULTS.ownershipSeconds),
		despawnSeconds = option(given, "despawnSeconds", DEFAULTS.despawnSeconds),
		maxCount = math.max(1, math.floor(option(given, "maxCount", DEFAULTS.maxCount))),
	}
	return { config = config, items = {}, nextUid = 1, cooldowns = {} }
end

function PickupLogic.distance(a: Vec3, b: Vec3): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Adds an item to the world. `ownerId` (a userId) gets the ownership window, for drops.
-- Returns the new uid, or nil and a reason for invalid input.
function PickupLogic.spawn(
	state: State,
	itemId: string,
	count: number,
	position: Vec3,
	now: number,
	ownerId: number?
): (number?, string?)
	if type(itemId) ~= "string" or itemId == "" then
		return nil, "invalid item"
	end
	if not isCount(count) or count > state.config.maxCount then
		return nil, "invalid count"
	end
	if not isVec3(position) or not isFinite(now) then
		return nil, "invalid input"
	end
	local uid = state.nextUid
	state.nextUid += 1
	local config = state.config
	state.items[uid] = {
		uid = uid,
		itemId = itemId,
		count = count,
		position = { x = position.x, y = position.y, z = position.z },
		ownerId = ownerId,
		ownerUntil = if ownerId ~= nil then now + config.ownershipSeconds else nil,
		despawnAt = if config.despawnSeconds > 0 then now + config.despawnSeconds else nil,
	}
	return uid, nil
end

function PickupLogic.get(state: State, uid: number): WorldItem?
	return state.items[uid]
end

function PickupLogic.remove(state: State, uid: number): boolean
	if state.items[uid] == nil then
		return false
	end
	state.items[uid] = nil
	return true
end

-- Checks every rule without changing anything.
function PickupLogic.canPickup(
	state: State,
	uid: number,
	userId: number,
	playerPosition: Vec3,
	now: number
): (boolean, string?)
	local item = state.items[uid]
	if item == nil then
		return false, "no such item"
	end
	if not isVec3(playerPosition) or not isFinite(now) then
		return false, "invalid input"
	end
	local despawnAt = item.despawnAt
	if despawnAt ~= nil and now >= despawnAt then
		return false, "despawned"
	end
	local ownerUntil = item.ownerUntil
	if item.ownerId ~= nil and item.ownerId ~= userId and ownerUntil ~= nil and now < ownerUntil then
		return false, "owned by another player"
	end
	if PickupLogic.distance(item.position, playerPosition) > state.config.maxDistance then
		return false, "too far"
	end
	local readyAt = state.cooldowns[userId]
	if readyAt ~= nil and now < readyAt then
		return false, "cooldown"
	end
	return true, nil
end

-- Picks up as much as fits. `give` moves items into the inventory and returns the leftover.
-- A full inventory is "inventory full" and starts no cooldown.
function PickupLogic.pickup(
	state: State,
	uid: number,
	userId: number,
	playerPosition: Vec3,
	now: number,
	give: Give
): PickupResult
	local allowed, reason = PickupLogic.canPickup(state, uid, userId, playerPosition, now)
	local item = state.items[uid]
	if not allowed or item == nil then
		local left = if item then item.count else 0
		return { ok = false, reason = reason, taken = 0, remaining = left, removed = item == nil }
	end
	local leftover = give(item.itemId, item.count)
	if not isFinite(leftover) or leftover < 0 then
		leftover = item.count
	end
	leftover = math.min(math.floor(leftover), item.count)
	local taken = item.count - leftover
	if taken == 0 then
		return { ok = false, reason = "inventory full", taken = 0, remaining = item.count, removed = false }
	end
	state.cooldowns[userId] = now + state.config.cooldown
	if leftover == 0 then
		state.items[uid] = nil
		return { ok = true, reason = nil, taken = taken, remaining = 0, removed = true }
	end
	item.count = leftover
	return { ok = true, reason = nil, taken = taken, remaining = leftover, removed = false }
end

-- Removes every item whose despawn time has passed and returns their uids in ascending order.
function PickupLogic.expire(state: State, now: number): { number }
	local expired: { number } = {}
	for uid, item in state.items do
		local despawnAt = item.despawnAt
		if despawnAt ~= nil and now >= despawnAt then
			table.insert(expired, uid)
		end
	end
	table.sort(expired)
	for _, uid in expired do
		state.items[uid] = nil
	end
	return expired
end

-- Drops cooldown entries that have run out, so the table does not grow forever.
function PickupLogic.pruneCooldowns(state: State, now: number)
	for userId, readyAt in state.cooldowns do
		if now >= readyAt then
			state.cooldowns[userId] = nil
		end
	end
end

-- Items within `radius` of `position`, nearest first.
function PickupLogic.nearby(state: State, position: Vec3, radius: number): { WorldItem }
	local found: { WorldItem } = {}
	for _, item in state.items do
		if PickupLogic.distance(item.position, position) <= radius then
			table.insert(found, item)
		end
	end
	table.sort(found, function(a: WorldItem, b: WorldItem): boolean
		local da, db = PickupLogic.distance(a.position, position), PickupLogic.distance(b.position, position)
		if da ~= db then
			return da < db
		end
		return a.uid < b.uid
	end)
	return found
end

return PickupLogic
