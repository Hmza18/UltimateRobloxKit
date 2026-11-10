--!strict
-- Sequences: timelines that coordinate effects, motion, camera moves, sound cues and callbacks
-- (pure Luau). A sequence is built with chained calls, then started on a clock:
--
--   Sequence.new(runner)
--       :Play("SparkleBurst", position)
--       :Wait(0.2)
--       :Parallel(function(a) a:Play("RewardGlow", position) end, function(b) b:Sound("reward") end)
--       :Marker("revealed")
--       :Start()
--
-- Every step gets an absolute time when it is added, so a sequence can be skipped, cancelled,
-- paused and replayed exactly:
--   Skip()    fast-forward. Cosmetic steps (Play, Sound) that have not fired are dropped; Call,
--             Animate and Marker steps still fire, with ctx.skipped = true, so state always ends
--             correct. Running handles are finished.
--   Cancel()  stop now. Nothing else fires; running handles are cancelled.
-- In all three endings (finished, skipped, cancelled) every Cleanup function runs exactly once.

local Clock = require("./Clock")

-- What a step may return: nothing, a cleanup function, or a handle with cancel and/or finish.
export type StepHandle = { cancel: ((...any) -> ())?, finish: (() -> ())?, [any]: any }

export type Context = { skipped: boolean, sequence: any }

export type Runner = {
	clock: Clock.Clock,
	play: ((name: string, ...any) -> any)?, -- Visuals:Play
	sound: ((cue: string, options: any?) -> any)?, -- Visuals.Audio.play
	animate: ((target: any, spec: any) -> any)?, -- Visuals.Motion.animate
}

type Event = {
	at: number,
	order: number,
	kind: "play" | "sound" | "call" | "animate" | "marker",
	run: (ctx: Context) -> any,
	name: string?,
	fired: boolean,
}

type Shared = {
	runner: Runner,
	events: { Event },
	order: number,
	duration: number,
	cleanups: { () -> () },
	doneCallbacks: { (completed: boolean, skipped: boolean) -> () },
	markerCallbacks: { (name: string, ctx: Context) -> () },
	handles: { any },
	state: "idle" | "running" | "paused" | "done",
	time: number,
	removeJob: (() -> ())?,
	speed: number,
}

export type Sequence = {
	Play: (self: Sequence, name: string, ...any) -> Sequence,
	Sound: (self: Sequence, cue: string, options: any?) -> Sequence,
	Wait: (self: Sequence, seconds: number) -> Sequence,
	At: (self: Sequence, seconds: number) -> Sequence,
	Call: (self: Sequence, callback: (ctx: Context) -> any) -> Sequence,
	Animate: (self: Sequence, target: any, spec: any) -> Sequence,
	Marker: (self: Sequence, name: string) -> Sequence,
	Parallel: (self: Sequence, ...(branch: Sequence) -> ()) -> Sequence,
	Stagger: (
		self: Sequence,
		count: number,
		interval: number,
		build: (branch: Sequence, index: number) -> ()
	) -> Sequence,
	Cleanup: (self: Sequence, callback: () -> ()) -> Sequence,
	OnDone: (self: Sequence, callback: (completed: boolean, skipped: boolean) -> ()) -> Sequence,
	OnMarker: (self: Sequence, callback: (name: string, ctx: Context) -> ()) -> Sequence,
	Speed: (self: Sequence, multiplier: number) -> Sequence,
	Start: (self: Sequence) -> Sequence,
	Skip: (self: Sequence) -> (),
	Cancel: (self: Sequence) -> (),
	Pause: (self: Sequence) -> (),
	Resume: (self: Sequence) -> (),
	Duration: (self: Sequence) -> number,
	Elapsed: (self: Sequence) -> number,
	State: (self: Sequence) -> string,
	IsRunning: (self: Sequence) -> boolean,
}

local Sequence = {}

local function safely(shared: Shared, callback: (...any) -> ...any, ...: any): any
	local ok, result = pcall(callback, ...)
	if not ok then
		shared.runner.clock.onError("[UVK] sequence step failed: " .. tostring(result))
		return nil
	end
	return result
end

local function endHandle(shared: Shared, handle: any, how: "finish" | "cancel")
	if type(handle) == "function" then
		safely(shared, handle)
	elseif type(handle) == "table" then
		local method = if how == "finish" then handle.finish or handle.cancel else handle.cancel
		if type(method) == "function" then
			safely(shared, method)
		elseif type(handle.Destroy) == "function" then
			safely(shared, handle.Destroy, handle)
		end
	end
end

local function fire(shared: Shared, event: Event, ctx: Context)
	event.fired = true
	local handle = safely(shared, event.run, ctx)
	if handle ~= nil then
		table.insert(shared.handles, handle)
	end
	if event.kind == "marker" then
		for _, callback in shared.markerCallbacks do
			safely(shared, callback, event.name, ctx)
		end
	end
end

local function finish(shared: Shared, completed: boolean, skipped: boolean)
	if shared.state == "done" or shared.state == "idle" then
		return
	end
	shared.state = "done"
	if shared.removeJob then
		shared.removeJob()
		shared.removeJob = nil
	end
	if not completed or skipped then
		for _, handle in shared.handles do
			endHandle(shared, handle, if skipped then "finish" else "cancel")
		end
	end
	shared.handles = {}
	for _, cleanup in shared.cleanups do
		safely(shared, cleanup)
	end
	for _, callback in shared.doneCallbacks do
		safely(shared, callback, completed, skipped)
	end
end

local function stateOf(shared: Shared): string
	return shared.state
end

local function build(shared: Shared, start: number): (Sequence, () -> number)
	local cursor = start
	local self: Sequence

	local function add(kind: any, run: (ctx: Context) -> any, name: string?)
		assert(shared.state == "idle" or shared.state == "done", "cannot add steps to a running sequence")
		shared.order += 1
		table.insert(
			shared.events,
			{ at = cursor, order = shared.order, kind = kind, run = run, name = name, fired = false }
		)
		shared.duration = math.max(shared.duration, cursor)
	end

	local function advance(seconds: number)
		cursor += math.max(0, seconds)
		shared.duration = math.max(shared.duration, cursor)
	end

	self = {
		Play = function(_self: Sequence, name: string, ...: any): Sequence
			local args = table.pack(...)
			add("play", function(): any
				local play = shared.runner.play
				return if play then play(name, table.unpack(args, 1, args.n)) else nil
			end, name)
			return self
		end,
		Sound = function(_self: Sequence, cue: string, options: any?): Sequence
			add("sound", function(): any
				local sound = shared.runner.sound
				return if sound then sound(cue, options) else nil
			end, cue)
			return self
		end,
		Wait = function(_self: Sequence, seconds: number): Sequence
			advance(seconds)
			return self
		end,
		At = function(_self: Sequence, seconds: number): Sequence
			cursor = start + math.max(0, seconds)
			shared.duration = math.max(shared.duration, cursor)
			return self
		end,
		Call = function(_self: Sequence, callback: (ctx: Context) -> any): Sequence
			add("call", callback)
			return self
		end,
		-- Runs a motion spec through runner.animate and, unless spec.wait == false, moves the
		-- cursor past it (delay + duration). When skipped, the animation is created and finished
		-- at once so the target lands on its end state.
		Animate = function(_self: Sequence, target: any, spec: any): Sequence
			add("animate", function(ctx: Context): any
				local animate = shared.runner.animate
				if animate == nil then
					return nil
				end
				local handle: any = animate(target, spec)
				if ctx.skipped and type(handle) == "table" then
					local finishNow = handle.finish :: (() -> ())?
					if finishNow then
						finishNow()
						return nil
					end
				end
				return handle
			end)
			if spec.wait ~= false then
				advance((spec.delay or 0) + (spec.duration or 0))
			end
			return self
		end,
		Marker = function(_self: Sequence, name: string): Sequence
			add("marker", function(): any
				return nil
			end, name)
			return self
		end,
		Parallel = function(_self: Sequence, ...: (branch: Sequence) -> ()): Sequence
			local latest = cursor
			local builders: { (branch: Sequence) -> () } = { ... }
			for _, builder in builders do
				local branch, branchEnd = build(shared, cursor)
				local call: any = builder
				call(branch)
				latest = math.max(latest, branchEnd())
			end
			cursor = latest
			shared.duration = math.max(shared.duration, cursor)
			return self
		end,
		Stagger = function(
			_self: Sequence,
			count: number,
			interval: number,
			builder: (branch: Sequence, index: number) -> ()
		): Sequence
			local latest = cursor
			for index = 1, count do
				local branch, branchEnd = build(shared, cursor + (index - 1) * math.max(0, interval))
				builder(branch, index)
				latest = math.max(latest, branchEnd())
			end
			cursor = latest
			shared.duration = math.max(shared.duration, cursor)
			return self
		end,
		Cleanup = function(_self: Sequence, callback: () -> ()): Sequence
			table.insert(shared.cleanups, callback)
			return self
		end,
		OnDone = function(_self: Sequence, callback: (completed: boolean, skipped: boolean) -> ()): Sequence
			table.insert(shared.doneCallbacks, callback)
			return self
		end,
		OnMarker = function(_self: Sequence, callback: (name: string, ctx: Context) -> ()): Sequence
			table.insert(shared.markerCallbacks, callback)
			return self
		end,
		Speed = function(_self: Sequence, multiplier: number): Sequence
			shared.speed = math.max(0.01, multiplier)
			return self
		end,
		Start = function(_self: Sequence): Sequence
			if shared.state == "running" or shared.state == "paused" then
				return self
			end
			table.sort(shared.events, function(a: Event, b: Event): boolean
				return if a.at == b.at then a.order < b.order else a.at < b.at
			end)
			for _, event in shared.events do
				event.fired = false
			end
			shared.time = 0
			shared.handles = {}
			shared.state = "running"
			local ctx: Context = { skipped = false, sequence = self }
			local function run(dt: number): boolean?
				if stateOf(shared) ~= "running" then
					return stateOf(shared) == "paused"
				end
				shared.time += dt * shared.speed
				for _, event in shared.events do
					if stateOf(shared) ~= "running" then
						return false
					end
					if not event.fired and event.at <= shared.time then
						fire(shared, event, ctx)
					end
				end
				if stateOf(shared) == "running" and shared.time >= shared.duration then
					shared.removeJob = nil
					finish(shared, true, false)
					return false
				end
				return stateOf(shared) == "running" or stateOf(shared) == "paused"
			end
			-- Steps at time 0 fire immediately, so feedback starts on the same frame as the input.
			shared.removeJob = shared.runner.clock:add(function(dt: number): boolean?
				return run(dt)
			end)
			run(0)
			return self
		end,
		Skip = function(_self: Sequence)
			if shared.state ~= "running" and shared.state ~= "paused" then
				return
			end
			shared.state = "running"
			local ctx: Context = { skipped = true, sequence = self }
			for _, event in shared.events do
				if not event.fired then
					if event.kind == "play" or event.kind == "sound" then
						event.fired = true
					else
						fire(shared, event, ctx)
					end
				end
			end
			shared.time = shared.duration
			finish(shared, true, true)
		end,
		Cancel = function(_self: Sequence)
			if shared.state == "running" or shared.state == "paused" then
				shared.state = "running"
				finish(shared, false, false)
			end
		end,
		Pause = function(_self: Sequence)
			if shared.state == "running" then
				shared.state = "paused"
			end
		end,
		Resume = function(_self: Sequence)
			if shared.state == "paused" then
				shared.state = "running"
			end
		end,
		Duration = function(_self: Sequence): number
			return shared.duration
		end,
		Elapsed = function(_self: Sequence): number
			return shared.time
		end,
		State = function(_self: Sequence): string
			return shared.state
		end,
		IsRunning = function(_self: Sequence): boolean
			return shared.state == "running" or shared.state == "paused"
		end,
	}
	return self, function(): number
		return cursor
	end
end

function Sequence.new(runner: Runner): Sequence
	local shared: Shared = {
		runner = runner,
		events = {},
		order = 0,
		duration = 0,
		cleanups = {},
		doneCallbacks = {},
		markerCallbacks = {},
		handles = {},
		state = "idle",
		time = 0,
		removeJob = nil,
		speed = 1,
	}
	local sequence = build(shared, 0)
	return sequence
end

return Sequence
