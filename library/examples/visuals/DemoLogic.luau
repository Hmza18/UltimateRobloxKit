--!strict
-- Pure maths and sample data for the UltimateVisualsKit demos. No Roblox types: points are plain
-- { x, y, z } tables, so library/tests/visuals_demos.spec.luau can check everything under Lune.
--
-- Everything named here is original demo content. Nothing in this module (or in the demos) is
-- authoritative: the "server" functions are local stand-ins that only decide what to show.

export type Vec3 = { x: number, y: number, z: number }

export type Arc = {
	start: Vec3,
	target: Vec3,
	apex: number, -- world height of the highest point
	flightTime: number, -- seconds from start to target
	peakTime: number, -- seconds from start to the highest point
	gravity: number, -- studs per second squared, positive
	launchSpeed: number, -- vertical speed at the start (studs per second, up is positive)
}

export type Stat = { label: string, value: string | number }

export type DemoPet = {
	id: string,
	name: string,
	description: string,
	rarity: string,
	color: string,
	variant: number,
	stats: { Stat },
}

export type Food = {
	id: string,
	name: string,
	color: string,
	shape: string,
	hunger: number,
	happiness: number,
	coins: number,
}

export type Animal = { id: string, name: string, color: string, accent: string, kind: string }

export type Needs = { hunger: number, happiness: number }

local DemoLogic = {}

DemoLogic.GRAVITY = 70

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function DemoLogic.vec(x: number, y: number, z: number): Vec3
	return { x = x, y = y, z = z }
end

function DemoLogic.distance(a: Vec3, b: Vec3): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Distance ignoring height: what "did the food land next to the animal" means.
function DemoLogic.flatDistance(a: Vec3, b: Vec3): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

-- Ballistics -----------------------------------------------------------------------------------

-- A throw from `start` to `target` whose highest point is `apexHeight` studs above the higher of
-- the two ends. The flight time follows from gravity, so a higher lob takes longer.
function DemoLogic.arc(start: Vec3, target: Vec3, apexHeight: number, gravity: number?): Arc
	local g = if gravity and finite(gravity) and gravity > 0 then gravity else DemoLogic.GRAVITY
	local lift = math.max(0.05, if finite(apexHeight) then apexHeight else 0.05)
	local apex = math.max(start.y, target.y) + lift
	local rise = math.sqrt(2 * (apex - start.y) / g)
	local fall = math.sqrt(2 * (apex - target.y) / g)
	return {
		start = start,
		target = target,
		apex = apex,
		flightTime = rise + fall,
		peakTime = rise,
		gravity = g,
		launchSpeed = g * rise,
	}
end

-- The same throw described by how long it should take. A time too short to rise at all gives a
-- flat throw whose highest point is the higher end.
function DemoLogic.arcForTime(start: Vec3, target: Vec3, flightTime: number, gravity: number?): Arc
	local g = if gravity and finite(gravity) and gravity > 0 then gravity else DemoLogic.GRAVITY
	local total = math.max(0.05, if finite(flightTime) then flightTime else 0.05)
	local launch = (target.y - start.y + 0.5 * g * total * total) / total
	local peakTime = math.clamp(launch / g, 0, total)
	local apex = start.y + launch * peakTime - 0.5 * g * peakTime * peakTime
	return {
		start = start,
		target = target,
		apex = math.max(apex, start.y, target.y),
		flightTime = total,
		peakTime = peakTime,
		gravity = g,
		launchSpeed = launch,
	}
end

-- Position `t` seconds into the throw (clamped to the flight).
function DemoLogic.arcPoint(arc: Arc, t: number): Vec3
	local time = math.clamp(t, 0, arc.flightTime)
	local alpha = time / arc.flightTime
	if time >= arc.flightTime then
		return { x = arc.target.x, y = arc.target.y, z = arc.target.z }
	end
	return {
		x = arc.start.x + (arc.target.x - arc.start.x) * alpha,
		y = arc.start.y + arc.launchSpeed * time - 0.5 * arc.gravity * time * time,
		z = arc.start.z + (arc.target.z - arc.start.z) * alpha,
	}
end

-- Velocity `t` seconds into the throw, for pointing the projectile along its path.
function DemoLogic.arcVelocity(arc: Arc, t: number): Vec3
	local time = math.clamp(t, 0, arc.flightTime)
	return {
		x = (arc.target.x - arc.start.x) / arc.flightTime,
		y = arc.launchSpeed - arc.gravity * time,
		z = (arc.target.z - arc.start.z) / arc.flightTime,
	}
end

-- Wind-up before a throw: the hand pulls back `pull` studs away from the target and dips, eased
-- out so it slows into the held pose. alpha 0..1 over the anticipation time.
function DemoLogic.windUp(start: Vec3, target: Vec3, alpha: number, pull: number?): Vec3
	local k = math.clamp(alpha, 0, 1)
	local eased = 1 - (1 - k) * (1 - k)
	local dx, dz = start.x - target.x, start.z - target.z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-6 then
		return { x = start.x, y = start.y - 0.3 * eased, z = start.z }
	end
	local amount = (pull or 1.2) * eased
	return { x = start.x + dx / length * amount, y = start.y - 0.3 * eased, z = start.z + dz / length * amount }
end

-- Deterministic pseudo-random numbers ----------------------------------------------------------

-- A value in [0, 1) from two integers. Stable across runs, so demos and specs agree.
function DemoLogic.hash(seed: number, index: number): number
	local value = math.sin(seed * 127.1 + index * 311.7) * 43758.5453
	return value - math.floor(value)
end

-- `count` points on the ground around a centre, each between minFraction * radius and radius
-- away. Angles are spread evenly with a little jitter so coins never stack.
function DemoLogic.scatter(count: number, radius: number, seed: number?, minFraction: number?): { Vec3 }
	local points: { Vec3 } = {}
	local n = math.max(0, math.floor(count))
	local r = math.max(0, radius)
	local inner = math.clamp(minFraction or 0.35, 0, 1)
	local base = seed or 1
	for index = 1, n do
		local angle = (index - 1 + DemoLogic.hash(base, index) * 0.6) / n * 2 * math.pi
		local reach = r * (inner + (1 - inner) * DemoLogic.hash(base + 17, index))
		table.insert(points, { x = math.cos(angle) * reach, y = 0, z = math.sin(angle) * reach })
	end
	return points
end

-- Tapping --------------------------------------------------------------------------------------

export type Tapper = { rate: number, carry: number, maxPerStep: number }

-- A steady stream of taps for the stress button: `rate` taps per second, at most `maxPerStep`
-- in one frame so a long frame cannot produce a burst.
function DemoLogic.newTapper(rate: number, maxPerStep: number?): Tapper
	return { rate = math.max(0, rate), carry = 0, maxPerStep = math.max(1, math.floor(maxPerStep or 4)) }
end

-- Advances the stream by `dt` seconds and returns how many taps are due now.
function DemoLogic.tapsDue(tapper: Tapper, dt: number): number
	if not finite(dt) or dt <= 0 or tapper.rate <= 0 then
		return 0
	end
	tapper.carry += dt * tapper.rate
	local due = math.floor(tapper.carry)
	if due <= 0 then
		return 0
	end
	if due > tapper.maxPerStep then
		-- Dropped, not saved up: the stream must not catch up after a hitch.
		tapper.carry = 0
		return tapper.maxPerStep
	end
	tapper.carry -= due
	return due
end

-- Simulator numbers (shown by the demo; the stand-in "server" below applies them) ---------------

-- Coins earned by one tap at an upgrade level.
function DemoLogic.tapValue(upgradeLevel: number, rebirths: number?): number
	local level = math.max(0, math.floor(upgradeLevel))
	return (1 + level) * (1 + math.max(0, math.floor(rebirths or 0)))
end

function DemoLogic.upgradeCost(upgradeLevel: number): number
	local level = math.max(0, math.floor(upgradeLevel))
	return math.floor(25 * 1.6 ^ level + 0.5)
end

function DemoLogic.xpForLevel(level: number): number
	return 20 + 15 * math.max(0, math.floor(level) - 1)
end

export type Progress = { level: number, xp: number, max: number, levelsGained: number }

-- Adds XP and rolls over as many levels as the gain covers.
function DemoLogic.gainXp(level: number, xp: number, gain: number): Progress
	local current = math.max(1, math.floor(level))
	local value = math.max(0, xp) + math.max(0, gain)
	local gained = 0
	local max = DemoLogic.xpForLevel(current)
	while value >= max and gained < 100 do
		value -= max
		current += 1
		gained += 1
		max = DemoLogic.xpForLevel(current)
	end
	return { level = current, xp = value, max = max, levelsGained = gained }
end

-- Sample data ----------------------------------------------------------------------------------

DemoLogic.RARITIES = table.freeze({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" })

-- A game-defined rarity for the reward demo, registered with Visuals.Rewards.registerRarity.
DemoLogic.CUSTOM_RARITY = table.freeze({
	id = "Stardust",
	profile = table.freeze({
		extends = "Legendary",
		rank = 5.5,
		label = "STARDUST",
		color = "#7AF0FF",
		secondary = "#3B7BFF",
		glow = "#E8FBFF",
	}),
})

local PETS: { DemoPet } = {
	{
		id = "pebble",
		name = "Pebble",
		description = "A steady little rock sprite. Slow to start, never gives up.",
		rarity = "Common",
		color = "#9AA7B8",
		variant = 1,
		stats = { { label = "Power", value = 12 }, { label = "Speed", value = 8 }, { label = "Luck", value = "x1.0" } },
	},
	{
		id = "sprout",
		name = "Sprout",
		description = "Grows a new leaf every time you level up. Loves the rain.",
		rarity = "Rare",
		color = "#63C174",
		variant = 3,
		stats = { { label = "Power", value = 18 }, { label = "Speed", value = 14 }, { label = "Luck", value = "x1.2" } },
	},
	{
		id = "ember",
		name = "Ember",
		description = "A warm spark with tall ears. Quick, bright and a little mischievous.",
		rarity = "Epic",
		color = "#FF8A3D",
		variant = 2,
		stats = { { label = "Power", value = 31 }, { label = "Speed", value = 26 }, { label = "Luck", value = "x1.5" } },
	},
	{
		id = "nimbus",
		name = "Nimbus",
		description = "A drifting cloud puff that hums when coins are near.",
		rarity = "Legendary",
		color = "#8E7BFF",
		variant = 1,
		stats = { { label = "Power", value = 54 }, { label = "Speed", value = 40 }, { label = "Luck", value = "x2.0" } },
	},
}

function DemoLogic.pets(): { DemoPet }
	return table.clone(PETS)
end

function DemoLogic.pet(id: string): DemoPet?
	for _, pet in PETS do
		if pet.id == id then
			return pet
		end
	end
	return nil
end

local EGG_NAMES: { [string]: { string } } = {
	Common = { "Pebble", "Moss Mite", "Dust Bun" },
	Uncommon = { "Sprig", "Puddle Pup" },
	Rare = { "Sprout", "Glow Snail" },
	Epic = { "Ember", "Frost Finch" },
	Legendary = { "Nimbus", "Sun Otter" },
	Mythic = { "Aurora Lynx" },
	Secret = { "Clockwork Moth" },
}

local RARITY_COLORS: { [string]: string } = {
	Common = "#B8C4D0",
	Uncommon = "#6FD08C",
	Rare = "#4EA3FF",
	Epic = "#B26BFF",
	Legendary = "#FFC53D",
	Mythic = "#FF5C8A",
	Secret = "#2B2D42",
}

function DemoLogic.rarityColor(rarity: string): string
	return RARITY_COLORS[rarity] or RARITY_COLORS.Common
end

-- A demo pet name for a rarity; `index` picks among the names so a batch is not all the same.
function DemoLogic.petName(rarity: string, index: number?): string
	local names = EGG_NAMES[rarity] or EGG_NAMES.Common
	return names[(math.max(1, math.floor(index or 1)) - 1) % #names + 1]
end

-- Stand-in for the server's egg roll: a rarity for roll number `n`. Deterministic and weighted
-- toward the low tiers. A real game rolls on the server and sends the result to the client.
function DemoLogic.fakeRoll(seed: number, n: number): string
	local roll = DemoLogic.hash(seed, n)
	if roll < 0.5 then
		return "Common"
	elseif roll < 0.75 then
		return "Uncommon"
	elseif roll < 0.89 then
		return "Rare"
	elseif roll < 0.96 then
		return "Epic"
	elseif roll < 0.99 then
		return "Legendary"
	end
	return "Mythic"
end

export type EggEntry = { rarity: string, name: string, isNew: boolean }

-- `count` egg entries for Visuals.Eggs.hatch. With `rarity` every egg is that rarity; without it
-- each is rolled by the stand-in server.
function DemoLogic.eggBatch(count: number, rarity: string?, seed: number?): { EggEntry }
	local eggs: { EggEntry } = {}
	local base = seed or 1
	for index = 1, math.max(1, math.floor(count)) do
		local rolled = rarity or DemoLogic.fakeRoll(base, index)
		table.insert(eggs, {
			rarity = rolled,
			name = DemoLogic.petName(rolled, base + index),
			isNew = DemoLogic.hash(base + 5, index) < 0.4,
		})
	end
	return eggs
end

export type RewardEntry = { rarity: string, name: string, amount: number }

-- Six mixed rewards for the batch reveal: mostly small, one rare and one top-tier.
function DemoLogic.mixedRewards(): { RewardEntry }
	return {
		{ rarity = "Common", name = "Coins", amount = 250 },
		{ rarity = "Common", name = "Wood", amount = 40 },
		{ rarity = "Uncommon", name = "Gems", amount = 15 },
		{ rarity = "Rare", name = "Lucky Charm", amount = 1 },
		{ rarity = "Epic", name = "Speed Potion", amount = 2 },
		{ rarity = "Legendary", name = "Golden Key", amount = 1 },
	}
end

local FOODS: { Food } = {
	{ id = "berry", name = "Berry", color = "#E0457B", shape = "ball", hunger = 18, happiness = 6, coins = 5 },
	{ id = "carrot", name = "Carrot", color = "#FF9A3D", shape = "wedge", hunger = 30, happiness = 4, coins = 8 },
	{ id = "cookie", name = "Cookie", color = "#C68A4A", shape = "disc", hunger = 12, happiness = 22, coins = 12 },
}

function DemoLogic.foods(): { Food }
	return table.clone(FOODS)
end

local ANIMALS: { Animal } = {
	{ id = "bramble", name = "Bramble", color = "#C9905A", accent = "#F4E3C8", kind = "hopper" },
	{ id = "puddle", name = "Puddle", color = "#6FB7D9", accent = "#EAF7FF", kind = "waddler" },
}

function DemoLogic.animals(): { Animal }
	return table.clone(ANIMALS)
end

function DemoLogic.startingNeeds(): Needs
	return { hunger = 35, happiness = 40 }
end

-- The needs after eating `food`: both bars rise and stop at 100.
function DemoLogic.feed(needs: Needs, food: Food): Needs
	return {
		hunger = math.clamp(needs.hunger + food.hunger, 0, 100),
		happiness = math.clamp(needs.happiness + food.happiness, 0, 100),
	}
end

-- Needs drift down over time so the bars keep moving while the demo runs.
function DemoLogic.decay(needs: Needs, dt: number): Needs
	local seconds = math.max(0, dt)
	return {
		hunger = math.clamp(needs.hunger - 1.5 * seconds, 0, 100),
		happiness = math.clamp(needs.happiness - 1 * seconds, 0, 100),
	}
end

-- Every fourth throw is aimed wide so the miss path (ground splat, dust) is easy to see.
function DemoLogic.throwMisses(throwNumber: number): boolean
	return math.max(1, math.floor(throwNumber)) % 4 == 0
end

-- Where a throw lands: on the animal, or `wide` studs beside it for a miss.
function DemoLogic.landing(animal: Vec3, groundY: number, miss: boolean, throwNumber: number, wide: number?): Vec3
	if not miss then
		return { x = animal.x, y = animal.y, z = animal.z }
	end
	local side = if math.floor(throwNumber / 4) % 2 == 0 then 1 else -1
	return { x = animal.x + side * (wide or 4.5), y = groundY, z = animal.z + 1.5 }
end

-- True when a landing point is close enough to the animal to count as eaten.
function DemoLogic.isHit(landing: Vec3, animal: Vec3, radius: number?): boolean
	return DemoLogic.flatDistance(landing, animal) <= (radius or 2.5)
end

return DemoLogic
