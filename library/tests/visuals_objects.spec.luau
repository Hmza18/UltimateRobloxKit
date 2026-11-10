--!strict
local ObjectsLogic = require("../src/Visuals/Objects/ObjectsLogic")
local Registry = require("../src/Visuals/Core/Registry")
local t = require("./lib/t")

type Sample = ObjectsLogic.Sample

local function close(a: Sample, b: Sample, epsilon: number, label: string)
	for i = 1, 3 do
		t.near(a.position[i], b.position[i], epsilon, label .. " position")
		local turn = math.abs(a.rotation[i] - b.rotation[i]) % 360
		t.truthy(math.min(turn, 360 - turn) < epsilon * 100, label .. " rotation")
		t.near(a.scale[i], b.scale[i], epsilon, label .. " scale")
	end
	t.near(a.transparency, b.transparency, epsilon, label .. " transparency")
end

local function volume(s: Sample): number
	return s.scale[1] * s.scale[2] * s.scale[3]
end

return {
	["presets: the contract's eighteen ids exist, split into loops and one-shots"] = function()
		t.deepEqual(ObjectsLogic.LOOPS, { "Float", "Hover", "Bounce", "Spin", "Pulse", "Sway", "Orbit" })
		t.equal(#ObjectsLogic.ONE_SHOTS, 11)
		for _, id in ObjectsLogic.LOOPS do
			t.truthy(ObjectsLogic.isLoop(id), id)
			t.equal(ObjectsLogic.duration(id), math.huge)
		end
		for _, id in ObjectsLogic.ONE_SHOTS do
			t.falsy(ObjectsLogic.isLoop(id), id)
			t.truthy(ObjectsLogic.duration(id) > 0 and ObjectsLogic.duration(id) < 5, id)
		end
		t.falsy(ObjectsLogic.has("Nope"))
		t.throws(function()
			ObjectsLogic.sample("Nope", 0)
		end)
		t.throws(function()
			ObjectsLogic.period("ScaleIn")
		end)
	end,
	["loops: periodic, never done, and finite at every time"] = function()
		for _, id in ObjectsLogic.LOOPS do
			local period = ObjectsLogic.period(id)
			t.truthy(period > 0 and period < 60, id)
			for i = 0, 20 do
				local time = period * i / 20 + 0.37
				local a = ObjectsLogic.sample(id, time)
				local b = ObjectsLogic.sample(id, time + period)
				local c = ObjectsLogic.sample(id, time + period * 7)
				close(a, b, 1e-6, id)
				close(a, c, 1e-6, id)
				t.falsy(a.done, id)
				t.equal(a.transparency, 0, id)
				for axis = 1, 3 do
					t.truthy(a.scale[axis] > 0, id .. " scale stays positive")
				end
			end
		end
	end,
	["loops: centred on the rest state"] = function()
		local n = 2000
		for _, id in { "Float", "Hover", "Sway", "Orbit", "Pulse" } do
			local period = ObjectsLogic.period(id)
			local sum = { 0, 0, 0 }
			local turn = { 0, 0, 0 }
			local size = 0
			for i = 0, n - 1 do
				local s = ObjectsLogic.sample(id, period * i / n)
				for axis = 1, 3 do
					sum[axis] += s.position[axis]
					turn[axis] += s.rotation[axis]
				end
				size += s.scale[2]
			end
			for axis = 1, 3 do
				t.near(sum[axis] / n, 0, 1e-6, id .. " mean position")
				t.near(turn[axis] / n, 0, 1e-6, id .. " mean rotation")
			end
			t.near(size / n, 1, 1e-3, id .. " mean scale")
		end
		-- Bounce rests on the ground: it leaves it and comes back, never below.
		local period = ObjectsLogic.period("Bounce")
		t.near(ObjectsLogic.sample("Bounce", 0).position[2], 0, 1e-9)
		t.near(ObjectsLogic.sample("Bounce", period / 2).position[2], 1.2, 1e-9)
		for i = 0, 100 do
			t.truthy(ObjectsLogic.sample("Bounce", period * i / 100).position[2] >= -1e-9)
		end
		-- Spin covers the whole turn.
		t.near(ObjectsLogic.sample("Spin", 1).rotation[2], 90, 1e-9)
		t.near(ObjectsLogic.sample("Spin", 1, { axis = "x", speed = -0.25 }).rotation[1], 270, 1e-9)
		-- Orbit stays on its radius.
		for i = 0, 20 do
			local s = ObjectsLogic.sample("Orbit", i * 0.31, { amplitude = 3 })
			t.near(math.sqrt(s.position[1] ^ 2 + s.position[3] ^ 2), 3, 1e-9)
			t.equal(s.position[2], 0)
		end
	end,
	["loops: phase offsets keep objects out of step"] = function()
		local seen: { [number]: boolean } = {}
		for index = 1, 12 do
			local phase = ObjectsLogic.phaseFor(index)
			t.truthy(phase >= 0 and phase < 1)
			local bucket = math.floor(phase * 1000)
			t.falsy(seen[bucket], "phases are distinct")
			seen[bucket] = true
		end
		local a = ObjectsLogic.sample("Float", 0.3, { phase = ObjectsLogic.phaseFor(1) })
		local b = ObjectsLogic.sample("Float", 0.3, { phase = ObjectsLogic.phaseFor(2) })
		t.truthy(math.abs(a.position[2] - b.position[2]) > 0.05)
		-- A phase of half a cycle mirrors the bob.
		local base = ObjectsLogic.sample("Float", 0.3)
		local opposite = ObjectsLogic.sample("Float", 0.3, { phase = 0.5 })
		t.near(opposite.position[2], -base.position[2], 1e-9)
	end,
	["one-shots: start where expected and end exactly on the end state"] = function()
		local ends: { [string]: { scale: number, transparency: number } } = {
			ScaleIn = { scale = 1, transparency = 0 },
			ScaleOut = { scale = 0, transparency = 1 },
			Reveal = { scale = 1, transparency = 0 },
			Dissolve = { scale = 1.15, transparency = 1 },
			Appear = { scale = 1, transparency = 0 },
			Disappear = { scale = 0.92, transparency = 1 },
			Collect = { scale = 0, transparency = 1 },
			Teleport = { scale = 1, transparency = 0 },
			Shake = { scale = 1, transparency = 0 },
			SquashStretch = { scale = 1, transparency = 0 },
			Interact = { scale = 1, transparency = 0 },
		}
		for _, id in ObjectsLogic.ONE_SHOTS do
			local duration = ObjectsLogic.duration(id)
			local expected = ends[id]
			local last = ObjectsLogic.sample(id, duration)
			t.truthy(last.done, id)
			t.falsy(ObjectsLogic.sample(id, duration * 0.99).done, id)
			for axis = 1, 3 do
				t.near(last.scale[axis], expected.scale, 1e-12, id .. " end scale")
				t.equal(last.rotation[axis], 0, id .. " end rotation")
			end
			t.equal(last.transparency, expected.transparency, id .. " end transparency")
			-- Past the end nothing changes, and endState agrees.
			t.deepEqual(ObjectsLogic.sample(id, duration + 10), last, id)
			t.deepEqual(ObjectsLogic.endState(id), last, id)
			if id ~= "Collect" and id ~= "Dissolve" then
				t.deepEqual(last.position, { 0, 0, 0 }, id .. " end position")
			end
			if expected.scale == 1 and expected.transparency == 0 then
				t.truthy(ObjectsLogic.isRest(last), id .. " ends at rest")
			else
				t.falsy(ObjectsLogic.isRest(last), id)
			end
			-- Negative time clamps to the start.
			t.deepEqual(ObjectsLogic.sample(id, -1), ObjectsLogic.sample(id, 0), id)
		end
		t.equal(ObjectsLogic.sample("ScaleIn", 0).scale[1], 0)
		t.equal(ObjectsLogic.sample("Reveal", 0).transparency, 1)
		t.equal(ObjectsLogic.sample("Appear", 0).transparency, 1)
		t.equal(ObjectsLogic.sample("Disappear", 0).transparency, 0)
		t.truthy(ObjectsLogic.isRest(ObjectsLogic.sample("Interact", 0)))
		t.truthy(ObjectsLogic.isRest(ObjectsLogic.endState("Float")))
	end,
	["one-shots: continuous, with overshoot and anticipation where promised"] = function()
		for _, id in ObjectsLogic.ONE_SHOTS do
			local duration = ObjectsLogic.duration(id)
			local steps = 600
			local previous = ObjectsLogic.sample(id, 0)
			for i = 1, steps do
				local s = ObjectsLogic.sample(id, duration * i / steps)
				for axis = 1, 3 do
					t.truthy(math.abs(s.scale[axis] - previous.scale[axis]) < 0.12, id .. " scale is continuous")
					t.truthy(s.scale[axis] >= 0, id .. " scale never negative")
				end
				t.truthy(s.transparency >= 0 and s.transparency <= 1, id .. " transparency in range")
				previous = s
			end
		end
		local peak, swell = 0, 0
		for i = 0, 100 do
			peak = math.max(peak, ObjectsLogic.sample("ScaleIn", 0.4 * i / 100).scale[1])
			swell = math.max(swell, ObjectsLogic.sample("ScaleOut", 0.3 * i / 100).scale[1])
		end
		t.truthy(peak > 1.02, "ScaleIn overshoots")
		t.truthy(swell > 1.02, "ScaleOut swells first")
		-- amplitude 0 removes the overshoot.
		local flat = 0
		for i = 0, 100 do
			flat = math.max(flat, ObjectsLogic.sample("ScaleIn", 0.4 * i / 100, { amplitude = 0 }).scale[1])
		end
		t.truthy(flat <= 1 + 1e-9)
	end,
	["squash and stretch keeps volume"] = function()
		local side = ObjectsLogic.squash(0.64)
		t.near(side[1], 1.25, 1e-9)
		t.near(side[1] * side[2] * side[3], 1, 1e-9)
		local lowest, highest = 1, 1
		for _, id in { "SquashStretch", "Interact", "Bounce", "Hover" } do
			local span = if ObjectsLogic.isLoop(id) then ObjectsLogic.period(id) else ObjectsLogic.duration(id)
			for i = 0, 200 do
				local s = ObjectsLogic.sample(id, span * i / 200)
				t.near(volume(s), 1, 1e-6, id .. " volume")
				t.near(s.scale[1], s.scale[3], 1e-12, id .. " x and z match")
				if id == "SquashStretch" then
					lowest = math.min(lowest, s.scale[2])
					highest = math.max(highest, s.scale[2])
				end
			end
		end
		t.near(lowest, 0.75, 1e-3) -- anticipation squash
		t.near(highest, 1.25, 1e-3) -- stretch
		-- The squash comes before the stretch.
		t.truthy(ObjectsLogic.sample("SquashStretch", 0.1).scale[2] < 1)
		t.truthy(ObjectsLogic.sample("SquashStretch", 0.28).scale[2] > 1)
		t.truthy(ObjectsLogic.sample("Interact", 0.05).scale[2] < 1)
	end,
	["collect and teleport reach their target"] = function()
		local target = { 6, 4, -3 }
		local last = ObjectsLogic.sample("Collect", 0.55, { target = target })
		t.deepEqual(last.position, target)
		t.deepEqual(last.scale, { 0, 0, 0 })
		t.deepEqual(ObjectsLogic.sample("Collect", 0.55).position, { 0, 3, 0 })
		-- It pulls away first, then closes in on the target.
		local early = ObjectsLogic.sample("Collect", 0.05, { target = target })
		t.truthy(early.position[1] < 0)
		t.truthy(early.scale[1] > 1)
		local previous = math.huge
		for i = 12, 55 do
			local s = ObjectsLogic.sample("Collect", i / 100, { target = target })
			local dx, dz = s.position[1] - target[1], s.position[3] - target[3]
			local flat = math.sqrt(dx * dx + dz * dz)
			t.truthy(flat <= previous + 1e-9, "closes in on the target")
			previous = flat
		end
		-- Custom duration stretches the same motion.
		t.deepEqual(ObjectsLogic.sample("Collect", 2, { target = target, duration = 2 }).position, target)
		t.falsy(ObjectsLogic.sample("Collect", 1, { target = target, duration = 2 }).done)

		local moved = ObjectsLogic.sample("Teleport", 0.7, { target = { 10, 0, 5 } })
		t.deepEqual(moved.position, { 10, 0, 5 })
		t.truthy(ObjectsLogic.sample("Teleport", 0.7 * 0.45, { target = { 10, 0, 5 } }).transparency == 1)
		t.truthy(ObjectsLogic.sample("Teleport", 0.1).scale[2] < 0.8, "squash before vanishing")
		t.equal(ObjectsLogic.sample("Teleport", 0.7).transparency, 0)
	end,
	["parameters: amplitude, intensity, speed, axis and bad values"] = function()
		local base = ObjectsLogic.sample("Float", 0.4)
		t.near(ObjectsLogic.sample("Float", 0.4, { amplitude = 1 }).position[2], base.position[2] * 2, 1e-9)
		t.near(ObjectsLogic.sample("Float", 0.4, { intensity = 0.5 }).position[2], base.position[2] * 0.5, 1e-9)
		t.truthy(ObjectsLogic.isRest(ObjectsLogic.sample("Float", 0.4, { intensity = 0 })))
		t.near(ObjectsLogic.period("Float", { speed = 2 }), 0.5, 1e-9)
		t.near(ObjectsLogic.sample("Float", 0.2, { speed = 1 }).position[2], base.position[2], 1e-9)
		t.near(
			ObjectsLogic.sample("Sway", 0.3, { axis = "x" }).rotation[1],
			ObjectsLogic.sample("Sway", 0.3).rotation[3],
			1e-9
		)
		t.equal(ObjectsLogic.sample("Sway", 0.3, { axis = "x" }).rotation[3], 0)
		t.near(ObjectsLogic.sample("Pulse", 0.3125, { amplitude = 0.2 }).scale[1], 1.2, 1e-9)
		t.equal(ObjectsLogic.duration("ScaleIn", { duration = 2 }), 2)
		-- NaN, infinity and unknown axes fall back to the defaults instead of spreading.
		local odd: any = { amplitude = 0 / 0, speed = math.huge, axis = "w", duration = -5 }
		local s = ObjectsLogic.sample("Float", 0.4, odd)
		t.near(s.position[2], base.position[2], 1e-9)
		t.equal(ObjectsLogic.duration("ScaleIn", odd), 0.01)
		t.near(
			ObjectsLogic.sample("Shake", 0.05).position[1] * 2,
			ObjectsLogic.sample("Shake", 0.05, { intensity = 2 }).position[1],
			1e-9
		)
	end,
	["throttle: far loops are redrawn less often on lower quality"] = function()
		t.equal(ObjectsLogic.updateEvery(nil, 50, 90, true), 1)
		t.equal(ObjectsLogic.updateEvery(30, 50, 90, true), 1)
		t.equal(ObjectsLogic.updateEvery(70, 50, 90, true), 3)
		t.equal(ObjectsLogic.updateEvery(70, 50, 90, false), 2)
		t.equal(ObjectsLogic.updateEvery(120, 50, 90, false), 0)
	end,
	["registry: eighteen object presets with valid metadata"] = function()
		local registry = ObjectsLogic.registry
		t.equal(registry.kind, "object")
		t.equal(registry:count(), 18)
		t.equal(#registry:ids({ category = "loop" }), 7)
		t.equal(#registry:ids({ category = "oneshot" }), 11)
		for _, preset in registry:list() do
			t.deepEqual(Registry.validate(preset), {}, preset.id)
			t.truthy(ObjectsLogic.has(preset.id))
			t.equal(preset.data.loop, ObjectsLogic.isLoop(preset.id))
			t.equal(preset.data.transparency, ObjectsLogic.usesTransparency(preset.id))
			local params = registry:params(preset.id)
			t.equal(params.intensity, 1)
			if preset.data.loop then
				t.near(1 / math.abs(params.speed), ObjectsLogic.period(preset.id), 1e-9, preset.id)
			else
				t.equal(params.duration, ObjectsLogic.duration(preset.id), preset.id)
			end
			-- The registry defaults are the sampler's defaults.
			t.deepEqual(ObjectsLogic.sample(preset.id, 0.2, params), ObjectsLogic.sample(preset.id, 0.2), preset.id)
		end
		t.equal(registry:search("squash")[1], "SquashStretch")
	end,
}
