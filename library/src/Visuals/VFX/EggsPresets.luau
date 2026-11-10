--!strict
-- Egg VFX presets (pure data): shake dust, the crack, the white-out flash, the rarity-scaled hatch
-- burst and the looping energy gather used while an egg charges.

local EffectLogic = require("./EffectLogic")
local Recipe = require("./RecipeLogic")
local Registry = require("../Core/Registry")

local R = Recipe
local P = Recipe.particles

local function n(value: number): number
	return math.max(1, math.floor(value + 0.5))
end

-- Shell fragments: matte, heavy, tumbling.
local function shards(overrides: { [string]: any }?): EffectLogic.Layer
	return R.merge(
		P({
			name = "shards",
			texture = "shard",
			colors = { "#FFFDF2", "#F1E6CC" },
			sizes = { 0.5, 0.45, 0.3 },
			transparency = { 0, 0, 0, 1 },
			lifetime = { 0.7, 1.1 },
			speed = { 9, 16 },
			spread = { 75, 75 },
			burst = 10,
			gravity = -55,
			drag = 0.8,
			rotSpeed = { -500, 500 },
			lightEmission = 0.1,
			lightInfluence = 0.6,
			tint = false,
		}) :: any,
		overrides
	)
end

local function hatchBurst(t: Recipe.Tier): EffectLogic.Definition
	local p = t.palette
	local rank = t.rank
	return {
		duration = t.duration,
		priority = if rank >= 5 then 10 else 2,
		layers = R.join(
			shards({ burst = n(8 + 2 * rank), speed = { 10 + rank, 18 + 2 * rank } }),
			P({
				name = "fountain",
				colors = { p.core, p.light, p.main },
				sizes = { 0, 0.45 * t.size, 0.25 * t.size, 0 },
				lifetime = { 0.6, 1 },
				speed = { 12 + 2 * rank, 20 + 3 * rank },
				spread = { 32, 32 },
				burst = n(12 * t.count),
				gravity = -14,
				drag = 2,
				lightEmission = 1,
			}),
			R.flash(p.core, { sizes = { 0.8, 3.5 + rank } }),
			R.glow(p.main, { sizes = { 0.8, 3 * t.size, 2.2 * t.size } }),
			rank >= 2 and R.sparkles(p.accent, { burst = n(6 * t.count), lifetime = { 0.8, 0.9 + 0.25 * rank } }),
			rank >= 3 and R.ring(p.main, { radius = { 0.6, 4.5 + 1.3 * rank }, time = 0.45 + 0.03 * rank }),
			rank >= 3
				and R.light(p.main, {
					range = 12 + 2 * rank,
					brightness = 1.8 + 0.4 * rank,
					fadeOut = 0.35 + 0.1 * rank,
				}),
			rank >= 4
				and R.streaks(p.light, {
					name = "rays",
					burst = n(4 * t.count),
					speed = { 26, 44 },
					spread = { 60, 60 },
				}),
			rank >= 4 and R.dust({ name = "shellDust", burst = 8, optional = true }),
			rank >= 5 and R.beam(p.main, { length = 20 + 6 * rank, hold = t.duration * 0.35 }),
			rank >= 5
				and R.ring(p.accent, {
					name = "ring2",
					delay = 0.14,
					radius = { 0.6, 7 + 1.5 * rank },
					thickness = 0.25,
					time = 0.65,
				}),
			rank >= 5 and R.shake("Hatch", { amount = 0.7 + 0.15 * (rank - 5) }),
			rank >= 5
				and P({
					name = "confetti",
					texture = "confetti",
					delay = 0.1,
					colors = { p.light, p.main },
					sizes = { 0.32, 0.32, 0.25 },
					transparency = { 0, 0, 0, 1 },
					lifetime = { 1.5, 2.2 },
					speed = { 14, 24 },
					spread = { 45, 45 },
					burst = n(5 * t.count),
					gravity = -20,
					drag = 2.2,
					rotSpeed = { -500, 500 },
					squash = { 0.8, -0.8, 0.8, -0.6 },
					lightEmission = 0.2,
				}),
			rank >= 6
				and R.beam("#FFFFFF", {
					name = "beamCore",
					width = { 0.8, 0.3 },
					length = 20 + 6 * rank,
					hold = t.duration * 0.3,
					optional = true,
				}),
			rank >= 6
				and P({
					name = "embers",
					delay = 0.3,
					colors = { p.core, p.accent, p.dark },
					sizes = { 0, 0.3, 0.2, 0 },
					lifetime = { 1.6, 2.4 },
					speed = { 2, 6 },
					burst = n(6 * t.count),
					gravity = 3,
					drag = 2,
					lightEmission = 1,
				}),
			rank >= 7
				and R.multicolor(
					P({
						name = "prism",
						delay = 0.45,
						sizes = { 0, 0.5, 0.35, 0 },
						lifetime = { 1, 1.6 },
						speed = { 8, 16 },
						drag = 2.5,
						gravity = 2,
						burst = 24,
						rotSpeed = { -200, 200 },
						lightEmission = 1,
					}),
					{ "#2CF5E0", "#FF5CF4", "#FFF27A" }
				),
			rank >= 7 and R.postfx("bloom", { amount = 0.65, fadeOut = 0.9 }),
			rank >= 7 and R.highlight(p.main, { fadeIn = 0.1, hold = 0.3, fadeOut = 0.8 })
		),
	}
end

local presets: { Registry.Preset } = {
	R.preset({
		id = "EggShakeDust",
		name = "Egg shake dust",
		category = "eggs",
		description = "Each wobble of an egg kicks up a little dust at its base and flicks off a few chips.",
		color = "#E6DCCB",
		tags = { "egg", "shake", "dust", "anticipation" },
		usage = 'Visuals:Play("EggShakeDust", eggModel)',
		data = {
			duration = 0.4,
			minInterval = 0.08,
			layers = R.join(
				R.groundDust({ burst = 5, sizes = { 0.3, 0.9, 1.2 }, speed = { 3, 6 }, offset = { 0, -1.2, 0 } }),
				shards({ name = "chips", burst = 3, sizes = { 0.16, 0.14, 0.1 }, speed = { 4, 8 }, optional = true })
			),
		},
	}),
	R.preset({
		id = "EggCrack",
		name = "Egg crack",
		category = "eggs",
		description = "Shell fragments snap off while light leaks through the crack in thin bright streaks.",
		color = "#FFF2C2",
		tags = { "egg", "crack", "shell" },
		usage = 'Visuals:Play("EggCrack", eggModel)',
		data = {
			duration = 0.5,
			minInterval = 0.1,
			layers = R.join(
				shards(),
				R.streaks("#FFF2C2", { name = "leak", burst = 6, speed = { 14, 24 }, spread = { 50, 50 } }),
				R.flash("#FFF2C2", { sizes = { 0.4, 2.2 }, time = 0.12 }),
				R.light("#FFF2C2", { range = 9, brightness = 1.8, fadeOut = 0.3, optional = true })
			),
		},
	}),
	R.preset({
		id = "EggFlash",
		name = "Egg flash",
		category = "eggs",
		description = "The white-out beat right before a reveal: a large orb, a strong light and a fast ring. "
			.. "Softened automatically when reduced flashing is on.",
		color = "#FFFFFF",
		tags = { "egg", "flash", "reveal", "whiteout" },
		usage = 'Visuals:Play("EggFlash", eggModel)',
		data = {
			duration = 0.5,
			minInterval = 0.2,
			priority = 5,
			layers = R.join(
				R.flash("#FFFFFF", { sizes = { 1.5, 16 }, time = 0.32, transparency = { 0.1, 1 } }),
				R.glow("#FFFFFF", { sizes = { 2, 9, 7 }, lifetime = { 0.35, 0.45 } }),
				R.ring("#FFFFFF", { radius = { 1, 12 }, time = 0.35, thickness = 0.5 }),
				R.light("#FFFFFF", { range = 30, brightness = 5, fadeOut = 0.4 }),
				R.postfx("bloom", { amount = 0.8, fadeOut = 0.4 }),
				R.postfx("color", { amount = 0.5, fadeOut = 0.35 })
			),
		},
	}),
	R.preset({
		id = "HatchBurst",
		name = "Hatch burst",
		category = "eggs",
		description = "The hatch itself, scaled by rarity: shell shards and an upward fountain for Common; rings, "
			.. "rays, a light pillar, confetti, embers and a prismatic wave as rarity climbs.",
		color = EffectLogic.rarityPalette("Common").main,
		tags = { "egg", "hatch", "rarity", "burst", "expensive" },
		params = { rarity = Recipe.RARITY_PARAM },
		usage = 'Visuals:Play("HatchBurst", eggModel, { rarity = "Mythic" })',
		data = Recipe.byRarity(hatchBurst),
	}),
	R.preset({
		id = "EggEnergy",
		name = "Egg energy",
		category = "eggs",
		description = "Looping charge around an egg: motes are drawn inward, the core breathes and the light pulses.",
		color = "#FFE08A",
		tags = { "egg", "charge", "loop", "energy" },
		usage = 'local handle = Visuals:Attach("EggEnergy", eggModel)',
		data = {
			looping = true,
			layers = R.join(
				R.inward("#FFE08A", 3.5, { rate = 22, lifetime = { 0.5, 0.62 }, speed = { 5.6, 6.6 } }),
				P({
					name = "core",
					texture = "glow",
					colors = { "#FFFFFF", "#FFE08A" },
					sizes = { 1.2, 3, 1.2 },
					transparency = { 1, 0.7, 1 },
					lifetime = { 0.9, 1.2 },
					speed = { 0, 0 },
					rate = 1.5,
					lightEmission = 1,
					lockedToPart = true,
				}),
				R.streaks("#FFF6D6", {
					name = "arcs",
					burst = false,
					rate = 4,
					speed = { 8, 14 },
					lifetime = { 0.2, 0.3 },
					shape = "Sphere",
					shapeStyle = "Surface",
					shapeSize = { 3.5, 3.5, 3.5 },
					optional = true,
				}),
				R.light("#FFE08A", { range = 10, brightness = 1.6, fadeIn = 0.3, pulse = { 0.9, 0.45 } })
			),
		},
	}),
}

return presets
