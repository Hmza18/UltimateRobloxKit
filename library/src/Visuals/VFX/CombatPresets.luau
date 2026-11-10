--!strict
-- Combat VFX presets (pure data): hits, bursts, shockwaves, ability activation and charge, the
-- eight-element burst, auras, the dash trail, the transformation and the cooldown ping.

local EffectLogic = require("./EffectLogic")
local Recipe = require("./RecipeLogic")
local Registry = require("../Core/Registry")

local R = Recipe
local P = Recipe.particles

-- One definition per element. Palettes come from EffectLogic.elementPalette; motion is what makes
-- them read differently: fire rises, ice brakes and sinks slowly, lightning is over in a blink,
-- water arcs under gravity, earth is chunky and heavy, wind is wide and fast with drag, light
-- radiates gently, dark implodes before it bursts.
local function element(name: string): EffectLogic.Definition
	local p = EffectLogic.elementPalette(name)
	if name == "fire" then
		return {
			duration = 1,
			layers = R.join(
				P({
					name = "flames",
					texture = "flare",
					colors = { "#FFF3B0", p.main, "#D63A0A" },
					sizes = { 0.6, 1.6, 0.4 },
					transparency = { 0.1, 0.3, 1 },
					lifetime = { 0.5, 0.9 },
					speed = { 5, 11 },
					spread = { 70, 70 },
					burst = 18,
					gravity = 9,
					drag = 2,
					rotSpeed = { -90, 90 },
					lightEmission = 1,
				}),
				P({
					name = "embers",
					colors = { "#FFF3B0", p.accent, p.main },
					sizes = { 0.22, 0.16, 0 },
					lifetime = { 0.8, 1.4 },
					speed = { 8, 16 },
					spread = { 60, 60 },
					burst = 14,
					gravity = 3,
					drag = 2.5,
					lightEmission = 1,
				}),
				R.dust({
					name = "smoke",
					delay = 0.15,
					colors = { "#4A4440", "#2B2826" },
					burst = 5,
					spread = { 30, 30 },
					speed = { 3, 6 },
					gravity = 4,
					optional = true,
				}),
				R.flash(p.accent, { sizes = { 0.6, 3.5 } }),
				R.light(p.main, { range = 16, brightness = 3, fadeOut = 0.6 })
			),
		}
	elseif name == "ice" then
		return {
			duration = 1.2,
			layers = R.join(
				P({
					name = "shards",
					texture = "shard",
					colors = { "#FFFFFF", p.accent, p.main },
					sizes = { 0, 0.7, 0.6, 0.4 },
					transparency = { 0, 0.1, 0.2, 1 },
					lifetime = { 1, 1.5 },
					speed = { 10, 18 },
					burst = 14,
					gravity = -6,
					drag = 4,
					rotSpeed = { -60, 60 },
					lightEmission = 0.4,
				}),
				R.groundDust({ name = "frost", colors = { "#FFFFFF", "#D6F4FF" }, burst = 8, tint = true }),
				P({
					name = "snow",
					colors = { "#FFFFFF", p.accent },
					sizes = { 0.14, 0.14, 0 },
					lifetime = { 1.4, 2 },
					speed = { 1, 4 },
					burst = 10,
					gravity = -3,
					drag = 1.5,
					lightEmission = 0.5,
					optional = true,
				}),
				R.ring(p.main, { radius = { 0.6, 6 }, time = 0.7, easing = "cubicOut", transparency = { 0.3, 1 } }),
				R.light(p.main, { range = 12, brightness = 1.4, fadeOut = 0.7 })
			),
		}
	elseif name == "lightning" then
		return {
			duration = 0.5,
			layers = R.join(
				R.streaks(p.main, { name = "bolts", burst = 18, speed = { 40, 70 }, lifetime = { 0.1, 0.22 } }),
				R.streaks(p.accent, {
					name = "crack",
					delay = 0.08,
					burst = 8,
					speed = { 30, 55 },
					lifetime = { 0.1, 0.18 },
				}),
				R.flash("#FFFFFF", { sizes = { 1, 7 }, time = 0.1, transparency = { 0.1, 1 } }),
				R.light(p.main, { range = 24, brightness = 5, fadeIn = 0.02, hold = 0.03, fadeOut = 0.15 }),
				P({
					name = "sparks",
					colors = { "#FFFFFF", p.main },
					sizes = { 0.2, 0.1, 0 },
					lifetime = { 0.3, 0.6 },
					speed = { 6, 14 },
					burst = 8,
					gravity = -20,
					lightEmission = 1,
					optional = true,
				}),
				R.shake("Tap")
			),
		}
	elseif name == "water" then
		return {
			duration = 1,
			layers = R.join(
				P({
					name = "drops",
					texture = "drop",
					colors = { "#FFFFFF", p.accent, p.main },
					sizes = { 0.35, 0.3, 0.15 },
					transparency = { 0.1, 0.2, 1 },
					lifetime = { 0.7, 1.1 },
					speed = { 14, 22 },
					spread = { 50, 50 },
					burst = 20,
					gravity = -55,
					squash = { 1.2, 0.4 },
					orientation = "VelocityParallel",
					lightEmission = 0.3,
				}),
				R.ring(p.main, { radius = { 0.5, 6 }, time = 0.6, easing = "cubicOut" }),
				R.dust({ name = "mist", colors = { "#FFFFFF", "#DDF2FF" }, burst = 6, speed = { 2, 5 } }),
				P({
					name = "spray",
					texture = "drop",
					colors = { "#FFFFFF", p.accent },
					sizes = { 0.15, 0.1, 0 },
					lifetime = { 0.4, 0.8 },
					speed = { 6, 12 },
					spread = { 80, 80 },
					burst = 10,
					gravity = -40,
					lightEmission = 0.3,
					optional = true,
				})
			),
		}
	elseif name == "earth" then
		return {
			duration = 1,
			layers = R.join(
				P({
					name = "rocks",
					texture = "shard",
					colors = { "#B58A5A", p.main, "#5E3F22" },
					sizes = { 0.9, 0.8, 0.6 },
					transparency = { 0, 0, 0, 1 },
					lifetime = { 0.7, 1.1 },
					speed = { 12, 20 },
					spread = { 60, 60 },
					burst = 10,
					gravity = -75,
					rotSpeed = { -300, 300 },
					lightEmission = 0,
					lightInfluence = 1,
				}),
				P({
					name = "pebbles",
					texture = "shard",
					colors = { "#C9A27A", p.main },
					sizes = { 0.3, 0.25, 0.2 },
					transparency = { 0, 0, 0, 1 },
					lifetime = { 0.6, 1 },
					speed = { 9, 18 },
					spread = { 75, 75 },
					burst = 12,
					gravity = -70,
					rotSpeed = { -400, 400 },
					lightEmission = 0,
					lightInfluence = 1,
					optional = true,
				}),
				R.groundDust({ burst = 12, sizes = { 0.8, 2.4, 3.2 }, colors = { "#C9B08E", "#9C8468" } }),
				R.shake("Impact", { amount = 0.6 })
			),
		}
	elseif name == "wind" then
		return {
			duration = 0.8,
			layers = R.join(
				R.streaks(p.main, {
					name = "gusts",
					emissionDirection = "Front",
					spread = { 25, 180 },
					speed = { 28, 42 },
					drag = 4,
					lifetime = { 0.35, 0.6 },
					burst = 16,
					sizes = { 0, 0.5, 0.4, 0 },
					squash = { 2.2, 1 },
					transparency = { 0.3, 0.5, 1 },
					lightEmission = 0.5,
				}),
				R.groundDust({ name = "swirl", colors = { "#FFFFFF", "#EAF7F1" }, burst = 8, speed = { 10, 16 } }),
				R.ring(p.main, { radius = { 1, 10 }, thickness = 0.2, time = 0.4, transparency = { 0.5, 1 } }),
				P({
					name = "debris",
					texture = "leaf",
					colors = { p.accent, p.main },
					sizes = { 0.25, 0.25, 0.15 },
					lifetime = { 0.6, 1 },
					speed = { 14, 24 },
					spread = { 30, 180 },
					emissionDirection = "Front",
					burst = 6,
					drag = 3,
					rotSpeed = { -600, 600 },
					lightEmission = 0.2,
					optional = true,
				})
			),
		}
	elseif name == "light" then
		return {
			duration = 1.1,
			layers = R.join(
				P({
					name = "rays",
					texture = "streak",
					colors = { "#FFFFFF", p.main },
					sizes = { 0, 5, 5, 0 },
					transparency = { 1, 0.6, 0.7, 1 },
					lifetime = { 0.7, 0.9 },
					speed = { 0, 0 },
					burst = 5,
					rotSpeed = { 30, 60 },
					lightEmission = 1,
					lockedToPart = true,
				}),
				P({
					name = "motes",
					colors = { "#FFFFFF", p.main },
					sizes = { 0, 0.35, 0 },
					lifetime = { 0.9, 1.4 },
					speed = { 3, 7 },
					burst = 16,
					gravity = 2.5,
					drag = 2,
					lightEmission = 1,
				}),
				R.ring(p.main, { radius = { 0.6, 7 }, time = 0.6, easing = "cubicOut" }),
				R.flash(p.accent, { sizes = { 1, 5 }, time = 0.25, transparency = { 0.4, 1 } }),
				R.light(p.main, { range = 20, brightness = 3, fadeIn = 0.1, hold = 0.1, fadeOut = 0.7 })
			),
		}
	end
	-- dark
	return {
		duration = 1,
		layers = R.join(
			R.inward(p.main, 4, {
				burst = 18,
				colors = { p.main, p.accent },
				lightEmission = 0.2,
				lifetime = { 0.3, 0.36 },
			}),
			P({
				name = "void",
				texture = "smoke",
				colors = { p.accent, "#000000" },
				sizes = { 3.2, 1.4, 0.3 },
				transparency = { 0.6, 0.2, 0 },
				lifetime = { 0.33, 0.36 },
				speed = { 0, 0 },
				burst = 3,
				lightEmission = 0,
				lightInfluence = 0,
				lockedToPart = true,
			}),
			R.ring(p.main, {
				radius = { 6, 0.4 },
				transparency = { 0.7, 0 },
				time = 0.34,
				easing = "cubicIn",
				thickness = 0.3,
			}),
			P({
				name = "burst",
				delay = 0.35,
				colors = { "#D9B8FF", p.main, p.accent },
				sizes = { 0, 0.55, 0.3, 0 },
				lifetime = { 0.5, 0.9 },
				speed = { 12, 20 },
				burst = 14,
				drag = 4,
				lightEmission = 0.6,
			}),
			R.dust({
				name = "wisps",
				delay = 0.35,
				colors = { "#2A1450", "#120824" },
				burst = 6,
				spread = { 40, 40 },
				gravity = 3,
				optional = true,
			}),
			R.light(p.main, { delay = 0.3, range = 12, brightness = 1.6, fadeOut = 0.6 })
		),
	}
end

local function elementBurst(): EffectLogic.Definition
	local variants: { [string]: EffectLogic.Definition } = {}
	for _, name in EffectLogic.ELEMENTS do
		variants[name] = element(name)
	end
	local base = table.clone(variants.fire)
	base.variantParam = "element"
	base.variants = variants
	base.minInterval = 0.08
	return base
end

local presets: { Registry.Preset } = {
	R.preset({
		id = "ImpactFlash",
		name = "Impact flash",
		category = "combat",
		description = "The smallest hit marker: a two-frame orb, a few radial streaks and a tiny glow.",
		color = "#FFE9A8",
		tags = { "hit", "impact", "flash", "cheap" },
		data = {
			duration = 0.2,
			minInterval = 0.04,
			layers = R.join(
				R.flash("#FFE9A8", { sizes = { 0.5, 2.6 }, time = 0.1 }),
				R.streaks("#FFE9A8", { burst = 8, speed = { 18, 30 }, lifetime = { 0.1, 0.2 } }),
				R.glow("#FFE9A8", { burst = 1, sizes = { 0.4, 1.6, 1 }, lifetime = { 0.15, 0.2 } })
			),
		},
	}),
	R.preset({
		id = "EnergyBurst",
		name = "Energy burst",
		category = "combat",
		description = "A radial release of energy: sparks that brake hard, fast streaks, a ring and a light pop.",
		color = "#56C8FF",
		tags = { "energy", "burst", "ability" },
		data = {
			duration = 0.7,
			minInterval = 0.08,
			layers = R.join(
				P({
					name = "sparks",
					colors = { "#FFFFFF", "#9FE2FF", "#56C8FF" },
					sizes = { 0, 0.5, 0.25, 0 },
					lifetime = { 0.4, 0.8 },
					speed = { 14, 24 },
					burst = 26,
					drag = 5,
					lightEmission = 1,
				}),
				R.streaks("#56C8FF", { burst = 14 }),
				R.ring("#56C8FF", { radius = { 0.6, 7 }, time = 0.4 }),
				R.glow("#56C8FF"),
				R.light("#56C8FF", { range = 16, brightness = 3 })
			),
		},
	}),
	R.preset({
		id = "Shockwave",
		name = "Shockwave",
		category = "combat",
		description = "A ground-pound: a thick ring races out, a thinner echo follows, dust rolls along the floor "
			.. "and the camera takes an impact shake.",
		color = "#DDEBFF",
		tags = { "shockwave", "slam", "ring", "impact" },
		data = {
			duration = 0.8,
			minInterval = 0.15,
			priority = 3,
			layers = R.join(
				R.ring("#DDEBFF", { radius = { 1, 14 }, thickness = 0.7, time = 0.55 }),
				R.ring("#FFFFFF", {
					name = "echo",
					delay = 0.08,
					radius = { 1, 11 },
					thickness = 0.25,
					time = 0.55,
					optional = true,
				}),
				R.groundDust({ burst = 16, speed = { 12, 20 }, sizes = { 0.8, 2.2, 3 } }),
				R.flash("#FFFFFF", { sizes = { 1, 6 }, time = 0.12 }),
				R.light("#DDEBFF", { range = 18, brightness = 2.5, optional = true }),
				R.shake("Impact")
			),
		},
	}),
	R.preset({
		id = "HitConfirm",
		name = "Hit confirm",
		category = "combat",
		description = "A red-orange slash of sparks with heavier chips that drop away: reads as damage dealt.",
		color = "#FF5A4A",
		tags = { "hit", "damage", "confirm", "cheap" },
		data = {
			duration = 0.3,
			minInterval = 0.04,
			layers = R.join(
				R.streaks("#FF5A4A", {
					burst = 6,
					speed = { 20, 34 },
					spread = { 35, 35 },
					lifetime = { 0.12, 0.22 },
					sizes = { 0.7, 0.4, 0 },
				}),
				P({
					name = "chips",
					colors = { "#FFD0B0", "#FF5A4A" },
					sizes = { 0.22, 0.16, 0 },
					lifetime = { 0.35, 0.6 },
					speed = { 6, 12 },
					spread = { 70, 70 },
					burst = 5,
					gravity = -40,
					lightEmission = 0.8,
				}),
				R.glow("#FF5A4A", { burst = 1, sizes = { 0.4, 1.8, 1.2 }, lifetime = { 0.14, 0.2 } })
			),
		},
	}),
	R.preset({
		id = "AbilityActivate",
		name = "Ability activate",
		category = "combat",
		description = "An ability goes off: a ground ring, streaks shooting upward and an outline pulse on the caster.",
		color = "#7C6BFF",
		tags = { "ability", "activate", "cast" },
		usage = 'Visuals:Play("AbilityActivate", character)',
		data = {
			duration = 0.6,
			minInterval = 0.1,
			layers = R.join(
				R.ring("#7C6BFF", { radius = { 0.6, 6 }, time = 0.4 }),
				R.streaks("#7C6BFF", {
					burst = 14,
					speed = { 16, 26 },
					spread = { 14, 14 },
					shape = "Cylinder",
					shapeSize = { 4, 0.2, 4 },
				}),
				R.highlight("#7C6BFF", { fadeIn = 0.05, hold = 0.1, fadeOut = 0.4 }),
				R.glow("#7C6BFF", { offset = { 0, 1, 0 } }),
				R.light("#7C6BFF", { range = 14, brightness = 2.4 })
			),
		},
	}),
	R.preset({
		id = "AbilityCharge",
		name = "Ability charge",
		category = "combat",
		description = "Looping wind-up: motes spiral in to a growing core while the light pulses faster than an aura.",
		color = "#FFB03A",
		tags = { "ability", "charge", "loop", "windup" },
		usage = 'local handle = Visuals:Attach("AbilityCharge", character)',
		data = {
			looping = true,
			layers = R.join(
				R.inward("#FFB03A", 4, { rate = 30, rotSpeed = { -300, 300 } }),
				P({
					name = "core",
					texture = "glow",
					colors = { "#FFFFFF", "#FFB03A" },
					sizes = { 0.6, 2.4, 0.6 },
					transparency = { 1, 0.5, 1 },
					lifetime = { 0.5, 0.7 },
					speed = { 0, 0 },
					rate = 3,
					lightEmission = 1,
					lockedToPart = true,
				}),
				R.streaks("#FFE2A8", {
					name = "ground",
					burst = false,
					rate = 8,
					speed = { 6, 10 },
					spread = { 4, 4 },
					lifetime = { 0.3, 0.5 },
					shape = "Cylinder",
					shapeSize = { 5, 0.2, 5 },
					offset = { 0, -2.5, 0 },
					optional = true,
				}),
				R.light("#FFB03A", { range = 12, brightness = 2, fadeIn = 0.2, pulse = { 0.5, 0.4 } })
			),
		},
	}),
	R.preset({
		id = "ElementBurst",
		name = "Element burst",
		category = "combat",
		description = "One burst, eight elements. Each has its own palette and motion: fire rises, ice brakes and "
			.. "sinks, lightning blinks, water arcs, earth is heavy, wind is wide, light radiates, dark implodes.",
		color = EffectLogic.elementPalette("fire").main,
		tags = { "element", "fire", "ice", "lightning", "water", "earth", "wind", "light", "dark" },
		params = {
			element = {
				type = "enum",
				default = "fire",
				options = table.clone(EffectLogic.ELEMENTS),
				description = "Which element to play",
			},
		},
		usage = 'Visuals:Play("ElementBurst", position, { element = "ice" })',
		data = elementBurst(),
	}),
	R.preset({
		id = "Aura",
		name = "Aura",
		category = "combat",
		description = "A flame-like looping aura in any colour: wisps lick upward from the feet with rising sparks.",
		color = "#56C8FF",
		tags = { "aura", "loop", "power", "buff" },
		usage = 'local handle = Visuals:Attach("Aura", character, { color = "#FF5A4A" })',
		data = {
			looping = true,
			layers = R.join(
				P({
					name = "wisps",
					texture = "flare",
					colors = { "#FFFFFF", "#9FE2FF", "#56C8FF" },
					sizes = { 0.8, 1.4, 0 },
					transparency = { 0.5, 0.6, 1 },
					lifetime = { 0.6, 1 },
					speed = { 2.5, 4.5 },
					spread = { 10, 10 },
					rate = 14,
					rotSpeed = { -60, 60 },
					shape = "Cylinder",
					shapeSize = { 3.5, 0.4, 3.5 },
					offset = { 0, -2, 0 },
					lightEmission = 1,
				}),
				P({
					name = "sparks",
					colors = { "#FFFFFF", "#56C8FF" },
					sizes = { 0.18, 0.12, 0 },
					lifetime = { 0.8, 1.3 },
					speed = { 3, 6 },
					spread = { 15, 15 },
					rate = 6,
					shape = "Cylinder",
					shapeSize = { 4, 0.4, 4 },
					offset = { 0, -2, 0 },
					lightEmission = 1,
					optional = true,
				}),
				R.light("#56C8FF", { range = 10, brightness = 1.4, fadeIn = 0.3, pulse = { 1.6, 0.25 } })
			),
		},
	}),
	R.preset({
		id = "DashTrail",
		name = "Dash trail",
		category = "combat",
		description = "A short, hot ribbon behind a dashing part with a thin scatter of streaks left in its wake.",
		color = "#FFFFFF",
		tags = { "dash", "trail", "loop", "movement" },
		usage = 'local handle = Visuals:Attach("DashTrail", character.HumanoidRootPart)',
		data = {
			looping = true,
			layers = R.join(
				R.trail("#BFE8FF", { time = 0.28, width = { 2.4 } }),
				R.streaks("#BFE8FF", {
					name = "wake",
					burst = false,
					rate = 14,
					speed = { 0, 1 },
					lifetime = { 0.2, 0.35 },
					sizes = { 0.4, 0.2, 0 },
				})
			),
		},
	}),
	R.preset({
		id = "Transformation",
		name = "Transformation",
		category = "combat",
		description = "A full power-up: energy is pulled in under three widening rings, a column builds, then a "
			.. "flash, a pillar, a heavy shake and a burst that leaves embers hanging.",
		color = "#FFD23F",
		tags = { "transform", "powerup", "big", "expensive" },
		usage = 'Visuals:Play("Transformation", character)',
		data = {
			duration = 2.6,
			minInterval = 1,
			priority = 10,
			layers = R.join(
				R.inward("#FFD23F", 6, { rate = 50, emitFor = 1 }),
				R.streaks("#FFF0B0", {
					name = "column",
					burst = false,
					rate = 40,
					emitFor = 1.2,
					speed = { 14, 22 },
					spread = { 4, 4 },
					lifetime = { 0.3, 0.5 },
					drag = 1,
					shape = "Cylinder",
					shapeSize = { 5, 0.2, 5 },
					offset = { 0, -2.5, 0 },
				}),
				R.ring("#FFD23F", { radius = { 0.5, 5 }, time = 0.4, offset = { 0, -2.5, 0 } }),
				R.ring(
					"#FFD23F",
					{ name = "ring2", delay = 0.4, radius = { 0.5, 7 }, time = 0.4, offset = { 0, -2.5, 0 } }
				),
				R.ring(
					"#FFD23F",
					{ name = "ring3", delay = 0.8, radius = { 0.5, 9 }, time = 0.4, offset = { 0, -2.5, 0 } }
				),
				R.flash("#FFFFFF", { delay = 1.2, sizes = { 2, 14 }, time = 0.25 }),
				P({
					name = "burst",
					delay = 1.2,
					colors = { "#FFFFFF", "#FFF0B0", "#FFD23F" },
					sizes = { 0, 0.7, 0.4, 0 },
					lifetime = { 0.6, 1.1 },
					speed = { 20, 34 },
					burst = 40,
					drag = 4,
					lightEmission = 1,
				}),
				R.ring("#FFFFFF", {
					name = "blast",
					delay = 1.2,
					radius = { 1, 18 },
					thickness = 0.6,
					time = 0.6,
					offset = { 0, -2.5, 0 },
				}),
				R.beam("#FFD23F", { delay = 1.2, length = 40, width = { 4, 1.5 }, hold = 0.6, fadeOut = 0.7 }),
				R.light("#FFD23F", { delay = 0.2, range = 26, brightness = 4, fadeIn = 1, hold = 0.4, fadeOut = 0.9 }),
				R.highlight("#FFD23F", { delay = 1.15, fadeIn = 0.05, hold = 0.3, fadeOut = 0.9 }),
				P({
					name = "embers",
					delay = 1.3,
					colors = { "#FFF0B0", "#FFD23F", "#C98A00" },
					sizes = { 0.25, 0.18, 0 },
					lifetime = { 1.4, 2.2 },
					speed = { 2, 7 },
					burst = 20,
					gravity = 3,
					drag = 2,
					lightEmission = 1,
					optional = true,
				}),
				R.postfx("bloom", { delay = 1.15, amount = 0.7, fadeOut = 0.8 }),
				R.postfx("color", { delay = 1.15, amount = 0.4, fadeOut = 0.5 }),
				R.shake("HeavyImpact", { delay = 1.2 })
			),
		},
	}),
	R.preset({
		id = "CooldownReady",
		name = "Cooldown ready",
		category = "combat",
		description = "A quiet ping that an ability is back: a small ring, a glyph pop above and rising sparkles.",
		color = "#7CFFB2",
		tags = { "cooldown", "ready", "ping", "ui" },
		usage = 'Visuals:Play("CooldownReady", character)',
		data = {
			duration = 0.5,
			minInterval = 0.2,
			layers = R.join(
				R.ring("#7CFFB2", { radius = { 0.3, 2.2 }, thickness = 0.22, time = 0.3 }),
				{
					kind = "billboard",
					name = "glyph",
					image = "star",
					colors = { "#7CFFB2" },
					sizes = { 0, 1.6, 1.1 },
					time = 0.45,
					rise = 0.6,
					offset = { 0, 3, 0 },
					easing = "backOut",
				},
				R.sparkles("#7CFFB2", {
					burst = 6,
					speed = { 3, 6 },
					spread = { 30, 30 },
					gravity = 2,
					lifetime = { 0.4, 0.7 },
					optional = false,
				})
			),
		},
	}),
}

return presets
