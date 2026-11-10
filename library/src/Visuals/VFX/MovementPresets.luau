--!strict
-- Movement VFX presets (pure data): trails, jump and landing puffs, double jump, sprint streaks and
-- a feet-level aura. Trails need a moving BasePart, so attach them to the character's root part.

local Recipe = require("./RecipeLogic")
local Registry = require("../Core/Registry")

local R = Recipe
local P = Recipe.particles

local presets: { Registry.Preset } = {
	R.preset({
		id = "SpeedTrail",
		name = "Speed trail",
		category = "movement",
		description = "A long two-layer ribbon for sustained speed: a wide coloured band with a thin white core.",
		color = "#4FD8FF",
		tags = { "speed", "trail", "loop", "boost" },
		usage = 'local handle = Visuals:Attach("SpeedTrail", character.HumanoidRootPart)',
		data = {
			looping = true,
			layers = R.join(
				R.trail("#4FD8FF", {
					name = "band",
					time = 0.55,
					width = { 2.6 },
					colors = { "#9BE8FF", "#4FD8FF", "#2F6BFF" },
					transparency = { 0.35, 0.6, 1 },
				}),
				R.trail("#FFFFFF", {
					name = "core",
					time = 0.3,
					width = { 0.7 },
					colors = { "#FFFFFF" },
					transparency = { 0, 0.4, 1 },
					tint = false,
				}),
				P({
					name = "flecks",
					colors = { "#FFFFFF", "#4FD8FF" },
					sizes = { 0.2, 0.12, 0 },
					lifetime = { 0.3, 0.6 },
					speed = { 0, 1.5 },
					rate = 10,
					lightEmission = 1,
				})
			),
		},
	}),
	R.preset({
		id = "JumpBurst",
		name = "Jump burst",
		category = "movement",
		description = "Take-off puff: dust fans out along the ground under a quick ring and a few upward streaks.",
		color = "#FFFFFF",
		tags = { "jump", "takeoff", "dust", "cheap" },
		usage = 'Visuals:Play("JumpBurst", footPosition)',
		data = {
			duration = 0.4,
			minInterval = 0.1,
			layers = R.join(
				R.groundDust({ burst = 8, speed = { 5, 9 }, sizes = { 0.4, 1.2, 1.6 } }),
				R.ring("#FFFFFF", { radius = { 0.4, 2.6 }, thickness = 0.2, time = 0.25, transparency = { 0.4, 1 } }),
				R.streaks("#FFFFFF", {
					burst = 4,
					speed = { 12, 18 },
					spread = { 12, 12 },
					transparency = { 0.4, 0.6, 1 },
					optional = true,
				})
			),
		},
	}),
	R.preset({
		id = "LandingDust",
		name = "Landing dust",
		category = "movement",
		description = "A landing thump: a wide low dust roll, kicked-up grit and a faint ground disc. Scale it "
			.. "with fall speed.",
		color = "#E6DCCB",
		tags = { "land", "dust", "impact", "fall" },
		usage = 'Visuals:Play("LandingDust", footPosition, { scale = fallSpeed / 50 })',
		data = {
			duration = 0.5,
			minInterval = 0.1,
			layers = R.join(
				R.groundDust({ burst = 12, speed = { 8, 14 }, sizes = { 0.6, 1.8, 2.5 } }),
				P({
					name = "grit",
					texture = "shard",
					colors = { "#CDBFA8", "#A8977C" },
					sizes = { 0.18, 0.15, 0.1 },
					transparency = { 0, 0, 0, 1 },
					lifetime = { 0.35, 0.6 },
					speed = { 6, 12 },
					spread = { 65, 65 },
					burst = 5,
					gravity = -55,
					lightEmission = 0,
					lightInfluence = 1,
					tint = false,
					optional = true,
				}),
				R.ring("#FFFFFF", {
					style = "disc",
					radius = { 0.5, 3.4 },
					thickness = 0.08,
					time = 0.3,
					transparency = { 0.75, 1 },
				})
			),
		},
	}),
	R.preset({
		id = "DoubleJump",
		name = "Double jump",
		category = "movement",
		description = "A mid-air kick: a ring opens under the feet, a soft cloud is pushed downward and sparkles pop.",
		color = "#8FE3FF",
		tags = { "jump", "double", "air", "ring" },
		usage = 'Visuals:Play("DoubleJump", footPosition)',
		data = {
			duration = 0.45,
			minInterval = 0.1,
			layers = R.join(
				R.ring("#8FE3FF", { radius = { 0.5, 3.6 }, thickness = 0.35, time = 0.32 }),
				R.dust({
					name = "cloud",
					colors = { "#FFFFFF", "#DDF6FF" },
					emissionDirection = "Bottom",
					spread = { 40, 40 },
					speed = { 5, 9 },
					burst = 8,
					gravity = 0,
					tint = true,
				}),
				R.sparkles("#8FE3FF", { burst = 6, speed = { 3, 7 }, lifetime = { 0.35, 0.6 } })
			),
		},
	}),
	R.preset({
		id = "SprintStreaks",
		name = "Sprint streaks",
		category = "movement",
		description = "Looping speed lines that whip backward past a sprinting character, with dust at the feet.",
		color = "#FFFFFF",
		tags = { "sprint", "run", "speedlines", "loop" },
		usage = 'local handle = Visuals:Attach("SprintStreaks", character.HumanoidRootPart)',
		data = {
			looping = true,
			layers = R.join(
				R.streaks("#FFFFFF", {
					name = "lines",
					burst = false,
					rate = 16,
					emissionDirection = "Back",
					spread = { 2, 2 },
					speed = { 20, 30 },
					lifetime = { 0.2, 0.3 },
					drag = 0,
					sizes = { 0, 0.3, 0.3, 0 },
					squash = { 2.5, 2.5 },
					transparency = { 1, 0.5, 0.6, 1 },
					lightEmission = 0.6,
					shape = "Box",
					shapeSize = { 5, 5, 1 },
					offset = { 0, 0, -2 },
				}),
				R.dust({
					name = "feet",
					burst = false,
					rate = 5,
					emissionDirection = "Back",
					spread = { 20, 20 },
					speed = { 2, 5 },
					sizes = { 0.3, 0.9, 1.2 },
					lifetime = { 0.4, 0.7 },
					offset = { 0, -2.8, 0 },
					optional = true,
				})
			),
		},
	}),
	R.preset({
		id = "TeleportTrail",
		name = "Teleport trail",
		category = "movement",
		description = "A long shimmering two-tone ribbon that pinches and swells, shedding glitter and afterglow.",
		color = "#B56BFF",
		tags = { "teleport", "trail", "loop", "warp", "magic" },
		usage = 'local handle = Visuals:Attach("TeleportTrail", character.HumanoidRootPart)',
		data = {
			looping = true,
			layers = R.join(
				R.trail("#B56BFF", {
					time = 0.6,
					width = { 3 },
					colors = { "#FFFFFF", "#B56BFF", "#4FD8FF" },
					widthScale = { 0.3, 1, 0.4, 0 },
					transparency = { 0.2, 0.5, 1 },
				}),
				R.sparkles("#B56BFF", {
					name = "glitter",
					burst = false,
					rate = 18,
					speed = { 0, 2 },
					lifetime = { 0.5, 0.9 },
					shape = "Sphere",
					shapeSize = { 2.5, 4, 2.5 },
					optional = false,
				}),
				P({
					name = "afterglow",
					texture = "glow",
					colors = { "#B56BFF", "#4FD8FF" },
					sizes = { 2, 1.4, 0.4 },
					transparency = { 0.7, 0.85, 1 },
					lifetime = { 0.4, 0.6 },
					speed = { 0, 0 },
					rate = 6,
					lightEmission = 1,
					optional = true,
				})
			),
		},
	}),
	R.preset({
		id = "MovementAura",
		name = "Movement aura",
		category = "movement",
		description = "A feet-level loop for a speed or jump buff: wisps skim the ground while motes lift off a ring.",
		color = "#7CFFB2",
		tags = { "aura", "buff", "loop", "feet" },
		usage = 'local handle = Visuals:Attach("MovementAura", character.HumanoidRootPart)',
		data = {
			looping = true,
			layers = R.join(
				P({
					name = "motes",
					colors = { "#FFFFFF", "#7CFFB2" },
					sizes = { 0, 0.22, 0 },
					lifetime = { 0.7, 1.1 },
					speed = { 2, 4 },
					spread = { 5, 5 },
					rate = 12,
					shape = "Cylinder",
					shapeStyle = "Surface",
					shapeSize = { 4, 0.3, 4 },
					offset = { 0, -2.8, 0 },
					lightEmission = 1,
				}),
				R.streaks("#7CFFB2", {
					name = "skim",
					burst = false,
					rate = 8,
					emissionDirection = "Front",
					spread = { 4, 180 },
					speed = { 3, 5 },
					lifetime = { 0.4, 0.6 },
					drag = 1,
					sizes = { 0, 0.3, 0 },
					offset = { 0, -2.8, 0 },
				}),
				R.light("#7CFFB2", {
					range = 7,
					brightness = 0.9,
					fadeIn = 0.3,
					offset = { 0, -2, 0 },
					optional = true,
				})
			),
		},
	}),
}

return presets
