--!strict
-- Pets and eggs. Pure Luau: randomness is injected (rng() -> [0, 1)), ids come from a counter in
-- the state, and every operation returns a new state. The server owns all of it; clients only send
-- intents (hatch this egg, equip this pet id).
--
-- Features: weighted egg tables with rarity, pity (guaranteed rarity after N misses), multi-hatch,
-- luck multipliers that favour rarer entries, inventory capacity, equip slots, locking, deleting,
-- fusing duplicates into a higher tier (normal -> golden -> rainbow), total multipliers, odds
-- display data and safe (de)serialization.

export type Rarity = { name: string, rank: number, color: string? }

export type EggEntry = { pet: string, weight: number }

export type EggDef = {
	cost: { [string]: number }?, -- currency costs per hatch, charged by the server adapter
	entries: { EggEntry },
	pity: { rarity: string, after: number }?, -- guarantee this rarity (or better) after N misses
	world: string?, -- optional world that must be unlocked (checked by the server adapter)
}

export type PetDef = { rarity: string, multiplier: number, tradeable: boolean? }

export type Config = {
	rarities: { Rarity },
	pets: { [string]: PetDef },
	eggs: { [string]: EggDef },
	capacity: number?, -- pets kept (default 100)
	equipSlots: number?, -- pets equipped at once (default 3)
	tiers: { { name: string, multiplier: number, fuse: number } }?, -- default normal/golden/rainbow
}

export type Pet = { id: string, kind: string, tier: number, locked: boolean? }

export type State = {
	pets: { [string]: Pet },
	equipped: { string },
	nextId: number,
	pity: { [string]: number }, -- misses since the egg's pity rarity per egg
	hatched: number,
}

export type Result = { ok: boolean, reason: string?, state: State }
export type HatchResult = { ok: boolean, reason: string?, state: State, pets: { Pet } }

local PetsLogic = {}

PetsLogic.SAVE_VERSION = 1
PetsLogic.MAX_HATCH = 10
PetsLogic.DEFAULT_TIERS = {
	{ name = "Normal", multiplier = 1, fuse = 0 },
	{ name = "Golden", multiplier = 2.5, fuse = 5 },
	{ name = "Rainbow", multiplier = 6, fuse = 5 },
}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function rankOf(config: Config, rarity: string): number
	for _, r in config.rarities do
		if r.name == rarity then
			return r.rank
		end
	end
	return 0
end

local function tiersOf(config: Config): { { name: string, multiplier: number, fuse: number } }
	return config.tiers or PetsLogic.DEFAULT_TIERS
end

local function copyState(state: State): State
	return {
		pets = table.clone(state.pets),
		equipped = table.clone(state.equipped),
		nextId = state.nextId,
		pity = table.clone(state.pity),
		hatched = state.hatched,
	}
end

function PetsLogic.validateConfig(config: Config): Config
	assert(type(config) == "table", "config must be a table")
	assert(type(config.rarities) == "table" and #config.rarities > 0, "rarities required")
	local rarityNames: { [string]: boolean } = {}
	for _, r in config.rarities do
		assert(type(r.name) == "string" and isFinite(r.rank), "each rarity needs name and rank")
		rarityNames[r.name] = true
	end
	assert(type(config.pets) == "table", "pets required")
	for name, def in config.pets do
		assert(rarityNames[def.rarity], "pet " .. name .. " has unknown rarity " .. tostring(def.rarity))
		assert(isFinite(def.multiplier) and def.multiplier >= 0, "pet " .. name .. " needs a multiplier >= 0")
	end
	assert(type(config.eggs) == "table", "eggs required")
	for name, egg in config.eggs do
		assert(type(egg.entries) == "table" and #egg.entries > 0, "egg " .. name .. " needs entries")
		local total = 0
		for _, entry in egg.entries do
			assert(config.pets[entry.pet] ~= nil, "egg " .. name .. " lists unknown pet " .. tostring(entry.pet))
			assert(isFinite(entry.weight) and entry.weight > 0, "egg " .. name .. " has a bad weight")
			total += entry.weight
		end
		assert(total > 0, "egg " .. name .. " has zero total weight")
		if egg.pity then
			assert(rarityNames[egg.pity.rarity], "egg " .. name .. " pity rarity unknown")
			assert(isFinite(egg.pity.after) and egg.pity.after >= 1, "egg " .. name .. " pity.after must be >= 1")
			local reachable = false
			for _, entry in egg.entries do
				if rankOf(config, config.pets[entry.pet].rarity) >= rankOf(config, egg.pity.rarity) then
					reachable = true
				end
			end
			assert(reachable, "egg " .. name .. " pity rarity is not in the egg")
		end
	end
	local capacity, slots = config.capacity, config.equipSlots
	assert(capacity == nil or isFinite(capacity) and capacity >= 1, "capacity must be >= 1")
	assert(slots == nil or isFinite(slots) and slots >= 0, "equipSlots must be >= 0")
	for i, tier in tiersOf(config) do
		assert(isFinite(tier.multiplier) and tier.multiplier > 0, "tier multiplier must be > 0")
		assert(i == 1 or isFinite(tier.fuse) and tier.fuse >= 2, "fuse counts must be >= 2")
	end
	return config
end

function PetsLogic.newState(): State
	return { pets = {}, equipped = {}, nextId = 1, pity = {}, hatched = 0 }
end

function PetsLogic.count(state: State): number
	local n = 0
	for _ in state.pets do
		n += 1
	end
	return n
end

-- Effective weights for an egg with a luck multiplier: luck >= 1 multiplies the weight of every
-- entry above the egg's most common rarity by `luck`, so rare odds rise and common odds fall.
function PetsLogic.weights(config: Config, eggName: string, luck: number?): { EggEntry }
	local egg = config.eggs[eggName]
	assert(egg ~= nil, "unknown egg " .. tostring(eggName))
	local factor = if isFinite(luck) and (luck :: number) > 1 then luck :: number else 1
	local lowest = math.huge
	for _, entry in egg.entries do
		lowest = math.min(lowest, rankOf(config, config.pets[entry.pet].rarity))
	end
	local result: { EggEntry } = {}
	for _, entry in egg.entries do
		local rank = rankOf(config, config.pets[entry.pet].rarity)
		local weight = if rank > lowest then entry.weight * factor else entry.weight
		table.insert(result, { pet = entry.pet, weight = weight })
	end
	return result
end

-- Odds per pet in 0..1, for the egg preview UI. Same order as the egg's entries.
function PetsLogic.odds(
	config: Config,
	eggName: string,
	luck: number?
): { { pet: string, chance: number, rarity: string } }
	local weights = PetsLogic.weights(config, eggName, luck)
	local total = 0
	for _, entry in weights do
		total += entry.weight
	end
	local result = {}
	for _, entry in weights do
		table.insert(result, { pet = entry.pet, chance = entry.weight / total, rarity = config.pets[entry.pet].rarity })
	end
	return result
end

local function pick(entries: { EggEntry }, roll: number): string
	local total = 0
	for _, entry in entries do
		total += entry.weight
	end
	local target = math.clamp(roll, 0, 0.999999999) * total
	local running = 0
	for _, entry in entries do
		running += entry.weight
		if target < running then
			return entry.pet
		end
	end
	return entries[#entries].pet
end

-- Hatches `amount` pets (1..MAX_HATCH) from an egg. Does not charge currency: the server adapter
-- charges first, then calls this. Fails without changes when there is no room.
function PetsLogic.hatch(
	config: Config,
	state: State,
	eggName: string,
	amount: number,
	rng: () -> number,
	luck: number?
): HatchResult
	local egg = config.eggs[eggName]
	if egg == nil then
		return { ok = false, reason = "unknown egg", state = state, pets = {} }
	end
	if not isFinite(amount) or amount < 1 or amount > PetsLogic.MAX_HATCH or amount % 1 ~= 0 then
		return { ok = false, reason = "invalid amount", state = state, pets = {} }
	end
	local capacity = config.capacity or 100
	if PetsLogic.count(state) + amount > capacity then
		return { ok = false, reason = "inventory full", state = state, pets = {} }
	end
	local weights = PetsLogic.weights(config, eggName, luck)
	local pityRank = if egg.pity then rankOf(config, egg.pity.rarity) else math.huge
	local pityWeights: { EggEntry } = {}
	for _, entry in weights do
		if rankOf(config, config.pets[entry.pet].rarity) >= pityRank then
			table.insert(pityWeights, entry)
		end
	end
	local nextState = copyState(state)
	local hatched: { Pet } = {}
	for _ = 1, amount do
		local misses = nextState.pity[eggName] or 0
		local useP = egg.pity ~= nil and misses + 1 >= (egg.pity :: any).after
		local kind = pick(if useP then pityWeights else weights, rng())
		local rank = rankOf(config, config.pets[kind].rarity)
		nextState.pity[eggName] = if rank >= pityRank then 0 else misses + 1
		local pet: Pet = { id = tostring(nextState.nextId), kind = kind, tier = 1 }
		nextState.nextId += 1
		nextState.pets[pet.id] = pet
		nextState.hatched += 1
		table.insert(hatched, pet)
	end
	return { ok = true, reason = nil, state = nextState, pets = hatched }
end

-- Adds a specific pet (rewards, codes, admin). Same capacity rule as hatching.
function PetsLogic.give(config: Config, state: State, kind: string, tier: number?): HatchResult
	if config.pets[kind] == nil then
		return { ok = false, reason = "unknown pet", state = state, pets = {} }
	end
	local t = tier or 1
	if t < 1 or t > #tiersOf(config) or t % 1 ~= 0 then
		return { ok = false, reason = "invalid tier", state = state, pets = {} }
	end
	if PetsLogic.count(state) >= (config.capacity or 100) then
		return { ok = false, reason = "inventory full", state = state, pets = {} }
	end
	local nextState = copyState(state)
	local pet: Pet = { id = tostring(nextState.nextId), kind = kind, tier = t }
	nextState.nextId += 1
	nextState.pets[pet.id] = pet
	return { ok = true, reason = nil, state = nextState, pets = { pet } }
end

function PetsLogic.isEquipped(state: State, id: string): boolean
	return table.find(state.equipped, id) ~= nil
end

function PetsLogic.equip(config: Config, state: State, id: string): Result
	if state.pets[id] == nil then
		return { ok = false, reason = "unknown pet", state = state }
	end
	if PetsLogic.isEquipped(state, id) then
		return { ok = false, reason = "already equipped", state = state }
	end
	if #state.equipped >= (config.equipSlots or 3) then
		return { ok = false, reason = "no free slot", state = state }
	end
	local nextState = copyState(state)
	table.insert(nextState.equipped, id)
	return { ok = true, reason = nil, state = nextState }
end

function PetsLogic.unequip(state: State, id: string): Result
	local index = table.find(state.equipped, id)
	if index == nil then
		return { ok = false, reason = "not equipped", state = state }
	end
	local nextState = copyState(state)
	table.remove(nextState.equipped, index)
	return { ok = true, reason = nil, state = nextState }
end

local function totalMultiplierOf(config: Config, pet: Pet): number
	local tier = tiersOf(config)[pet.tier] or tiersOf(config)[1]
	return config.pets[pet.kind].multiplier * tier.multiplier
end

-- Equips the best pets by multiplier (ties: lower id first), replacing the current selection.
function PetsLogic.equipBest(config: Config, state: State): Result
	local list: { Pet } = {}
	for _, pet in state.pets do
		if config.pets[pet.kind] then
			table.insert(list, pet)
		end
	end
	table.sort(list, function(a: Pet, b: Pet): boolean
		local ma, mb = totalMultiplierOf(config, a), totalMultiplierOf(config, b)
		if ma ~= mb then
			return ma > mb
		end
		return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
	end)
	local nextState = copyState(state)
	nextState.equipped = {}
	for i = 1, math.min(#list, config.equipSlots or 3) do
		table.insert(nextState.equipped, list[i].id)
	end
	return { ok = true, reason = nil, state = nextState }
end

function PetsLogic.setLocked(state: State, id: string, locked: boolean): Result
	local pet = state.pets[id]
	if pet == nil then
		return { ok = false, reason = "unknown pet", state = state }
	end
	local nextState = copyState(state)
	local copy = table.clone(pet)
	copy.locked = if locked then true else nil
	nextState.pets[id] = copy
	return { ok = true, reason = nil, state = nextState }
end

-- Deletes pets by id, all or nothing. Locked pets refuse; deleting unequips.
function PetsLogic.delete(state: State, ids: { string }): Result
	for _, id in ids do
		local pet = state.pets[id]
		if pet == nil then
			return { ok = false, reason = "unknown pet", state = state }
		end
		if pet.locked then
			return { ok = false, reason = "pet is locked", state = state }
		end
	end
	local nextState = copyState(state)
	for _, id in ids do
		nextState.pets[id] = nil
		local index = table.find(nextState.equipped, id)
		if index then
			table.remove(nextState.equipped, index)
		end
	end
	return { ok = true, reason = nil, state = nextState }
end

-- Fuses N pets of the same kind and tier into one pet of the next tier. N is the next tier's
-- `fuse` count. The result keeps the first id and is equipped if any input was.
function PetsLogic.fuse(config: Config, state: State, ids: { string }): HatchResult
	local tiers = tiersOf(config)
	local first = state.pets[ids[1] or ""]
	if first == nil then
		return { ok = false, reason = "unknown pet", state = state, pets = {} }
	end
	local nextTier = tiers[first.tier + 1]
	if nextTier == nil then
		return { ok = false, reason = "max tier", state = state, pets = {} }
	end
	if #ids ~= nextTier.fuse then
		return { ok = false, reason = "need " .. nextTier.fuse .. " pets", state = state, pets = {} }
	end
	local seen: { [string]: boolean } = {}
	local wasEquipped = false
	for _, id in ids do
		local pet = state.pets[id]
		if pet == nil or seen[id] then
			return { ok = false, reason = "unknown pet", state = state, pets = {} }
		end
		if pet.kind ~= first.kind or pet.tier ~= first.tier then
			return { ok = false, reason = "pets must match", state = state, pets = {} }
		end
		if pet.locked then
			return { ok = false, reason = "pet is locked", state = state, pets = {} }
		end
		seen[id] = true
		wasEquipped = wasEquipped or PetsLogic.isEquipped(state, id)
	end
	local deleted = PetsLogic.delete(state, ids)
	local nextState = deleted.state
	local fused: Pet = { id = first.id, kind = first.kind, tier = first.tier + 1 }
	nextState.pets[fused.id] = fused
	if wasEquipped and #nextState.equipped < (config.equipSlots or 3) then
		table.insert(nextState.equipped, fused.id)
	end
	return { ok = true, reason = nil, state = nextState, pets = { fused } }
end

function PetsLogic.multiplierOf(config: Config, pet: Pet): number
	if config.pets[pet.kind] == nil then
		return 0
	end
	return totalMultiplierOf(config, pet)
end

-- Sum of equipped multipliers, plus 1 so no pets means x1.
function PetsLogic.totalMultiplier(config: Config, state: State): number
	local total = 1
	for _, id in state.equipped do
		local pet = state.pets[id]
		if pet then
			total += PetsLogic.multiplierOf(config, pet)
		end
	end
	return total
end

function PetsLogic.isTradeable(config: Config, pet: Pet): boolean
	local def = config.pets[pet.kind]
	return def ~= nil and def.tradeable ~= false and not pet.locked
end

-- Replaces pets owned by this state (used by Trading after a completed swap): removes `give` ids
-- and adds `receive` pets with fresh ids. Fails if capacity would be exceeded.
function PetsLogic.exchange(config: Config, state: State, give: { string }, receive: { Pet }): HatchResult
	for _, id in give do
		if state.pets[id] == nil then
			return { ok = false, reason = "unknown pet", state = state, pets = {} }
		end
	end
	if PetsLogic.count(state) - #give + #receive > (config.capacity or 100) then
		return { ok = false, reason = "inventory full", state = state, pets = {} }
	end
	local nextState = copyState(state)
	for _, id in give do
		nextState.pets[id] = nil
		local index = table.find(nextState.equipped, id)
		if index then
			table.remove(nextState.equipped, index)
		end
	end
	local added: { Pet } = {}
	for _, incoming in receive do
		local pet: Pet = { id = tostring(nextState.nextId), kind = incoming.kind, tier = incoming.tier }
		nextState.nextId += 1
		nextState.pets[pet.id] = pet
		table.insert(added, pet)
	end
	return { ok = true, reason = nil, state = nextState, pets = added }
end

function PetsLogic.serialize(state: State): { [string]: any }
	local pets = {}
	for _, pet in state.pets do
		table.insert(pets, { pet.id, pet.kind, pet.tier, if pet.locked then 1 else 0 })
	end
	table.sort(pets, function(a: { any }, b: { any }): boolean
		return (tonumber(a[1]) or 0) < (tonumber(b[1]) or 0)
	end)
	return {
		v = PetsLogic.SAVE_VERSION,
		p = pets,
		e = table.clone(state.equipped),
		n = state.nextId,
		y = table.clone(state.pity),
		h = state.hatched,
	}
end

-- Rebuilds state from untrusted data: unknown kinds and bad tiers are dropped, equipped ids must
-- exist and fit the slots, nextId stays above every id, counters are clamped.
function PetsLogic.deserialize(config: Config, raw: any): State
	local state = PetsLogic.newState()
	if type(raw) ~= "table" or type(raw.p) ~= "table" then
		return state
	end
	local maxTier = #tiersOf(config)
	local highest = 0
	local capacity = config.capacity or 100
	for _, row in raw.p do
		if type(row) == "table" and PetsLogic.count(state) < capacity then
			local id, kind, tier = row[1], row[2], row[3]
			local numericId = tonumber(id)
			if
				type(id) == "string"
				and numericId
				and type(kind) == "string"
				and config.pets[kind]
				and isFinite(tier)
				and tier >= 1
				and tier <= maxTier
				and tier % 1 == 0
				and state.pets[id] == nil
			then
				state.pets[id] = { id = id, kind = kind, tier = tier, locked = if row[4] == 1 then true else nil }
				highest = math.max(highest, numericId)
			end
		end
	end
	if type(raw.e) == "table" then
		for _, id in raw.e do
			if type(id) == "string" and state.pets[id] and not table.find(state.equipped, id) then
				if #state.equipped < (config.equipSlots or 3) then
					table.insert(state.equipped, id)
				end
			end
		end
	end
	state.nextId = math.max(if isFinite(raw.n) then math.floor(raw.n) else 1, highest + 1)
	if type(raw.y) == "table" then
		for egg, misses in raw.y do
			if type(egg) == "string" and config.eggs[egg] and isFinite(misses) and misses >= 0 then
				state.pity[egg] = math.floor(misses)
			end
		end
	end
	state.hatched = if isFinite(raw.h) and raw.h >= 0 then math.floor(raw.h) else 0
	return state
end

return PetsLogic
