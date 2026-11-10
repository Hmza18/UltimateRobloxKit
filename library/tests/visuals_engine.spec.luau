--!strict
local Clock = require("../src/Visuals/Core/Clock")
local Curves = require("../src/Visuals/Core/Curves")
local Engine = require("../src/Visuals/Core/Engine")
local Springs = require("../src/Visuals/Core/Springs")
local t = require("./lib/t")

-- Fake targets are tables; a target with dead = true counts as destroyed.
local adapter: Engine.Adapter = {
	read = function(target: any, property: string): { number }?
		local value = target[property]
		if type(value) == "number" then
			return { value }
		elseif type(value) == "table" then
			return table.clone(value)
		end
		return nil
	end,
	write = function(target: any, property: string, value: { number })
		target.writes = (target.writes or 0) + 1
		target[property] = if type(target[property]) == "table" then table.clone(value) else value[1]
	end,
	alive = function(target: any): boolean
		return target.dead ~= true
	end,
}

local function setup()
	local clock = Clock.new()
	clock.onError = function(message: string)
		error(message)
	end
	return clock, Engine.new(adapter, clock)
end

local function run(clock: Clock.Clock, seconds: number, dt: number?)
	local step = dt or 1 / 60
	local n = math.floor(seconds / step + 0.5)
	for _ = 1, n do
		clock:step(step)
	end
end

return {
	["clock: jobs, timers and the active callback"] = function()
		local clock = Clock.new()
		local active: { boolean } = {}
		clock.onActive = function(value: boolean)
			table.insert(active, value)
		end
		local ticks = 0
		local remove = clock:add(function(): boolean?
			ticks += 1
			return ticks < 3
		end)
		local fired = false
		clock:after(0.05, function()
			fired = true
		end)
		clock:step(0.02)
		t.falsy(fired)
		clock:step(0.02)
		clock:step(0.02)
		t.truthy(fired)
		t.equal(ticks, 3)
		t.equal(clock:count(), 0)
		t.deepEqual(active, { true, false })
		remove() -- removing a finished job is harmless
		t.near(clock:now(), 0.06, 1e-9)
	end,
	["clock: a cancelled timer never fires and a failing job is removed"] = function()
		local clock = Clock.new()
		local errors = 0
		clock.onError = function()
			errors += 1
		end
		local fired = false
		local cancel = clock:after(0.1, function()
			fired = true
		end)
		cancel()
		clock:add(function(): boolean?
			error("boom")
		end)
		clock:step(0.2)
		t.falsy(fired)
		t.equal(errors, 1)
		t.equal(clock:count(), 0)
	end,
	["springs: every preset settles on the target at any frame rate"] = function()
		for _, name in Springs.NAMES do
			for _, dt in { 1 / 240, 1 / 60, 1 / 20 } do
				local spring = Springs.get(name)
				local x, v = 0, 0
				for _ = 1, math.ceil(12 / dt) do
					x, v = Springs.step(x, v, 1, dt, spring)
				end
				t.near(x, 1, 1e-3, name .. " position")
				t.near(v, 0, 1e-2, name .. " velocity")
			end
		end
	end,
	["springs: frame rate does not change the curve"] = function()
		local spring = Springs.get("Bouncy")
		local a, av = 0, 0
		for _ = 1, 30 do
			a, av = Springs.step(a, av, 1, 1 / 60, spring)
		end
		local b, bv = Springs.step(0, 0, 1, 0.5, spring)
		t.near(a, b, 1e-6)
		t.near(av, bv, 1e-5)
	end,
	["springs: underdamped presets overshoot, critically damped ones do not"] = function()
		local function peak(name: string): number
			local spring = Springs.get(name)
			local x, v, high = 0, 0, 0
			for _ = 1, 600 do
				x, v = Springs.step(x, v, 1, 1 / 120, spring)
				high = math.max(high, x)
			end
			return high
		end
		t.truthy(peak("Bouncy") > 1.1)
		t.truthy(peak("Elastic") > peak("Bouncy"))
		t.truthy(peak("Gentle") <= 1 + 1e-6)
		t.truthy(peak("Heavy") <= 1 + 1e-6)
		t.throws(function()
			Springs.get("Nope")
		end)
		t.truthy(Springs.settleTime("Snappy") < Springs.settleTime("Cinematic"))
	end,
	["curves: every curve starts at 0 and ends at 1"] = function()
		for _, name in Curves.names() do
			t.near(Curves.ease(name, 0), 0, 1e-6, name)
			t.near(Curves.ease(name, 1), 1, 1e-6, name)
		end
		t.truthy(Curves.has("quadOut") and Curves.has("anticipate"))
		t.truthy(Curves.ease("anticipate", 0.3) < 0, "anticipation pulls back first")
		local bezier = Curves.bezier(0.25, 0.1, 0.25, 1)
		t.near(bezier(0), 0)
		t.near(bezier(1), 1)
		t.truthy(bezier(0.5) > 0.7 and bezier(0.5) < 0.9)
		t.near(Curves.steps(4)(0.6), 0.5)
		t.near(Curves.yoyo("linear")(0.75), 0.5)
		Curves.register("half", function(x: number): number
			return x
		end)
		t.truthy(Curves.has("half"))
	end,
	["engine: a tween reaches its goal and reports completion"] = function()
		local clock, engine = setup()
		local target = { x = 0 }
		local done: boolean? = nil
		local handle = engine:animate(target, {
			props = { x = { 10 } },
			duration = 0.5,
			easing = "linear",
			onDone = function(completed: boolean)
				done = completed
			end,
		})
		run(clock, 0.25)
		t.near(target.x, 5, 0.2)
		t.falsy(handle.isDone())
		run(clock, 0.3)
		t.equal(target.x, 10)
		t.equal(done, true)
		t.equal(handle.completed, true)
		t.equal(engine:count(), 0)
		t.equal(clock:count(), 0, "engine goes idle")
	end,
	["engine: cancel stops in place; cancel(true) restores the original"] = function()
		local clock, engine = setup()
		local a = { x = 1 }
		local handle = engine:animate(a, { props = { x = { 9 } }, duration = 1, easing = "linear" })
		run(clock, 0.5)
		handle.cancel()
		local stopped = a.x
		t.truthy(stopped > 1 and stopped < 9)
		run(clock, 0.5)
		t.equal(a.x, stopped)
		t.equal(handle.completed, false)

		local b = { x = 1 }
		local second = engine:animate(b, { props = { x = { 9 } }, duration = 1 })
		run(clock, 0.5)
		second.cancel(true)
		t.equal(b.x, 1)
	end,
	["engine: restore puts back the first value seen, across several animations"] = function()
		local clock, engine = setup()
		local target = { x = 2, y = { 1, 1 } }
		engine:animate(target, { props = { x = { 5 } }, duration = 0.1 })
		run(clock, 0.2)
		engine:animate(target, { props = { x = { 8 }, y = { 4, 4 } }, duration = 0.1 })
		run(clock, 0.2)
		t.equal(target.x, 8)
		engine:restore(target)
		t.equal(target.x, 2)
		t.deepEqual(target.y, { 1, 1 })
		t.falsy(engine:isAnimating(target))
	end,
	["engine: equal priority takes a property over without a jump"] = function()
		local clock, engine = setup()
		local target = { x = 0, y = 0 }
		local firstDone: boolean? = nil
		engine:animate(target, {
			props = { x = { 10 }, y = { 10 } },
			duration = 1,
			easing = "linear",
			onDone = function(completed: boolean)
				firstDone = completed
			end,
		})
		run(clock, 0.5)
		local before = target.x
		engine:animate(target, { props = { x = { 0 } }, duration = 0.5, easing = "linear" })
		clock:step(1 / 60)
		t.truthy(math.abs(target.x - before) < 0.5, "no jump at takeover")
		t.equal(firstDone, nil, "first track still owns y")
		run(clock, 0.6)
		t.equal(target.x, 0)
		t.equal(target.y, 10)
		t.equal(firstDone, true)
	end,
	["engine: a lower priority animation is refused; losing every property ends a track"] = function()
		local clock, engine = setup()
		local target = { x = 0 }
		local lowDone: boolean? = nil
		engine:animate(target, { props = { x = { 10 } }, duration = 1, priority = 5 })
		local low = engine:animate(target, {
			props = { x = { -10 } },
			duration = 1,
			priority = 1,
			onDone = function(completed: boolean)
				lowDone = completed
			end,
		})
		t.equal(low.completed, false)
		t.equal(lowDone, false)
		t.deepEqual(low.skipped, { "x" })
		local firstDone: boolean? = nil
		local other = { x = 0 }
		engine:animate(other, {
			props = { x = { 1 } },
			duration = 1,
			onDone = function(completed: boolean)
				firstDone = completed
			end,
		})
		engine:animate(other, { props = { x = { 2 } }, duration = 1, priority = 3 })
		t.equal(firstDone, false, "the replaced track ends as cancelled")
		run(clock, 1.1)
		t.equal(target.x, 10)
		t.equal(other.x, 2)
	end,
	["engine: springs carry velocity into a retargeted spring"] = function()
		local clock, engine = setup()
		local target = { x = 0 }
		engine:animate(target, { props = { x = { 1 } }, spring = "Bouncy" })
		run(clock, 0.08)
		local moving = target.x
		engine:animate(target, { props = { x = { 0 } }, spring = "Bouncy" })
		clock:step(1 / 60)
		t.truthy(target.x > moving, "still travelling forward right after retarget")
		run(clock, 3)
		t.near(target.x, 0, 1e-6)
		t.equal(engine:count(), 0)
	end,
	["engine: destroyed targets are dropped"] = function()
		local clock, engine = setup()
		local target: any = { x = 0 }
		local done: boolean? = nil
		engine:animate(target, {
			props = { x = { 1 } },
			duration = 1,
			repeatCount = -1,
			onDone = function(completed: boolean)
				done = completed
			end,
		})
		run(clock, 0.2)
		target.dead = true
		local writes = target.writes
		run(clock, 0.2)
		t.equal(done, false)
		t.equal(target.writes, writes, "no writes to a dead target")
		t.equal(engine:count(), 0)
		t.equal(engine:animate(target, { props = { x = { 1 } } }).completed, false)
	end,
	["engine: loops, reverses, delay, pause and finish"] = function()
		local clock, engine = setup()
		local loop = { x = 0 }
		local handle = engine:animate(
			loop,
			{ props = { x = { 1 } }, duration = 0.2, easing = "linear", reverses = true, repeatCount = -1 }
		)
		run(clock, 0.1)
		t.near(loop.x, 0.5, 0.1)
		run(clock, 0.2)
		t.near(loop.x, 0.5, 0.1)
		run(clock, 5)
		t.falsy(handle.isDone())
		handle.finish()
		t.equal(loop.x, 0, "a reversing loop finishes at rest")
		t.equal(handle.completed, true)

		local delayed = { x = 0 }
		engine:animate(delayed, { props = { x = { 1 } }, duration = 0.1, delay = 0.3 })
		run(clock, 0.25)
		t.equal(delayed.x, 0)
		run(clock, 0.2)
		t.equal(delayed.x, 1)

		local paused = { x = 0 }
		local p = engine:animate(paused, { props = { x = { 1 } }, duration = 0.2, easing = "linear" })
		run(clock, 0.1)
		p.pause()
		local held = paused.x
		run(clock, 1)
		t.equal(paused.x, held)
		p.resume()
		run(clock, 0.2)
		t.equal(paused.x, 1)

		local twice = { x = 0 }
		local passes = 0
		engine:animate(twice, {
			props = { x = { 1 } },
			duration = 0.1,
			easing = "linear",
			repeatCount = 1,
			onStep = function(alpha: number)
				if alpha == 1 then
					passes += 1
				end
			end,
		})
		run(clock, 0.3)
		t.equal(twice.x, 1)
		t.equal(engine:count(), 0)
	end,
	["engine: reduced motion jumps one-shots, refuses loops, keeps essential motion"] = function()
		local clock, engine = setup()
		engine.reducedMotion = true
		local a = { x = 0 }
		local handle = engine:animate(a, { props = { x = { 7 } }, duration = 1 })
		t.equal(a.x, 7)
		t.equal(handle.completed, true)
		local loop = engine:animate(a, { props = { x = { 1 } }, duration = 1, repeatCount = -1 })
		t.equal(loop.completed, false)
		t.equal(a.x, 7)
		local bar = { x = 0 }
		engine:animate(bar, { props = { x = { 1 } }, duration = 0.5, easing = "linear", essential = true })
		run(clock, 0.25)
		t.truthy(bar.x > 0.3 and bar.x < 0.7)
	end,
	["engine: stop(target), cancelAll, unknown properties and from values"] = function()
		local clock, engine = setup()
		local target = { x = 0, y = 0 }
		local handle = engine:animate(
			target,
			{ props = { x = { 1 }, nope = { 1 } }, from = { x = { 5 } }, duration = 1, restore = true }
		)
		t.deepEqual(handle.skipped, { "nope" })
		t.equal(target.x, 5, "from is applied on the first frame")
		run(clock, 0.5)
		engine:stop(target)
		t.equal(target.x, 0, "restore = true puts the original back on stop")
		engine:animate(target, { props = { y = { 3 } }, duration = 1 })
		engine:animate({ x = 0 }, { props = { x = { 3 } }, duration = 1 })
		t.equal(engine:count(), 2)
		engine:cancelAll()
		t.equal(engine:count(), 0)
		engine.timeScale = 2
		local fast = { x = 0 }
		engine:animate(fast, { props = { x = { 1 } }, duration = 1, easing = "linear" })
		run(clock, 0.5)
		t.near(fast.x, 1, 0.05)
	end,
}
