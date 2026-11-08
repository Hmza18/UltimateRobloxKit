--!strict
-- Gatherable resource nodes (trees, rocks, ore). Pure Luau. Nodes have health, a weighted yield
-- table rolled with an injected random source, a respawn time and a minimum tool tier.
-- Nodes are immutable values; the per-player cooldown table is modified in place.

export type YieldEntry = {
	id: string, -- item id dropped
	weight: number, -- relative chance, > 0
	min: number?, -- smallest count per roll (default 1)
	max: number?, -- largest count per roll (default min)
}

export type NodeDefInput = {
	kind: string, -- unique node kind, such as "OakTree"
	maxHealth: number, -- damage needed to deplete it
	yield: { YieldEntry }, -- what it drops
	rolls: number?, -- yield rolls per drop event (default 1)
	respawnSeconds: number?, -- seconds until a depleted node returns (default 30)
	minTier: number?, -- lowest tool tier that can damage it (default 0)
	dropOnHit: boolean?, -- roll drops on every hit instead of only when depleted (default false)
}

export type Entry = { id: string, weight: number, min: number, max: number }

export type NodeDef = {
	kind: string, -- node kind
	maxHealth: number, -- full health
	yield: { Entry }, -- normalized yield table
	totalWeight: number, -- sum of weights
	rolls: number, -- rolls per drop event
	respawnSeconds: number, -- respawn delay
	minTier: number, -- lowest tool tier
	dropOnHit: boolean, -- drops per hit
}

export type Defs = { kinds: { [string]: NodeDef } }

export type Node = { kind: string, health: number, respawnAt: number? }

export type Tool = { tier: number, damage: number }

export type Drop = { id: string, count: number }

export type Options = { tierBonus: number?, rolls: number? }

export type HitResult = {
	ok: boolean, -- whether the hit landed
	reason: string?, -- why not
	node: Node, -- node after the hit (unchanged on failure)
	damage: number, -- damage dealt
	depleted: boolean, -- true when this hit depleted the node
	drops: { Drop }, -- items to give, merged by id
}

export type Cooldowns = { [string]: number }

local ResourcesLogic = {}

ResourcesLogic.DEFAULT_RESPAWN = 30
-- Each tier above the node's minimum adds this fraction of the tool's damage.
ResourcesLogic.DEFAULT_TIER_BONUS = 0.25

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isCount(value: any): boolean
	return isFinite(value) and value >= 1 and value % 1 == 0
end

function ResourcesLogic.newDefs(inputs: { NodeDefInput }): Defs
	assert(type(inputs) == "table", "inputs must be an array")
	local kinds: { [string]: NodeDef } = {}
	for _, input in inputs do
		local kind = input.kind
		assert(type(kind) == "string" and kind ~= "", "kind must be a non-empty string")
		assert(kinds[kind] == nil, "duplicate kind " .. kind)
		assert(isFinite(input.maxHealth) and input.maxHealth > 0, "maxHealth must be > 0 for " .. kind)
		local rolls = input.rolls or 1
		assert(isCount(rolls), "rolls must be a positive integer for " .. kind)
		local respawn = input.respawnSeconds or ResourcesLogic.DEFAULT_RESPAWN
		assert(isFinite(respawn) and respawn >= 0, "respawnSeconds must be >= 0 for " .. kind)
		local minTier = input.minTier or 0
		assert(isFinite(minTier), "minTier must be a number for " .. kind)
		assert(type(input.yield) == "table", "yield must be an array for " .. kind)
		local entries: { Entry } = {}
		local total = 0
		for _, entry in input.yield do
			assert(type(entry.id) == "string" and entry.id ~= "", "yield ids must be strings for " .. kind)
			assert(isFinite(entry.weight) and entry.weight > 0, "yield weights must be > 0 for " .. kind)
			local min = entry.min or 1
			local max = entry.max or min
			assert(isCount(min) and isCount(max) and max >= min, "yield counts must be 1 <= min <= max for " .. kind)
			table.insert(entries, { id = entry.id, weight = entry.weight, min = min, max = max })
			total += entry.weight
		end
		kinds[kind] = {
			kind = kind,
			maxHealth = input.maxHealth,
			yield = entries,
			totalWeight = total,
			rolls = rolls,
			respawnSeconds = respawn,
			minTier = minTier,
			dropOnHit = input.dropOnHit == true,
		}
	end
	return { kinds = kinds }
end

function ResourcesLogic.getDef(defs: Defs, kind: string): NodeDef?
	return defs.kinds[kind]
end

function ResourcesLogic.newNode(defs: Defs, kind: string): Node
	local def = defs.kinds[kind]
	assert(def ~= nil, "unknown node kind " .. tostring(kind))
	return { kind = kind, health = def.maxHealth, respawnAt = nil }
end

-- True when the node has health, or its respawn time has passed.
function ResourcesLogic.isAvailable(node: Node, now: number): boolean
	if node.health > 0 then
		return true
	end
	local respawnAt = node.respawnAt
	return respawnAt ~= nil and now >= respawnAt
end

-- Returns the node at full health if its respawn time has passed, otherwise the same node.
function ResourcesLogic.refresh(defs: Defs, node: Node, now: number): Node
	local respawnAt = node.respawnAt
	if node.health > 0 or respawnAt == nil or now < respawnAt then
		return node
	end
	local def = defs.kinds[node.kind]
	if def == nil then
		return node
	end
	return { kind = node.kind, health = def.maxHealth, respawnAt = nil }
end

-- Damage a tool deals to a node kind: 0 below the minimum tier, then +tierBonus per tier above it.
function ResourcesLogic.damageFor(def: NodeDef, tool: Tool, tierBonus: number?): number
	if type(tool) ~= "table" or not isFinite(tool.tier) or not isFinite(tool.damage) or tool.damage <= 0 then
		return 0
	end
	if tool.tier < def.minTier then
		return 0
	end
	local bonus = tierBonus or ResourcesLogic.DEFAULT_TIER_BONUS
	return tool.damage * (1 + (tool.tier - def.minTier) * bonus)
end

local function random01(rng: () -> number): number
	local value = rng()
	if not isFinite(value) then
		return 0
	end
	return math.clamp(value, 0, 1)
end

-- Rolls the yield table `rolls` times (default: the definition's rolls). `rng` returns [0, 1).
-- Drops are merged by item id in the order they first appear.
function ResourcesLogic.rollYield(def: NodeDef, rng: () -> number, rolls: number?): { Drop }
	local drops: { Drop } = {}
	if def.totalWeight <= 0 then
		return drops
	end
	local byId: { [string]: Drop } = {}
	for _ = 1, rolls or def.rolls do
		local target = random01(rng) * def.totalWeight
		local chosen = def.yield[#def.yield]
		local cumulative = 0
		for _, entry in def.yield do
			cumulative += entry.weight
			if target < cumulative then
				chosen = entry
				break
			end
		end
		local span = chosen.max - chosen.min + 1
		local count = math.min(chosen.min + math.floor(random01(rng) * span), chosen.max)
		local existing = byId[chosen.id]
		if existing then
			existing.count += count
		else
			local drop = { id = chosen.id, count = count }
			byId[chosen.id] = drop
			table.insert(drops, drop)
		end
	end
	return drops
end

-- Hits a node with a tool. Refreshes it first, so a node whose respawn time passed is whole again.
function ResourcesLogic.hit(
	defs: Defs,
	node: Node,
	tool: Tool,
	now: number,
	rng: () -> number,
	options: Options?
): HitResult
	local def = defs.kinds[node.kind]
	if def == nil then
		return { ok = false, reason = "unknown kind", node = node, damage = 0, depleted = false, drops = {} }
	end
	if not isFinite(now) then
		return { ok = false, reason = "invalid time", node = node, damage = 0, depleted = false, drops = {} }
	end
	local current = ResourcesLogic.refresh(defs, node, now)
	if current.health <= 0 then
		return { ok = false, reason = "depleted", node = current, damage = 0, depleted = false, drops = {} }
	end
	local opts: Options = options or {}
	local damage = ResourcesLogic.damageFor(def, tool, opts.tierBonus)
	if damage <= 0 then
		return { ok = false, reason = "tool tier too low", node = current, damage = 0, depleted = false, drops = {} }
	end
	local health = math.max(current.health - damage, 0)
	local depleted = health == 0
	local respawnAt = if depleted then now + def.respawnSeconds else nil
	local drops: { Drop } = {}
	if def.dropOnHit or depleted then
		drops = ResourcesLogic.rollYield(def, rng, opts.rolls)
	end
	local nextNode: Node = { kind = current.kind, health = health, respawnAt = respawnAt }
	return { ok = true, reason = nil, node = nextNode, damage = damage, depleted = depleted, drops = drops }
end

-- Per-player (or per player and node) gather cooldown. `key` is any string you choose.
function ResourcesLogic.ready(cooldowns: Cooldowns, key: string, now: number): boolean
	local readyAt = cooldowns[key]
	return readyAt == nil or now >= readyAt
end

-- Starts a cooldown of `seconds` for `key`. Modifies `cooldowns`.
function ResourcesLogic.markCooldown(cooldowns: Cooldowns, key: string, now: number, seconds: number)
	cooldowns[key] = now + math.max(seconds, 0)
end

-- Forgets finished cooldowns. Modifies `cooldowns`.
function ResourcesLogic.pruneCooldowns(cooldowns: Cooldowns, now: number)
	for key, readyAt in cooldowns do
		if now >= readyAt then
			cooldowns[key] = nil
		end
	end
end

-- Seeded random source for tests and deterministic simulations (a small LCG). On Roblox pass
-- `function() return rng:NextNumber() end` with a Random object instead.
function ResourcesLogic.seededRng(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % 2147483647
	if state == 0 then
		state = 1
	end
	local function nextValue(): number
		state = state * 48271 % 2147483647
		return (state - 1) / 2147483646
	end
	return nextValue
end

return ResourcesLogic
