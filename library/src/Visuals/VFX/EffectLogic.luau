--!strict
-- Effect schema and resolver (pure Luau). A VFX preset is plain data: a list of layers, each of
-- which the runtime (VFX/Builders) turns into one real Roblox object.
--
--   { duration = 1.2, layers = {
--       { kind = "particles", texture = "coin", colors = { "#FFF3B0", "#FFC93C" }, sizes = { 0.5, 0.4, 0 },
--         lifetime = { 0.7, 1.1 }, speed = { 14, 22 }, spread = { 28, 28 }, burst = 14, gravity = -45 },
--       { kind = "light", colors = { "#FFD84A" }, range = 12, brightness = 2.5 },
--   } }
--
-- Layer kinds: particles, beam, trail, light, highlight, ring, flash, billboard, shake, sound,
-- postfx. validate() lists every problem with a definition, resolve() adapts one to a quality
-- profile, caller params, distance and accessibility settings, and cost() estimates live particles
-- and lights for the effect budget. Colour helpers work on "#RRGGBB" strings so presets stay data.

local Curves = require("../Core/Curves")
local Quality = require("../Core/Quality")

export type Layer = {
	kind: string,
	name: string?,
	optional: boolean?, -- dropped when the profile drops optional layers (Low)
	delay: number?, -- seconds after the effect starts
	tint: boolean?, -- false keeps this layer's colours when the caller passes `color`
	offset: { number }?, -- { x, y, z } studs from the effect origin
	orient: { number }?, -- { x, y, z } degrees: rotates the layer (emit volume, ring plane) at the origin
	colors: { string }?, -- hex stops
	transparency: { number }?,
	texture: string?, -- texture key ("spark", "glow", ...) or a raw rbxassetid / rbxasset string
	lightEmission: number?,
	lightInfluence: number?,
	brightness: number?,
	zOffset: number?,
	-- particles
	sizes: { number }?, -- also flash { from, to } and billboard { from, peak, to } in studs
	lifetime: { number }?, -- { min, max } seconds
	speed: { number }?, -- { min, max } studs per second
	spread: { number }?, -- { x, y } degrees
	rate: number?, -- particles per second (looping, or for `emitFor` seconds in a one-shot)
	burst: number?, -- particles emitted at once
	emitFor: number?, -- seconds a rate layer emits in a one-shot effect
	acceleration: { number }?, -- { x, y, z }
	gravity: number?, -- added to acceleration Y (negative falls)
	drag: number?,
	rotation: { number }?, -- { min, max } degrees
	rotSpeed: { number }?, -- { min, max } degrees per second
	squash: { number }?,
	shape: string?, -- Box | Sphere | Cylinder | Disc
	shapeStyle: string?, -- Volume | Surface
	shapeInOut: string?, -- Outward | Inward | InAndOut
	shapeSize: { number }?, -- { x, y, z } size of the emitting volume in studs
	emissionDirection: string?, -- Top | Bottom | Front | Back | Left | Right
	orientation: string?, -- FacingCamera | FacingCameraWorldUp | VelocityParallel | VelocityPerpendicular
	lockedToPart: boolean?,
	timeScale: number?,
	-- beam (a pillar from the origin along `direction`)
	width: { number }?, -- beam { start, end } studs; trail { width }
	length: number?,
	direction: { number }?, -- { x, y, z }, default up
	curve: { number }?, -- { CurveSize0, CurveSize1 }
	segments: number?,
	textureSpeed: number?,
	textureLength: number?,
	faceCamera: boolean?,
	-- envelopes: light, highlight, beam, postfx
	fadeIn: number?,
	hold: number?,
	fadeOut: number?,
	-- trail
	time: number?, -- trail lifetime; ring, flash and billboard animation time
	widthScale: { number }?,
	minLength: number?,
	maxLength: number?,
	-- light
	light: string?, -- point | spot | surface
	range: number?,
	angle: number?,
	face: string?,
	pulse: { number }?, -- { period seconds, depth 0..1 } for looping lights
	-- highlight
	outline: string?, -- hex
	fillTransparency: number?,
	outlineTransparency: number?,
	depthMode: string?, -- Occluded | AlwaysOnTop
	-- ring / flash
	radius: { number }?, -- { from, to } studs
	thickness: number?,
	easing: string?,
	style: string?, -- ring: line | disc; flash: orb | light
	-- billboard
	image: string?, -- texture key
	text: string?,
	rise: number?, -- studs travelled upward over `time`
	alwaysOnTop: boolean?,
	-- shake / sound / postfx
	preset: string?, -- Camera shake preset name
	amount: number?, -- shake and postfx strength
	cue: string?, -- Audio cue name
	volume: number?,
	effect: string?, -- bloom | color | blur
}

export type Definition = {
	duration: number?, -- seconds; one-shots default to the end of their longest layer
	looping: boolean?,
	minInterval: number?, -- seconds between starts of the same preset
	priority: number?,
	layers: { Layer },
	-- Ambient effects: the numeric param `param` sets the horizontal extent of every emit volume.
	-- `base` is the extent the layers were tuned for; rates follow the area within limits.
	area: { param: string, base: number }?,
	-- Optional variants chosen by a param value (for example rarity or element).
	variantParam: string?,
	variants: { [string]: Definition }?,
}

export type Settings = { reducedMotion: boolean?, reducedFlashing: boolean?, intensity: number? }

export type Resolved = {
	layers: { Layer },
	duration: number, -- seconds until the last layer finished starting or animating (0 when looping)
	linger: number, -- extra seconds so live particles and trails can fade
	looping: boolean,
	priority: number,
	minInterval: number,
	particles: number, -- estimated live particles after scaling
	lights: number,
}

export type Cost = { particles: number, lights: number }

local EffectLogic = {}

EffectLogic.KINDS = table.freeze({
	"particles",
	"beam",
	"trail",
	"light",
	"highlight",
	"ring",
	"flash",
	"billboard",
	"shake",
	"sound",
	"postfx",
})

EffectLogic.TEXTURE_KEYS = table.freeze({
	"spark",
	"glow",
	"star",
	"ring",
	"smoke",
	"circle",
	"confetti",
	"coin",
	"gem",
	"heart",
	"leaf",
	"drop",
	"shard",
	"bubble",
	"flare",
	"streak",
})

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

-- Built-in texture used for a key that has no asset id configured.
local FALLBACK: { [string]: string } = {
	spark = SPARKLE,
	star = SPARKLE,
	confetti = SPARKLE,
	coin = SPARKLE,
	gem = SPARKLE,
	heart = SPARKLE,
	leaf = SPARKLE,
	shard = SPARKLE,
	streak = SPARKLE,
	glow = SMOKE,
	ring = SMOKE,
	smoke = SMOKE,
	circle = SMOKE,
	drop = SMOKE,
	bubble = SMOKE,
	flare = FIRE,
}
EffectLogic.FALLBACK_TEXTURES = FALLBACK

local COMMON_FIELDS = { "kind", "name", "optional", "delay", "tint", "offset", "orient" }

local FIELDS: { [string]: { string } } = {
	particles = {
		"texture",
		"colors",
		"sizes",
		"transparency",
		"lifetime",
		"speed",
		"spread",
		"rate",
		"burst",
		"emitFor",
		"acceleration",
		"gravity",
		"drag",
		"rotation",
		"rotSpeed",
		"lightEmission",
		"lightInfluence",
		"brightness",
		"squash",
		"shape",
		"shapeStyle",
		"shapeInOut",
		"shapeSize",
		"emissionDirection",
		"orientation",
		"zOffset",
		"lockedToPart",
		"timeScale",
	},
	beam = {
		"texture",
		"colors",
		"transparency",
		"width",
		"length",
		"direction",
		"curve",
		"segments",
		"textureSpeed",
		"textureLength",
		"lightEmission",
		"lightInfluence",
		"brightness",
		"faceCamera",
		"zOffset",
		"fadeIn",
		"hold",
		"fadeOut",
	},
	trail = {
		"texture",
		"colors",
		"transparency",
		"time",
		"width",
		"widthScale",
		"minLength",
		"maxLength",
		"lightEmission",
		"lightInfluence",
		"brightness",
		"faceCamera",
	},
	light = { "light", "colors", "range", "brightness", "angle", "face", "pulse", "fadeIn", "hold", "fadeOut" },
	highlight = {
		"colors",
		"outline",
		"fillTransparency",
		"outlineTransparency",
		"depthMode",
		"fadeIn",
		"hold",
		"fadeOut",
	},
	ring = { "colors", "radius", "thickness", "transparency", "time", "easing", "style", "lightEmission", "brightness" },
	flash = { "colors", "sizes", "transparency", "time", "style", "range", "brightness", "easing" },
	billboard = { "image", "text", "colors", "sizes", "transparency", "time", "rise", "alwaysOnTop", "easing" },
	shake = { "preset", "amount" },
	sound = { "cue", "volume" },
	postfx = { "effect", "amount", "colors", "fadeIn", "hold", "fadeOut" },
}

local KNOWN: { [string]: { [string]: boolean } } = {}
for kind, fields in FIELDS do
	local set: { [string]: boolean } = {}
	for _, field in COMMON_FIELDS do
		set[field] = true
	end
	for _, field in fields do
		set[field] = true
	end
	KNOWN[kind] = set
end

local SHAPES = { Box = true, Sphere = true, Cylinder = true, Disc = true }
local SHAPE_STYLES = { Volume = true, Surface = true }
local SHAPE_IN_OUT = { Outward = true, Inward = true, InAndOut = true }
local FACES = { Top = true, Bottom = true, Front = true, Back = true, Left = true, Right = true }
local ORIENTATIONS =
	{ FacingCamera = true, FacingCameraWorldUp = true, VelocityParallel = true, VelocityPerpendicular = true }
local LIGHTS = { point = true, spot = true, surface = true }
local DEPTH_MODES = { Occluded = true, AlwaysOnTop = true }
local RING_STYLES = { line = true, disc = true }
local FLASH_STYLES = { orb = true, light = true }
local POSTFX = { bloom = true, color = true, blur = true }

-- Colour helpers --------------------------------------------------------------------------------

function EffectLogic.isHex(value: any): boolean
	return type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") ~= nil
end

-- "#RRGGBB" -> r, g, b in 0..1. Raises on anything else.
function EffectLogic.rgb(hex: string): (number, number, number)
	if not EffectLogic.isHex(hex) then
		error("expected #RRGGBB, got " .. tostring(hex), 2)
	end
	local r = tonumber(string.sub(hex, 2, 3), 16) or 0
	local g = tonumber(string.sub(hex, 4, 5), 16) or 0
	local b = tonumber(string.sub(hex, 6, 7), 16) or 0
	return r / 255, g / 255, b / 255
end

local function channel(value: number): number
	return math.floor(math.clamp(value, 0, 1) * 255 + 0.5)
end

function EffectLogic.hex(r: number, g: number, b: number): string
	return string.format("#%02X%02X%02X", channel(r), channel(g), channel(b))
end

-- Linear blend of two colours; t = 0 gives `a`, t = 1 gives `b`.
function EffectLogic.mix(a: string, b: string, t: number): string
	local k = math.clamp(t, 0, 1)
	local ar, ag, ab = EffectLogic.rgb(a)
	local br, bg, bb = EffectLogic.rgb(b)
	return EffectLogic.hex(ar + (br - ar) * k, ag + (bg - ag) * k, ab + (bb - ab) * k)
end

function EffectLogic.lighten(hex: string, amount: number): string
	return EffectLogic.mix(hex, "#FFFFFF", amount)
end

function EffectLogic.darken(hex: string, amount: number): string
	return EffectLogic.mix(hex, "#000000", amount)
end

-- hue in degrees 0..360, saturation and value in 0..1.
function EffectLogic.hsv(hex: string): (number, number, number)
	local r, g, b = EffectLogic.rgb(hex)
	local max = math.max(r, g, b)
	local min = math.min(r, g, b)
	local delta = max - min
	local hue = 0
	if delta > 0 then
		if max == r then
			hue = ((g - b) / delta) % 6
		elseif max == g then
			hue = (b - r) / delta + 2
		else
			hue = (r - g) / delta + 4
		end
		hue *= 60
	end
	local saturation = if max > 0 then delta / max else 0
	return hue, saturation, max
end

function EffectLogic.fromHsv(hue: number, saturation: number, value: number): string
	local h = (hue % 360) / 60
	local s = math.clamp(saturation, 0, 1)
	local v = math.clamp(value, 0, 1)
	local c = v * s
	local x = c * (1 - math.abs(h % 2 - 1))
	local m = v - c
	local r, g, b = 0, 0, 0
	if h < 1 then
		r, g = c, x
	elseif h < 2 then
		r, g = x, c
	elseif h < 3 then
		g, b = c, x
	elseif h < 4 then
		g, b = x, c
	elseif h < 5 then
		r, b = x, c
	else
		r, b = c, x
	end
	return EffectLogic.hex(r + m, g + m, b + m)
end

function EffectLogic.shiftHue(hex: string, degrees: number): string
	local hue, saturation, value = EffectLogic.hsv(hex)
	return EffectLogic.fromHsv(hue + degrees, saturation, value)
end

-- Recolours `hex` with the hue of `tint`, keeping its brightness and how washed-out it was: a
-- white core stays white, a saturated stop takes the tint fully, a dark stop stays dark.
function EffectLogic.tint(hex: string, tint: string): string
	local _, saturation, value = EffectLogic.hsv(hex)
	local tintHue, tintSaturation = EffectLogic.hsv(tint)
	return EffectLogic.fromHsv(tintHue, tintSaturation * math.sqrt(saturation), value)
end

export type Palette = {
	core: string, -- near white, for hot centres
	light: string,
	main: string,
	dark: string,
	accent: string, -- a second hue for secondary layers
}

-- A five-colour palette around one colour.
function EffectLogic.palette(main: string, accent: string?): Palette
	return {
		core = EffectLogic.lighten(main, 0.8),
		light = EffectLogic.lighten(main, 0.45),
		main = main,
		dark = EffectLogic.darken(main, 0.35),
		accent = accent or EffectLogic.shiftHue(main, 28),
	}
end

EffectLogic.RARITIES = table.freeze({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" })

local RARITY_COLORS: { [string]: { string } } = {
	Common = { "#C9D4E0", "#FFFFFF" },
	Uncommon = { "#5BE37D", "#C8FFB0" },
	Rare = { "#4AA8FF", "#8EF0FF" },
	Epic = { "#B56BFF", "#FF8CF0" },
	Legendary = { "#FFB627", "#FFF27A" },
	Mythic = { "#FF4D8D", "#FFB03A" },
	Secret = { "#2CF5E0", "#FF5CF4" },
}

function EffectLogic.rarityRank(rarity: string): number
	return table.find(EffectLogic.RARITIES, rarity) or 0
end

-- Palette for a rarity name. Unknown names get the Common palette.
function EffectLogic.rarityPalette(rarity: string): Palette
	local colors = RARITY_COLORS[rarity] or RARITY_COLORS.Common
	return EffectLogic.palette(colors[1], colors[2])
end

EffectLogic.ELEMENTS = table.freeze({ "fire", "ice", "lightning", "water", "earth", "wind", "light", "dark" })

local ELEMENT_COLORS: { [string]: { string } } = {
	fire = { "#FF6A1A", "#FFD23F" },
	ice = { "#8FE3FF", "#E8FBFF" },
	lightning = { "#FFF04A", "#B8C8FF" },
	water = { "#2F8CFF", "#7FE0FF" },
	earth = { "#9A6B3C", "#6FA04A" },
	wind = { "#BFF5DC", "#F2FFF9" },
	light = { "#FFE9A8", "#FFFFFF" },
	dark = { "#6A2BD9", "#1B0B33" },
}

function EffectLogic.elementPalette(element: string): Palette
	local colors = ELEMENT_COLORS[element] or ELEMENT_COLORS.light
	return EffectLogic.palette(colors[1], colors[2])
end

-- Validation ------------------------------------------------------------------------------------

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function inRange(value: any, low: number, high: number): boolean
	return finite(value) and value >= low and value <= high
end

local function numbers(value: any, minCount: number, maxCount: number, low: number, high: number): boolean
	if type(value) ~= "table" or #value < minCount or #value > maxCount then
		return false
	end
	for _, item in value do
		if not inRange(item, low, high) then
			return false
		end
	end
	return true
end

local function minMax(value: any, low: number, high: number): boolean
	return numbers(value, 2, 2, low, high) and value[1] <= value[2]
end

local function hexList(value: any, minCount: number, maxCount: number): boolean
	if type(value) ~= "table" or #value < minCount or #value > maxCount then
		return false
	end
	for _, item in value do
		if not EffectLogic.isHex(item) then
			return false
		end
	end
	return true
end

local function knownTexture(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return FALLBACK[value] ~= nil or string.sub(value, 1, 3) == "rbx"
end

local function validateLayer(raw: Layer, label: string, problems: { string })
	local layer: any = raw
	local function need(ok: boolean, message: string)
		if not ok then
			table.insert(problems, label .. ": " .. message)
		end
	end
	local function optional(field: string, ok: boolean, message: string)
		if layer[field] ~= nil then
			need(ok, field .. " " .. message)
		end
	end
	local kind = layer.kind
	local known = KNOWN[kind]
	if known == nil then
		table.insert(problems, label .. ": unknown kind " .. tostring(kind))
		return
	end
	for field in layer do
		if not known[field] then
			table.insert(problems, label .. ": unknown field " .. tostring(field) .. " for " .. kind)
		end
	end
	optional("name", type(layer.name) == "string", "must be a string")
	optional("optional", type(layer.optional) == "boolean", "must be a boolean")
	optional("tint", type(layer.tint) == "boolean", "must be a boolean")
	optional("delay", inRange(layer.delay, 0, 30), "must be 0..30 seconds")
	optional("offset", numbers(layer.offset, 3, 3, -500, 500), "must be { x, y, z }")
	optional("orient", numbers(layer.orient, 3, 3, -360, 360), "must be { x, y, z } degrees")
	optional("lightEmission", inRange(layer.lightEmission, 0, 1), "must be 0..1")
	optional("lightInfluence", inRange(layer.lightInfluence, 0, 1), "must be 0..1")
	optional("brightness", inRange(layer.brightness, 0, 40), "must be 0..40")
	optional("zOffset", inRange(layer.zOffset, -20, 20), "must be -20..20")
	optional("texture", knownTexture(layer.texture), "must be a texture key or an rbx asset string")
	optional("fadeIn", inRange(layer.fadeIn, 0, 10), "must be 0..10 seconds")
	optional("hold", inRange(layer.hold, 0, 60), "must be 0..60 seconds")
	optional("fadeOut", inRange(layer.fadeOut, 0, 10), "must be 0..10 seconds")
	optional("easing", type(layer.easing) == "string" and Curves.has(layer.easing), "must be a known curve")

	if kind == "particles" then
		need(hexList(layer.colors, 1, 4), "colors must be 1-4 hex stops")
		need(numbers(layer.sizes, 1, 4, 0, 60), "sizes must be 1-4 stops of 0..60 studs")
		optional("transparency", numbers(layer.transparency, 1, 4, 0, 1), "must be 1-4 stops of 0..1")
		need(minMax(layer.lifetime, 0.02, 20), "lifetime must be { min, max } within 0.02..20 seconds")
		need(minMax(layer.speed, -200, 200), "speed must be { min, max } within -200..200")
		optional("spread", numbers(layer.spread, 2, 2, 0, 180), "must be { x, y } of 0..180 degrees")
		need((layer.burst ~= nil) ~= (layer.rate ~= nil), "needs exactly one of burst or rate")
		optional("burst", inRange(layer.burst, 1, 400) and layer.burst % 1 == 0, "must be a whole number 1..400")
		optional("rate", inRange(layer.rate, 0.1, 400), "must be 0.1..400 per second")
		optional("emitFor", inRange(layer.emitFor, 0.02, 60), "must be 0.02..60 seconds")
		need(layer.emitFor == nil or layer.rate ~= nil, "emitFor needs rate")
		optional("acceleration", numbers(layer.acceleration, 3, 3, -500, 500), "must be { x, y, z }")
		optional("gravity", inRange(layer.gravity, -500, 500), "must be -500..500")
		optional("drag", inRange(layer.drag, 0, 50), "must be 0..50")
		optional("rotation", minMax(layer.rotation, -3600, 3600), "must be { min, max } degrees")
		optional("rotSpeed", minMax(layer.rotSpeed, -3600, 3600), "must be { min, max } degrees per second")
		optional("squash", numbers(layer.squash, 1, 4, -3, 3), "must be 1-4 stops of -3..3")
		optional("shape", SHAPES[layer.shape] == true, "must be Box, Sphere, Cylinder or Disc")
		optional("shapeStyle", SHAPE_STYLES[layer.shapeStyle] == true, "must be Volume or Surface")
		optional("shapeInOut", SHAPE_IN_OUT[layer.shapeInOut] == true, "must be Outward, Inward or InAndOut")
		optional("shapeSize", numbers(layer.shapeSize, 3, 3, 0.05, 2048), "must be { x, y, z } of 0.05..2048")
		optional("emissionDirection", FACES[layer.emissionDirection] == true, "must be a NormalId name")
		optional("orientation", ORIENTATIONS[layer.orientation] == true, "must be a ParticleOrientation name")
		optional("lockedToPart", type(layer.lockedToPart) == "boolean", "must be a boolean")
		optional("timeScale", inRange(layer.timeScale, 0, 1), "must be 0..1")
	elseif kind == "beam" then
		need(hexList(layer.colors, 1, 4), "colors must be 1-4 hex stops")
		optional("transparency", numbers(layer.transparency, 1, 4, 0, 1), "must be 1-4 stops of 0..1")
		need(numbers(layer.width, 2, 2, 0, 200), "width must be { start, end } of 0..200 studs")
		need(inRange(layer.length, 0.5, 2000), "length must be 0.5..2000 studs")
		optional("direction", numbers(layer.direction, 3, 3, -1, 1), "must be a unit-ish { x, y, z }")
		if type(layer.direction) == "table" and #layer.direction == 3 then
			local d = layer.direction
			need(math.abs(d[1]) + math.abs(d[2]) + math.abs(d[3]) > 0.01, "direction must not be zero")
		end
		optional("curve", numbers(layer.curve, 2, 2, -500, 500), "must be { size0, size1 }")
		optional("segments", inRange(layer.segments, 1, 100) and layer.segments % 1 == 0, "must be 1..100")
		optional("textureSpeed", inRange(layer.textureSpeed, -50, 50), "must be -50..50")
		optional("textureLength", inRange(layer.textureLength, 0.01, 500), "must be 0.01..500")
		optional("faceCamera", type(layer.faceCamera) == "boolean", "must be a boolean")
	elseif kind == "trail" then
		need(hexList(layer.colors, 1, 4), "colors must be 1-4 hex stops")
		optional("transparency", numbers(layer.transparency, 1, 4, 0, 1), "must be 1-4 stops of 0..1")
		need(inRange(layer.time, 0.05, 20), "time must be 0.05..20 seconds")
		need(numbers(layer.width, 1, 1, 0.05, 100), "width must be { studs }")
		optional("widthScale", numbers(layer.widthScale, 1, 4, 0, 1), "must be 1-4 stops of 0..1")
		optional("minLength", inRange(layer.minLength, 0, 100), "must be 0..100")
		optional("maxLength", inRange(layer.maxLength, 0, 2000), "must be 0..2000")
		optional("faceCamera", type(layer.faceCamera) == "boolean", "must be a boolean")
	elseif kind == "light" then
		need(hexList(layer.colors, 1, 1), "colors must be one hex colour")
		optional("light", LIGHTS[layer.light] == true, "must be point, spot or surface")
		need(inRange(layer.range, 1, 60), "range must be 1..60 studs")
		need(inRange(layer.brightness, 0.05, 40), "brightness must be 0.05..40")
		optional("angle", inRange(layer.angle, 0, 180), "must be 0..180 degrees")
		optional("face", FACES[layer.face] == true, "must be a NormalId name")
		if layer.pulse ~= nil then
			need(numbers(layer.pulse, 2, 2, 0, 60), "pulse must be { period, depth }")
			if type(layer.pulse) == "table" and #layer.pulse == 2 then
				need(inRange(layer.pulse[1], 0.1, 60), "pulse period must be 0.1..60 seconds")
				need(inRange(layer.pulse[2], 0, 1), "pulse depth must be 0..1")
			end
		end
	elseif kind == "highlight" then
		need(hexList(layer.colors, 1, 1), "colors must be one hex colour")
		optional("outline", EffectLogic.isHex(layer.outline), "must be #RRGGBB")
		optional("fillTransparency", inRange(layer.fillTransparency, 0, 1), "must be 0..1")
		optional("outlineTransparency", inRange(layer.outlineTransparency, 0, 1), "must be 0..1")
		optional("depthMode", DEPTH_MODES[layer.depthMode] == true, "must be Occluded or AlwaysOnTop")
	elseif kind == "ring" then
		need(hexList(layer.colors, 1, 2), "colors must be 1-2 hex colours")
		need(numbers(layer.radius, 2, 2, 0, 500), "radius must be { from, to } of 0..500 studs")
		need(inRange(layer.thickness, 0.02, 50), "thickness must be 0.02..50 studs")
		optional("transparency", numbers(layer.transparency, 2, 2, 0, 1), "must be { from, to } of 0..1")
		need(inRange(layer.time, 0.05, 20), "time must be 0.05..20 seconds")
		optional("style", RING_STYLES[layer.style] == true, "must be line or disc")
	elseif kind == "flash" then
		need(hexList(layer.colors, 1, 1), "colors must be one hex colour")
		need(numbers(layer.sizes, 2, 2, 0, 200), "sizes must be { from, to } of 0..200 studs")
		optional("transparency", numbers(layer.transparency, 2, 2, 0, 1), "must be { from, to } of 0..1")
		need(inRange(layer.time, 0.03, 5), "time must be 0.03..5 seconds")
		optional("style", FLASH_STYLES[layer.style] == true, "must be orb or light")
		optional("range", inRange(layer.range, 1, 60), "must be 1..60 studs")
	elseif kind == "billboard" then
		optional("image", knownTexture(layer.image), "must be a texture key or an rbx asset string")
		optional("text", type(layer.text) == "string" and #layer.text > 0 and #layer.text <= 24, "must be 1-24 bytes")
		need(layer.image ~= nil or layer.text ~= nil, "needs image or text")
		need(hexList(layer.colors, 1, 1), "colors must be one hex colour")
		need(numbers(layer.sizes, 3, 3, 0, 100), "sizes must be { from, peak, to } studs")
		optional("transparency", numbers(layer.transparency, 2, 2, 0, 1), "must be { from, to } of 0..1")
		need(inRange(layer.time, 0.05, 10), "time must be 0.05..10 seconds")
		optional("rise", inRange(layer.rise, -50, 50), "must be -50..50 studs")
		optional("alwaysOnTop", type(layer.alwaysOnTop) == "boolean", "must be a boolean")
	elseif kind == "shake" then
		need(type(layer.preset) == "string" and layer.preset ~= "", "preset must be a Camera shake preset name")
		optional("amount", inRange(layer.amount, 0, 3), "must be 0..3")
	elseif kind == "sound" then
		need(type(layer.cue) == "string" and layer.cue ~= "", "cue must be an Audio cue name")
		optional("volume", inRange(layer.volume, 0, 3), "must be 0..3")
	elseif kind == "postfx" then
		need(POSTFX[layer.effect] == true, "effect must be bloom, color or blur")
		need(inRange(layer.amount, 0, 2), "amount must be 0..2")
		optional("colors", hexList(layer.colors, 1, 1), "must be one hex colour")
	end
end

local function validateInto(def: Definition, prefix: string, problems: { string }, nested: boolean)
	local raw: any = def
	if type(raw) ~= "table" then
		table.insert(problems, prefix .. "definition must be a table")
		return
	end
	if raw.duration ~= nil and not inRange(raw.duration, 0.03, 120) then
		table.insert(problems, prefix .. "duration must be 0.03..120 seconds")
	end
	if raw.looping ~= nil and type(raw.looping) ~= "boolean" then
		table.insert(problems, prefix .. "looping must be a boolean")
	end
	if raw.minInterval ~= nil and not inRange(raw.minInterval, 0, 60) then
		table.insert(problems, prefix .. "minInterval must be 0..60 seconds")
	end
	if raw.priority ~= nil and not inRange(raw.priority, -100, 100) then
		table.insert(problems, prefix .. "priority must be -100..100")
	end
	if type(raw.layers) ~= "table" or #raw.layers == 0 then
		table.insert(problems, prefix .. "needs at least one layer")
	else
		if #raw.layers > 24 then
			table.insert(problems, prefix .. "has more than 24 layers")
		end
		for index, layer in raw.layers do
			local label = prefix .. "layer " .. tostring(index)
			if type(layer) ~= "table" then
				table.insert(problems, label .. ": must be a table")
			else
				if type(layer.name) == "string" then
					label ..= " (" .. layer.name .. ")"
				end
				validateLayer(layer, label, problems)
			end
		end
	end
	if raw.area ~= nil then
		local area = raw.area
		if
			type(area) ~= "table"
			or type(area.param) ~= "string"
			or area.param == ""
			or not inRange(area.base, 1, 2048)
		then
			table.insert(problems, prefix .. "area must be { param = name, base = studs }")
		end
	end
	if raw.variants ~= nil or raw.variantParam ~= nil then
		if nested then
			table.insert(problems, prefix .. "variants cannot be nested")
		elseif type(raw.variantParam) ~= "string" or type(raw.variants) ~= "table" then
			table.insert(problems, prefix .. "variants need both variantParam and variants")
		else
			local names: { string } = {}
			for name in raw.variants do
				table.insert(names, tostring(name))
			end
			table.sort(names)
			for _, name in names do
				validateInto(raw.variants[name], prefix .. "variant " .. name .. ": ", problems, true)
			end
		end
	end
end

-- Problems with a definition (empty when valid). Strict: unknown kinds and fields, out-of-range
-- numbers, wrong stop counts and malformed colours are all reported.
function EffectLogic.validate(def: Definition): { string }
	local problems: { string } = {}
	validateInto(def, "", problems, false)
	return problems
end

-- Variants and timing ---------------------------------------------------------------------------

-- The definition to use for `params`: the matching variant, or the base definition.
function EffectLogic.pick(def: Definition, params: { [string]: any }?): Definition
	local variants = def.variants
	local key = def.variantParam
	if variants and key and params then
		local chosen = variants[tostring(params[key])]
		if chosen then
			return chosen
		end
	end
	return def
end

local function averageLifetime(layer: Layer): number
	local lifetime = layer.lifetime
	if lifetime == nil then
		return 0
	end
	return (lifetime[1] + lifetime[2]) / 2
end

local function envelope(layer: Layer): number
	return (layer.fadeIn or 0.05) + (layer.hold or 0) + (layer.fadeOut or 0.3)
end

-- Seconds after the effect starts at which a layer has finished starting and animating.
local function layerEnd(layer: Layer, duration: number): number
	local delay = layer.delay or 0
	local kind = layer.kind
	if kind == "particles" then
		if layer.rate then
			return delay + (layer.emitFor or math.max(0, duration - delay))
		end
		return delay
	elseif kind == "ring" or kind == "flash" or kind == "billboard" then
		return delay + (layer.time or 0)
	elseif kind == "light" or kind == "highlight" or kind == "beam" or kind == "postfx" then
		return delay + envelope(layer)
	end
	return delay
end

local function timing(def: Definition, layers: { Layer }): (number, number)
	local linger = 0.1
	for _, layer in layers do
		if layer.kind == "particles" and layer.lifetime then
			linger = math.max(linger, layer.lifetime[2])
		elseif layer.kind == "trail" then
			linger = math.max(linger, layer.time or 0)
		end
	end
	if def.looping then
		return 0, linger
	end
	local base = def.duration or 0
	local duration = base
	for _, layer in layers do
		duration = math.max(duration, layerEnd(layer, base))
	end
	return math.max(duration, 0.05), linger
end

local function liveParticles(layer: Layer, looping: boolean, duration: number): number
	if layer.kind ~= "particles" then
		return 0
	end
	if layer.burst then
		return layer.burst
	end
	local rate = layer.rate or 0
	local life = averageLifetime(layer)
	if looping then
		return rate * life
	end
	local emitting = layer.emitFor or math.max(0, duration - (layer.delay or 0))
	return rate * math.min(life, emitting)
end

local function lightCount(layer: Layer): number
	if layer.kind == "light" or (layer.kind == "flash" and layer.style == "light") then
		return 1
	end
	return 0
end

-- Horizontal stretch of the emit volumes and the matching count multiplier for an area effect.
-- Counts follow the area but stay within 0.25x..2.5x so a huge box gets sparser, not heavier.
local function areaFactor(def: Definition, params: { [string]: any }?): (number, number)
	local area = def.area
	if area == nil or params == nil then
		return 1, 1
	end
	local value = params[area.param]
	if not finite(value) or value <= 0 then
		return 1, 1
	end
	local stretch = math.clamp(value / area.base, 0.05, 20)
	return stretch, math.clamp(stretch * stretch, 0.25, 2.5)
end

-- Estimated live particles and dynamic lights at full quality, for the effect budget. `params`
-- picks the variant; without it the most expensive variant is reported.
function EffectLogic.cost(def: Definition, params: { [string]: any }?): Cost
	local function one(chosen: Definition): Cost
		local particles, lights = 0, 0
		local looping = chosen.looping == true
		local duration = chosen.duration or 0
		local _, density = areaFactor(chosen, params)
		for _, layer in chosen.layers do
			local live = liveParticles(layer, looping, duration)
			particles += if layer.shapeSize then live * density else live
			lights += lightCount(layer)
		end
		return { particles = math.ceil(particles), lights = lights }
	end
	if params ~= nil or def.variants == nil then
		return one(EffectLogic.pick(def, params))
	end
	local worst = one(def)
	local variants: { [string]: Definition } = def.variants or {}
	for _, variant in variants do
		local cost = one(variant)
		worst.particles = math.max(worst.particles, cost.particles)
		worst.lights = math.max(worst.lights, cost.lights)
	end
	return worst
end

-- Resolve ---------------------------------------------------------------------------------------

local function scaled(values: { number }?, k: number): { number }?
	if values == nil then
		return nil
	end
	local out: { number } = {}
	for i, value in values do
		out[i] = value * k
	end
	return out
end

local function tinted(colors: { string }?, tint: string?): { string }?
	if colors == nil or tint == nil then
		return colors
	end
	local out: { string } = {}
	for i, color in colors do
		out[i] = EffectLogic.tint(color, tint)
	end
	return out
end

-- Adapts a definition to a quality profile, caller params, a distance scale (0..1 from
-- Core/Effects) and the accessibility settings. The result is a new table; `def` is not changed.
--   * layers marked optional are dropped when the profile drops them; trails, beams, lights,
--     highlights and post-processing follow the profile's switches
--   * burst counts and rates follow particleScale / rateScale, intensity and distance; a kept burst
--     layer always emits at least one particle
--   * params.scale multiplies every size, speed, radius and range; params.color (hex) retints
--   * reduced flashing softens `flash` layers and drops `postfx`; reduced motion drops `shake`
function EffectLogic.resolve(
	def: Definition,
	profile: Quality.Profile,
	params: { [string]: any }?,
	distanceScale: number?,
	settings: Settings?
): Resolved
	local given: { [string]: any } = params or {}
	local chosen = EffectLogic.pick(def, given)
	local options: Settings = settings or {}
	local size = if finite(given.scale) then math.clamp(given.scale, 0.05, 20) else 1
	local intensity =
		math.clamp((if finite(given.intensity) then given.intensity else 1) * (options.intensity or 1), 0, 3)
	local distance = math.clamp(distanceScale or 1, 0, 1)
	local tint: string? = if EffectLogic.isHex(given.color) then given.color else nil
	local reducedFlashing = options.reducedFlashing == true
	local reducedMotion = options.reducedMotion == true
	-- Fewer particles read better slightly larger.
	local sizeBoost = if profile.particleScale < 0.5 then 1.15 else 1
	local baseDuration = chosen.duration or 0
	local stretch, density = areaFactor(chosen, given)

	local layers: { Layer } = {}
	for _, source in chosen.layers do
		if source.optional and profile.dropOptional then
			continue
		end
		local kind = source.kind
		if
			(kind == "trail" and not profile.trails)
			or (kind == "beam" and not profile.beams)
			or (kind == "light" and not profile.lights)
			or (kind == "highlight" and not profile.highlights)
		then
			continue
		end
		if kind == "postfx" and (not profile.postProcessing or reducedFlashing or distance < 1 or intensity <= 0) then
			continue
		end
		if kind == "shake" and (reducedMotion or intensity <= 0) then
			continue
		end
		if kind == "flash" and source.style == "light" and not profile.lights then
			continue
		end

		local layer = table.clone(source)
		layer.offset = scaled(source.offset, size)
		if source.tint ~= false then
			layer.colors = tinted(source.colors, tint)
			if source.outline and tint then
				layer.outline = EffectLogic.tint(source.outline, tint)
			end
		end

		if kind == "particles" then
			layer.sizes = scaled(source.sizes, size * sizeBoost)
			layer.speed = scaled(source.speed, size)
			layer.lifetime = scaled(source.lifetime, profile.lifetimeScale)
			local volume = source.shapeSize
			local spread = 1
			if volume then
				layer.shapeSize = { volume[1] * size * stretch, volume[2] * size, volume[3] * size * stretch }
				spread = density
			end
			local acceleration = source.acceleration or { 0, 0, 0 }
			layer.acceleration =
				{ acceleration[1] * size, (acceleration[2] + (source.gravity or 0)) * size, acceleration[3] * size }
			layer.gravity = nil
			if source.burst then
				layer.burst =
					math.max(1, math.floor(source.burst * profile.particleScale * intensity * distance * spread + 0.5))
			elseif source.rate then
				layer.rate = math.max(0.5, source.rate * profile.rateScale * intensity * distance * spread)
				if not chosen.looping then
					layer.emitFor = source.emitFor or math.max(0.05, baseDuration - (source.delay or 0))
				end
			end
		elseif kind == "beam" then
			layer.width = scaled(source.width, size)
			layer.length = (source.length or 1) * size
			layer.curve = scaled(source.curve, size)
		elseif kind == "trail" then
			layer.width = scaled(source.width, size)
			layer.time = (source.time or 0.3) * profile.lifetimeScale
		elseif kind == "light" then
			layer.range = math.min(60, (source.range or 8) * size)
			layer.brightness = (source.brightness or 1) * math.clamp(intensity, 0, 1.5)
			if reducedFlashing or reducedMotion then
				layer.pulse = nil
			end
			if reducedFlashing then
				layer.fadeIn = math.max(source.fadeIn or 0.05, 0.2)
				layer.brightness = (layer.brightness or 1) * 0.6
			end
		elseif kind == "ring" then
			layer.radius = scaled(source.radius, size)
			layer.thickness = (source.thickness or 0.3) * size
		elseif kind == "flash" then
			layer.sizes = scaled(source.sizes, size)
			if source.range then
				layer.range = math.min(60, source.range * size)
			end
			if reducedFlashing then
				local transparency = source.transparency or { 0.2, 1 }
				layer.transparency = { math.max(transparency[1], 0.7), transparency[2] }
				layer.time = math.max(source.time or 0.2, 0.35)
				layer.brightness = (source.brightness or 2) * 0.4
			end
		elseif kind == "billboard" then
			layer.sizes = scaled(source.sizes, size)
			layer.rise = if reducedMotion then 0 else (source.rise or 0) * size
		elseif kind == "shake" then
			layer.amount = (source.amount or 1) * math.min(intensity, 1.5) * distance
		elseif kind == "postfx" then
			layer.amount = (source.amount or 0.5) * math.min(intensity, 1)
		end
		table.insert(layers, layer)
	end

	local duration, linger = timing(chosen, layers)
	local looping = chosen.looping == true
	local particles, lights = 0, 0
	for _, layer in layers do
		particles += liveParticles(layer, looping, duration)
		lights += lightCount(layer)
	end
	return {
		layers = layers,
		duration = duration,
		linger = linger,
		looping = looping,
		priority = chosen.priority or def.priority or 0,
		minInterval = chosen.minInterval or def.minInterval or 0,
		particles = math.ceil(particles),
		lights = lights,
	}
end

-- Built-in texture for a key ("spark" -> sparkles). Raw rbx strings are returned unchanged.
function EffectLogic.fallbackTexture(key: string?): string
	if key == nil then
		return SPARKLE
	end
	if string.sub(key, 1, 3) == "rbx" then
		return key
	end
	return FALLBACK[key] or SPARKLE
end

-- Texture for a key given the configured ids; falls back to a built-in particle texture.
function EffectLogic.texture(key: string?, configured: { [string]: string }?): string
	if key ~= nil and configured ~= nil then
		local id = configured[key]
		if type(id) == "string" and id ~= "" then
			return id
		end
	end
	return EffectLogic.fallbackTexture(key)
end

-- Evenly spaced keypoints for 1-4 stops: { { time, value } } starting at 0 and ending at 1, the
-- form NumberSequence and ColorSequence need. One stop becomes a constant (two equal keypoints).
function EffectLogic.keypoints<T>(stops: { T }): { { time: number, value: T } }
	local count = #stops
	if count == 0 then
		return {}
	end
	if count == 1 then
		return { { time = 0, value = stops[1] }, { time = 1, value = stops[1] } }
	end
	local out = {}
	for index, value in stops do
		table.insert(out, { time = if index == count then 1 else (index - 1) / (count - 1), value = value })
	end
	return out
end

-- Strength of an attack / hold / release envelope at `elapsed` seconds (0..1).
function EffectLogic.envelopeAt(fadeIn: number, hold: number, fadeOut: number, elapsed: number): number
	if elapsed < 0 then
		return 0
	end
	if elapsed < fadeIn then
		return elapsed / fadeIn
	end
	local after = elapsed - fadeIn - hold
	if after <= 0 then
		return 1
	end
	if fadeOut <= 0 or after >= fadeOut then
		return 0
	end
	return 1 - after / fadeOut
end

return EffectLogic
