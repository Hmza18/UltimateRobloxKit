--!strict
-- UI animation player (Visuals.UI). Plays the recipes in UIPresets on GuiObjects through
-- Runtime/Motion, and adds the pieces a game HUD needs: button bindings, show / hide, staggered
-- lists, number counters, typewriter text, shine, ripple, screen flash, backdrops, floating
-- popups and currency that flies to its counter.
--
--   UI.animate(button, "BouncyPress")
--   UI.show(panel, "PopIn")  /  UI.hide(panel, "PopOut")
--   local binding = UI.bind(button, "Premium")      -- hover / press / release / selected / disabled
--   UI.countTo(label, 2400, { format = "abbrev" })
--   UI.popup(125, hitPosition, { style = "crit" })
--   UI.flyTo(chest, coinCounter.Instance, { count = 10, onArrive = addCoin })
--
-- Rules this module keeps:
--   * Recipes are relative to the object's rest state (position, size, rotation, scale, fade),
--     captured on first use. UI.rest(gui) recaptures after you move or restyle an object.
--   * Steps are chained with Host.clock timers; stopping a handle cancels the rest of the chain.
--   * Two presets that animate the same thing cannot run on one object: the newer one replaces
--     the older (unless the older has a higher priority). A shine can run over a press.
--   * Reduced motion: loops do not start, entrances and exits become fades, everything else
--     jumps to its end pose. Reduced flashing softens tints and screen flashes.
--   * Per-frame work (popups, flying items, counters, typewriters) is a Host.clock job that ends
--     when nothing is alive.
--
-- NOT run in Studio. See README.md.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Host = require("../Runtime/Host")
local Motion = require("../Runtime/Motion")
local Pool = require("../Core/Pool")
local Props = require("../Runtime/Props")
local Quality = require("../Core/Quality")
local Trove = require("../../Util/Trove")
local UILogic = require("./UILogic")
local UIPresets = require("./UIPresets")

export type Handle = {
	stop: (restore: boolean?) -> (),
	cancel: (restore: boolean?) -> (),
	finish: () -> (),
	isDone: () -> boolean,
	[string]: any,
}

export type Options = {
	duration: number?, -- wanted total seconds
	speed: number?, -- playback speed multiplier
	intensity: number?, -- amount multiplier
	delay: number?,
	easing: string?,
	spring: any?, -- spring preset name or { frequency, damping }
	mirror: boolean?, -- flip horizontal offsets and rotation
	priority: number?,
	restore: boolean?, -- put the rest state back when stopped (default: only for loops)
	color: any?, -- Color3 or hex for glow / tint / shine / border layers
	colors: { any }?, -- border gradient colours
	at: Vector2?, -- ripple origin in AbsolutePosition space
	position: UDim2?, -- IndicatorSlide: new rest position
	size: UDim2?, -- IndicatorSlide: new rest size
	onDone: ((completed: boolean) -> ())?,
	onMarker: ((marker: string) -> ())?,
	[string]: any,
}

local UI = {}

UI.registry = UIPresets.registry
UI.Logic = UILogic

local function noop() end

local function doneHandle(): Handle
	return {
		stop = noop,
		cancel = noop,
		finish = noop,
		isDone = function(): boolean
			return true
		end,
	}
end

local function color3(value: any, fallback: Color3): Color3
	if typeof(value) == "Color3" then
		return value
	elseif type(value) == "string" then
		local ok, parsed = pcall(Color3.fromHex, value)
		if ok then
			return parsed
		end
	end
	return fallback
end

local function alive(instance: Instance): boolean
	return Props.adapter.alive(instance)
end

local function call(callback: any, ...: any)
	if callback then
		local ok, err = pcall(callback, ...)
		if not ok then
			warn("[UVK.UI] callback failed: " .. tostring(err))
		end
	end
end

-- Rest state --------------------------------------------------------------------------------------

local rests: { [GuiObject]: UILogic.Rest } = setmetatable({}, { __mode = "k" }) :: any
local displaced: { [GuiObject]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

local function packUDim2(value: UDim2): { number }
	return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
end

-- Product of every UIScale from `gui` up, to turn AbsoluteSize back into 1x pixels.
local function scaleFactor(gui: Instance): number
	local factor = 1
	local current: Instance? = gui
	while current do
		local scale = current:FindFirstChildOfClass("UIScale")
		if scale then
			factor *= scale.Scale
		end
		current = current.Parent
	end
	return if factor > 1e-4 then factor else 1
end

local function readFade(gui: GuiObject): number
	local value = Props.adapter.read(gui, "GroupFade")
	return if value then value[1] else 0
end

local function restOf(gui: GuiObject): UILogic.Rest
	local rest = rests[gui]
	if rest == nil then
		rest = {
			scale = Props.scaleOf(gui).Scale,
			rotation = gui.Rotation,
			fade = readFade(gui),
			position = packUDim2(gui.Position),
			size = packUDim2(gui.Size),
			pixels = { 0, 0 },
		}
		rests[gui] = rest
	else
		-- Layouts and game code move and resize objects; follow them while this module is not
		-- holding the object away from rest.
		local moved = displaced[gui]
		if not (moved and moved.Position) and not Motion.isAnimating(gui, "Position") then
			rest.position = packUDim2(gui.Position)
		end
		if not (moved and moved.Size) and not Motion.isAnimating(gui, "Size") then
			rest.size = packUDim2(gui.Size)
		end
	end
	local factor = scaleFactor(gui)
	rest.pixels = { gui.AbsoluteSize.X / factor, gui.AbsoluteSize.Y / factor }
	return rest
end

local function values(goals: { [string]: { number } }): { [string]: any }
	local out: { [string]: any } = {}
	for property, v in goals do
		if property == "Position" or property == "Size" then
			out[property] = UDim2.new(v[1], v[2], v[3], v[4])
		else
			out[property] = v[1]
		end
	end
	return out
end

-- Writes a pose at once through the engine, so it also takes the properties over from whatever
-- was animating them.
local function snap(gui: GuiObject, props: UILogic.Props, rest: UILogic.Rest, priority: number?)
	if next(props) == nil then
		return
	end
	Motion.tween(gui, values(UILogic.resolve(props, rest)), { duration = 0, essential = true, priority = priority })
end

local function restPoseFor(channels: { [string]: boolean }): UILogic.Props
	local pose: UILogic.Props = {}
	if channels.Scale then
		pose.Scale = 1
	end
	if channels.Rotation then
		pose.Rotation = 0
	end
	if channels.GroupFade then
		pose.GroupFade = 0
	end
	if channels.Position then
		pose.OffsetX, pose.OffsetY = 0, 0
	end
	if channels.Size then
		pose.Width, pose.Height = 1, 1
	end
	return pose
end

-- Recaptures the rest state of `gui` (call after moving, resizing or restyling it yourself).
function UI.rest(gui: GuiObject)
	Motion.stop(gui, false)
	rests[gui] = nil
	displaced[gui] = nil
	restOf(gui)
end

-- Layers ------------------------------------------------------------------------------------------
-- Overlay effects a recipe can ask for. Each returns a function that removes it.

local function cornerOf(gui: GuiObject): UICorner?
	local own = gui:FindFirstChildOfClass("UICorner")
	if own then
		return own
	end
	-- UrkUI game components draw their surface in a "Body" child of a transparent root.
	local body = gui:FindFirstChild("Body")
	return if body then body:FindFirstChildOfClass("UICorner") else nil
end

local function copyCorner(gui: GuiObject, onto: Instance, grow: number?)
	local source = cornerOf(gui)
	if source == nil then
		return
	end
	local corner = Instance.new("UICorner")
	local radius = source.CornerRadius
	corner.CornerRadius = UDim.new(radius.Scale, radius.Offset + (grow or 0))
	corner.Parent = onto
end

local function overlayFrame(_gui: GuiObject, name: string, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = zIndex
	frame.Active = false
	frame:SetAttribute("UrkInternal", true)
	return frame
end

export type ShineOptions = {
	duration: number?,
	delay: number?,
	angle: number?,
	width: number?, -- streak half-width as a share of the object, default 0.22
	alpha: number?, -- streak transparency at its centre, default 0.45
	color: any?,
	loop: boolean?, -- repeat every `interval` seconds until stopped
	interval: number?,
	onDone: ((completed: boolean) -> ())?,
}

-- A bright streak sweeps across `gui` once (or repeatedly with loop = true). The streak is a
-- frame with a UIGradient created on demand and destroyed when the sweep ends or is stopped.
function UI.shine(gui: GuiObject, options: ShineOptions?): Handle
	local opts: ShineOptions = options or {}
	local settings = Host.settings()
	if settings.reducedMotion or (opts.loop and not Host.profile().uiShine) or not alive(gui) then
		call(opts.onDone, false)
		return doneHandle()
	end
	local width = math.clamp(opts.width or 0.22, 0.02, 0.45)
	local streak = overlayFrame(gui, "UvkShine", 50)
	streak.BackgroundColor3 = color3(opts.color, Color3.new(1, 1, 1))
	copyCorner(gui, streak)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = opts.angle or 20
	gradient.Offset = Vector2.new(-1, 0)
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5 - width, 1),
		NumberSequenceKeypoint.new(0.5, math.clamp(opts.alpha or 0.45, 0, 1)),
		NumberSequenceKeypoint.new(0.5 + width, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = streak
	streak.Parent = gui

	local done = false
	local cancelTimer: (() -> ())? = nil
	local function finish(completed: boolean)
		if done then
			return
		end
		done = true
		if cancelTimer then
			cancelTimer()
			cancelTimer = nil
		end
		Motion.stop(gradient, false)
		streak:Destroy()
		call(opts.onDone, completed)
	end
	local sweep: () -> ()
	function sweep()
		cancelTimer = nil
		if done then
			return
		end
		if not alive(gui) then
			finish(false)
			return
		end
		Motion.tween(gradient, { Offset = Vector2.new(1, 0) }, {
			from = { Offset = Vector2.new(-1, 0) },
			duration = opts.duration or 0.6,
			easing = "sineInOut",
			onDone = function(completed: boolean)
				if done then
					return
				end
				if completed and opts.loop then
					cancelTimer = Host.clock:after(opts.interval or 2.4, sweep)
				else
					finish(completed)
				end
			end,
		})
	end
	if opts.delay and opts.delay > 0 then
		streak.Visible = false
		cancelTimer = Host.clock:after(opts.delay, function()
			streak.Visible = true
			sweep()
		end)
	else
		sweep()
	end
	local function stop()
		finish(false)
	end
	return {
		stop = stop,
		cancel = stop,
		finish = stop,
		isDone = function(): boolean
			return done
		end,
	}
end

type Glow = { frame: Frame, stroke: UIStroke, on: boolean, level: number }
local glows: { [GuiObject]: Glow } = setmetatable({}, { __mode = "k" }) :: any

local GLOW_PAD = 2

local function ensureGlow(gui: GuiObject, color: Color3?, thickness: number?): Glow
	local glow = glows[gui]
	if glow == nil or glow.frame.Parent == nil then
		local frame = Instance.new("Frame")
		frame.Name = "UvkGlow"
		frame.BackgroundTransparency = 1
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.new(1, GLOW_PAD * 2, 1, GLOW_PAD * 2)
		frame.ZIndex = 49
		frame.Active = false
		frame:SetAttribute("UrkInternal", true)
		copyCorner(gui, frame, GLOW_PAD)
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Transparency = 1
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Parent = frame
		frame.Parent = gui
		glow = { frame = frame, stroke = stroke, on = false, level = 0.1 }
		glows[gui] = glow
	end
	if color then
		glow.stroke.Color = color
	end
	if thickness then
		glow.stroke.Thickness = thickness
	end
	return glow
end

local function removeGlow(gui: GuiObject)
	local glow = glows[gui]
	if glow then
		glows[gui] = nil
		Motion.stop(glow.stroke, false)
		glow.frame:Destroy()
	end
end

-- Outline glow around `gui`. Modes: "on" (stays), "off", "flash" (once), "pulse" (loop).
local function runGlow(gui: GuiObject, layer: UILogic.Layer, options: Options): () -> ()
	local mode: string = layer.mode or "flash"
	if mode == "off" then
		local glow = glows[gui]
		if glow then
			glow.on = false
			Motion.tween(glow.stroke, { Transparency = 1 }, {
				duration = 0.14,
				essential = true,
				onDone = function(completed: boolean)
					if completed and glows[gui] == glow and not glow.on then
						removeGlow(gui)
					end
				end,
			})
		end
		return noop
	end
	local hue: Color3? = if options.color ~= nil or layer.color ~= nil
		then color3(options.color or layer.color, Color3.new(1, 1, 1))
		else nil
	local glow = ensureGlow(gui, hue, layer.thickness or 3)
	local stroke = glow.stroke
	if mode == "pulse" and not Host.profile().uiShine then
		mode = "on" -- low quality: a steady glow instead of a loop
	end
	if mode == "on" then
		glow.on = true
		Motion.tween(stroke, { Transparency = glow.level }, { duration = 0.14, essential = true })
		return noop
	end
	local wasOn = glow.on
	local function settle()
		if glows[gui] ~= glow then
			return
		end
		if glow.on then
			Motion.tween(stroke, { Transparency = glow.level }, { duration = 0.12, essential = true })
		else
			removeGlow(gui)
		end
	end
	if mode == "pulse" then
		Motion.tween(stroke, { Transparency = layer.max or 0.85 }, {
			from = { Transparency = layer.min or 0.2 },
			duration = (layer.period or 1.2) / 2,
			easing = "sineInOut",
			repeatCount = -1,
			reverses = true,
		})
		return function()
			Motion.stop(stroke, false)
			glow.on = wasOn
			settle()
		end
	end
	-- flash: up fast, down slow.
	local duration: number = layer.duration or 0.45
	local cancelled = false
	Motion.tween(stroke, { Transparency = 0 }, {
		duration = duration * 0.2,
		essential = true,
		onDone = function(completed: boolean)
			if not completed or cancelled then
				return
			end
			Motion.tween(stroke, { Transparency = if glow.on then glow.level else 1 }, {
				duration = duration * 0.8,
				easing = "quadIn",
				essential = true,
				onDone = function(finished: boolean)
					if finished and not cancelled then
						settle()
					end
				end,
			})
		end,
	})
	return function()
		if not cancelled then
			cancelled = true
			Motion.stop(stroke, false)
			settle()
		end
	end
end

export type RippleOptions = {
	at: Vector2?, -- origin in AbsolutePosition space (InputObject.Position); default: the centre
	color: any?,
	duration: number?,
	alpha: number?, -- starting transparency, default 0.72
	onDone: ((completed: boolean) -> ())?,
}

-- A circle grows from the press point and fades. It lives in a clipping frame inside `gui`, so it
-- is cut to the object's rectangle; rounded corners only clip when the object is a CanvasGroup.
function UI.ripple(gui: GuiObject, options: RippleOptions?): Handle
	local opts: RippleOptions = options or {}
	if Host.settings().reducedMotion or not alive(gui) then
		call(opts.onDone, false)
		return doneHandle()
	end
	local factor = scaleFactor(gui)
	local width, height = gui.AbsoluteSize.X / factor, gui.AbsoluteSize.Y / factor
	local x, y = width / 2, height / 2
	if opts.at then
		x = math.clamp((opts.at.X - gui.AbsolutePosition.X) / factor, 0, width)
		y = math.clamp((opts.at.Y - gui.AbsolutePosition.Y) / factor, 0, height)
	end
	local radius = UILogic.rippleRadius(width, height, x, y)
	local clip = overlayFrame(gui, "UvkRipple", 48)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.BorderSizePixel = 0
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromOffset(x, y)
	circle.BackgroundColor3 = color3(opts.color, Color3.new(1, 1, 1))
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = circle
	circle.Parent = clip
	local function draw(alpha: number)
		local sample = UILogic.rippleSample(alpha, opts.alpha)
		local diameter = radius * 2 * sample.size
		circle.Size = UDim2.fromOffset(diameter, diameter)
		circle.BackgroundTransparency = sample.transparency
	end
	draw(0)
	clip.Parent = gui
	local done = false
	local progress = { t = 0 }
	local track: Motion.Handle
	local function finish(completed: boolean)
		if done then
			return
		end
		done = true
		clip:Destroy()
		call(opts.onDone, completed)
	end
	track = Motion.tween(progress, { t = 1 }, {
		duration = opts.duration or 0.45,
		easing = "linear",
		onStep = function(alpha: number)
			if not done then
				draw(alpha)
			end
		end,
		onDone = finish,
	})
	local function stop()
		track.cancel(false)
		finish(false)
	end
	return {
		stop = stop,
		cancel = stop,
		finish = stop,
		isDone = function(): boolean
			return done
		end,
	}
end

-- Colour overlay that fades out (the red flash of "Error").
local function runTint(gui: GuiObject, layer: UILogic.Layer, options: Options): () -> ()
	local alpha: number = layer.alpha or 0.5
	if Host.settings().reducedFlashing then
		alpha *= 0.4
	end
	local frame = overlayFrame(gui, "UvkTint", 47)
	frame.BackgroundColor3 = color3(options.color or layer.color, Color3.new(1, 1, 1))
	frame.BackgroundTransparency = 1 - alpha
	copyCorner(gui, frame)
	frame.Parent = gui
	local removed = false
	local function remove()
		if not removed then
			removed = true
			Motion.stop(frame, false)
			frame:Destroy()
		end
	end
	Motion.tween(frame, { BackgroundTransparency = 1 }, {
		duration = layer.duration or 0.3,
		easing = "quadOut",
		essential = true,
		onDone = remove,
	})
	return remove
end

local function borderStroke(gui: GuiObject): UIStroke?
	local own = gui:FindFirstChildOfClass("UIStroke")
	if own and own.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
		return own
	end
	local body = gui:FindFirstChild("Body")
	return if body then body:FindFirstChildOfClass("UIStroke") else nil
end

-- A highlight travels around the outline: a rotating UIGradient on the object's border UIStroke
-- (or on a glow outline when it has none). The gradient multiplies the stroke colour, so the
-- default grey-white-grey band works with any rarity colour.
local function runBorder(gui: GuiObject, layer: UILogic.Layer, options: Options): () -> ()
	if not Host.profile().uiShine then
		return noop
	end
	local stroke = borderStroke(gui)
	local madeGlow = false
	if stroke == nil then
		local glow = ensureGlow(gui, color3(options.color or layer.color, Color3.new(1, 1, 1)), layer.thickness or 3)
		madeGlow = not glow.on
		glow.stroke.Transparency = 0
		stroke = glow.stroke
	end
	local target = stroke :: UIStroke
	local old = target:FindFirstChild("UvkBorderGradient")
	if old then
		Motion.stop(old, false)
		old:Destroy()
	end
	local gradient = Instance.new("UIGradient")
	gradient.Name = "UvkBorderGradient"
	local colors = options.colors
	if colors and #colors >= 2 then
		local points: { ColorSequenceKeypoint } = {}
		for index, value in colors do
			local at = (index - 1) / (#colors - 1)
			table.insert(points, ColorSequenceKeypoint.new(at, color3(value, Color3.new(1, 1, 1))))
		end
		gradient.Color = ColorSequence.new(points)
	else
		local dim = Color3.new(0.55, 0.55, 0.55)
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, dim),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, dim),
		})
	end
	gradient.Parent = target
	Motion.tween(gradient, { Rotation = 360 }, {
		from = { Rotation = 0 },
		duration = layer.period or 2.4,
		easing = "linear",
		repeatCount = -1,
	})
	return function()
		Motion.stop(gradient, false)
		gradient:Destroy()
		if madeGlow then
			removeGlow(gui)
		end
	end
end

-- The text outline brightens and thickens in a loop: the label's UIStroke when it has one,
-- otherwise its TextStroke properties. Everything is put back when stopped.
local function runTextGlow(gui: GuiObject, layer: UILogic.Layer, options: Options): () -> ()
	if not Host.profile().uiShine then
		return noop
	end
	local hue = color3(options.color or layer.color, Color3.new(1, 0.95, 0.66))
	local half = (layer.period or 1.4) / 2
	local stroke = gui:FindFirstChildOfClass("UIStroke")
	if stroke then
		Motion.tween(stroke, { Color = hue, Thickness = stroke.Thickness * 1.5 }, {
			duration = half,
			easing = "sineInOut",
			repeatCount = -1,
			reverses = true,
		})
		return function()
			Motion.stop(stroke, true)
		end
	end
	if not (gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox")) then
		return noop
	end
	local label: any = gui
	local color, transparency = label.TextStrokeColor3, label.TextStrokeTransparency
	label.TextStrokeColor3 = hue
	Motion.tween(label, { TextStrokeTransparency = 0.15 }, {
		from = { TextStrokeTransparency = 0.85 },
		duration = half,
		easing = "sineInOut",
		repeatCount = -1,
		reverses = true,
	})
	return function()
		Motion.stop(label, false)
		label.TextStrokeColor3 = color
		label.TextStrokeTransparency = transparency
	end
end

local function runLayer(gui: GuiObject, layer: UILogic.Layer, options: Options): () -> ()
	local kind = layer.kind
	if kind == "shine" then
		local handle = UI.shine(gui, {
			duration = layer.duration,
			angle = layer.angle,
			width = layer.width,
			alpha = layer.alpha,
			color = options.color or layer.color,
		})
		return handle.stop
	elseif kind == "glow" then
		return runGlow(gui, layer, options)
	elseif kind == "ripple" then
		local handle = UI.ripple(gui, {
			at = options.at,
			color = options.color or layer.color,
			duration = layer.duration,
			alpha = layer.alpha,
		})
		return handle.stop
	elseif kind == "tint" then
		return runTint(gui, layer, options)
	elseif kind == "border" then
		return runBorder(gui, layer, options)
	elseif kind == "textGlow" then
		return runTextGlow(gui, layer, options)
	end
	return noop
end

-- Chains -------------------------------------------------------------------------------------------

type Chain = {
	gui: GuiObject,
	id: string,
	recipe: UILogic.Recipe,
	channels: { [string]: boolean },
	priority: number,
	rest: UILogic.Rest,
	options: Options,
	timers: { () -> () },
	tracks: { Motion.Handle },
	layers: { () -> () },
	done: boolean,
}

local chains: { [GuiObject]: { Chain } } = setmetatable({}, { __mode = "k" }) :: any

local function clearRun(chain: Chain)
	for _, cancel in chain.timers do
		cancel()
	end
	table.clear(chain.timers)
	for _, track in chain.tracks do
		track.cancel(false)
	end
	table.clear(chain.tracks)
end

-- Ends a chain. `completed` tells onDone whether it played to the end.
local function endChain(chain: Chain, completed: boolean, restore: boolean)
	if chain.done then
		return
	end
	chain.done = true
	local gui = chain.gui
	local list = chains[gui]
	if list then
		local index = table.find(list, chain)
		if index then
			table.remove(list, index)
		end
		if #list == 0 then
			chains[gui] = nil
		end
	end
	for _, cancel in chain.timers do
		cancel()
	end
	table.clear(chain.timers)
	if not completed then
		for _, track in chain.tracks do
			track.cancel(false)
		end
	end
	table.clear(chain.tracks)
	if not completed or chain.recipe.loop then
		for _, stopLayer in chain.layers do
			stopLayer()
		end
	end
	table.clear(chain.layers)
	local moved = displaced[gui]
	if moved == nil then
		moved = {}
		displaced[gui] = moved
	end
	local atRest = restore or (completed and UILogic.endsAtRest(chain.recipe))
	for channel in chain.channels do
		if atRest then
			moved[channel] = nil
		else
			moved[channel] = true
		end
	end
	if restore and alive(gui) then
		snap(gui, restPoseFor(chain.channels), chain.rest, chain.priority)
	end
	call(chain.options.onDone, completed)
end

local function runStep(chain: Chain, step: UILogic.Step)
	if chain.done then
		return
	end
	if step.marker then
		call(chain.options.onMarker, step.marker)
		if chain.done then
			return
		end
	end
	local track = Motion.animate(chain.gui, {
		props = values(UILogic.resolve(step.props, chain.rest)),
		from = if step.from then values(UILogic.resolve(step.from, chain.rest)) else nil,
		duration = step.duration,
		easing = step.easing,
		spring = step.spring,
		priority = chain.priority,
		essential = step.essential,
	})
	table.insert(chain.tracks, track)
end

local function runCycle(chain: Chain, plan: UILogic.Schedule)
	table.clear(chain.tracks)
	for _, entry in plan.entries do
		if entry.at <= 0 then
			runStep(chain, entry.step)
		else
			table.insert(
				chain.timers,
				Host.clock:after(entry.at, function()
					runStep(chain, entry.step)
				end)
			)
		end
	end
	if chain.done then
		return
	end
	local recipe = chain.recipe
	if recipe.loop then
		if plan.total > 0 and #plan.entries > 0 then
			table.insert(
				chain.timers,
				Host.clock:after(plan.total + (recipe.gap or 0), function()
					if chain.done then
						return
					end
					table.clear(chain.timers)
					if not alive(chain.gui) then
						endChain(chain, false, false)
						return
					end
					-- Later cycles run without the start delay.
					local again = table.clone(recipe)
					again.delay = 0
					runCycle(chain, UILogic.schedule(again))
				end)
			)
		end
		return
	end
	if plan.total <= 0 then
		endChain(chain, true, false)
	else
		table.insert(
			chain.timers,
			Host.clock:after(plan.total, function()
				endChain(chain, true, false)
			end)
		)
	end
end

local function chainHandle(chain: Chain): Handle
	local function stop(restore: boolean?)
		local back = restore
		if back == nil then
			back = if chain.options.restore ~= nil then chain.options.restore else chain.recipe.loop == true
		end
		endChain(chain, false, back == true)
	end
	return {
		stop = stop,
		cancel = stop,
		finish = function()
			if chain.done then
				return
			end
			if chain.recipe.loop then
				stop(true)
				return
			end
			clearRun(chain)
			if alive(chain.gui) then
				snap(chain.gui, UILogic.endPose(chain.recipe), chain.rest, chain.priority)
			end
			endChain(chain, true, false)
		end,
		isDone = function(): boolean
			return chain.done
		end,
		id = chain.id,
	}
end

-- Plays preset `presetId` on `gui`. Options: duration (total seconds) or speed, intensity, delay,
-- easing, spring, mirror, priority, restore, color, onDone(completed), onMarker(name).
function UI.animate(gui: GuiObject, presetId: string, options: Options?): Handle
	local opts: Options = options or {}
	local recipe: UILogic.Recipe = UI.registry:get(presetId).data
	if (gui :: any) == nil or not alive(gui) then
		call(opts.onDone, false)
		return doneHandle()
	end
	local settings = Host.settings()
	local jump = false
	if settings.reducedMotion then
		local substitute = UILogic.reduced(recipe)
		if substitute == false then
			call(opts.onDone, false)
			return doneHandle()
		elseif type(substitute) == "string" then
			recipe = UI.registry:get(substitute).data
		else
			jump = true
		end
	end
	local scaled = UILogic.scale(recipe, {
		duration = opts.duration,
		speed = opts.speed,
		intensity = (opts.intensity or 1) * Host.juice("scale"),
		easing = opts.easing,
		spring = opts.spring,
		delay = opts.delay,
		mirror = opts.mirror,
	})
	local priority = opts.priority or 0
	local layers: { UILogic.Layer } = scaled.layers or {}
	local channels = UILogic.channels(scaled)
	local running: { Chain } = table.clone(chains[gui] or {})
	for _, other in running do
		if UILogic.sharesChannel(channels, other.channels) then
			if other.priority > priority then
				call(opts.onDone, false)
				return doneHandle()
			end
			endChain(other, false, false)
		end
	end
	local rest = restOf(gui)
	local chain: Chain = {
		gui = gui,
		id = presetId,
		recipe = scaled,
		channels = channels,
		priority = priority,
		rest = rest,
		options = opts,
		timers = {},
		tracks = {},
		layers = {},
		done = false,
	}
	local list = chains[gui]
	if list == nil then
		list = {}
		chains[gui] = list
	end
	table.insert(list, chain)
	local handle = chainHandle(chain)

	if scaled.travel and (opts.position or opts.size) then
		local goals: { [string]: any } = {}
		if opts.position then
			rest.position = packUDim2(opts.position)
			goals.Position = opts.position
		end
		if opts.size then
			rest.size = packUDim2(opts.size)
			goals.Size = opts.size
		end
		if jump then
			Motion.tween(gui, goals, { duration = 0, essential = true, priority = priority })
		else
			table.insert(chain.tracks, Motion.spring(gui, goals, scaled.travel.spring, { priority = priority }))
		end
	end

	if jump then
		-- Reduced motion: no travel. Show the end pose, keep state layers (selection glow).
		for _, step in scaled.steps do
			if step.marker then
				call(opts.onMarker, step.marker)
			end
		end
		snap(gui, UILogic.endPose(scaled), rest, priority)
		for _, layer in layers do
			if layer.kind == "glow" and (layer.mode == "on" or layer.mode == "off") then
				runLayer(gui, layer, opts)
			end
		end
		endChain(chain, true, false)
		return handle
	end

	-- The start pose applies now, even when the first step is delayed, so staggered entrances
	-- wait in their hidden pose instead of flashing at rest.
	snap(gui, UILogic.startPose(scaled), rest, priority)
	local offset = scaled.delay or 0
	for _, layer in layers do
		local wait = offset + (if type(layer.delay) == "number" then layer.delay else 0)
		if wait <= 0 then
			table.insert(chain.layers, runLayer(gui, layer, opts))
		else
			table.insert(
				chain.timers,
				Host.clock:after(wait, function()
					if not chain.done and alive(gui) then
						table.insert(chain.layers, runLayer(gui, layer, opts))
					end
				end)
			)
		end
	end
	runCycle(chain, UILogic.schedule(scaled))
	return handle
end

-- Stops every preset on `gui`. With restore = true the object returns to its rest state and
-- overlays (glow, shine) are removed.
function UI.stop(gui: GuiObject, restore: boolean?)
	local touched: { [string]: boolean } = {}
	local running: { Chain } = table.clone(chains[gui] or {})
	for _, chain in running do
		for channel in chain.channels do
			touched[channel] = true
		end
		endChain(chain, false, false)
	end
	if restore then
		-- Only what this module moved goes back: an object a layout has since repositioned keeps
		-- its new place.
		local moved = displaced[gui]
		if moved then
			for channel in moved do
				touched[channel] = true
			end
		end
		Motion.stop(gui, false)
		removeGlow(gui)
		local rest = rests[gui]
		if rest and alive(gui) then
			snap(gui, restPoseFor(touched), rest)
		end
		displaced[gui] = nil
	end
end

-- True while a preset chain is running on `gui`.
function UI.isAnimating(gui: GuiObject): boolean
	local list = chains[gui]
	return list ~= nil and #list > 0
end

-- Show / hide ------------------------------------------------------------------------------------

local tokens: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any

local function nextToken(gui: GuiObject): number
	local token = (tokens[gui] or 0) + 1
	tokens[gui] = token
	return token
end

-- Makes `gui` visible and plays an entrance (default "PopIn").
function UI.show(gui: GuiObject, presetId: string?, options: Options?): Handle
	nextToken(gui)
	gui.Visible = true
	return UI.animate(gui, presetId or "PopIn", options)
end

-- Plays an exit (default "PopOut"), then hides `gui` and puts it back at rest so a plain
-- Visible = true shows it correctly. A show() that starts meanwhile wins: the stale hide never
-- hides it.
function UI.hide(gui: GuiObject, presetId: string?, options: Options?): Handle
	local opts: Options = if options then table.clone(options) else {}
	local token = nextToken(gui)
	local onDone = opts.onDone
	opts.onDone = function(completed: boolean)
		if tokens[gui] == token and alive(gui) then
			gui.Visible = false
			UI.stop(gui, true)
		end
		call(onDone, completed)
	end
	return UI.animate(gui, presetId or "PopOut", opts)
end

-- Stagger ----------------------------------------------------------------------------------------

export type StaggerOptions = Options & {
	interval: number?, -- seconds between items, default 0.05
	order: string?, -- "forward" | "reverse" | "center" | "edges" | "random"
	seed: number?,
	show: boolean?, -- set Visible = true on each item first
}

-- Plays one preset on many objects with a delay between them. Items wait in the preset's start
-- pose. onDone fires once, when the last item has finished.
function UI.stagger(guis: { GuiObject }, presetId: string, options: StaggerOptions?): Handle
	local opts: StaggerOptions = options or ({} :: any)
	local interval = if Host.settings().reducedMotion then 0 else opts.interval or 0.05
	local delays = UILogic.staggerDelays(#guis, interval, opts.order, opts.seed)
	local handles: { Handle } = {}
	local pending = #guis
	local allCompleted = true
	local finished = false
	local function itemDone(completed: boolean)
		pending -= 1
		allCompleted = allCompleted and completed
		if pending <= 0 and not finished then
			finished = true
			call(opts.onDone, allCompleted)
		end
	end
	if pending == 0 then
		finished = true
		call(opts.onDone, true)
	end
	for index, gui in guis do
		local each: Options = table.clone(opts) :: any
		each.delay = (opts.delay or 0) + delays[index]
		each.onDone = itemDone
		if opts.show then
			gui.Visible = true
		end
		table.insert(handles, UI.animate(gui, presetId, each))
	end
	local function stop(restore: boolean?)
		for _, handle in handles do
			handle.stop(restore)
		end
	end
	return {
		stop = stop,
		cancel = stop,
		finish = function()
			for _, handle in handles do
				handle.finish()
			end
		end,
		isDone = function(): boolean
			return finished
		end,
	}
end

-- Button binding ---------------------------------------------------------------------------------

export type BindOptions = {
	target: GuiObject?, -- object that animates (default: the button)
	enabled: (() -> boolean)?, -- extra gate checked on hover and press
	selected: boolean?,
	disabled: boolean?,
	color: any?, -- glow / ripple / shine colour
	onActivated: (() -> ())?,
	onState: ((status: string) -> ())?, -- "idle" | "hover" | "focused" | "pressed" | "selected" | "disabled"
}

export type Binding = {
	setSelected: (value: boolean) -> (),
	setDisabled: (value: boolean) -> (),
	status: () -> string,
	destroy: () -> (),
	Destroy: () -> (),
}

-- Wires hover, press, release, gamepad selection and touch on `button` to a style: "BouncyPress"
-- (default), "Soft", "Snappy", "Premium", "Arcade" or "Minimal". Returns a binding with
-- setSelected, setDisabled, status and destroy; calling the binding like a function also cleans up.
function UI.bind(button: GuiObject, style: string?, options: BindOptions?): Binding
	local opts: BindOptions = options or {}
	local look = if style and UILogic.hasButtonStyle(style) then style else "BouncyPress"
	if style and look ~= style then
		warn("[UVK.UI] unknown button style " .. tostring(style) .. "; using BouncyPress")
	end
	local target = opts.target or button
	local trove = Trove.new()
	local state = UILogic.buttonState()
	local pressAt: Vector2? = nil
	local destroyed = false

	local function show(action: string?)
		if action == nil then
			return
		end
		local spec = UILogic.buttonAction(look, action)
		if spec then
			UI.animate(target, spec.preset, {
				intensity = spec.intensity,
				spring = spec.spring,
				speed = spec.speed,
				color = opts.color,
			})
			if spec.effect == "shine" then
				UI.shine(target)
			elseif spec.effect == "ripple" then
				UI.ripple(target, { at = pressAt, color = opts.color })
			end
		end
		call(opts.onState, UILogic.buttonStatus(state))
	end

	local function fire(event: string)
		if destroyed then
			return
		end
		local action: string?
		state, action = UILogic.buttonEvent(state, event)
		show(action)
	end

	local function allowed(): boolean
		return opts.enabled == nil or opts.enabled()
	end

	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA
	end

	trove:Connect(button.MouseEnter, function()
		if allowed() then
			fire("enter")
		end
	end)
	trove:Connect(button.MouseLeave, function()
		fire("leave")
	end)
	trove:Connect(button.SelectionGained, function()
		if allowed() then
			fire("focus")
		end
	end)
	trove:Connect(button.SelectionLost, function()
		fire("blur")
	end)
	if button:IsA("GuiButton") then
		trove:Connect(button.MouseButton1Down, function(x: number, y: number)
			if allowed() then
				-- MouseButton1Down reports viewport coordinates; AbsolutePosition excludes the inset.
				local inset = GuiService:GetGuiInset()
				pressAt = Vector2.new(x - inset.X, y - inset.Y)
				fire("press")
			end
		end)
		trove:Connect(button.MouseButton1Up, function()
			fire("release")
		end)
		trove:Connect(button.Activated, function()
			if not state.disabled and allowed() then
				call(opts.onActivated)
			end
		end)
	end
	trove:Connect(button.InputBegan, function(input: InputObject)
		if isPress(input) and allowed() then
			pressAt = if input.UserInputType == Enum.UserInputType.Touch
				then Vector2.new(input.Position.X, input.Position.Y)
				else nil
			fire("press")
		end
	end)
	trove:Connect(button.InputEnded, function(input: InputObject)
		if isPress(input) then
			if input.UserInputType == Enum.UserInputType.Touch then
				-- A finger does not hover: release to rest, not to the hover pose.
				state.hovered = false
			end
			fire("release")
		end
	end)

	local function setSelected(value: boolean)
		fire(if value then "select" else "deselect")
	end
	local function setDisabled(value: boolean)
		fire(if value then "disable" else "enable")
		if not value and state.selected then
			show("selectedRest")
		end
	end
	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		trove:Clean()
		UI.stop(target, true)
	end
	if opts.selected then
		setSelected(true)
	end
	if opts.disabled then
		setDisabled(true)
	end
	local binding = {
		setSelected = setSelected,
		setDisabled = setDisabled,
		status = function(): string
			return UILogic.buttonStatus(state)
		end,
		destroy = destroy,
		Destroy = destroy,
	}
	return setmetatable(binding, { __call = destroy }) :: any
end

-- Counter and typewriter -------------------------------------------------------------------------

export type CountOptions = {
	from: number?, -- default: the value this label last counted to, else 0
	duration: number?, -- default: 0.4-1.2 s, growing with the size of the change
	easing: string?, -- default "cubicOut"
	format: string?, -- Core/Format spec, default "number"
	prefix: string?,
	suffix: string?,
	pop: boolean?, -- scale pop when the roll ends (default true)
	onStep: ((value: number) -> ())?,
	onDone: ((completed: boolean) -> ())?,
}

type Counter = { value: number, stop: (() -> ())? }
local counters: { [Instance]: Counter } = setmetatable({}, { __mode = "k" }) :: any

-- Rolls the number in `label` to `to`. A second call while rolling continues from the value shown.
function UI.countTo(label: TextLabel | TextButton, to: number, options: CountOptions?): Handle
	local opts: CountOptions = options or {}
	local text: any = label
	local counter = counters[label]
	if counter == nil then
		counter = { value = opts.from or 0, stop = nil }
		counters[label] = counter
	end
	local state: Counter = counter
	if state.stop then
		state.stop()
	end
	local from = opts.from or state.value
	local function write(value: number)
		state.value = value
		text.Text = UILogic.countText(value, opts)
		call(opts.onStep, value)
	end
	local duration = opts.duration or UILogic.countDuration(to - from)
	if Host.settings().reducedMotion or duration <= 0 or from == to or not alive(label) then
		write(to)
		call(opts.onDone, true)
		return doneHandle()
	end
	local elapsed = 0
	local done = false
	local remove: (() -> ())? = nil
	local function finish(completed: boolean, jump: boolean)
		if done then
			return
		end
		done = true
		if remove then
			remove()
			remove = nil
		end
		state.stop = nil
		if jump then
			write(to)
		end
		if completed and opts.pop ~= false and alive(label) then
			UI.animate(label, "TextBounce", { intensity = 0.7 })
		end
		call(opts.onDone, completed)
	end
	write(from)
	remove = Host.clock:add(function(dt: number): boolean?
		if done then
			return false
		end
		if not alive(label) then
			remove = nil
			finish(false, false)
			return false
		end
		elapsed += dt
		local t = math.clamp(elapsed / duration, 0, 1)
		write(UILogic.count(from, to, t, opts.easing))
		if t >= 1 then
			remove = nil
			finish(true, false)
			return false
		end
		return true
	end)
	state.stop = function()
		finish(false, false)
	end
	return {
		stop = function()
			finish(false, false)
		end,
		cancel = function()
			finish(false, false)
		end,
		finish = function()
			finish(true, true)
		end,
		isDone = function(): boolean
			return done
		end,
	}
end

export type TypeOptions = {
	speed: number?, -- characters per second, default 40
	onChar: ((index: number) -> ())?,
	onDone: ((completed: boolean) -> ())?,
}

local typing: { [Instance]: () -> () } = setmetatable({}, { __mode = "k" }) :: any

-- Reveals `text` in `label` one character at a time with MaxVisibleGraphemes (so the layout does
-- not move while typing); objects without that property get their Text cut instead. Stopping
-- shows the whole text.
function UI.typewriter(label: TextLabel | TextButton | TextBox, text: string, options: TypeOptions?): Handle
	local opts: TypeOptions = options or {}
	local target: any = label
	local previous = typing[label]
	if previous then
		previous()
	end
	local graphemes = pcall(function(): number
		return target.MaxVisibleGraphemes
	end)
	local count = UILogic.typeCount(text)
	local function reveal(index: number)
		if graphemes then
			target.MaxVisibleGraphemes = if index >= count then -1 else index
		else
			target.Text = UILogic.typePrefix(text, index)
		end
	end
	if graphemes then
		target.Text = text
	end
	if Host.settings().reducedMotion or count == 0 or not alive(label) then
		reveal(count)
		call(opts.onDone, true)
		return doneHandle()
	end
	local elapsed = 0
	local shown = 0
	local done = false
	local remove: (() -> ())? = nil
	local function finish(completed: boolean)
		if done then
			return
		end
		done = true
		if remove then
			remove()
			remove = nil
		end
		if typing[label] ~= nil then
			typing[label] = nil
		end
		reveal(count)
		call(opts.onDone, completed)
	end
	reveal(0)
	remove = Host.clock:add(function(dt: number): boolean?
		if done then
			return false
		end
		if not alive(label) then
			remove = nil
			finish(false)
			return false
		end
		elapsed += dt
		local index = UILogic.typeIndex(elapsed, opts.speed, count)
		if index ~= shown then
			for step = shown + 1, index do
				call(opts.onChar, step)
			end
			shown = index
			reveal(index)
		end
		if index >= count then
			remove = nil
			finish(true)
			return false
		end
		return true
	end)
	local function stop()
		finish(false)
	end
	typing[label] = stop
	return {
		stop = stop,
		cancel = stop,
		finish = function()
			finish(true)
		end,
		isDone = function(): boolean
			return done
		end,
	}
end

-- Overlay ----------------------------------------------------------------------------------------
-- Popups, flying items and screen flashes share one ScreenGui under the local player's PlayerGui,
-- created on first use. It ignores the GUI inset, so viewport points map to it directly.

local overlay: ScreenGui? = nil

type PopupParts = { label: TextLabel, scale: UIScale, stroke: UIStroke }
type FlyerParts = { object: GuiObject, scale: UIScale }

type Popup = {
	parts: PopupParts,
	label: TextLabel,
	scale: UIScale,
	stroke: UIStroke,
	at: any,
	style: UILogic.PopupStyle,
	age: number,
	duration: number,
	seed: number,
	offset: Vector2,
	calm: boolean,
	onDone: ((completed: boolean) -> ())?,
	done: boolean,
}

type Flyer = {
	parts: FlyerParts,
	object: GuiObject,
	scale: UIScale,
	image: boolean,
	item: UILogic.FlyItem,
	index: number,
	age: number,
	from: Vector2,
	group: FlyGroup,
}

type FlyGroup = {
	to: GuiObject,
	left: number,
	done: boolean,
	onArrive: ((index: number) -> ())?,
	onDone: ((completed: boolean) -> ())?,
	punch: boolean,
}

local popups: { Popup } = {}
local flyers: { Flyer } = {}
local removeJob: (() -> ())? = nil
local popupSeed = 0

local function makePopupLabel(): PopupParts
	local label = Instance.new("TextLabel")
	label.Name = "Popup"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.fromOffset(260, 60)
	label.FontFace = Font.fromEnum(Enum.Font.GothamBlack)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	return { label = label, scale = scale, stroke = stroke }
end

local function makeFlyer(image: boolean): FlyerParts
	local object: GuiObject
	if image then
		local picture = Instance.new("ImageLabel")
		picture.BackgroundTransparency = 1
		picture.ScaleType = Enum.ScaleType.Fit
		object = picture
	else
		local dot = Instance.new("Frame")
		dot.BorderSizePixel = 0
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = dot
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromHex("#1B1530")
		stroke.Parent = dot
		object = dot
	end
	object.Name = "Flyer"
	object.AnchorPoint = Vector2.new(0.5, 0.5)
	object.Visible = false
	local scale = Instance.new("UIScale")
	scale.Parent = object
	return { object = object, scale = scale }
end

local function destroyItem(item: any)
	local instance: Instance? = item.label or item.object
	if instance then
		instance:Destroy()
	end
end

local function hideItem(item: any)
	local instance: any = item.label or item.object
	if instance then
		instance.Visible = false
	end
end

local popupPool = Pool.new({ create = makePopupLabel, reset = hideItem, destroy = destroyItem, max = 32 })
local dotPool = Pool.new({
	create = function()
		return makeFlyer(false)
	end,
	reset = hideItem,
	destroy = destroyItem,
	max = 32,
})
local imagePool = Pool.new({
	create = function()
		return makeFlyer(true)
	end,
	reset = hideItem,
	destroy = destroyItem,
	max = 32,
})

local function overlayGui(): ScreenGui?
	if overlay and overlay.Parent then
		return overlay
	end
	local player = Players.LocalPlayer
	local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	if playerGui == nil then
		return nil
	end
	if overlay then
		-- The old overlay was destroyed with everything pooled inside it.
		popupPool:clear()
		dotPool:clear()
		imagePool:clear()
		table.clear(popups)
		table.clear(flyers)
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "UvkOverlay"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	overlay = gui
	return gui
end

-- Where `at` is on screen, in viewport pixels, and whether it is in front of the camera.
-- at: Vector3 | Vector2 (viewport pixels) | GuiObject | BasePart | Attachment | Model.
local function screenPoint(at: any): (Vector2?, boolean)
	local kind = typeof(at)
	if kind == "Vector2" then
		return at, true
	end
	local world: Vector3? = nil
	if kind == "Vector3" then
		world = at
	elseif kind == "CFrame" then
		world = at.Position
	elseif kind == "Instance" then
		if at:IsA("GuiObject") then
			if at.Parent == nil then
				return nil, false
			end
			local inset = GuiService:GetGuiInset()
			return at.AbsolutePosition + at.AbsoluteSize / 2 + inset, true
		elseif at:IsA("BasePart") then
			world = at.Position
		elseif at:IsA("Attachment") then
			world = at.WorldPosition
		elseif at:IsA("PVInstance") then
			world = at:GetPivot().Position
		end
	end
	local camera = Workspace.CurrentCamera
	if world == nil or camera == nil then
		return nil, false
	end
	local point = camera:WorldToViewportPoint(world)
	return Vector2.new(point.X, point.Y), point.Z > 0
end

local function releasePopup(popup: Popup, completed: boolean)
	if popup.done then
		return
	end
	popup.done = true
	local index = table.find(popups, popup)
	if index then
		table.remove(popups, index)
	end
	if popup.label.Parent ~= nil then
		popupPool:release(popup.parts)
	end
	call(popup.onDone, completed)
end

local function drawPopup(popup: Popup): boolean
	local point, visible = screenPoint(popup.at)
	if point == nil then
		return false
	end
	local sample = UILogic.popupSample(popup.style, popup.age / popup.duration, popup.seed)
	local label = popup.label
	if popup.calm then
		sample.x, sample.rotation, sample.scale = 0, 0, 1
	end
	label.Position = UDim2.fromOffset(point.X + popup.offset.X + sample.x, point.Y + popup.offset.Y + sample.y)
	label.Rotation = sample.rotation
	label.TextTransparency = sample.transparency
	popup.stroke.Transparency = sample.transparency
	popup.scale.Scale = sample.scale
	label.Visible = visible
	return true
end

local function settle(to: GuiObject)
	if not alive(to) then
		return
	end
	local rest = restOf(to)
	local k = Host.juice("scale")
	Motion.spring(to, { Scale = rest.scale }, "Bouncy", { from = { Scale = rest.scale * (1 + 0.14 * k) } })
end

local function releaseFlyer(flyer: Flyer, arrived: boolean)
	local index = table.find(flyers, flyer)
	if index then
		table.remove(flyers, index)
	end
	if flyer.object.Parent ~= nil then
		if flyer.image then
			imagePool:release(flyer.parts)
		else
			dotPool:release(flyer.parts)
		end
	end
	local group = flyer.group
	group.left -= 1
	if arrived and not group.done then
		if group.punch then
			settle(group.to)
		end
		call(group.onArrive, flyer.index)
	end
	if group.left <= 0 and not group.done then
		group.done = true
		call(group.onDone, arrived)
	end
end

local function tick(dt: number): boolean?
	for _, popup in table.clone(popups) do
		popup.age += dt
		if popup.age >= popup.duration then
			releasePopup(popup, true)
		elseif not drawPopup(popup) then
			releasePopup(popup, false)
		end
	end
	for _, flyer in table.clone(flyers) do
		flyer.age += dt
		local item = flyer.item
		local u = (flyer.age - item.delay) / item.duration
		if u < 0 then
			continue
		end
		local target = screenPoint(flyer.group.to)
		if target == nil or flyer.group.done then
			releaseFlyer(flyer, false)
		elseif u >= 1 then
			releaseFlyer(flyer, true)
		else
			local sample = UILogic.flySample(item, flyer.from.X, flyer.from.Y, target.X, target.Y, u)
			flyer.object.Position = UDim2.fromOffset(sample.x, sample.y)
			flyer.scale.Scale = sample.scale
			flyer.object.Visible = true
		end
	end
	if #popups == 0 and #flyers == 0 then
		removeJob = nil
		return false
	end
	return true
end

local function ensureJob()
	if removeJob == nil then
		removeJob = Host.clock:add(tick)
	end
end

export type PopupOptions = {
	style: string?, -- "damage" (default) | "currency" | "crit" | "heal"
	color: any?,
	size: number?, -- text size, default from the style
	duration: number?,
	format: string?, -- Core/Format spec for numbers, default "abbrev"
	font: Font?,
	offset: Vector2?, -- pixels added to the anchor
	onDone: ((completed: boolean) -> ())?,
}

-- Floating text that pops, rises and fades at `at`: a world position (re-projected every frame),
-- viewport pixels, a GuiObject, a part, an attachment or a model. Numbers are formatted and get
-- the style's prefix / suffix. Returns nil when there is no local PlayerGui. At most
-- profile.maxPopups are alive; the oldest is recycled.
function UI.popup(text: string | number, at: any, options: PopupOptions?): Handle?
	local opts: PopupOptions = options or {}
	local gui = overlayGui()
	if gui == nil then
		return nil
	end
	local style = UILogic.popupStyle(opts.style)
	local limit = math.max(1, Host.profile().maxPopups)
	while #popups >= limit do
		releasePopup(popups[1], false)
	end
	local parts = popupPool:acquire()
	local label = parts.label
	local shown: string
	if type(text) == "number" then
		shown =
			UILogic.countText(text, { format = opts.format or "abbrev", prefix = style.prefix, suffix = style.suffix })
	else
		shown = text
	end
	label.Text = shown
	label.TextSize = opts.size or style.size
	label.TextColor3 = color3(opts.color, Color3.fromHex(style.color))
	label.FontFace = opts.font or Font.fromEnum(Enum.Font.GothamBlack)
	parts.stroke.Color = Color3.fromHex("#1B1530")
	label.ZIndex = if opts.style == "crit" then 3 else 2
	label.Parent = gui
	popupSeed += 1
	local popup: Popup = {
		parts = parts,
		label = label,
		scale = parts.scale,
		stroke = parts.stroke,
		at = at,
		style = style,
		age = 0,
		duration = math.max(0.1, opts.duration or style.duration),
		seed = popupSeed,
		offset = opts.offset or Vector2.zero,
		calm = Host.settings().reducedMotion,
		onDone = opts.onDone,
		done = false,
	}
	table.insert(popups, popup)
	if not drawPopup(popup) then
		releasePopup(popup, false)
		return doneHandle()
	end
	ensureJob()
	local function stop()
		releasePopup(popup, false)
	end
	return {
		stop = stop,
		cancel = stop,
		finish = stop,
		isDone = function(): boolean
			return popup.done
		end,
	}
end

export type FlyOptions = {
	count: number?, -- items at High quality (default 8); scaled by the quality profile
	image: string?, -- asset id or content string; without it items are coloured dots
	color: any?, -- dot colour, default gold
	size: number?, -- pixels, default 28
	spread: number?, -- burst radius in pixels, default 70
	duration: number?, -- seconds per item, default 0.6
	stagger: number?, -- seconds between items, default 0.045
	seed: number?,
	punch: boolean?, -- pop the target on each arrival (default true)
	onArrive: ((index: number) -> ())?,
	onDone: ((completed: boolean) -> ())?,
}

-- Items burst out of `from` and home onto `toGui` (a counter). onArrive(index) fires per item and
-- onDone at the end; the target pops on each arrival. The number of items follows the quality
-- profile, so grant rewards from onDone (or before calling), never by counting arrivals. Under
-- reduced motion nothing flies: the target pops once and the callbacks fire at once.
function UI.flyTo(from: any, toGui: GuiObject, options: FlyOptions?): Handle
	local opts: FlyOptions = options or {}
	local gui = overlayGui()
	local origin = screenPoint(from)
	local settings = Host.settings()
	local count = Quality.scaleCount(opts.count or 8, Host.profile(), nil, math.max(settings.intensity, 0.1))
	local group: FlyGroup = {
		to = toGui,
		left = count,
		done = false,
		onArrive = opts.onArrive,
		onDone = opts.onDone,
		punch = opts.punch ~= false,
	}
	if gui == nil or origin == nil or settings.reducedMotion or not alive(toGui) then
		group.done = true
		if group.punch and alive(toGui) then
			settle(toGui)
		end
		for index = 1, count do
			call(opts.onArrive, index)
		end
		call(opts.onDone, true)
		local handle = doneHandle()
		handle.count = count
		return handle
	end
	local useImage = opts.image ~= nil and opts.image ~= ""
	local size = opts.size or 28
	popupSeed += 1
	local plan = UILogic.flyPlan(count, opts.seed or popupSeed, {
		spread = opts.spread,
		stagger = opts.stagger,
		duration = opts.duration,
	})
	local mine: { Flyer } = {}
	for index, item in plan do
		local parts = if useImage then imagePool:acquire() else dotPool:acquire()
		local object: any = parts.object
		object.Size = UDim2.fromOffset(size, size)
		if useImage then
			local image = opts.image :: string
			object.Image = if string.find(image, "^%d+$") then "rbxassetid://" .. image else image
		else
			object.BackgroundColor3 = color3(opts.color, Color3.fromHex("#FFD84A"))
		end
		object.Position = UDim2.fromOffset(origin.X, origin.Y)
		parts.scale.Scale = 0.3
		object.Parent = gui
		local flyer: Flyer = {
			parts = parts,
			object = object,
			scale = parts.scale,
			image = useImage,
			item = item,
			index = index,
			age = 0,
			from = origin,
			group = group,
		}
		table.insert(flyers, flyer)
		table.insert(mine, flyer)
	end
	ensureJob()
	local function stop()
		if group.done then
			return
		end
		group.done = true
		for _, flyer in mine do
			if table.find(flyers, flyer) then
				releaseFlyer(flyer, false)
			end
		end
		call(opts.onDone, false)
	end
	return {
		stop = stop,
		cancel = stop,
		finish = stop,
		isDone = function(): boolean
			return group.done
		end,
		count = count,
	}
end

export type FlashOptions = {
	duration: number?, -- default 0.25
	alpha: number?, -- peak opacity 0..1, default 0.6
	onDone: ((completed: boolean) -> ())?,
}

-- Full-screen colour flash that fades out. Under reduced flashing it becomes a faint, slower
-- fade (at most 15 % opacity). Returns nil when there is no local PlayerGui.
function UI.flash(color: any?, options: FlashOptions?): Handle?
	local opts: FlashOptions = options or {}
	local gui = overlayGui()
	if gui == nil then
		return nil
	end
	local alpha = math.clamp(opts.alpha or 0.6, 0, 1)
	local duration = opts.duration or 0.25
	if Host.settings().reducedFlashing then
		alpha = math.min(alpha * 0.3, 0.15)
		duration *= 2
	end
	local frame = Instance.new("Frame")
	frame.Name = "Flash"
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color3(color, Color3.new(1, 1, 1))
	frame.BackgroundTransparency = 1 - alpha
	frame.ZIndex = 10
	frame.Active = false
	frame.Parent = gui
	local done = false
	local function finish(completed: boolean)
		if done then
			return
		end
		done = true
		Motion.stop(frame, false)
		frame:Destroy()
		call(opts.onDone, completed)
	end
	Motion.tween(frame, { BackgroundTransparency = 1 }, {
		duration = duration,
		easing = "quadOut",
		essential = true,
		onDone = finish,
	})
	local function stop()
		finish(false)
	end
	return {
		stop = stop,
		cancel = stop,
		finish = stop,
		isDone = function(): boolean
			return done
		end,
	}
end

export type BackdropOptions = {
	color: any?, -- default black
	transparency: number?, -- resting transparency, default 0.45
	zIndex: number?,
	modal: boolean?, -- TextButton.Modal: frees the mouse in first person (default false)
	onActivated: (() -> ())?, -- click or tap on the backdrop (close the modal)
}

-- A dim layer filling `parent` (a ScreenGui or any GuiObject) that fades in with "BackdropIn" and
-- swallows clicks. handle.Instance is the backdrop; handle.stop() fades it out and destroys it.
function UI.backdrop(parent: Instance, options: BackdropOptions?): Handle
	local opts: BackdropOptions = options or {}
	local button = Instance.new("TextButton")
	button.Name = "UvkBackdrop"
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Selectable = false
	button.Modal = opts.modal == true
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = color3(opts.color, Color3.new(0, 0, 0))
	button.BackgroundTransparency = opts.transparency or 0.45
	button.ZIndex = opts.zIndex or 1
	button.Parent = parent
	local connection = button.Activated:Connect(function()
		call(opts.onActivated)
	end)
	local done = false
	UI.animate(button, "BackdropIn")
	local function remove()
		connection:Disconnect()
		UI.stop(button, false)
		button:Destroy()
	end
	local function stop()
		if done then
			return
		end
		done = true
		UI.animate(button, "BackdropOut", { onDone = remove })
	end
	return {
		stop = stop,
		cancel = stop,
		finish = function()
			if not done then
				done = true
			end
			remove()
		end,
		isDone = function(): boolean
			return done
		end,
		Instance = button,
	}
end

-- Live counts for the debug overlay: running chains, popups and flying items.
function UI.stats(): { chains: number, popups: number, flyers: number }
	local running = 0
	for _, list in chains do
		running += #list
	end
	return { chains = running, popups = #popups, flyers = #flyers }
end

return UI
