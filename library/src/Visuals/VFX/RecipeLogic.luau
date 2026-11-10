--!strict
-- Layer recipes shared by the preset modules (pure Luau). Each recipe returns one layer with tuned
-- defaults - a sparkle cloud, a soft glow core, ground dust, a shockwave ring - and takes a table
-- of overrides, so a preset reads as a composition ("fountain + core glow + lingering sparkles")
-- instead of forty numbers per emitter. `Recipe.preset` adds the registry metadata every preset
-- shares: the common params, an honest cost label computed from the definition, and a usage line.

local EffectLogic = require("./EffectLogic")
local Registry = require("../Core/Registry")

type Layer = EffectLogic.Layer
type Definition = EffectLogic.Definition

local Recipe = {}

-- Copies `overrides` over `base`. A value of false for a non-boolean default removes the field.
local function merge(base: { [string]: any }, overrides: { [string]: any }?): Layer
	local out: { [string]: any } = table.clone(base)
	if overrides then
		for key, value in overrides do
			if value == false and type(base[key]) ~= "boolean" then
				out[key] = nil
			else
				out[key] = value
			end
		end
	end
	return out :: any
end
Recipe.merge = merge

-- Flattens layers and lists of layers into one list; nil entries are skipped.
function Recipe.join(...: any): { Layer }
	local out: { Layer } = {}
	for index = 1, select("#", ...) do
		local item = select(index, ...)
		if type(item) == "table" then
			if item.kind ~= nil then
				table.insert(out, item)
			else
				for _, layer in item do
					table.insert(out, layer)
				end
			end
		end
	end
	return out
end

-- A generic particle layer: pops in, fades out, random rotation. Give it burst or rate.
function Recipe.particles(overrides: { [string]: any }): Layer
	return merge({
		kind = "particles",
		texture = "spark",
		colors = { "#FFFFFF" },
		sizes = { 0.2, 0.5, 0 },
		transparency = { 0, 0.15, 1 },
		lifetime = { 0.5, 0.9 },
		speed = { 4, 9 },
		spread = { 180, 180 },
		rotation = { 0, 360 },
		lightEmission = 0.7,
	}, overrides)
end

-- Small twinkles that hang in the air after the main hit. Optional: dropped on Low.
function Recipe.sparkles(color: string, overrides: { [string]: any }?): Layer
	return merge({
		kind = "particles",
		name = "sparkles",
		texture = "spark",
		colors = { "#FFFFFF", EffectLogic.lighten(color, 0.3), color },
		sizes = { 0, 0.34, 0.12, 0 },
		transparency = { 0, 0, 0.3, 1 },
		lifetime = { 0.7, 1.3 },
		speed = { 1, 4 },
		spread = { 180, 180 },
		burst = 10,
		drag = 2,
		gravity = -1.5,
		rotation = { 0, 360 },
		rotSpeed = { -200, 200 },
		lightEmission = 1,
		optional = true,
	}, overrides)
end

-- One soft blob that swells and fades: the hot centre of a burst.
function Recipe.glow(color: string, overrides: { [string]: any }?): Layer
	return merge({
		kind = "particles",
		name = "glow",
		texture = "glow",
		colors = { EffectLogic.lighten(color, 0.7), color },
		sizes = { 0.6, 3.2, 2.4 },
		transparency = { 0.45, 0.7, 1 },
		lifetime = { 0.3, 0.42 },
		speed = { 0, 0 },
		spread = { 0, 0 },
		burst = 2,
		rotation = { 0, 360 },
		lightEmission = 1,
		lockedToPart = true,
		zOffset = 0.5,
	}, overrides)
end

-- Soft puffs that roll outward and settle. Never tinted: dust stays dust.
function Recipe.dust(overrides: { [string]: any }?): Layer
	return merge({
		kind = "particles",
		name = "dust",
		texture = "smoke",
		colors = { "#E6DCCB", "#C9BFAE" },
		sizes = { 0.5, 1.7, 2.3 },
		transparency = { 0.55, 0.78, 1 },
		lifetime = { 0.6, 1.1 },
		speed = { 3, 7 },
		spread = { 85, 85 },
		burst = 8,
		drag = 3.5,
		gravity = 1.2,
		rotation = { 0, 360 },
		rotSpeed = { -50, 50 },
		lightEmission = 0,
		lightInfluence = 1,
		tint = false,
	}, overrides)
end

-- Dust that rolls outward along the ground in every direction (a flat fan, not a dome).
function Recipe.groundDust(overrides: { [string]: any }?): Layer
	return merge(
		Recipe.dust({
			name = "groundDust",
			emissionDirection = "Front",
			spread = { 9, 180 },
			speed = { 6, 11 },
			drag = 4.5,
			gravity = 0.6,
		}) :: any,
		overrides
	)
end

-- Motes that start on a sphere around the origin and fly to its centre: charge-up and suction.
-- `radius` sets the sphere; speed and lifetime are tuned so particles die at the centre.
function Recipe.inward(color: string, radius: number, overrides: { [string]: any }?): Layer
	return merge({
		kind = "particles",
		name = "inward",
		texture = "spark",
		colors = { color, EffectLogic.lighten(color, 0.5), "#FFFFFF" },
		sizes = { 0, 0.35, 0.2 },
		transparency = { 1, 0.1, 0 },
		lifetime = { 0.36, 0.44 },
		speed = { radius * 2.2, radius * 2.6 },
		spread = { 0, 0 },
		shape = "Sphere",
		shapeStyle = "Surface",
		shapeInOut = "Inward",
		shapeSize = { radius * 2, radius * 2, radius * 2 },
		rotation = { 0, 360 },
		lightEmission = 1,
	}, overrides)
end

-- The `size` param of ambient effects (box width in studs).
function Recipe.sizeParam(default: number): Registry.Param
	return {
		type = "number",
		default = default,
		min = 4,
		max = 200,
		description = "Width of the emitting volume in studs; rates follow the area within limits",
	}
end

-- Fast streaks that stretch along their velocity: rays, speed lines, lightning shards.
function Recipe.streaks(color: string, overrides: { [string]: any }?): Layer
	return merge({
		kind = "particles",
		name = "streaks",
		texture = "streak",
		colors = { "#FFFFFF", color },
		sizes = { 0.5, 0.35, 0 },
		transparency = { 0, 0.2, 1 },
		lifetime = { 0.18, 0.35 },
		speed = { 22, 38 },
		spread = { 180, 180 },
		burst = 12,
		drag = 5,
		squash = { 1.6, 0.6 },
		orientation = "VelocityParallel",
		lightEmission = 1,
	}, overrides)
end

-- An expanding ground ring.
function Recipe.ring(color: string, overrides: { [string]: any }?): Layer
	return merge({
		kind = "ring",
		name = "ring",
		colors = { EffectLogic.lighten(color, 0.55), color },
		radius = { 0.6, 6 },
		thickness = 0.4,
		transparency = { 0.05, 1 },
		time = 0.45,
		easing = "quartOut",
		style = "line",
		lightEmission = 1,
	}, overrides)
end

-- A short world-space glow orb.
function Recipe.flash(color: string, overrides: { [string]: any }?): Layer
	return merge({
		kind = "flash",
		name = "flash",
		colors = { EffectLogic.lighten(color, 0.6) },
		sizes = { 0.8, 4.5 },
		transparency = { 0.25, 1 },
		time = 0.16,
		style = "orb",
	}, overrides)
end

-- A point light that pops and decays.
function Recipe.light(color: string, overrides: { [string]: any }?): Layer
	return merge({
		kind = "light",
		name = "light",
		light = "point",
		colors = { color },
		range = 14,
		brightness = 2.6,
		fadeIn = 0.04,
		hold = 0.06,
		fadeOut = 0.45,
	}, overrides)
end

-- A vertical pillar of light.
function Recipe.beam(color: string, overrides: { [string]: any }?): Layer
	return merge({
		kind = "beam",
		name = "beam",
		colors = { "#FFFFFF", EffectLogic.lighten(color, 0.3), color },
		transparency = { 0.15, 0.55, 1 },
		width = { 2.2, 1.2 },
		length = 36,
		segments = 8,
		lightEmission = 1,
		faceCamera = true,
		fadeIn = 0.12,
		hold = 0.6,
		fadeOut = 0.5,
	}, overrides)
end

function Recipe.trail(color: string, overrides: { [string]: any }?): Layer
	return merge({
		kind = "trail",
		name = "trail",
		colors = { "#FFFFFF", EffectLogic.lighten(color, 0.3), color },
		transparency = { 0.1, 0.5, 1 },
		time = 0.35,
		width = { 1.6 },
		widthScale = { 1, 0.6, 0 },
		minLength = 0.1,
		lightEmission = 1,
		faceCamera = true,
	}, overrides)
end

function Recipe.highlight(color: string, overrides: { [string]: any }?): Layer
	return merge({
		kind = "highlight",
		name = "highlight",
		colors = { color },
		outline = EffectLogic.lighten(color, 0.6),
		fillTransparency = 0.55,
		outlineTransparency = 0,
		depthMode = "Occluded",
		fadeIn = 0.08,
		hold = 0.1,
		fadeOut = 0.4,
		optional = true,
	}, overrides)
end

function Recipe.shake(preset: string, overrides: { [string]: any }?): Layer
	return merge({ kind = "shake", name = "shake", preset = preset, amount = 1 }, overrides)
end

function Recipe.sound(cue: string, overrides: { [string]: any }?): Layer
	return merge({ kind = "sound", name = "sound", cue = cue }, overrides)
end

function Recipe.postfx(effect: string, overrides: { [string]: any }?): Layer
	return merge({
		kind = "postfx",
		name = effect,
		effect = effect,
		amount = 0.5,
		fadeIn = 0.06,
		hold = 0.05,
		fadeOut = 0.5,
		optional = true,
	}, overrides)
end

-- One copy of `layer` per colour, sharing the burst (or rate) between them. A ParticleEmitter has
-- one colour ramp, so mixed-colour effects such as confetti are several small emitters.
function Recipe.multicolor(layer: Layer, colors: { string }): { Layer }
	local out: { Layer } = {}
	local count = #colors
	for index, color in colors do
		local copy = table.clone(layer)
		copy.colors = { color, EffectLogic.darken(color, 0.12) }
		copy.name = (layer.name or "color") .. tostring(index)
		if layer.burst then
			copy.burst = math.max(1, math.floor(layer.burst / count + 0.5))
		elseif layer.rate then
			copy.rate = layer.rate / count
		end
		-- Keep at least two colours on Low: the rest are optional.
		if index > 2 then
			copy.optional = true
		end
		table.insert(out, copy)
	end
	return out
end

-- low: up to 40 live particles and one light; medium: up to 120 and two lights; high: above that.
function Recipe.costLabel(def: Definition): string
	local cost = EffectLogic.cost(def)
	if cost.particles <= 40 and cost.lights <= 1 then
		return "low"
	elseif cost.particles <= 120 and cost.lights <= 2 then
		return "medium"
	end
	return "high"
end

export type Spec = {
	id: string,
	name: string,
	category: string,
	description: string,
	color: string, -- the preset's main colour; the default of the `color` param
	tags: { string },
	data: Definition,
	params: { [string]: Registry.Param }?,
	min: string?, -- lowest quality level that shows it
	usage: string?,
	preview: { [string]: any }?,
}

-- Builds the registry entry: common params (color, scale, intensity), cost label, usage, preview.
function Recipe.preset(spec: Spec): Registry.Preset
	local params: { [string]: Registry.Param } = {
		color = {
			type = "color",
			default = spec.color,
			description = "Tint. The default is the preset's own palette; any other colour recolours every layer",
		},
		scale = { type = "number", default = 1, min = 0.25, max = 4, description = "Size multiplier" },
		intensity = {
			type = "number",
			default = 1,
			min = 0,
			max = 2,
			description = "Particle count and light strength multiplier",
		},
	}
	local extra: { [string]: Registry.Param } = spec.params or {}
	for name, param in extra do
		params[name] = param
	end
	local looping = spec.data.looping == true
	local cost = EffectLogic.cost(spec.data)
	local usage = spec.usage
	if usage == nil then
		usage = if looping
			then string.format('local handle = Visuals:Attach("%s", part)', spec.id)
			else string.format('Visuals:Play("%s", position)', spec.id)
	end
	local preview: { [string]: any } = { distance = 14, background = "dark", loop = looping }
	local hints: { [string]: any } = spec.preview or {}
	for key, value in hints do
		preview[key] = value
	end
	preview.particles = cost.particles
	preview.lights = cost.lights
	return {
		id = spec.id,
		name = spec.name,
		category = spec.category,
		description = spec.description,
		params = params,
		quality = { min = spec.min or "Low", cost = Recipe.costLabel(spec.data) },
		dependencies = nil,
		preview = preview,
		usage = usage,
		tags = spec.tags,
		data = spec.data,
	}
end

Recipe.RARITY_PARAM = {
	type = "enum",
	default = "Common",
	options = table.clone(EffectLogic.RARITIES),
	description = "Rarity tier: sets palette, particle count, size, extra layers and duration",
} :: Registry.Param

export type Tier = {
	rarity: string,
	rank: number, -- 1 (Common) .. 7 (Secret)
	palette: EffectLogic.Palette,
	count: number, -- particle count multiplier
	size: number, -- size multiplier
	duration: number, -- seconds for the main beat
}

local TIERS: { { number } } = {
	{ 1, 1, 0.9 },
	{ 1.3, 1.1, 1.1 },
	{ 1.7, 1.2, 1.4 },
	{ 2.2, 1.35, 1.8 },
	{ 2.8, 1.5, 2.4 },
	{ 3.4, 1.7, 3 },
	{ 4, 1.85, 3.5 },
}

-- The rarity ladder: count, size and duration all grow from Common to Secret.
function Recipe.tier(rarity: string): Tier
	local rank = math.max(1, EffectLogic.rarityRank(rarity))
	local row = TIERS[rank]
	return {
		rarity = rarity,
		rank = rank,
		palette = EffectLogic.rarityPalette(rarity),
		count = row[1],
		size = row[2],
		duration = row[3],
	}
end

-- A definition with one variant per rarity, built by `build(tier)`. The base is the Common one.
function Recipe.byRarity(build: (tier: Tier) -> Definition): Definition
	local variants: { [string]: Definition } = {}
	for _, rarity in EffectLogic.RARITIES do
		variants[rarity] = build(Recipe.tier(rarity))
	end
	local base = table.clone(variants.Common)
	base.variantParam = "rarity"
	base.variants = variants
	return base
end

return Recipe
