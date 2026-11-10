--!strict
-- Reward VFX presets (pure data): coins, gems, stars, cash, chests, rarity bursts and beams,
-- confetti and fireworks. Each preset is a layered composition built from VFX/RecipeLogic.

local EffectLogic = require("./EffectLogic")
local Recipe = require("./RecipeLogic")
local Registry = require("../Core/Registry")

local R = Recipe
local P = Recipe.particles

local function n(value: number): number
	return math.max(1, math.floor(value + 0.5))
end

local GOLD = "#FFC93C"

-- A fountain of coins: fast up, heavy gravity, tumbling.
local function coins(overrides: { [string]: any }?): EffectLogic.Layer
	return R.merge(
		P({
			name = "coins",
			texture = "coin",
			colors = { "#FFF6C2", "#FFD23F", "#F2A900" },
			sizes = { 0.25, 0.55, 0.5, 0.35 },
			transparency = { 0, 0, 0, 1 },
			lifetime = { 0.7, 1.1 },
			speed = { 16, 24 },
			spread = { 24, 24 },
			burst = 14,
			gravity = -52,
			drag = 0.6,
			rotSpeed = { -420, 420 },
			lightEmission = 0.55,
		}) :: any,
		overrides
	)
end

local function rarityBurst(t: Recipe.Tier): EffectLogic.Definition
	local p = t.palette
	local rank = t.rank
	return {
		duration = t.duration,
		priority = if rank >= 5 then 10 else 0,
		layers = R.join(
			P({
				name = "burst",
				colors = { p.core, p.light, p.main },
				sizes = { 0, 0.5 * t.size, 0.3 * t.size, 0 },
				lifetime = { 0.5, 0.9 },
				speed = { 9 + 2 * rank, 15 + 3 * rank },
				drag = 3.5,
				burst = n(12 * t.count),
				rotSpeed = { -260, 260 },
				lightEmission = 1,
			}),
			R.glow(p.main, { sizes = { 0.6, 2.6 * t.size, 2 * t.size } }),
			rank >= 2 and R.sparkles(p.accent, { burst = n(6 * t.count), lifetime = { 0.8, 0.8 + 0.25 * rank } }),
			rank >= 3 and R.ring(p.main, { radius = { 0.6, 4 + 1.2 * rank }, time = 0.45 + 0.03 * rank }),
			rank >= 3
				and R.light(p.main, {
					range = 10 + 2 * rank,
					brightness = 1.5 + 0.4 * rank,
					fadeOut = 0.3 + 0.1 * rank,
				}),
			rank >= 4 and R.streaks(p.light, { burst = n(5 * t.count) }),
			rank >= 4
				and R.ring(p.accent, {
					name = "ring2",
					delay = 0.12,
					radius = { 0.6, 6 + 1.5 * rank },
					thickness = 0.25,
					time = 0.6,
					optional = true,
				}),
			rank >= 5 and R.beam(p.main, { length = 18 + 6 * rank, hold = t.duration * 0.35 }),
			rank >= 5
				and P({
					name = "embers",
					delay = 0.1,
					colors = { p.core, p.main, p.dark },
					sizes = { 0, 0.3, 0.2, 0 },
					lifetime = { 1.4, 2.2 },
					speed = { 2, 6 },
					burst = n(5 * t.count),
					gravity = 3,
					drag = 2,
					lightEmission = 1,
				}),
			rank >= 5 and R.shake("SoftImpact", { amount = 0.6 + 0.2 * (rank - 5) }),
			rank >= 6 and R.flash(p.core, { sizes = { 1, 8 } }),
			rank >= 6
				and P({
					name = "secondWave",
					delay = 0.25,
					colors = { "#FFFFFF", p.accent },
					sizes = { 0, 0.55 * t.size, 0 },
					lifetime = { 0.6, 1 },
					speed = { 14, 26 },
					drag = 4,
					burst = n(8 * t.count),
					lightEmission = 1,
				}),
			rank >= 6
				and R.beam("#FFFFFF", {
					name = "beamCore",
					width = { 0.8, 0.3 },
					length = 18 + 6 * rank,
					hold = t.duration * 0.3,
					optional = true,
				}),
			rank >= 7
				and R.multicolor(
					P({
						name = "prism",
						delay = 0.4,
						sizes = { 0, 0.5, 0.35, 0 },
						lifetime = { 1, 1.6 },
						speed = { 6, 14 },
						drag = 2.5,
						gravity = 2,
						burst = 24,
						rotSpeed = { -200, 200 },
						lightEmission = 1,
					}),
					{ "#2CF5E0", "#FF5CF4", "#FFF27A" }
				),
			rank >= 7
				and R.ring("#FFFFFF", {
					name = "ring3",
					delay = 0.3,
					radius = { 1, 20 },
					thickness = 0.3,
					time = 0.9,
					optional = true,
				}),
			rank >= 7 and R.postfx("bloom", { amount = 0.6, fadeOut = 0.8 })
		),
	}
end

local function rarityBeam(t: Recipe.Tier): EffectLogic.Definition
	local p = t.palette
	local rank = t.rank
	local height = 14 + 5 * rank
	return {
		looping = true,
		priority = if rank >= 5 then 5 else 0,
		layers = R.join(
			R.beam(p.main, {
				width = { 1 + 0.35 * rank, 0.5 + 0.2 * rank },
				length = height,
				transparency = { 0.25, 0.6, 1 },
				fadeIn = 0.35,
				fadeOut = 0.4,
			}),
			P({
				name = "base",
				texture = "glow",
				colors = { p.light, p.main },
				sizes = { 1, 2 + 0.4 * rank, 1.4 },
				transparency = { 1, 0.6, 1 },
				lifetime = { 1, 1.4 },
				speed = { 0, 0.4 },
				rate = 2,
				lightEmission = 1,
				lockedToPart = true,
			}),
			P({
				name = "motes",
				colors = { "#FFFFFF", p.main },
				sizes = { 0, 0.3, 0 },
				lifetime = { 1.2, 1.8 },
				speed = { 5, 9 },
				spread = { 4, 4 },
				rate = 3 * t.count,
				shape = "Cylinder",
				shapeSize = { 1 + 0.3 * rank, 0.2, 1 + 0.3 * rank },
				lightEmission = 1,
			}),
			rank >= 3
				and R.light(p.main, {
					range = 8 + 2 * rank,
					brightness = 1 + 0.25 * rank,
					fadeIn = 0.4,
					pulse = { 2.2, 0.3 },
				}),
			rank >= 3 and R.ring(p.main, { radius = { 0.5, 3 + rank }, time = 0.6 }),
			rank >= 5
				and R.beam("#FFFFFF", {
					name = "beamCore",
					width = { 0.5, 0.2 },
					length = height,
					transparency = { 0.1, 0.5, 1 },
					fadeIn = 0.35,
					optional = true,
				}),
			rank >= 6
				and R.sparkles(p.accent, {
					name = "halo",
					burst = false,
					rate = 8,
					speed = { 0.5, 2 },
					shape = "Cylinder",
					shapeStyle = "Surface",
					shapeSize = { 5, 3, 5 },
					offset = { 0, 1.5, 0 },
				}),
			rank >= 7
				and P({
					name = "prism",
					colors = { "#2CF5E0", "#FF5CF4", "#FFF27A" },
					sizes = { 0, 0.4, 0 },
					lifetime = { 1.5, 2.2 },
					speed = { 6, 10 },
					spread = { 6, 6 },
					rate = 8,
					lightEmission = 1,
					optional = true,
				})
		),
	}
end

local presets: { Registry.Preset } = {
	R.preset({
		id = "CoinBurst",
		name = "Coin burst",
		category = "rewards",
		description = "A fast fountain of tumbling coins with a brief core glow and a few lingering sparkles.",
		color = GOLD,
		tags = { "coin", "currency", "pickup", "burst" },
		data = {
			duration = 0.6,
			minInterval = 0.05,
			layers = R.join(
				coins(),
				R.glow(GOLD, { sizes = { 0.5, 2.6, 2 } }),
				R.sparkles(GOLD, { burst = 8, speed = { 2, 6 } }),
				R.light(GOLD, { range = 10, brightness = 1.8, optional = true })
			),
		},
	}),
	R.preset({
		id = "GemBurst",
		name = "Gem burst",
		category = "rewards",
		description = "Faceted shards drift out and hang before falling, with sharp glints and a small ring.",
		color = "#4FD8FF",
		tags = { "gem", "currency", "premium", "burst" },
		data = {
			duration = 0.8,
			minInterval = 0.05,
			layers = R.join(
				P({
					name = "gems",
					texture = "gem",
					colors = { "#FFFFFF", "#7FE8FF", "#5B8CFF" },
					sizes = { 0, 0.6, 0.45, 0 },
					lifetime = { 0.8, 1.2 },
					speed = { 9, 15 },
					spread = { 70, 70 },
					burst = 10,
					gravity = -18,
					drag = 1.8,
					rotSpeed = { -240, 240 },
					lightEmission = 0.9,
				}),
				R.streaks("#9BE8FF", { name = "glints", burst = 6, speed = { 14, 22 } }),
				R.ring("#4FD8FF", { radius = { 0.4, 3.2 }, thickness = 0.25, time = 0.35 }),
				R.sparkles("#B48CFF", { burst = 8 }),
				R.light("#4FD8FF", { range = 10, brightness = 2, optional = true })
			),
		},
	}),
	R.preset({
		id = "StarBurst",
		name = "Star burst",
		category = "rewards",
		description = "Spinning stars pop outward and hang in the air, followed by a smaller second wave.",
		color = "#FFE45C",
		tags = { "star", "burst", "reward" },
		data = {
			duration = 0.9,
			minInterval = 0.05,
			layers = R.join(
				P({
					name = "stars",
					texture = "star",
					colors = { "#FFFFFF", "#FFF27A", "#FFC93C" },
					sizes = { 0, 0.9, 0.6, 0 },
					lifetime = { 0.7, 1.1 },
					speed = { 10, 16 },
					burst = 12,
					drag = 3,
					rotSpeed = { -300, 300 },
					lightEmission = 0.9,
				}),
				P({
					name = "secondWave",
					texture = "star",
					delay = 0.12,
					colors = { "#FFFFFF", "#FFE45C" },
					sizes = { 0, 0.5, 0 },
					lifetime = { 0.5, 0.8 },
					speed = { 16, 24 },
					burst = 8,
					drag = 5,
					rotSpeed = { -400, 400 },
					lightEmission = 1,
					optional = true,
				}),
				R.glow("#FFE45C"),
				R.sparkles("#FFE45C", { burst = 6 })
			),
		},
	}),
	R.preset({
		id = "CashExplosion",
		name = "Cash explosion",
		category = "rewards",
		description = "A big payout: fluttering bills and coins thrown high, a ground ring, a flash and a soft shake.",
		color = "#58D66B",
		tags = { "cash", "money", "jackpot", "burst", "expensive" },
		data = {
			duration = 1.4,
			minInterval = 0.2,
			priority = 5,
			layers = R.join(
				P({
					name = "bills",
					texture = "confetti",
					colors = { "#B9FFC2", "#58D66B", "#2FA84A" },
					sizes = { 0.5, 0.55, 0.45 },
					transparency = { 0, 0, 0, 1 },
					lifetime = { 1.1, 1.7 },
					speed = { 18, 30 },
					spread = { 55, 55 },
					burst = 28,
					gravity = -38,
					drag = 1.2,
					rotSpeed = { -360, 360 },
					squash = { 0.7, -0.7, 0.7, -0.5 },
					lightEmission = 0.1,
					lightInfluence = 0,
				}),
				coins({ burst = 16, speed = { 20, 32 }, spread = { 40, 40 } }),
				R.flash("#E8FFD0", { sizes = { 1, 7 } }),
				R.ring("#58D66B", { radius = { 0.8, 9 }, time = 0.5 }),
				R.sparkles(GOLD, { burst = 12, lifetime = { 1, 1.6 } }),
				R.light(GOLD, { range = 18, brightness = 3 }),
				R.shake("SoftImpact")
			),
		},
	}),
	R.preset({
		id = "SparkleBurst",
		name = "Sparkle burst",
		category = "rewards",
		description = "A light, quick puff of sparkles that brakes hard and twinkles out. The everyday accent.",
		color = "#FFF2B0",
		tags = { "sparkle", "generic", "accent" },
		data = {
			duration = 0.5,
			minInterval = 0.04,
			layers = R.join(
				P({
					name = "sparkles",
					colors = { "#FFFFFF", "#FFF2B0" },
					sizes = { 0, 0.45, 0.2, 0 },
					lifetime = { 0.45, 0.8 },
					speed = { 5, 11 },
					burst = 16,
					drag = 4,
					rotSpeed = { -220, 220 },
					lightEmission = 1,
				}),
				R.glow("#FFF2B0", { burst = 1, sizes = { 0.4, 1.8, 1.2 } }),
				R.sparkles("#FFF2B0", { name = "twinkle", burst = 8, delay = 0.08 })
			),
		},
	}),
	R.preset({
		id = "RewardGlow",
		name = "Reward glow",
		category = "rewards",
		description = "A soft halo that swells behind a reward, with slow rotating rays and rising motes.",
		color = "#FFD86B",
		tags = { "glow", "reveal", "halo" },
		data = {
			duration = 1.6,
			layers = R.join(
				P({
					name = "halo",
					texture = "glow",
					colors = { "#FFF6D6", "#FFD86B" },
					sizes = { 1, 5, 5.5, 4 },
					transparency = { 1, 0.6, 0.7, 1 },
					lifetime = { 1.3, 1.5 },
					speed = { 0, 0 },
					burst = 2,
					lightEmission = 1,
					lockedToPart = true,
					zOffset = -0.5,
				}),
				P({
					name = "rays",
					texture = "streak",
					colors = { "#FFFFFF", "#FFD86B" },
					sizes = { 0, 4.5, 4.5, 0 },
					transparency = { 1, 0.7, 0.75, 1 },
					lifetime = { 1.1, 1.4 },
					speed = { 0, 0 },
					rate = 5,
					emitFor = 0.5,
					rotSpeed = { 25, 45 },
					lightEmission = 1,
					lockedToPart = true,
					optional = true,
				}),
				P({
					name = "motes",
					colors = { "#FFFFFF", "#FFD86B" },
					sizes = { 0, 0.3, 0 },
					lifetime = { 0.9, 1.4 },
					speed = { 1.5, 3.5 },
					spread = { 40, 40 },
					rate = 12,
					emitFor = 1,
					drag = 1,
					lightEmission = 1,
				}),
				R.light("#FFD86B", { range = 12, brightness = 1.6, fadeIn = 0.3, hold = 0.6, fadeOut = 0.6 })
			),
		},
	}),
	R.preset({
		id = "TreasureOpen",
		name = "Treasure open",
		category = "rewards",
		description = "Light pours up out of an opening chest: a widening beam, a sparkle stream, then coins.",
		color = GOLD,
		tags = { "chest", "treasure", "open", "reveal" },
		data = {
			duration = 1.4,
			priority = 5,
			layers = R.join(
				R.dust({ burst = 6, sizes = { 0.4, 1.2, 1.6 } }),
				R.beam(GOLD, {
					width = { 2.5, 5 },
					length = 9,
					transparency = { 0.3, 0.7, 1 },
					fadeIn = 0.2,
					hold = 0.7,
					fadeOut = 0.4,
				}),
				P({
					name = "stream",
					colors = { "#FFFFFF", "#FFE9A8", GOLD },
					sizes = { 0, 0.35, 0 },
					lifetime = { 0.5, 0.9 },
					speed = { 8, 14 },
					spread = { 18, 18 },
					rate = 30,
					emitFor = 0.7,
					drag = 1,
					lightEmission = 1,
				}),
				coins({ delay = 0.12, burst = 10 }),
				R.glow(GOLD, { sizes = { 0.8, 3.4, 2.8 }, lifetime = { 0.5, 0.7 } }),
				R.light(GOLD, { range = 14, brightness = 2.4, fadeIn = 0.15, hold = 0.6, fadeOut = 0.5 })
			),
		},
	}),
	R.preset({
		id = "ChestGlow",
		name = "Chest glow",
		category = "rewards",
		description = "Idle loop for an unopened chest: a breathing glow, slow rising motes and an occasional glint.",
		color = GOLD,
		tags = { "chest", "idle", "loop", "glow" },
		data = {
			looping = true,
			layers = R.join(
				P({
					name = "breath",
					texture = "glow",
					colors = { "#FFF0C2", GOLD },
					sizes = { 1.5, 3.2, 1.5 },
					transparency = { 1, 0.75, 1 },
					lifetime = { 1.6, 2 },
					speed = { 0, 0 },
					rate = 1.2,
					lightEmission = 1,
					lockedToPart = true,
				}),
				P({
					name = "motes",
					colors = { "#FFFFFF", GOLD },
					sizes = { 0, 0.22, 0 },
					lifetime = { 1.4, 2 },
					speed = { 1, 2.5 },
					spread = { 30, 30 },
					rate = 8,
					lightEmission = 1,
				}),
				P({
					name = "glint",
					texture = "star",
					colors = { "#FFFFFF" },
					sizes = { 0, 0.9, 0 },
					lifetime = { 0.35, 0.5 },
					speed = { 0, 0.5 },
					rate = 1.5,
					rotSpeed = { 90, 180 },
					lightEmission = 1,
					optional = true,
				}),
				R.light(GOLD, { range = 9, brightness = 1.2, fadeIn = 0.4, pulse = { 2.4, 0.35 } })
			),
		},
	}),
	R.preset({
		id = "RarityBurst",
		name = "Rarity burst",
		category = "rewards",
		description = "Reveal burst that scales with rarity: Common is a small pop; Mythic and Secret add rings, a "
			.. "light pillar, a second wave and lingering embers.",
		color = EffectLogic.rarityPalette("Common").main,
		tags = { "rarity", "reveal", "burst", "expensive" },
		params = { rarity = Recipe.RARITY_PARAM },
		usage = 'Visuals:Play("RarityBurst", position, { rarity = "Legendary" })',
		data = Recipe.byRarity(rarityBurst),
	}),
	R.preset({
		id = "RarityBeam",
		name = "Rarity beam",
		category = "rewards",
		description = "A standing pillar of light that marks a drop. Height, width and extra layers grow with rarity.",
		color = EffectLogic.rarityPalette("Common").main,
		tags = { "rarity", "beam", "loop", "drop", "marker" },
		params = { rarity = Recipe.RARITY_PARAM },
		usage = 'local handle = Visuals:Attach("RarityBeam", dropPart, { rarity = "Epic" })',
		data = Recipe.byRarity(rarityBeam),
	}),
	R.preset({
		id = "Confetti",
		name = "Confetti",
		category = "rewards",
		description = "A cannon of five-colour paper that flutters and drifts down under drag.",
		color = "#FF5A5A",
		tags = { "confetti", "celebration", "party" },
		data = {
			duration = 1,
			minInterval = 0.15,
			layers = R.join(
				R.multicolor(
					P({
						name = "paper",
						texture = "confetti",
						sizes = { 0.38, 0.38, 0.3 },
						transparency = { 0, 0, 0, 1 },
						lifetime = { 1.6, 2.4 },
						speed = { 18, 30 },
						spread = { 38, 38 },
						burst = 40,
						gravity = -22,
						drag = 2.2,
						rotSpeed = { -500, 500 },
						squash = { 0.8, -0.8, 0.8, -0.6 },
						lightEmission = 0,
						lightInfluence = 0,
					}),
					{ "#FF5A5A", "#FFE45C", "#4FC3FF", "#7CFF6B", "#C77DFF" }
				),
				R.dust({
					name = "pop",
					burst = 5,
					colors = { "#FFFFFF", "#F2F2F2" },
					speed = { 6, 12 },
					spread = { 30, 30 },
				})
			),
		},
	}),
	R.preset({
		id = "Fireworks",
		name = "Fireworks",
		category = "rewards",
		description = "Rockets streak up, then two shells burst overhead in different colours with a late crackle.",
		color = "#FF6B9A",
		tags = { "fireworks", "celebration", "sky", "expensive" },
		preview = { distance = 40 },
		data = {
			duration = 1.6,
			minInterval = 0.3,
			layers = R.join(
				R.streaks("#FFE9A8", {
					name = "rockets",
					burst = 3,
					speed = { 50, 58 },
					spread = { 4, 4 },
					lifetime = { 0.4, 0.5 },
					drag = 1.5,
					sizes = { 0.6, 0.45, 0 },
				}),
				P({
					name = "shell",
					delay = 0.5,
					offset = { 0, 22, 0 },
					colors = { "#FFFFFF", "#FF6B9A", "#C2185B" },
					sizes = { 0.5, 0.45, 0.25, 0 },
					lifetime = { 1.2, 1.8 },
					speed = { 16, 24 },
					burst = 46,
					gravity = -9,
					drag = 3.5,
					lightEmission = 1,
				}),
				R.flash("#FFD0E0", { delay = 0.5, offset = { 0, 22, 0 }, sizes = { 1, 9 } }),
				R.light("#FF6B9A", { delay = 0.5, offset = { 0, 22, 0 }, range = 30, brightness = 3 }),
				P({
					name = "shell2",
					delay = 0.8,
					offset = { 5, 18, -3 },
					colors = { "#FFFFFF", "#6BE0FF", "#2F6BFF" },
					sizes = { 0.45, 0.4, 0.2, 0 },
					lifetime = { 1, 1.5 },
					speed = { 12, 18 },
					burst = 26,
					gravity = -9,
					drag = 3.5,
					lightEmission = 1,
				}),
				R.sparkles("#FFF27A", {
					name = "crackle",
					delay = 0.95,
					offset = { 0, 22, 0 },
					burst = 20,
					speed = { 4, 12 },
					lifetime = { 0.4, 0.9 },
				})
			),
		},
	}),
	R.preset({
		id = "GoldenShine",
		name = "Golden shine",
		category = "rewards",
		description = "A golden sheen over a part or model: a highlight pulse with star glints in two beats.",
		color = "#FFD84A",
		tags = { "gold", "shine", "highlight", "upgrade" },
		usage = 'Visuals:Play("GoldenShine", model)',
		data = {
			duration = 0.9,
			minInterval = 0.2,
			layers = R.join(
				R.highlight("#FFD84A", { fadeIn = 0.15, hold = 0.2, fadeOut = 0.5, optional = false }),
				P({
					name = "glints",
					texture = "star",
					colors = { "#FFFFFF", "#FFF27A" },
					sizes = { 0, 1.1, 0 },
					lifetime = { 0.3, 0.45 },
					speed = { 0, 1 },
					burst = 3,
					rotSpeed = { 120, 240 },
					lightEmission = 1,
					shape = "Sphere",
					shapeSize = { 3, 3, 3 },
				}),
				P({
					name = "glints2",
					texture = "star",
					delay = 0.25,
					colors = { "#FFFFFF", "#FFF27A" },
					sizes = { 0, 0.8, 0 },
					lifetime = { 0.3, 0.45 },
					speed = { 0, 1 },
					burst = 3,
					rotSpeed = { 120, 240 },
					lightEmission = 1,
					shape = "Sphere",
					shapeSize = { 3, 3, 3 },
				}),
				R.glow("#FFD84A", { sizes = { 1, 3.5, 3 }, transparency = { 0.7, 0.8, 1 }, lifetime = { 0.5, 0.7 } })
			),
		},
	}),
}

return presets
