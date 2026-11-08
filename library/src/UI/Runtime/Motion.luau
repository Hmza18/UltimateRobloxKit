--!strict
-- TweenService presets and panel transitions. Every animation goes through Motion.duration, so the
-- reduced-motion setting turns all of them into instant property changes in one place.
--
-- Transitions: "none", "fade" (CanvasGroup only; other objects fall back to "pop"), "pop",
-- "slideUp", "slideDown", "slideLeft", "slideRight". Scale effects use a child UIScale named
-- "UrkScale", created on demand, so they never fight with the object's own Size.

local TweenService = game:GetService("TweenService")

local Decor = require("../Core/Decor")
local Driver = require("./Driver")
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

-- Rainbow helper shared with UrkAnimate: converts Decor's plain RGB to Color3.
function Motion.rainbowColor(t: number, speed: number?, phase: number?): Color3
	local rgb = Decor.rainbow(t, { speed = speed, phase = phase }, reduced)
	return Color3.new(rgb.r, rgb.g, rgb.b)
end

return Motion
