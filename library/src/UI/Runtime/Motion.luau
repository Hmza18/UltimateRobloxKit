--!strict
-- TweenService presets and panel transitions. Every animation goes through Motion.duration, so the
-- reduced-motion setting turns all of them into instant property changes in one place.
--
-- Motion.play(instance, presetName, options?) runs a Core/MotionPresets preset through the shared
-- frame driver (see the end of this file).
--
-- Transitions: "none", "fade" (CanvasGroup only; other objects fall back to "pop"), "pop",
-- "slideUp", "slideDown", "slideLeft", "slideRight". Scale effects use a child UIScale named
-- "UrkScale", created on demand, so they never fight with the object's own Size.

local TweenService = game:GetService("TweenService")

local Decor = require("../Core/Decor")
local Driver = require("./Driver")
local MotionPresets = require("../Core/MotionPresets")
local Tokens = require("../Core/Tokens")

local Motion = {}

local SLIDE_DISTANCE = 40
local SCALE_NAME = "UrkScale"

local reduced = false
local durations: { [string]: number } = table.clone(Tokens.defaults.motion)

-- Running tweens and home positions per object; weak keys so destroyed objects are forgotten.
local running: { [Instance]: Tween } = setmetatable({}, { __mode = "k" }) :: any
local homePositions: { [GuiObject]: UDim2 } = setmetatable({}, { __mode = "k" }) :: any
local tokens: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

local OFFSETS: { [string]: Vector2 } = {
	slideUp = Vector2.new(0, 1),
	slideDown = Vector2.new(0, -1),
	slideLeft = Vector2.new(1, 0),
	slideRight = Vector2.new(-1, 0),
}

function Motion.setReducedMotion(value: boolean)
	reduced = value
end

function Motion.isReduced(): boolean
	return reduced
end

function Motion.setDurations(values: { [string]: number })
	for name, seconds in values do
		durations[name] = seconds
	end
end

-- Seconds for a token name ("fast", "normal", "slow") or a number; 0 with reduced motion.
function Motion.duration(value: (string | number)?): number
	if reduced then
		return 0
	end
	if type(value) == "number" then
		return math.max(0, value)
	end
	if type(value) == "string" then
		return durations[value] or durations.normal
	end
	return durations.normal
end

local function cancel(instance: Instance)
	local tween = running[instance]
	if tween then
		running[instance] = nil
		tween:Cancel()
	end
end

-- Tweens `props` on `instance`. With a zero duration (or reduced motion) the properties are set
-- immediately and `onDone` runs straight away. Returns the Tween, or nil when applied instantly.
function Motion.tween(
	instance: Instance,
	props: { [string]: any },
	duration: (string | number)?,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
	onDone: (() -> ())?
): Tween?
	cancel(instance)
	local seconds = Motion.duration(duration)
	if seconds <= 0 then
		local target: any = instance
		for property, value in props do
			target[property] = value
		end
		if onDone then
			onDone()
		end
		return nil
	end
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local tween = TweenService:Create(instance, info, props)
	running[instance] = tween
	tween.Completed:Connect(function(state: Enum.PlaybackState)
		if running[instance] == tween then
			running[instance] = nil
		end
		if onDone and state == Enum.PlaybackState.Completed then
			onDone()
		end
	end)
	tween:Play()
	return tween
end

-- The UIScale used for pop/pulse effects, created on first use.
function Motion.scaleOf(object: GuiObject): UIScale
	local existing = object:FindFirstChild(SCALE_NAME)
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = SCALE_NAME
	scale.Parent = object
	return scale
end

local function home(object: GuiObject): UDim2
	local position = homePositions[object]
	if position == nil then
		position = object.Position
		homePositions[object] = position
	end
	return position
end

-- Forgets the stored resting position, for example after a layout change moved the object.
function Motion.resetHome(object: GuiObject)
	homePositions[object] = nil
end

local function nextToken(object: Instance): number
	local token = (tokens[object] or 0) + 1
	tokens[object] = token
	return token
end

-- Shows `object` with a transition. Safe to call while a hide is still running.
function Motion.show(object: GuiObject, transition: string?, onDone: (() -> ())?)
	local kind = transition or "pop"
	nextToken(object)
	object.Visible = true
	if kind == "fade" and object:IsA("CanvasGroup") then
		object.GroupTransparency = 1
		Motion.tween(object, { GroupTransparency = 0 }, "normal", nil, nil, onDone)
		return
	end
	local offset = OFFSETS[kind]
	if offset then
		local target = home(object)
		local shift = UDim2.fromOffset(offset.X * SLIDE_DISTANCE, offset.Y * SLIDE_DISTANCE)
		object.Position = target + shift
		Motion.tween(object, { Position = target }, "normal", Enum.EasingStyle.Quint, nil, onDone)
		return
	end
	if kind == "none" then
		if onDone then
			onDone()
		end
		return
	end
	local scale = Motion.scaleOf(object)
	scale.Scale = if Motion.isReduced() then 1 else 0.85
	Motion.tween(scale, { Scale = 1 }, "normal", Enum.EasingStyle.Back, nil, onDone)
end

-- Hides `object` with a transition and sets Visible = false at the end. A show() during the hide
-- wins: the stale hide never turns the object invisible afterwards.
function Motion.hide(object: GuiObject, transition: string?, onDone: (() -> ())?)
	local kind = transition or "pop"
	local token = nextToken(object)
	local function finish()
		if tokens[object] == token then
			object.Visible = false
			if OFFSETS[kind] then
				object.Position = home(object)
			end
		end
		if onDone then
			onDone()
		end
	end
	if kind == "none" or not object.Visible then
		finish()
		return
	end
	if kind == "fade" and object:IsA("CanvasGroup") then
		Motion.tween(object, { GroupTransparency = 1 }, "fast", nil, nil, finish)
		return
	end
	local offset = OFFSETS[kind]
	if offset then
		local shift = UDim2.fromOffset(offset.X * SLIDE_DISTANCE, offset.Y * SLIDE_DISTANCE)
		local away = home(object) + shift
		Motion.tween(object, { Position = away }, "fast", Enum.EasingStyle.Quad, Enum.EasingDirection.In, finish)
		return
	end
	local scale = Motion.scaleOf(object)
	Motion.tween(scale, { Scale = 0.9 }, "fast", Enum.EasingStyle.Quad, Enum.EasingDirection.In, function()
		finish()
		if tokens[object] == token then
			scale.Scale = 1
		end
	end)
end

-- A quick scale bump, for example when a counter changes or a toast is merged.
function Motion.pop(object: GuiObject, amount: number?)
	if Motion.isReduced() then
		return
	end
	local scale = Motion.scaleOf(object)
	scale.Scale = 1 + (amount or 0.12)
	Motion.tween(scale, { Scale = 1 }, "normal", Enum.EasingStyle.Back)
end

-- Drops in from above with a bounce.
function Motion.bounce(object: GuiObject)
	if Motion.isReduced() then
		return
	end
	local target = home(object)
	object.Position = target - UDim2.fromOffset(0, 24)
	Motion.tween(object, { Position = target }, "slow", Enum.EasingStyle.Bounce)
end

-- Horizontal shake for errors (wrong code, cannot afford). Uses the shared frame driver.
function Motion.shake(object: GuiObject, intensity: number?, seconds: number?)
	if Motion.isReduced() then
		return
	end
	local target = home(object)
	local strength = intensity or 8
	local length = seconds or 0.35
	local started = os.clock()
	Driver.add(function(_dt: number, now: number): boolean?
		local elapsed = now - started
		if elapsed >= length or object.Parent == nil then
			object.Position = target
			return false
		end
		local falloff = 1 - elapsed / length
		local offset = math.sin(elapsed * 60) * strength * falloff
		object.Position = target + UDim2.fromOffset(offset, 0)
		return true
	end)
end

-- Cancels a running Motion.tween on `instance` (the tween stops where it is).
function Motion.cancel(instance: Instance)
	cancel(instance)
end

-- Rainbow helper shared with UrkAnimate: converts Decor's plain RGB to Color3.
function Motion.rainbowColor(t: number, speed: number?, phase: number?): Color3
	local rgb = Decor.rainbow(t, { speed = speed, phase = phase }, reduced)
	return Color3.new(rgb.r, rgb.g, rgb.b)
end

-- Presets -------------------------------------------------------------------------------------
-- Motion.play(instance, presetName, options?) plays a Core/MotionPresets preset on the shared frame
-- driver and returns a stop function. What each key property drives:
--   GuiObject:  scale -> its "UrkScale" UIScale, rotation -> Rotation (relative to the resting
--               value), offsetY -> Position.Y offset (relative), transparency -> GroupTransparency
--               on a CanvasGroup (ignored on other objects)
--   UIScale:    scale only
--   UIGradient: offsetY -> Offset.X (the "shine" sweep, -1..1)
-- Starting a preset stops the previous one on the same instance. Looping presets skip frames while
-- the object is hidden and restore the resting values when stopped. Under reduced motion a
-- one-shot preset jumps to its last key (onDone still runs) and looping presets do not start.

export type PlayOptions = {
	onDone: (() -> ())?, -- runs when a one-shot preset finishes
	fromCurrent: boolean?, -- start from the current values instead of the first key (state changes)
	speed: number?, -- playback rate, default 1
	loop: boolean?, -- override the preset's loop flag
}

type Uses = { scale: boolean, rotation: boolean, offsetY: boolean, transparency: boolean }
type Base = { position: UDim2, rotation: number }
type Playing = { stop: (restore: boolean) -> (), loop: boolean, uses: Uses, base: Base, final: MotionPresets.Sample }

local playing: { [Instance]: Playing } = setmetatable({}, { __mode = "k" }) :: any
local bases: { [Instance]: Base } = setmetatable({}, { __mode = "k" }) :: any
local usesCache: { [any]: Uses } = setmetatable({}, { __mode = "k" }) :: any

local function noop() end

local function usesOf(preset: MotionPresets.Preset): Uses
	local cached = usesCache[preset]
	if cached then
		return cached
	end
	local uses: Uses = {
		scale = MotionPresets.uses(preset, "scale"),
		rotation = MotionPresets.uses(preset, "rotation"),
		offsetY = MotionPresets.uses(preset, "offsetY"),
		transparency = MotionPresets.uses(preset, "transparency"),
	}
	usesCache[preset] = uses
	return uses
end

local function baseOf(instance: Instance): Base
	local base = bases[instance]
	if base == nil then
		local object: any = instance
		local isGui = instance:IsA("GuiObject")
		base = {
			position = if isGui then object.Position else UDim2.fromOffset(0, 0),
			rotation = if isGui then object.Rotation else 0,
		}
		bases[instance] = base
	end
	return base :: Base
end

local function currentSample(instance: Instance, base: Base): MotionPresets.Sample
	local object: any = instance
	local sample = { scale = 1, rotation = 0, offsetY = 0, transparency = 0 }
	if instance:IsA("UIScale") then
		sample.scale = object.Scale
	elseif instance:IsA("UIGradient") then
		sample.offsetY = object.Offset.X
	elseif instance:IsA("GuiObject") then
		local scale = instance:FindFirstChild(SCALE_NAME)
		if scale and scale:IsA("UIScale") then
			sample.scale = scale.Scale
		end
		sample.rotation = object.Rotation - base.rotation
		sample.offsetY = object.Position.Y.Offset - base.position.Y.Offset
		if instance:IsA("CanvasGroup") then
			sample.transparency = object.GroupTransparency
		end
	end
	return sample
end

local function applySample(instance: Instance, uses: Uses, base: Base, sample: MotionPresets.Sample)
	local object: any = instance
	if instance:IsA("UIGradient") then
		if uses.offsetY then
			object.Offset = Vector2.new(sample.offsetY, object.Offset.Y)
		end
	elseif instance:IsA("UIScale") then
		if uses.scale then
			object.Scale = sample.scale
		end
	elseif instance:IsA("GuiObject") then
		if uses.scale then
			Motion.scaleOf(instance).Scale = sample.scale
		end
		if uses.rotation then
			object.Rotation = base.rotation + sample.rotation
		end
		if uses.offsetY then
			object.Position = base.position + UDim2.fromOffset(0, sample.offsetY)
		end
		if uses.transparency and instance:IsA("CanvasGroup") then
			object.GroupTransparency = sample.transparency
		end
	end
end

local function cancelScaleTween(instance: Instance)
	if instance:IsA("UIScale") then
		cancel(instance)
		return
	end
	local scale = instance:FindFirstChild(SCALE_NAME)
	if scale then
		cancel(scale)
	end
end

-- Stops the preset playing on `instance`. Looping presets return to their resting values.
function Motion.stop(instance: Instance)
	local current = playing[instance]
	if current then
		current.stop(current.loop)
	end
end

function Motion.isPlaying(instance: Instance): boolean
	return playing[instance] ~= nil
end

-- Plays preset `presetName` on `instance`. Returns a function that stops it.
function Motion.play(instance: Instance, presetName: string, options: PlayOptions?): () -> ()
	local opts: PlayOptions = options or {}
	local preset = MotionPresets.get(presetName)
	local loop = if opts.loop ~= nil then opts.loop == true else preset.loop == true
	local uses = usesOf(preset)
	local previous = playing[instance]
	if previous then
		previous.stop(previous.loop)
		if not previous.loop then
			-- Properties the new preset does not drive jump to where the interrupted one would end.
			local leftover: Uses = {
				scale = previous.uses.scale and not uses.scale,
				rotation = previous.uses.rotation and not uses.rotation,
				offsetY = previous.uses.offsetY and not uses.offsetY,
				transparency = previous.uses.transparency and not uses.transparency,
			}
			applySample(instance, leftover, previous.base, previous.final)
		end
	end
	if uses.scale then
		cancelScaleTween(instance)
	end
	local base = baseOf(instance)
	local active = if opts.fromCurrent then MotionPresets.from(preset, currentSample(instance, base)) else preset
	local onDone = opts.onDone

	if reduced then
		if not loop then
			applySample(instance, uses, base, MotionPresets.sample(active, 1))
			bases[instance] = nil
			if onDone then
				onDone()
			end
		end
		return noop
	end

	local duration = active.duration / math.max(0.01, opts.speed or 1)
	local started = os.clock()
	local removeJob: (() -> ())? = nil
	local entry: Playing

	local function stop(restore: boolean)
		if removeJob then
			removeJob()
			removeJob = nil
		end
		if playing[instance] == entry then
			playing[instance] = nil
		end
		if restore then
			applySample(instance, uses, base, MotionPresets.REST)
			bases[instance] = nil
		end
	end

	entry = { stop = stop, loop = loop, uses = uses, base = base, final = MotionPresets.sample(active, 1) }
	playing[instance] = entry
	-- Apply the first key now, so nothing shows in its resting state for a frame.
	applySample(instance, uses, base, MotionPresets.sample(active, 0))
	local object: any = instance
	removeJob = Driver.add(function(_dt: number, now: number): boolean?
		if instance.Parent == nil then
			removeJob = nil
			if playing[instance] == entry then
				playing[instance] = nil
			end
			return false
		end
		local t = if duration > 0 then (now - started) / duration else 1
		if loop then
			if instance:IsA("GuiObject") and not object.Visible then
				return true
			end
			applySample(instance, uses, base, MotionPresets.sample(active, t % 1))
			return true
		end
		if t < 1 then
			applySample(instance, uses, base, MotionPresets.sample(active, t))
			return true
		end
		applySample(instance, uses, base, MotionPresets.sample(active, 1))
		removeJob = nil
		if playing[instance] == entry then
			playing[instance] = nil
			bases[instance] = nil
		end
		if onDone then
			onDone()
		end
		return false
	end)
	return function()
		stop(loop)
	end
end

-- The preset data module, for callers that need durations or samples.
Motion.presets = MotionPresets

return Motion
