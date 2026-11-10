--!strict
-- Motion engine (pure Luau). Animates numeric properties of any target through an adapter, so the
-- same engine drives GUI objects, parts, models and the camera in Roblox and plain tables in specs.
--
-- Rules the engine guarantees:
--   * One owner per (target, property). A new animation takes a property over when its priority is
--     equal or higher, starting from the current value (and current velocity for springs), so
--     interrupted motion never jumps. A lower-priority animation is refused that property.
--   * The first value the engine sees for a property is remembered. cancel(true), stop(target, true)
--     and restore(target) put it back, so effects can always be undone.
--   * Targets that stop being alive (destroyed instances) are dropped on the next step.
--   * Reduced motion: one-shot animations jump to their goal, loops do not start. Mark an animation
--     `essential` when it carries state (a progress bar fill) and must still be seen.
--   * The engine only runs a clock job while at least one track is active.

local Clock = require("./Clock")
local Curves = require("./Curves")
local Springs = require("./Springs")

export type Value = { number }

export type Adapter = {
	-- Current value as numbers, or nil when the target has no such property.
	read: (target: any, property: string) -> Value?,
	write: (target: any, property: string, value: Value) -> (),
	alive: (target: any) -> boolean,
}

export type Spec = {
	props: { [string]: Value }, -- goals
	from: { [string]: Value }?, -- start values (default: current)
	duration: number?, -- seconds, tween mode (default 0.3)
	easing: (string | Curves.Curve)?, -- tween curve (default "quadOut")
	spring: (string | Springs.Spring)?, -- spring mode when set; duration and easing are ignored
	delay: number?,
	priority: number?, -- default 0
	repeatCount: number?, -- extra plays; -1 loops forever (tween mode)
	reverses: boolean?, -- play back to the start after each forward pass (tween mode)
	restore: boolean?, -- put the original values back when cancelled or stopped
	essential: boolean?, -- still animates under reduced motion
	epsilon: number?, -- spring settle threshold (default 0.001)
	onDone: ((completed: boolean) -> ())?,
	onStep: ((alpha: number) -> ())?, -- eased progress each frame (tween mode)
}

export type Handle = {
	cancel: (restore: boolean?) -> (),
	finish: () -> (), -- jump to the end state and complete
	pause: () -> (),
	resume: () -> (),
	isDone: () -> boolean,
	completed: boolean?, -- nil while running; true finished, false cancelled or refused
	skipped: { string }, -- properties the engine could not or would not animate
}

type PropState = { from: Value, to: Value, value: Value, velocity: Value }

type Track = {
	target: any,
	priority: number,
	props: { [string]: PropState },
	propCount: number,
	spring: Springs.Spring?,
	curve: Curves.Curve,
	duration: number,
	delay: number,
	elapsed: number,
	plays: number, -- forward passes left after the current one (-1 = forever)
	reverses: boolean,
	backwards: boolean,
	restore: boolean,
	epsilon: number,
	paused: boolean,
	done: boolean,
	handle: Handle,
	onDone: ((completed: boolean) -> ())?,
	onStep: ((alpha: number) -> ())?,
}

export type Engine = {
	animate: (self: Engine, target: any, spec: Spec) -> Handle,
	stop: (self: Engine, target: any, restore: boolean?) -> (),
	restore: (self: Engine, target: any, properties: { string }?) -> (),
	forget: (self: Engine, target: any) -> (),
	isAnimating: (self: Engine, target: any, property: string?) -> boolean,
	count: (self: Engine) -> number,
	cancelAll: (self: Engine, restore: boolean?) -> (),
	reducedMotion: boolean,
	timeScale: number,
}

local Engine = {}

local function noop() end

local function finishedHandle(completed: boolean, skipped: { string }): Handle
	return {
		cancel = noop,
		finish = noop,
		pause = noop,
		resume = noop,
		isDone = function(): boolean
			return true
		end,
		completed = completed,
		skipped = skipped,
	}
end

function Engine.new(adapter: Adapter, clock: Clock.Clock): Engine
	local tracks: { Track } = {}
	local owners: { [any]: { [string]: Track } } = setmetatable({}, { __mode = "k" }) :: any
	local originals: { [any]: { [string]: Value } } = setmetatable({}, { __mode = "k" }) :: any
	local removeJob: (() -> ())? = nil
	local self: Engine

	local function call(callback: ((completed: boolean) -> ())?, completed: boolean)
		if callback then
			local ok, err = pcall(callback, completed)
			if not ok then
				clock.onError("[UVK] onDone failed: " .. tostring(err))
			end
		end
	end

	local function release(track: Track, property: string)
		if track.props[property] ~= nil then
			track.props[property] = nil
			track.propCount -= 1
		end
		local owned = owners[track.target]
		if owned and owned[property] == track then
			owned[property] = nil
		end
	end

	local function writeOriginals(target: any, properties: { [string]: any })
		local saved = originals[target]
		if saved == nil or not adapter.alive(target) then
			return
		end
		for property in properties do
			local value = saved[property]
			if value then
				adapter.write(target, property, value)
			end
		end
	end

	local function finish(track: Track, completed: boolean, restore: boolean)
		if track.done then
			return
		end
		track.done = true
		track.handle.completed = completed
		if restore then
			writeOriginals(track.target, track.props)
		end
		for property in table.clone(track.props) do
			release(track, property)
		end
		call(track.onDone, completed)
	end

	local function writeTrack(track: Track)
		for property, state in track.props do
			adapter.write(track.target, property, state.value)
		end
	end

	local function stepTween(track: Track, dt: number)
		track.elapsed += dt
		local t = if track.duration > 0 then track.elapsed / track.duration else 1
		while t >= 1 do
			-- A pass ended. Reverse, repeat or complete.
			if track.reverses and not track.backwards then
				track.backwards = true
			elseif track.plays ~= 0 then
				track.backwards = false
				if track.plays > 0 then
					track.plays -= 1
				end
			else
				local last = if track.reverses then 0 else 1
				for _, state in track.props do
					for i = 1, #state.to do
						state.value[i] = state.from[i] + (state.to[i] - state.from[i]) * last
					end
				end
				writeTrack(track)
				if track.onStep then
					track.onStep(last)
				end
				finish(track, true, false)
				return
			end
			track.elapsed -= track.duration
			t = if track.duration > 0 then track.elapsed / track.duration else 1
			if track.duration <= 0 then
				break
			end
		end
		local alpha = track.curve(math.clamp(if track.backwards then 1 - t else t, 0, 1))
		for _, state in track.props do
			for i = 1, #state.to do
				state.value[i] = state.from[i] + (state.to[i] - state.from[i]) * alpha
			end
		end
		writeTrack(track)
		if track.onStep then
			track.onStep(alpha)
		end
	end

	local function stepSpring(track: Track, dt: number)
		local spring = track.spring :: Springs.Spring
		local settled = true
		for _, state in track.props do
			for i = 1, #state.to do
				local position, velocity = Springs.step(state.value[i], state.velocity[i], state.to[i], dt, spring)
				state.value[i] = position
				state.velocity[i] = velocity
				if not Springs.settled(position, velocity, state.to[i], track.epsilon) then
					settled = false
				end
			end
		end
		if settled then
			for _, state in track.props do
				for i = 1, #state.to do
					state.value[i] = state.to[i]
				end
			end
		end
		writeTrack(track)
		if settled then
			finish(track, true, false)
		end
	end

	local function step(dt: number): boolean?
		local scaled = dt * self.timeScale
		for _, track in table.clone(tracks) do
			if track.done then
				continue
			end
			if not adapter.alive(track.target) then
				finish(track, false, false)
				originals[track.target] = nil
				continue
			end
			if track.paused then
				continue
			end
			local delta = scaled
			if track.delay > 0 then
				track.delay -= delta
				if track.delay > 0 then
					continue
				end
				delta = -track.delay
				track.delay = 0
			end
			if track.spring then
				stepSpring(track, delta)
			else
				stepTween(track, delta)
			end
		end
		local kept: { Track } = {}
		for _, track in tracks do
			if not track.done then
				table.insert(kept, track)
			end
		end
		tracks = kept
		if #tracks == 0 then
			removeJob = nil
			return false
		end
		return true
	end

	local function animate(_self: Engine, target: any, spec: Spec): Handle
		local skipped: { string } = {}
		if target == nil or not adapter.alive(target) then
			call(spec.onDone, false)
			return finishedHandle(false, skipped)
		end
		local priority = spec.priority or 0
		local springMode = spec.spring ~= nil
		local loops = spec.repeatCount == -1
		local owned = owners[target]
		if owned == nil then
			owned = {}
			owners[target] = owned
		end
		local saved = originals[target]
		if saved == nil then
			saved = {}
			originals[target] = saved
		end

		local props: { [string]: PropState } = {}
		local count = 0
		for property, goal in spec.props do
			local current = adapter.read(target, property)
			if current == nil or #current ~= #goal then
				table.insert(skipped, property)
				continue
			end
			local owner = owned[property]
			if owner and owner.priority > priority then
				table.insert(skipped, property)
				continue
			end
			local velocity = table.create(#goal, 0)
			if owner then
				local previous = owner.props[property]
				if previous and springMode and owner.spring then
					velocity = table.clone(previous.velocity)
				end
				release(owner, property)
				if owner.propCount == 0 then
					finish(owner, false, false)
				end
			end
			if saved[property] == nil then
				saved[property] = table.clone(current)
			end
			local from = if spec.from and spec.from[property] then table.clone(spec.from[property]) else current
			props[property] = { from = from, to = table.clone(goal), value = table.clone(from), velocity = velocity }
			count += 1
		end
		table.sort(skipped)
		if count == 0 then
			call(spec.onDone, false)
			return finishedHandle(false, skipped)
		end

		local reduced = self.reducedMotion and not spec.essential
		if reduced and loops then
			call(spec.onDone, false)
			return finishedHandle(false, skipped)
		end
		local duration = math.max(0, spec.duration or 0.3)
		local delay = math.max(0, spec.delay or 0)
		if reduced or (not springMode and duration <= 0 and delay <= 0) then
			local last = if spec.reverses then "from" else "to"
			for property, state in props do
				adapter.write(target, property, if last == "from" then state.from else state.to)
			end
			if spec.onStep then
				spec.onStep(if spec.reverses then 0 else 1)
			end
			call(spec.onDone, true)
			return finishedHandle(true, skipped)
		end

		local easing = spec.easing
		local curve: Curves.Curve = if type(easing) == "function" then easing else Curves.get(easing or "quadOut")
		local track: Track
		local handle: Handle = {
			cancel = function(restore: boolean?)
				finish(track, false, if restore == nil then track.restore else restore)
			end,
			finish = function()
				if track.done then
					return
				end
				local atStart = track.reverses and track.spring == nil
				if adapter.alive(track.target) then
					for property, state in track.props do
						adapter.write(track.target, property, if atStart then state.from else state.to)
					end
				end
				finish(track, true, false)
			end,
			pause = function()
				track.paused = true
			end,
			resume = function()
				track.paused = false
			end,
			isDone = function(): boolean
				return track.done
			end,
			completed = nil,
			skipped = skipped,
		}
		track = {
			target = target,
			priority = priority,
			props = props,
			propCount = count,
			spring = if springMode then Springs.get(spec.spring) else nil,
			curve = curve,
			duration = duration,
			delay = delay,
			elapsed = 0,
			plays = spec.repeatCount or 0,
			reverses = spec.reverses == true,
			backwards = false,
			restore = spec.restore == true,
			epsilon = spec.epsilon or 1e-3,
			paused = false,
			done = false,
			handle = handle,
			onDone = spec.onDone,
			onStep = spec.onStep,
		}
		for property in props do
			owned[property] = track
		end
		-- Show the first frame now so nothing flashes at its resting value.
		if spec.from and delay <= 0 then
			writeTrack(track)
		end
		table.insert(tracks, track)
		if removeJob == nil then
			removeJob = clock:add(function(dt: number): boolean?
				return step(dt)
			end)
		end
		return handle
	end

	local function stop(_self: Engine, target: any, restore: boolean?)
		for _, track in table.clone(tracks) do
			if track.target == target and not track.done then
				finish(track, false, if restore == nil then track.restore else restore)
			end
		end
	end

	local function restore(_self: Engine, target: any, properties: { string }?)
		local saved = originals[target]
		if saved == nil then
			return
		end
		local wanted: { [string]: boolean } = {}
		if properties then
			for _, property in properties do
				wanted[property] = true
			end
		else
			for property in saved do
				wanted[property] = true
			end
		end
		for _, track in table.clone(tracks) do
			if track.target == target and not track.done then
				for property in table.clone(track.props) do
					if wanted[property] then
						release(track, property)
					end
				end
				if track.propCount == 0 then
					finish(track, false, false)
				end
			end
		end
		writeOriginals(target, wanted)
		for property in wanted do
			saved[property] = nil
		end
	end

	self = {
		animate = animate,
		stop = stop,
		restore = restore,
		forget = function(_self: Engine, target: any)
			originals[target] = nil
		end,
		isAnimating = function(_self: Engine, target: any, property: string?): boolean
			local owned = owners[target]
			if owned == nil then
				return false
			end
			if property then
				return owned[property] ~= nil
			end
			return next(owned) ~= nil
		end,
		count = function(_self: Engine): number
			local live = 0
			for _, track in tracks do
				if not track.done then
					live += 1
				end
			end
			return live
		end,
		cancelAll = function(_self: Engine, restoreAll: boolean?)
			for _, track in table.clone(tracks) do
				finish(track, false, if restoreAll == nil then track.restore else restoreAll)
			end
		end,
		reducedMotion = false,
		timeScale = 1,
	}
	return self
end

return Engine
