--!strict
-- Motion: the public animation API (Visuals.Motion). Goals are ordinary Roblox values; the engine
-- interpolates them, resolves conflicts by priority, and can always restore what it changed.
--
--   Motion.tween(frame, { Position = UDim2.fromScale(0.5, 0.5) }, { duration = 0.3, easing = "backOut" })
--   Motion.spring(button, { Scale = 1.08 }, "Bouncy")
--   Motion.stop(button, true)          -- cancel and restore original values
--   Motion.native(part, { Transparency = 1 }, { duration = 0.4 })   -- TweenService, off the Lua frame loop
--
-- See Runtime/Props for the virtual properties ("Scale", "Pivot", "PivotCFrame", "ModelScale",
-- "GroupFade").

local TweenService = game:GetService("TweenService")

local Curves = require("../Core/Curves")
local Engine = require("../Core/Engine")
local Host = require("./Host")
local Props = require("./Props")
local Sequence = require("../Core/Sequence")
local Springs = require("../Core/Springs")

export type Handle = Engine.Handle

export type Options = {
	duration: number?,
	easing: (string | Curves.Curve)?,
	spring: (string | Springs.Spring)?,
	delay: number?,
	priority: number?,
	repeatCount: number?,
	reverses: boolean?,
	restore: boolean?,
	essential: boolean?,
	from: { [string]: any }?,
	onDone: ((completed: boolean) -> ())?,
	onStep: ((alpha: number) -> ())?,
}

local Motion = {}

Motion.Springs = Springs
Motion.Curves = Curves

local function spec(goals: { [string]: any }, options: Options?): Engine.Spec
	local opts: Options = options or {}
	return {
		props = Props.packAll(goals) or {},
		from = Props.packAll(opts.from),
		duration = opts.duration,
		easing = opts.easing,
		spring = opts.spring,
		delay = opts.delay,
		priority = opts.priority,
		repeatCount = opts.repeatCount,
		reverses = opts.reverses,
		restore = opts.restore,
		essential = opts.essential,
		onDone = opts.onDone,
		onStep = opts.onStep,
	}
end

-- Timed animation with an easing curve.
function Motion.tween(target: any, goals: { [string]: any }, options: Options?): Handle
	return Host.engine:animate(target, spec(goals, options))
end

-- Spring animation towards `goals`. `spring` is a preset name ("Bouncy") or { frequency, damping }.
function Motion.spring(
	target: any,
	goals: { [string]: any },
	spring: (string | Springs.Spring)?,
	options: Options?
): Handle
	local built = spec(goals, options)
	built.spring = spring or (options and options.spring) or "Soft"
	return Host.engine:animate(target, built)
end

-- One call for both: a spec with `props` (goals) and any Options field; `spring` picks spring mode.
function Motion.animate(target: any, options: Options & { props: { [string]: any } }): Handle
	return Host.engine:animate(target, spec(options.props, options))
end

-- Jumps from the current value by `amount` and springs back: the basic "punch" for feedback.
function Motion.punch(target: any, property: string, amount: any, spring: (string | Springs.Spring)?): Handle
	local current = Props.adapter.read(target, property)
	local delta = Props.pack(amount)
	if current == nil or delta == nil or #current ~= #delta then
		return Host.engine:animate(nil, { props = {} })
	end
	local k = Host.juice("scale")
	local from = table.clone(current)
	for i = 1, #from do
		from[i] += delta[i] * k
	end
	return Host.engine:animate(target, {
		props = { [property] = current },
		from = { [property] = from },
		spring = spring or "Bouncy",
	})
end

function Motion.stop(target: any, restore: boolean?)
	Host.engine:stop(target, restore)
end

-- Cancels animations on `target` and writes back the values it had before the kit touched it.
function Motion.restore(target: any, properties: { string }?)
	Host.engine:restore(target, properties)
end

function Motion.isAnimating(target: any, property: string?): boolean
	return Host.engine:isAnimating(target, property)
end

-- Number of running tracks (0 means the engine is idle).
function Motion.count(): number
	return Host.engine:count()
end

-- TweenService tween for simple one-shot property changes. It runs inside the engine, so it costs
-- no Luau time per frame, but it does not take part in priorities or restoration. Starting another
-- native tween on the same instance cancels the previous one.
local native: { [Instance]: Tween } = setmetatable({}, { __mode = "k" }) :: any

export type NativeOptions =
	{ duration: number?, easing: string?, delay: number?, onDone: ((completed: boolean) -> ())? }

local STYLES: { [string]: { any } } = {
	linear = { Enum.EasingStyle.Linear, Enum.EasingDirection.Out },
	quadIn = { Enum.EasingStyle.Quad, Enum.EasingDirection.In },
	quadOut = { Enum.EasingStyle.Quad, Enum.EasingDirection.Out },
	quadInOut = { Enum.EasingStyle.Quad, Enum.EasingDirection.InOut },
	cubicIn = { Enum.EasingStyle.Cubic, Enum.EasingDirection.In },
	cubicOut = { Enum.EasingStyle.Cubic, Enum.EasingDirection.Out },
	cubicInOut = { Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut },
	quartOut = { Enum.EasingStyle.Quart, Enum.EasingDirection.Out },
	quintOut = { Enum.EasingStyle.Quint, Enum.EasingDirection.Out },
	sineInOut = { Enum.EasingStyle.Sine, Enum.EasingDirection.InOut },
	expoOut = { Enum.EasingStyle.Exponential, Enum.EasingDirection.Out },
	backIn = { Enum.EasingStyle.Back, Enum.EasingDirection.In },
	backOut = { Enum.EasingStyle.Back, Enum.EasingDirection.Out },
	elasticOut = { Enum.EasingStyle.Elastic, Enum.EasingDirection.Out },
	bounceOut = { Enum.EasingStyle.Bounce, Enum.EasingDirection.Out },
}

function Motion.native(instance: Instance, goals: { [string]: any }, options: NativeOptions?): Tween?
	local opts: NativeOptions = options or {}
	local previous = native[instance]
	if previous then
		previous:Cancel()
		native[instance] = nil
	end
	local duration = if Host.engine.reducedMotion then 0 else math.max(0, opts.duration or 0.3)
	if duration <= 0 then
		local target: any = instance
		for property, value in goals do
			target[property] = value
		end
		if opts.onDone then
			opts.onDone(true)
		end
		return nil
	end
	local style = STYLES[opts.easing or "quadOut"] or STYLES.quadOut
	local info = TweenInfo.new(duration, style[1], style[2], 0, false, opts.delay or 0)
	local tween = TweenService:Create(instance, info, goals)
	native[instance] = tween
	tween.Completed:Once(function(state: Enum.PlaybackState)
		if native[instance] == tween then
			native[instance] = nil
		end
		if opts.onDone then
			opts.onDone(state == Enum.PlaybackState.Completed)
		end
	end)
	tween:Play()
	return tween
end

-- A new sequence bound to the shared clock. `runner` supplies play / sound (Visuals fills these).
function Motion.sequence(runner: { play: any?, sound: any? }?): Sequence.Sequence
	return Sequence.new({
		clock = Host.clock,
		play = runner and runner.play,
		sound = runner and runner.sound,
		animate = function(target: any, options: any): any
			return Motion.animate(target, options)
		end,
	})
end

-- Runs `each(item, index)` for every item, `interval` seconds apart. Returns a cancel function.
function Motion.stagger<T>(items: { T }, interval: number, each: (item: T, index: number) -> ()): () -> ()
	local cancels: { () -> () } = {}
	local step = if Host.engine.reducedMotion then 0 else math.max(0, interval)
	for index, item in items do
		if index == 1 or step == 0 then
			each(item, index)
		else
			table.insert(
				cancels,
				Host.clock:after((index - 1) * step, function()
					each(item, index)
				end)
			)
		end
	end
	return function()
		for _, cancel in cancels do
			cancel()
		end
	end
end

-- Calls `callback` after `seconds` on the shared clock. Returns a cancel function.
function Motion.delay(seconds: number, callback: () -> ()): () -> ()
	return Host.clock:after(seconds, callback)
end

return Motion
