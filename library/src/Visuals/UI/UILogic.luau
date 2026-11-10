--!strict
-- Pure maths and rules for UI animation (no Roblox globals). UIAnimations is the thin player on
-- top of this module; everything that can be decided without an Instance lives here and is covered
-- by tests/visuals_ui.spec.luau.
--
-- A recipe is data: numbers and names, relative to the object's rest state.
--
--   { steps = {
--       { props = { Scale = 0.92 }, duration = 0.07, easing = "quadOut" },
--       { props = { Scale = 1 }, spring = "Bouncy" },
--     } }
--
-- Step properties (all relative to rest, so one preset fits any object):
--   Scale         multiplier of the rest scale (1 = rest)
--   Rotation      degrees added to the rest rotation
--   GroupFade     0 = as visible as at rest, 1 = invisible
--   OffsetX/Y     pixels from the rest position
--   OffsetXSize   fraction of the object's own width / height from the rest position (drawers,
--   OffsetYSize   pages); not scaled by intensity, because a drawer must leave the screen
--   Width/Height  multiplier of the rest Size (works under a UIListLayout, where offsets do not)
--
-- Steps run one after another. `join = true` starts a step together with the previous one (a quick
-- fade next to a slow spring). `from` sets start values; without it a step continues from where
-- the object is, so interrupted motion never jumps.

local Curves = require("../Core/Curves")
local Easing = require("../../UI/Core/Easing")
local Format = require("../../UI/Core/Format")
local Springs = require("../Core/Springs")
local TextFit = require("../../UI/Core/TextFit")

export type Props = { [string]: number }

export type Step = {
	props: Props,
	from: Props?,
	duration: number?, -- seconds (timed step)
	easing: string?, -- Core/Curves name, default "quadOut"
	spring: (string | Springs.Spring)?, -- spring step when set
	delay: number?, -- seconds before the step starts
	join: boolean?, -- start with the previous step instead of after it
	marker: string?, -- options.onMarker(marker) is called when the step starts (CardFlip: "flip")
	essential: boolean?, -- still animates under reduced motion (fades)
}

export type Layer = { kind: string, [string]: any }

export type Recipe = {
	steps: { Step },
	layers: { Layer }?, -- overlay effects the player runs next to the steps
	loop: boolean?, -- repeats until stopped; never starts under reduced motion
	gap: number?, -- pause between loop cycles
	delay: number?, -- seconds before the first step (set by scale)
	out: boolean?, -- leaves the object away from rest on purpose (exit presets)
	reduced: (string | boolean)?, -- reduced motion: preset id to play instead, false to skip
	travel: { spring: string }?, -- moves the rest position / size to options.position / options.size
}

export type ScaleOptions = {
	duration: number?, -- wanted total seconds
	speed: number?, -- time multiplier (2 = twice as fast); ignored when duration is set
	intensity: number?, -- amount multiplier (0.5 = half the travel)
	easing: string?, -- replaces the curve of timed steps
	spring: (string | Springs.Spring)?, -- replaces the spring of spring steps
	delay: number?,
	mirror: boolean?, -- flips horizontal offsets and rotation
}

export type Rest = {
	scale: number,
	rotation: number,
	fade: number,
	position: { number }, -- { xScale, xOffset, yScale, yOffset }
	size: { number },
	pixels: { number }, -- { width, height } at 1x
}

export type Entry = { at: number, duration: number, step: Step }
export type Schedule = { entries: { Entry }, total: number }

local UILogic = {}

-- Springs count as finished for timing once they stay within 5 % of the goal; the engine keeps
-- settling the last few percent on its own.
UILogic.SETTLE = 0.05

local IDENTITY: { [string]: number } = {
	Scale = 1,
	Rotation = 0,
	GroupFade = 0,
	OffsetX = 0,
	OffsetY = 0,
	OffsetXSize = 0,
	OffsetYSize = 0,
	Width = 1,
	Height = 1,
}
UILogic.PROPS = table.freeze(table.clone(IDENTITY))

local CHANNEL: { [string]: string } = {
	Scale = "Scale",
	Rotation = "Rotation",
	GroupFade = "GroupFade",
	OffsetX = "Position",
	OffsetY = "Position",
	OffsetXSize = "Position",
	OffsetYSize = "Position",
	Width = "Size",
	Height = "Size",
}

local LAYER_KINDS: { [string]: boolean } = {
	shine = true, -- gradient sweep
	glow = true, -- outline glow: mode "flash" | "pulse" | "on" | "off"
	ripple = true, -- expanding circle from the press point
	tint = true, -- colour overlay that fades out
	border = true, -- rotating gradient on the outline
	textGlow = true, -- pulsing text outline
}
UILogic.LAYER_KINDS = table.freeze(table.clone(LAYER_KINDS))

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function validSpring(spring: any): boolean
	if type(spring) == "string" then
		return Springs.has(spring)
	end
	return type(spring) == "table" and finite(spring.frequency) and spring.frequency > 0 and finite(spring.damping)
end

local function checkProps(problems: { string }, label: string, props: any, needOne: boolean)
	if type(props) ~= "table" then
		table.insert(problems, label .. " must be a table")
		return
	end
	local count = 0
	for name, value in props :: { [any]: any } do
		count += 1
		if IDENTITY[name] == nil then
			table.insert(problems, label .. ": unknown property " .. tostring(name))
		elseif not finite(value) then
			table.insert(problems, label .. "." .. tostring(name) .. " must be a number")
		elseif (name == "Scale" or name == "Width" or name == "Height") and value < 0 then
			table.insert(problems, label .. "." .. name .. " cannot be negative")
		elseif name == "GroupFade" and (value < 0 or value > 1) then
			table.insert(problems, label .. ".GroupFade must be 0..1")
		end
	end
	if needOne and count == 0 then
		table.insert(problems, label .. " is empty")
	end
end

-- Seconds a step takes: its duration, or the spring's settle time.
function UILogic.stepDuration(step: Step): number
	if step.spring ~= nil then
		return Springs.settleTime(step.spring, UILogic.SETTLE)
	end
	return math.max(0, step.duration or 0)
end

local function layerEnd(layer: Layer): number
	if layer.loop == true or layer.mode == "pulse" or layer.mode == "on" or layer.mode == "off" then
		return 0
	end
	local delay: number = if finite(layer.delay) then layer.delay else 0
	local duration: number = if finite(layer.duration) then layer.duration else 0
	return delay + duration
end

-- When each step starts and how long the whole recipe takes (one cycle for loops).
function UILogic.schedule(recipe: Recipe): Schedule
	local entries: { Entry } = {}
	local offset = math.max(0, recipe.delay or 0)
	local cursor = offset
	local groupStart = offset
	for index, step in recipe.steps do
		local start = cursor
		if step.join and index > 1 then
			start = groupStart
		else
			groupStart = start
		end
		local at = start + math.max(0, step.delay or 0)
		local duration = UILogic.stepDuration(step)
		table.insert(entries, { at = at, duration = duration, step = step })
		cursor = math.max(cursor, at + duration)
	end
	local total = cursor
	if recipe.travel then
		total = math.max(total, offset + Springs.settleTime(recipe.travel.spring, UILogic.SETTLE))
	end
	for _, layer in recipe.layers or {} do
		total = math.max(total, offset + layerEnd(layer))
	end
	return { entries = entries, total = total }
end

function UILogic.duration(recipe: Recipe): number
	return UILogic.schedule(recipe).total
end

-- Problems with a recipe (empty when valid).
function UILogic.validate(recipe: any): { string }
	local problems: { string } = {}
	if type(recipe) ~= "table" then
		return { "recipe must be a table" }
	end
	if type(recipe.steps) ~= "table" then
		return { "steps must be an array" }
	end
	local layers: { any } = if type(recipe.layers) == "table" then recipe.layers else {}
	if recipe.layers ~= nil and type(recipe.layers) ~= "table" then
		table.insert(problems, "layers must be an array")
	end
	if #recipe.steps == 0 and #layers == 0 and recipe.travel == nil then
		table.insert(problems, "recipe needs a step, a layer or travel")
	end
	for index, step in recipe.steps :: { any } do
		local label = "step " .. index
		if type(step) ~= "table" then
			table.insert(problems, label .. " must be a table")
			continue
		end
		checkProps(problems, label .. ".props", step.props, true)
		if step.from ~= nil then
			checkProps(problems, label .. ".from", step.from, false)
		end
		if step.spring ~= nil then
			if not validSpring(step.spring) then
				table.insert(problems, label .. ": unknown spring " .. tostring(step.spring))
			end
		elseif not finite(step.duration) or step.duration < 0 then
			table.insert(problems, label .. " needs a duration or a spring")
		end
		if step.easing ~= nil and not (type(step.easing) == "string" and Curves.has(step.easing)) then
			table.insert(problems, label .. ": unknown easing " .. tostring(step.easing))
		end
		if step.delay ~= nil and (not finite(step.delay) or step.delay < 0) then
			table.insert(problems, label .. ".delay must be 0 or more")
		end
		if step.join and index == 1 then
			table.insert(problems, "step 1 cannot join")
		end
	end
	for index, layer in layers do
		local label = "layer " .. index
		if type(layer) ~= "table" or not LAYER_KINDS[layer.kind] then
			table.insert(problems, label .. ": unknown kind")
			continue
		end
		local endless = layer.loop == true or layer.mode == "pulse" or layer.mode == "on" or layer.mode == "off"
		if endless and layer.mode ~= "off" and layer.mode ~= "on" and recipe.loop ~= true then
			table.insert(problems, label .. " loops, so the recipe must set loop = true")
		end
		if not endless and (not finite(layer.duration) or layer.duration <= 0) then
			table.insert(problems, label .. " needs a duration")
		end
	end
	if recipe.travel ~= nil then
		if type(recipe.travel) ~= "table" or not validSpring(recipe.travel.spring) then
			table.insert(problems, "travel.spring must be a spring preset")
		end
	end
	if recipe.gap ~= nil and (not finite(recipe.gap) or recipe.gap < 0) then
		table.insert(problems, "gap must be 0 or more")
	end
	if recipe.reduced ~= nil and recipe.reduced ~= false and type(recipe.reduced) ~= "string" then
		table.insert(problems, "reduced must be a preset id or false")
	end
	if #problems == 0 and recipe.loop and #recipe.steps > 0 and UILogic.duration(recipe) <= 0 then
		table.insert(problems, "a looping recipe needs a positive duration")
	end
	return problems
end

local function scaleProps(props: Props?, intensity: number, mirror: boolean): Props?
	if props == nil then
		return nil
	end
	local out: Props = {}
	for name, value in props do
		local scaled = value
		if name == "Scale" then
			scaled = math.max(0, 1 + (value - 1) * intensity)
		elseif name == "Rotation" or name == "OffsetX" or name == "OffsetY" then
			scaled = value * intensity
		end
		if mirror and (name == "Rotation" or name == "OffsetX" or name == "OffsetXSize") then
			scaled = -scaled
		end
		out[name] = scaled
	end
	return out
end

local function scaleSpring(spring: (string | Springs.Spring)?, k: number): (string | Springs.Spring)?
	if spring == nil or k == 1 then
		return spring
	end
	-- A spring k times slower in time is the same spring with frequency / k.
	local resolved = Springs.get(spring)
	return { frequency = resolved.frequency / k, damping = resolved.damping }
end

-- A copy of `recipe` with time, amount, curve, spring, delay and mirroring applied. `duration`
-- asks for a total length in seconds; `speed` multiplies playback speed.
function UILogic.scale(recipe: Recipe, options: ScaleOptions?): Recipe
	local opts: ScaleOptions = options or {}
	local intensity = math.max(0, opts.intensity or 1)
	local mirror = opts.mirror == true
	local k = 1
	if opts.duration ~= nil then
		local total = UILogic.duration(recipe) - math.max(0, recipe.delay or 0)
		if total > 0 then
			k = math.max(0, opts.duration) / total
		end
	elseif opts.speed ~= nil and opts.speed > 0 then
		k = 1 / opts.speed
	end
	k = math.max(k, 1e-3)
	local steps: { Step } = {}
	for _, step in recipe.steps do
		local spring = step.spring
		local easing = step.easing
		if spring ~= nil and opts.spring ~= nil then
			spring = opts.spring
		elseif spring == nil and opts.easing ~= nil then
			easing = opts.easing
		end
		table.insert(steps, {
			props = scaleProps(step.props, intensity, mirror) :: Props,
			from = scaleProps(step.from, intensity, mirror),
			duration = if step.duration then step.duration * k else nil,
			easing = easing,
			spring = scaleSpring(spring, k),
			delay = if step.delay then step.delay * k else nil,
			join = step.join,
			marker = step.marker,
			essential = step.essential,
		})
	end
	local layers: { Layer }? = nil
	if recipe.layers then
		local copies: { Layer } = {}
		for _, layer in recipe.layers do
			local copy: Layer = table.clone(layer)
			for _, field in { "duration", "delay", "period", "gap" } do
				if finite(copy[field]) then
					copy[field] = copy[field] * k
				end
			end
			table.insert(copies, copy)
		end
		layers = copies
	end
	local travel = recipe.travel
	if travel and opts.spring ~= nil and type(opts.spring) == "string" then
		travel = { spring = opts.spring }
	end
	return {
		steps = steps,
		layers = layers,
		loop = recipe.loop,
		gap = if recipe.gap then recipe.gap * k else nil,
		delay = math.max(0, (recipe.delay or 0) + (opts.delay or 0)),
		out = recipe.out,
		reduced = recipe.reduced,
		travel = travel,
	}
end

-- The pose a recipe starts from: the first `from` given for each property.
function UILogic.startPose(recipe: Recipe): Props
	local pose: Props = {}
	local seen: { [string]: boolean } = {}
	for _, step in recipe.steps do
		if step.from then
			for name, value in step.from do
				if not seen[name] then
					pose[name] = value
				end
			end
		end
		for name in step.props do
			seen[name] = true
		end
		if step.from then
			for name in step.from do
				seen[name] = true
			end
		end
	end
	return pose
end

-- The pose a recipe ends in: the last goal of each property.
function UILogic.endPose(recipe: Recipe): Props
	local pose: Props = {}
	for _, step in recipe.steps do
		for name, value in step.props do
			pose[name] = value
		end
	end
	return pose
end

-- True when the recipe returns every property it touches to rest.
function UILogic.endsAtRest(recipe: Recipe): boolean
	if recipe.out then
		return false
	end
	for name, value in UILogic.endPose(recipe) do
		if math.abs(value - IDENTITY[name]) > 1e-6 then
			return false
		end
	end
	return true
end

-- What a recipe animates: engine properties and "layer:<kind>". Two recipes that share a channel
-- cannot run on one object at the same time; the newer one replaces the older.
function UILogic.channels(recipe: Recipe): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, step in recipe.steps do
		for name in step.props do
			set[CHANNEL[name] or name] = true
		end
		if step.from then
			for name in step.from do
				set[CHANNEL[name] or name] = true
			end
		end
	end
	for _, layer in recipe.layers or {} do
		set["layer:" .. layer.kind] = true
	end
	if recipe.travel then
		set.Position = true
		set.Size = true
	end
	return set
end

function UILogic.sharesChannel(a: { [string]: boolean }, b: { [string]: boolean }): boolean
	for channel in a do
		if b[channel] then
			return true
		end
	end
	return false
end

-- Turns relative step properties into engine goals for an object at `rest`: Scale, Rotation and
-- GroupFade as one number, Position and Size as { xScale, xOffset, yScale, yOffset }. A step that
-- sets one offset axis leaves the other at rest.
function UILogic.resolve(props: Props, rest: Rest): { [string]: { number } }
	local goals: { [string]: { number } } = {}
	if props.Scale ~= nil then
		goals.Scale = { math.max(0, rest.scale * props.Scale) }
	end
	if props.Rotation ~= nil then
		goals.Rotation = { rest.rotation + props.Rotation }
	end
	if props.GroupFade ~= nil then
		goals.GroupFade = { rest.fade + (1 - rest.fade) * math.clamp(props.GroupFade, 0, 1) }
	end
	if props.OffsetX ~= nil or props.OffsetY ~= nil or props.OffsetXSize ~= nil or props.OffsetYSize ~= nil then
		local x = (props.OffsetX or 0) + (props.OffsetXSize or 0) * rest.pixels[1]
		local y = (props.OffsetY or 0) + (props.OffsetYSize or 0) * rest.pixels[2]
		local p = rest.position
		goals.Position = { p[1], p[2] + x, p[3], p[4] + y }
	end
	if props.Width ~= nil or props.Height ~= nil then
		local w = math.max(0, props.Width or 1)
		local h = math.max(0, props.Height or 1)
		local s = rest.size
		goals.Size = { s[1] * w, s[2] * w, s[3] * h, s[4] * h }
	end
	return goals
end

-- Reduced motion: a preset id to play instead, false to skip, nil to jump to the end pose.
function UILogic.reduced(recipe: Recipe): (string | boolean)?
	if recipe.reduced ~= nil then
		return recipe.reduced
	end
	if recipe.loop then
		return false
	end
	return nil
end

-- Counters --------------------------------------------------------------------------------------

-- Value shown at progress t of a count from `from` to `to` (whole numbers stay whole).
function UILogic.count(from: number, to: number, t: number, easing: string?): number
	return Easing.countUp(from, to, t, easing or "cubicOut")
end

-- Roll time that grows with the size of the change: 0.4 s for small gains up to 1.2 s.
function UILogic.countDuration(delta: number, minSeconds: number?, maxSeconds: number?): number
	return Easing.countUpDuration(delta, minSeconds or 0.4, maxSeconds or 1.2)
end

export type CountFormat = { format: string?, prefix: string?, suffix: string? }

-- Counter text: a Core/Format spec ("number", "abbrev", "abbrev:2", "percent", "time") with an
-- optional prefix and suffix.
function UILogic.countText(value: number, options: CountFormat?): string
	local opts: CountFormat = options or {}
	return (opts.prefix or "") .. Format.apply(opts.format or "number", value) .. (opts.suffix or "")
end

-- Typewriter ------------------------------------------------------------------------------------

-- Characters in `text` (UTF-8 code points; bytes when the text is not valid UTF-8).
function UILogic.typeCount(text: string): number
	return TextFit.length(text)
end

function UILogic.typeDuration(count: number, charsPerSecond: number?): number
	local rate = math.max(1, charsPerSecond or 40)
	return math.max(0, count) / rate
end

-- Characters visible after `elapsed` seconds.
function UILogic.typeIndex(elapsed: number, charsPerSecond: number?, count: number): number
	local rate = math.max(1, charsPerSecond or 40)
	return math.clamp(math.floor(math.max(0, elapsed) * rate + 1e-6), 0, math.max(0, count))
end

-- The first `count` characters of `text`, never cutting a UTF-8 sequence.
function UILogic.typePrefix(text: string, count: number): string
	if count <= 0 then
		return ""
	end
	if utf8.len(text) == nil then
		return string.sub(text, 1, count)
	end
	local cut = utf8.offset(text, count + 1)
	if cut == nil then
		return text
	end
	return string.sub(text, 1, cut - 1)
end

-- Stagger ---------------------------------------------------------------------------------------

local MODULUS = 2147483647

-- Park-Miller generator: the next seed and a number in 0..1. Deterministic, so a seed always gives
-- the same burst.
function UILogic.random(seed: number): (number, number)
	local state = math.floor(math.abs(seed)) % MODULUS
	if state == 0 then
		state = 1
	end
	local nextSeed = (state * 16807) % MODULUS
	return nextSeed, nextSeed / MODULUS
end

-- Delay in seconds for each of `count` items. Orders: "forward", "reverse", "center" (centre
-- out), "edges" (ends first) and "random" (shuffled by `seed`).
function UILogic.staggerDelays(count: number, interval: number, order: string?, seed: number?): { number }
	local delays: { number } = table.create(math.max(0, count), 0)
	local step = math.max(0, interval)
	local mode = order or "forward"
	if mode == "random" then
		local slots: { number } = {}
		for index = 1, count do
			slots[index] = index - 1
		end
		local state = seed or 1
		for index = count, 2, -1 do
			local value: number
			state, value = UILogic.random(state)
			local pick = math.min(index, math.floor(value * index) + 1)
			slots[index], slots[pick] = slots[pick], slots[index]
		end
		for index = 1, count do
			delays[index] = slots[index] * step
		end
		return delays
	end
	local middle = (count + 1) / 2
	local last = math.floor(math.abs(1 - middle))
	for index = 1, count do
		local rank = index - 1
		if mode == "reverse" then
			rank = count - index
		elseif mode == "center" then
			rank = math.floor(math.abs(index - middle))
		elseif mode == "edges" then
			rank = last - math.floor(math.abs(index - middle))
		end
		delays[index] = rank * step
	end
	return delays
end

-- Popups ----------------------------------------------------------------------------------------

export type PopupStyle = {
	duration: number,
	rise: number, -- pixels travelled upward
	drift: number, -- largest sideways travel in pixels
	pop: number, -- peak scale
	popTime: number, -- seconds to reach the peak
	fadeAt: number, -- progress 0..1 where the fade starts
	wobble: number, -- degrees of decaying rotation (crit)
	color: string,
	size: number, -- text size
	prefix: string,
	suffix: string,
}

export type PopupSample = { x: number, y: number, scale: number, transparency: number, rotation: number }

local POPUPS: { [string]: PopupStyle } = {
	damage = {
		duration = 0.8,
		rise = 64,
		drift = 22,
		pop = 1.35,
		popTime = 0.1,
		fadeAt = 0.6,
		wobble = 0,
		color = "#FFFFFF",
		size = 28,
		prefix = "",
		suffix = "",
	},
	currency = {
		duration = 1,
		rise = 80,
		drift = 10,
		pop = 1.25,
		popTime = 0.12,
		fadeAt = 0.65,
		wobble = 0,
		color = "#FFD84A",
		size = 26,
		prefix = "+",
		suffix = "",
	},
	crit = {
		duration = 1.1,
		rise = 84,
		drift = 28,
		pop = 1.9,
		popTime = 0.14,
		fadeAt = 0.7,
		wobble = 9,
		color = "#FF5A3C",
		size = 38,
		prefix = "",
		suffix = "!",
	},
	heal = {
		duration = 0.9,
		rise = 56,
		drift = 8,
		pop = 1.2,
		popTime = 0.12,
		fadeAt = 0.6,
		wobble = 0,
		color = "#6BF08A",
		size = 26,
		prefix = "+",
		suffix = "",
	},
}
for _, style in POPUPS do
	table.freeze(style)
end

UILogic.POPUP_STYLES = table.freeze({ "damage", "currency", "crit", "heal" })

function UILogic.popupStyle(name: string?): PopupStyle
	return POPUPS[name or "damage"] or POPUPS.damage
end

-- Offset, scale, transparency and rotation of a popup at progress t in 0..1. It pops past its
-- size, settles, rises quickly and then slows, drifts to one side (chosen by `seed`) and fades.
function UILogic.popupSample(style: PopupStyle, t: number, seed: number?): PopupSample
	local u = math.clamp(t, 0, 1)
	local _, side = UILogic.random((seed or 1) * 7919 + 13)
	local direction = side * 2 - 1
	local peak = math.clamp(style.popTime / math.max(style.duration, 1e-3), 0.01, 0.5)
	local settle = math.min(1, peak * 2.6)
	local scale: number
	if u < peak then
		scale = 0.4 + (style.pop - 0.4) * Easing.ease("quadOut", u / peak)
	elseif u < settle then
		scale = style.pop + (1 - style.pop) * Easing.ease("cubicOut", (u - peak) / (settle - peak))
	else
		scale = 1
	end
	local transparency = 0
	if u > style.fadeAt then
		local f = (u - style.fadeAt) / math.max(1e-3, 1 - style.fadeAt)
		transparency = f * f
		scale *= 1 - 0.15 * f
	end
	local decay = (1 - u) * (1 - u)
	return {
		x = style.drift * direction * Easing.ease("quadOut", u),
		y = -style.rise * Easing.ease("cubicOut", u),
		scale = scale,
		transparency = transparency,
		rotation = style.wobble * math.sin(u * 30) * decay,
	}
end

-- Fly to counter --------------------------------------------------------------------------------

export type FlyOptions = { spread: number?, stagger: number?, duration: number?, lift: number? }
export type FlyItem = { delay: number, duration: number, bx: number, by: number, lift: number }
export type FlySample = { x: number, y: number, scale: number, transparency: number }

UILogic.FLY_BURST = 0.32 -- share of each item's time spent bursting outward

-- One flight per item: a burst offset in every direction around the source (evenly spread, with
-- jitter from `seed`), a start delay so arrivals tick one by one, and a slightly varied duration.
function UILogic.flyPlan(count: number, seed: number?, options: FlyOptions?): { FlyItem }
	local opts: FlyOptions = options or {}
	local spread = opts.spread or 70
	local stagger = math.max(0, opts.stagger or 0.045)
	local duration = math.max(0.05, opts.duration or 0.6)
	local items: { FlyItem } = {}
	local state = seed or 1
	for index = 1, math.max(0, math.floor(count)) do
		local a: number, r: number, d: number
		state, a = UILogic.random(state)
		state, r = UILogic.random(state)
		state, d = UILogic.random(state)
		local angle = ((index - 1) / math.max(1, count) + (a - 0.5) * 0.12) * 2 * math.pi
		local radius = spread * (0.55 + 0.45 * r)
		table.insert(items, {
			delay = (index - 1) * stagger,
			duration = duration * (0.9 + 0.2 * d),
			bx = math.cos(angle) * radius,
			by = math.sin(angle) * radius,
			lift = opts.lift or 36,
		})
	end
	return items
end

-- Seconds until the last item arrives.
function UILogic.flyDuration(items: { FlyItem }): number
	local total = 0
	for _, item in items do
		total = math.max(total, item.delay + item.duration)
	end
	return total
end

-- Position, scale and transparency of an item at progress u in 0..1, flying from (fx, fy) to
-- (tx, ty). First it bursts out to its offset and slows; then it homes along a quadratic Bezier
-- that keeps the burst direction for a moment, accelerating into the target.
function UILogic.flySample(item: FlyItem, fx: number, fy: number, tx: number, ty: number, u: number): FlySample
	local t = math.clamp(u, 0, 1)
	local split = UILogic.FLY_BURST
	local bx, by = fx + item.bx, fy + item.by
	if t < split then
		local e = Easing.ease("cubicOut", t / split)
		return {
			x = fx + item.bx * e,
			y = fy + item.by * e,
			scale = 0.3 + 0.8 * Easing.ease("backOut", t / split),
			transparency = 0,
		}
	end
	local v = (t - split) / (1 - split)
	local e = v * v
	local cx, cy = bx + item.bx * 0.5, by + item.by * 0.5 - item.lift
	local inv = 1 - e
	return {
		x = inv * inv * bx + 2 * inv * e * cx + e * e * tx,
		y = inv * inv * by + 2 * inv * e * cy + e * e * ty,
		scale = 1.1 - 0.45 * e,
		transparency = 0,
	}
end

-- Ripple ----------------------------------------------------------------------------------------

-- Radius that covers a width x height box from a point inside it (distance to the far corner).
function UILogic.rippleRadius(width: number, height: number, x: number, y: number): number
	local dx = math.max(math.abs(x), math.abs(width - x))
	local dy = math.max(math.abs(y), math.abs(height - y))
	return math.sqrt(dx * dx + dy * dy)
end

-- Ripple at progress t: `size` is the share of the full radius (starts visible, decelerates),
-- `transparency` fades from `startAlpha` to invisible, mostly in the second half.
function UILogic.rippleSample(t: number, startAlpha: number?): { size: number, transparency: number }
	local u = math.clamp(t, 0, 1)
	local base = startAlpha or 0.72
	return {
		size = 0.12 + 0.88 * Easing.ease("cubicOut", u),
		transparency = base + (1 - base) * u * u,
	}
end

-- Button states ---------------------------------------------------------------------------------

export type ButtonState = {
	hovered: boolean,
	focused: boolean, -- gamepad selection
	pressed: boolean,
	selected: boolean,
	disabled: boolean,
}

export type ButtonAction = {
	preset: string,
	intensity: number?,
	spring: string?,
	speed: number?,
	effect: string?, -- "shine" | "ripple", played next to the preset
}

function UILogic.buttonState(): ButtonState
	return { hovered = false, focused = false, pressed = false, selected = false, disabled = false }
end

-- "disabled" | "pressed" | "selected" | "focused" | "hover" | "idle"
function UILogic.buttonStatus(state: ButtonState): string
	if state.disabled then
		return "disabled"
	elseif state.pressed then
		return "pressed"
	elseif state.selected then
		return "selected"
	elseif state.focused then
		return "focused"
	elseif state.hovered then
		return "hover"
	end
	return "idle"
end

UILogic.BUTTON_EVENTS = table.freeze({
	"enter",
	"leave",
	"focus",
	"blur",
	"press",
	"release",
	"select",
	"deselect",
	"disable",
	"enable",
})

-- Applies an event and returns the new state and the action to show, or nil when nothing should
-- move. Actions: hover, unhover, press, release, releaseHover, select, selectedRest, deselect,
-- disable, enable. Events are idempotent, so mouse and touch may both report the same press.
function UILogic.buttonEvent(state: ButtonState, event: string): (ButtonState, string?)
	local s: ButtonState = table.clone(state)
	local lit = s.hovered or s.focused
	if event == "disable" then
		if s.disabled then
			return s, nil
		end
		s.disabled, s.pressed = true, false
		return s, "disable"
	elseif event == "enable" then
		if not s.disabled then
			return s, nil
		end
		s.disabled = false
		return s, "enable"
	elseif event == "select" or event == "deselect" then
		local value = event == "select"
		if s.selected == value then
			return s, nil
		end
		s.selected = value
		if s.disabled or s.pressed then
			return s, nil
		end
		return s, event
	elseif event == "enter" or event == "focus" then
		if event == "enter" then
			s.hovered = true
		else
			s.focused = true
		end
		if lit or s.disabled or s.pressed then
			return s, nil
		end
		return s, "hover"
	elseif event == "leave" or event == "blur" then
		if event == "leave" then
			s.hovered = false
		else
			s.focused = false
		end
		local wasPressed = s.pressed
		if event == "leave" then
			s.pressed = false
		end
		if s.disabled or s.hovered or s.focused or not (lit or wasPressed) then
			return s, nil
		end
		return s, if s.selected then "selectedRest" else "unhover"
	elseif event == "press" then
		if s.disabled or s.pressed then
			return s, nil
		end
		s.pressed = true
		return s, "press"
	elseif event == "release" then
		if not s.pressed then
			return s, nil
		end
		s.pressed = false
		if s.disabled then
			return s, nil
		end
		if lit then
			return s, "releaseHover"
		end
		return s, if s.selected then "selectedRest" else "release"
	end
	return s, nil
end

local SHARED_ACTIONS: { [string]: ButtonAction } = {
	select = { preset = "Selected" },
	selectedRest = { preset = "Selected" },
	deselect = { preset = "Deselected" },
	disable = { preset = "Disabled" },
	enable = { preset = "Enabled" },
}

local BUTTON_STYLES: { [string]: { [string]: ButtonAction } } = {
	-- The default: clear hover, deep press, two-bounce release.
	BouncyPress = {
		hover = { preset = "HoverScale" },
		unhover = { preset = "HoverReset" },
		press = { preset = "PressDown" },
		release = { preset = "ReleaseSpring" },
		releaseHover = { preset = "HoverScale", spring = "Bouncy" },
	},
	-- Calm menus: half the travel, no bounce.
	Soft = {
		hover = { preset = "HoverScale", intensity = 0.5, spring = "Soft" },
		unhover = { preset = "HoverReset", spring = "Soft" },
		press = { preset = "PressDown", intensity = 0.5 },
		release = { preset = "ReleaseSpring", spring = "Soft" },
		releaseHover = { preset = "HoverScale", intensity = 0.5, spring = "Soft" },
	},
	-- Tight and fast for dense HUDs and lists.
	Snappy = {
		hover = { preset = "HoverScale", intensity = 0.7 },
		unhover = { preset = "HoverReset" },
		press = { preset = "PressDown", intensity = 0.75, speed = 1.4 },
		release = { preset = "ReleaseSpring", spring = "Snappy" },
		releaseHover = { preset = "HoverScale", intensity = 0.7, spring = "Snappy" },
	},
	-- Shop and reward buttons: smooth landing and a shine on hover.
	Premium = {
		hover = { preset = "HoverScale", intensity = 0.8, spring = "Premium", effect = "shine" },
		unhover = { preset = "HoverReset", spring = "Premium" },
		press = { preset = "PressDown", intensity = 0.7 },
		release = { preset = "ReleaseSpring", spring = "Premium" },
		releaseHover = { preset = "HoverScale", intensity = 0.8, spring = "Premium" },
	},
	-- Loud: big hover, ripple on press, ringing release.
	Arcade = {
		hover = { preset = "HoverScale", intensity = 1.6, spring = "Bouncy" },
		unhover = { preset = "HoverReset", spring = "Bouncy" },
		press = { preset = "PressDown", intensity = 1.4, effect = "ripple" },
		release = { preset = "ReleaseSpring", spring = "Elastic" },
		releaseHover = { preset = "HoverScale", intensity = 1.6, spring = "Elastic" },
	},
	-- Almost still: no hover motion, a shallow press.
	Minimal = {
		press = { preset = "PressDown", intensity = 0.4 },
		release = { preset = "ReleaseSpring", spring = "Snappy" },
		releaseHover = { preset = "ReleaseSpring", spring = "Snappy" },
	},
}

UILogic.BUTTON_STYLES = table.freeze({ "BouncyPress", "Soft", "Snappy", "Premium", "Arcade", "Minimal" })

function UILogic.hasButtonStyle(style: string): boolean
	return BUTTON_STYLES[style] ~= nil
end

-- What a button style plays for an action, or nil when the style does not move for it.
function UILogic.buttonAction(style: string?, action: string): ButtonAction?
	local actions = BUTTON_STYLES[style or "BouncyPress"] or BUTTON_STYLES.BouncyPress
	return actions[action] or SHARED_ACTIONS[action]
end

return UILogic
