--!strict
local Clock = require("../src/Visuals/Core/Clock")
local Sequence = require("../src/Visuals/Core/Sequence")
local t = require("./lib/t")

type Log = { string }

local function setup()
	local clock = Clock.new()
	local log: Log = {}
	local live: { [string]: boolean } = {}
	local runner: Sequence.Runner = {
		clock = clock,
		play = function(name: string): any
			table.insert(log, "play:" .. name)
			live[name] = true
			return {
				cancel = function()
					live[name] = nil
					table.insert(log, "cancel:" .. name)
				end,
				finish = function()
					live[name] = nil
					table.insert(log, "finish:" .. name)
				end,
			}
		end,
		sound = function(cue: string): any
			table.insert(log, "sound:" .. cue)
			return nil
		end,
		animate = function(target: any, spec: any): any
			table.insert(log, "animate:" .. tostring(spec.id))
			return {
				finish = function()
					target.value = spec.goal
				end,
				cancel = function() end,
			}
		end,
	}
	return clock, runner, log, live
end

local function run(clock: Clock.Clock, seconds: number)
	for _ = 1, math.floor(seconds * 60 + 0.5) do
		clock:step(1 / 60)
	end
end

return {
	["steps fire in order at their times and the sequence completes"] = function()
		local clock, runner, log = setup()
		local done: { any } = {}
		local sequence = Sequence.new(runner)
			:Play("A")
			:Wait(0.2)
			:Play("B")
			:Sound("ding")
			:Wait(0.1)
			:Marker("end")
			:OnMarker(function(name: string)
				table.insert(log, "marker:" .. name)
			end)
			:OnDone(function(completed: boolean, skipped: boolean)
				done = { completed, skipped }
			end)
		t.near(sequence:Duration(), 0.3)
		sequence:Start()
		t.deepEqual(log, { "play:A" }, "time-zero steps fire on Start")
		run(clock, 0.21)
		t.deepEqual(log, { "play:A", "play:B", "sound:ding" })
		run(clock, 0.15)
		t.deepEqual(log, { "play:A", "play:B", "sound:ding", "marker:end" })
		t.deepEqual(done, { true, false })
		t.equal(sequence:State(), "done")
		t.equal(clock:count(), 0)
	end,
	["parallel branches share a start and the cursor moves to the longest"] = function()
		local clock, runner, log = setup()
		local sequence = Sequence.new(runner)
			:Wait(0.1)
			:Parallel(function(a)
				a:Play("P1"):Wait(0.5):Play("P1b")
			end, function(b)
				b:Wait(0.2):Play("P2")
			end)
			:Play("After")
		t.near(sequence:Duration(), 0.6)
		sequence:Start()
		run(clock, 0.11)
		t.deepEqual(log, { "play:P1" })
		run(clock, 0.2)
		t.deepEqual(log, { "play:P1", "play:P2" })
		run(clock, 0.31)
		t.deepEqual(log, { "play:P1", "play:P2", "play:P1b", "play:After" })
	end,
	["stagger offsets each branch by the interval"] = function()
		local clock, runner, log = setup()
		local sequence = Sequence.new(runner):Stagger(3, 0.1, function(branch, index)
			branch:Play("S" .. index)
		end)
		t.near(sequence:Duration(), 0.2)
		sequence:Start()
		t.deepEqual(log, { "play:S1" })
		run(clock, 0.11)
		t.deepEqual(log, { "play:S1", "play:S2" })
		run(clock, 0.1)
		t.equal(#log, 3)
	end,
	["skip drops cosmetic steps, still runs calls, markers and animations, and cleans up"] = function()
		local clock, runner, log, live = setup()
		local target = { value = 0 }
		local cleaned = 0
		local done: { any } = {}
		local sequence = Sequence.new(runner)
			:Play("Glow")
			:Wait(0.5)
			:Play("NeverShown")
			:Animate(target, { id = "bar", goal = 100, duration = 0.4 })
			:Call(function(ctx: Sequence.Context): any
				table.insert(log, "call:" .. tostring(ctx.skipped))
				return nil
			end)
			:Marker("result")
			:OnMarker(function(name: string, ctx: Sequence.Context)
				table.insert(log, "marker:" .. name .. ":" .. tostring(ctx.skipped))
			end)
			:Cleanup(function()
				cleaned += 1
			end)
			:OnDone(function(completed: boolean, skipped: boolean)
				done = { completed, skipped }
			end)
			:Start()
		run(clock, 0.1)
		sequence:Skip()
		t.deepEqual(log, { "play:Glow", "animate:bar", "call:true", "marker:result:true", "finish:Glow" })
		t.equal(target.value, 100, "skipped animation lands on its end state")
		t.equal(live.Glow, nil, "running effect was finished")
		t.equal(cleaned, 1)
		t.deepEqual(done, { true, true })
		sequence:Skip()
		sequence:Cancel()
		t.equal(cleaned, 1, "cleanup runs once")
		run(clock, 1)
		t.equal(clock:count(), 0)
	end,
	["cancel stops everything now and cancels live handles"] = function()
		local clock, runner, log, live = setup()
		local cleaned = 0
		local done: { any } = {}
		local sequence = Sequence.new(runner)
			:Play("Aura")
			:Call(function(): any
				return function()
					table.insert(log, "cleanup-fn")
				end
			end)
			:Wait(1)
			:Play("Later")
			:Cleanup(function()
				cleaned += 1
			end)
			:OnDone(function(completed: boolean, skipped: boolean)
				done = { completed, skipped }
			end)
			:Start()
		run(clock, 0.2)
		sequence:Cancel()
		t.deepEqual(log, { "play:Aura", "cancel:Aura", "cleanup-fn" })
		t.equal(live.Aura, nil)
		t.equal(cleaned, 1)
		t.deepEqual(done, { false, false })
		run(clock, 2)
		t.equal(#log, 3, "nothing fires after cancel")
	end,
	["pause holds time; speed scales it; a finished sequence can replay"] = function()
		local clock, runner, log = setup()
		local sequence = Sequence.new(runner):Wait(0.2):Play("X"):Speed(2):Start()
		sequence:Pause()
		run(clock, 1)
		t.equal(#log, 0)
		sequence:Resume()
		run(clock, 0.11)
		t.deepEqual(log, { "play:X" })
		t.equal(sequence:State(), "done")
		sequence:Start()
		run(clock, 0.11)
		t.deepEqual(log, { "play:X", "play:X" })
	end,
	["a failing step does not stop the sequence or skip cleanup"] = function()
		local clock, runner, log = setup()
		local errors = 0
		clock.onError = function()
			errors += 1
		end
		local cleaned = false
		Sequence.new(runner)
			:Call(function(): any
				error("bad step")
			end)
			:Wait(0.1)
			:Play("StillRuns")
			:Cleanup(function()
				cleaned = true
			end)
			:Start()
		run(clock, 0.2)
		t.equal(errors, 1)
		t.deepEqual(log, { "play:StillRuns" })
		t.truthy(cleaned)
	end,
	["a step may cancel its own sequence"] = function()
		local clock, runner, log = setup()
		local sequence: Sequence.Sequence
		sequence = Sequence.new(runner)
			:Call(function(): any
				sequence:Cancel()
				return nil
			end)
			:Play("Never")
		sequence:Start()
		run(clock, 0.1)
		t.equal(#log, 0)
		t.equal(sequence:State(), "done")
		t.equal(clock:count(), 0)
	end,
}
