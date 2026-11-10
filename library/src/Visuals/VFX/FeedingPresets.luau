--!strict
-- Feeding VFX presets (pure data): food trails, splats, hearts, crumbs and the tap pop.

local Recipe = require("./RecipeLogic")
local Registry = require("../Core/Registry")

local R = Recipe
local P = Recipe.particles

local presets: { Registry.Preset } = {
	R.preset({
		id = "FoodTrail",
		name = "Food trail",
		category = "feeding",
		description = "A warm ribbon behind thrown food, dropping crumbs that fall away and the odd sparkle.",
		color = "#FFB86B",
		tags = { "food", "trail", "loop", "throw" },
		usage = 'local handle = Visuals:Attach("FoodTrail", foodPart)',
		data = {
			looping = true,
			layers = R.join(
				R.trail("#FFB86B", { time = 0.3, width = { 1 }, transparency = { 0.3, 0.6, 1 } }),
				P({
					name = "crumbs",
					texture = "shard",
					colors = { "#FFE2B8", "#D9A066" },
					sizes = { 0.16, 0.13, 0.08 },
					transparency = { 0, 0, 0.2, 1 },
					lifetime = { 0.4, 0.7 },
					speed = { 0, 2 },
					rate = 12,
					gravity = -20,
					rotSpeed = { -300, 300 },
					lightEmission = 0.1,
				}),
				R.sparkles("#FFE2B8", { burst = false, rate = 3, lifetime = { 0.4, 0.7 } })
			),
		},
	}),
	R.preset({
		id = "FoodSplat",
		name = "Food splat",
		category = "feeding",
		description = "A squishy landing: blobs hop out in low arcs, a flat disc spreads and a juicy mist puffs.",
		color = "#FF6B5A",
		tags = { "food", "splat", "squish", "impact" },
		data = {
			duration = 0.6,
			minInterval = 0.06,
			layers = R.join(
				P({
					name = "blobs",
					texture = "drop",
					colors = { "#FFB0A6", "#FF6B5A", "#C93A2B" },
					sizes = { 0.4, 0.35, 0.2 },
					transparency = { 0, 0, 0.2, 1 },
					lifetime = { 0.4, 0.7 },
					speed = { 6, 11 },
					spread = { 70, 70 },
					burst = 12,
					gravity = -45,
					squash = { 0.8, -0.3 },
					orientation = "VelocityParallel",
					lightEmission = 0,
					lightInfluence = 0.6,
				}),
				R.ring("#FF6B5A", {
					style = "disc",
					radius = { 0.4, 2.2 },
					thickness = 0.08,
					time = 0.5,
					easing = "backOut",
					transparency = { 0.3, 1 },
				}),
				R.dust({
					name = "mist",
					colors = { "#FFC2BA", "#FF8A7A" },
					burst = 4,
					sizes = { 0.4, 1.1, 1.4 },
					speed = { 2, 4 },
					tint = true,
					optional = true,
				})
			),
		},
	}),
	R.preset({
		id = "HeartBurst",
		name = "Heart burst",
		category = "feeding",
		description = "One big heart swells in the middle while small hearts pop outward, brake and float up.",
		color = "#FF4D7A",
		tags = { "heart", "love", "feed", "like" },
		data = {
			duration = 0.9,
			minInterval = 0.1,
			layers = R.join(
				P({
					name = "bigHeart",
					texture = "heart",
					colors = { "#FFC2D4", "#FF4D7A" },
					sizes = { 0, 2.4, 1.8, 0 },
					transparency = { 0, 0, 0.2, 1 },
					lifetime = { 0.6, 0.7 },
					speed = { 0.5, 1 },
					spread = { 0, 0 },
					burst = 1,
					rotation = { -12, 12 },
					lightEmission = 0.4,
					zOffset = 0.5,
				}),
				P({
					name = "hearts",
					texture = "heart",
					colors = { "#FFC2D4", "#FF7EA0", "#FF4D7A" },
					sizes = { 0, 0.6, 0.5, 0 },
					lifetime = { 0.8, 1.2 },
					speed = { 8, 13 },
					burst = 10,
					gravity = 5,
					drag = 4,
					rotation = { -25, 25 },
					rotSpeed = { -40, 40 },
					lightEmission = 0.4,
				}),
				R.glow("#FF4D7A", { sizes = { 0.6, 2.8, 2.2 }, transparency = { 0.6, 0.8, 1 } }),
				R.sparkles("#FFC2D4", { burst = 6 })
			),
		},
	}),
	R.preset({
		id = "CrumbBurst",
		name = "Crumb burst",
		category = "feeding",
		description = "A bite: matte crumbs scatter upward and drop quickly, with a small puff of flour.",
		color = "#D9A066",
		tags = { "food", "crumb", "bite", "eat", "cheap" },
		data = {
			duration = 0.4,
			minInterval = 0.05,
			layers = R.join(
				P({
					name = "crumbs",
					texture = "shard",
					colors = { "#F2D2A6", "#D9A066", "#A8743C" },
					sizes = { 0.22, 0.18, 0.12 },
					transparency = { 0, 0, 0, 1 },
					lifetime = { 0.4, 0.7 },
					speed = { 5, 10 },
					spread = { 60, 60 },
					burst = 12,
					gravity = -50,
					rotSpeed = { -500, 500 },
					lightEmission = 0,
					lightInfluence = 0.8,
				}),
				R.dust({ name = "flour", burst = 3, sizes = { 0.3, 0.8, 1 }, speed = { 1, 3 }, optional = true })
			),
		},
	}),
	R.preset({
		id = "TapPop",
		name = "Tap pop",
		category = "feeding",
		description = "The smallest touch feedback: a quick ring, five short streaks and a dot of glow. Safe to "
			.. "fire on every tap.",
		color = "#FFE45C",
		tags = { "tap", "click", "touch", "pop", "cheap" },
		data = {
			duration = 0.25,
			minInterval = 0.03,
			layers = R.join(
				R.ring("#FFE45C", { radius = { 0.2, 1.6 }, thickness = 0.16, time = 0.22 }),
				R.streaks(
					"#FFE45C",
					{ burst = 5, speed = { 10, 16 }, lifetime = { 0.12, 0.2 }, sizes = { 0.35, 0.2, 0 } }
				),
				R.glow("#FFE45C", { burst = 1, sizes = { 0.3, 1.2, 0.8 }, lifetime = { 0.14, 0.2 } })
			),
		},
	}),
}

return presets
