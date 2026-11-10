--!strict
local CameraLogic = require("../src/Visuals/Camera/CameraLogic")
local Registry = require("../src/Visuals/Core/Registry")
local t = require("./lib/t")

local function magnitude(offset: CameraLogic.Offset): number
	return math.abs(offset.x)
		+ math.abs(offset.y)
		+ math.abs(offset.z)
		+ math.abs(offset.pitch)
		+ math.abs(offset.yaw)
		+ math.abs(offset.roll)
end

-- Largest absolute value of one field over the life of a shake.
local function peak(shake: CameraLogic.Shake, field: string): number
	local best = 0
	local steps = 400
	for i = 0, steps do
		local offset: any = CameraLogic.sample(shake, shake.def.duration * i / steps)
		best = math.max(best, math.abs(offset[field]))
	end
	return best
end

local function run(stack: CameraLogic.Stack, seconds: number, base: CameraLogic.Pose): CameraLogic.StackResult
	local result = stack:step(0, base)
	local n = math.floor(seconds * 60 + 0.5)
	for _ = 1, n do
		result = stack:step(1 / 60, base)
	end
	return result
end

local BASE: CameraLogic.Pose = { position = { 0, 10, 20 }, lookAt = { 0, 5, 0 }, fov = 70 }

return {
	["shake: every preset is valid, starts moving and is exactly zero after its duration"] = function()
		t.equal(#CameraLogic.SHAKE_NAMES, 8)
		for _, name in CameraLogic.SHAKE_NAMES do
			local def = CameraLogic.shakeDef(name)
			t.truthy(def, name)
			t.equal(#CameraLogic.validateShake(def :: CameraLogic.ShakeDef), 0, name)
			local shake = CameraLogic.makeShake(name, { seed = 3 })
			t.truthy(peak(shake, "y") > 0, name .. " moves")
			t.truthy(peak(shake, "pitch") > 0, name .. " rotates")
			t.equal(magnitude(CameraLogic.sample(shake, shake.def.duration)), 0, name .. " ends")
			t.equal(magnitude(CameraLogic.sample(shake, shake.def.duration + 5)), 0, name .. " stays off")
			t.equal(magnitude(CameraLogic.sample(shake, -1)), 0, name .. " before start")
		end
	end,
	["shake: trauma decays for impacts, holds for rumble and builds for hatch"] = function()
		local impact = CameraLogic.makeShake("Impact")
		t.near(CameraLogic.trauma(impact, 0), 1, 1e-9)
		local previous = 1
		for i = 1, 20 do
			local value = CameraLogic.trauma(impact, impact.def.duration * i / 20)
			t.truthy(value <= previous + 1e-12, "impact trauma never grows")
			previous = value
		end
		t.equal(previous, 0)

		local rumble = CameraLogic.makeShake("Rumble")
		t.equal(CameraLogic.trauma(rumble, 0), 0)
		t.near(CameraLogic.trauma(rumble, 1), 1, 1e-9)
		t.near(CameraLogic.trauma(rumble, 1.8), 1, 1e-9)
		t.truthy(CameraLogic.trauma(rumble, rumble.def.duration - 0.1) < 0.5)

		local hatch = CameraLogic.makeShake("Hatch")
		t.truthy(CameraLogic.trauma(hatch, 0.3) < CameraLogic.trauma(hatch, 0.8))
		t.truthy(CameraLogic.trauma(hatch, 0.8) < CameraLogic.trauma(hatch, 1.25))
		t.equal(CameraLogic.trauma(hatch, hatch.def.duration), 0)
	end,
	["shake: amplitude is trauma squared times the preset amplitude"] = function()
		local shake = CameraLogic.makeShake("Impact", { seed = 1 })
		local def = shake.def
		for i = 0, 100 do
			local time = def.duration * i / 100
			local limit = CameraLogic.trauma(shake, time) ^ 2
			local offset = CameraLogic.sample(shake, time)
			t.truthy(math.abs(offset.x) <= def.amplitude * limit + 1e-9)
			t.truthy(math.abs(offset.yaw) <= def.rotation * limit + 1e-9)
		end
	end,
	["shake: deterministic for a time and seed, different across seeds and axes"] = function()
		local a = CameraLogic.makeShake("Explosion", { seed = 7 })
		local b = CameraLogic.makeShake("Explosion", { seed = 7 })
		local c = CameraLogic.makeShake("Explosion", { seed = 8 })
		t.deepEqual(CameraLogic.sample(a, 0.123), CameraLogic.sample(b, 0.123))
		local first, other = CameraLogic.sample(a, 0.123), CameraLogic.sample(c, 0.123)
		t.truthy(math.abs(first.x - other.x) > 1e-6)
		t.truthy(math.abs(first.x - first.y) > 1e-6, "axes are out of phase")
		for i = 0, 200 do
			local value = CameraLogic.noise(i * 0.013, 12, 5, 2)
			t.truthy(value >= -1 and value <= 1)
		end
		-- Smooth: a 1 ms step never jumps.
		local jump = math.abs(CameraLogic.noise(0.2, 16, 5, 1) - CameraLogic.noise(0.201, 16, 5, 1))
		t.truthy(jump < 0.4)
	end,
	["shake: landing is biased to the vertical axis"] = function()
		local landing = CameraLogic.makeShake("Landing", { seed = 2 })
		t.truthy(peak(landing, "y") > peak(landing, "x") * 3)
		t.truthy(peak(landing, "y") > peak(landing, "z") * 3)
		t.truthy(peak(landing, "pitch") > peak(landing, "yaw") * 3)
	end,
	["shake: intensity and juice scale it, zero juice silences it"] = function()
		local normal = CameraLogic.makeShake("Impact", { seed = 4 })
		local double = CameraLogic.makeShake("Impact", { seed = 4, intensity = 2 })
		local dimmed = CameraLogic.makeShake("Impact", { seed = 4 }, 0.5)
		local reduced = CameraLogic.makeShake("Impact", { seed = 4 }, 0)
		local a, b = CameraLogic.sample(normal, 0.05), CameraLogic.sample(double, 0.05)
		t.near(b.x, a.x * 2, 1e-9)
		t.near(b.roll, a.roll * 2, 1e-9)
		t.near(CameraLogic.sample(dimmed, 0.05).y, a.y * 0.5, 1e-9)
		for i = 0, 40 do
			t.equal(magnitude(CameraLogic.sample(reduced, i * 0.01)), 0)
		end
	end,
	["shake: options override the preset and bad input is rejected"] = function()
		local shake = CameraLogic.makeShake("Rumble", { duration = 0.3, amplitude = 2, frequency = 4 })
		t.equal(shake.def.duration, 0.3)
		t.equal(shake.def.amplitude, 2)
		t.truthy(shake.def.fadeIn + shake.def.fadeOut <= 0.3 + 1e-9, "fades shrink to fit")
		t.throws(function()
			CameraLogic.makeShake("NoSuchShake")
		end)
		local broken: any = { amplitude = -1, rotation = 0, frequency = 0, duration = 0, fadeIn = 0, fadeOut = 0 }
		t.truthy(#CameraLogic.validateShake(broken) >= 3)
	end,
	["shake: several shakes sum and the sum is clamped"] = function()
		local one = CameraLogic.makeShake("Impact", { seed = 1 })
		local two = CameraLogic.makeShake("SoftImpact", { seed = 2 })
		local a, b = CameraLogic.sample(one, 0.03), CameraLogic.sample(two, 0.03)
		local sum = CameraLogic.combine({ a, b })
		t.near(sum.x, a.x + b.x, 1e-9)
		t.near(sum.pitch, a.pitch + b.pitch, 1e-9)

		local many: { CameraLogic.Offset } = {}
		for _ = 1, 30 do
			table.insert(many, { x = 1, y = -1, z = 1, pitch = 5, yaw = -5, roll = 5 })
		end
		local clamped = CameraLogic.combine(many)
		t.equal(clamped.x, CameraLogic.MAX_SHAKE_OFFSET)
		t.equal(clamped.y, -CameraLogic.MAX_SHAKE_OFFSET)
		t.equal(clamped.yaw, -CameraLogic.MAX_SHAKE_ROTATION)
		t.truthy(CameraLogic.isZero(CameraLogic.combine({})))
	end,
	["framing: focus puts the camera at the distance, angle and elevation, looking at the target"] = function()
		local target = { 10, 4, -6 }
		local pose = CameraLogic.focusPose(target, { distance = 12, angle = 90, elevation = 30, height = 1 })
		local position = pose.position :: CameraLogic.Vec3
		local lookAt = pose.lookAt :: CameraLogic.Vec3
		t.deepEqual(lookAt, { 10, 5, -6 })
		t.near(CameraLogic.distance(position, lookAt), 12, 1e-9)
		t.near(position[2] - lookAt[2], 6, 1e-9) -- sin(30) * 12
		t.near(position[3], lookAt[3], 1e-9) -- at 90 degrees the camera is on +X
		t.truthy(position[1] > lookAt[1])
		local default = CameraLogic.focusPose({ 0, 0, 0 })
		t.near(CameraLogic.distance(default.position :: CameraLogic.Vec3, { 0, 0, 0 }), 12, 1e-9)
	end,
	["framing: orbit keeps its distance and turns at the given speed"] = function()
		local target = { 0, 0, 0 }
		local options = { distance = 8, elevation = 0, speed = 45 }
		t.equal(CameraLogic.orbitAngle(options, 2), 90)
		for i = 0, 16 do
			local pose = CameraLogic.orbitPose(target, options, i * 0.5)
			t.near(CameraLogic.distance(pose.position :: CameraLogic.Vec3, target), 8, 1e-9)
		end
		local quarter = CameraLogic.orbitPose(target, options, 2).position :: CameraLogic.Vec3
		t.near(quarter[1], 8, 1e-9)
		t.near(quarter[3], 0, 1e-9)
		local full = CameraLogic.orbitPose(target, options, 8).position :: CameraLogic.Vec3
		t.near(full[1], 0, 1e-9)
		t.near(full[3], 8, 1e-9)
	end,
	["framing: pan, zoom and fit-bounds"] = function()
		local from: CameraLogic.Pose = { position = { 0, 0, 0 }, lookAt = { 0, 0, -10 }, fov = 70 }
		local to: CameraLogic.Pose = { position = { 10, 0, 0 }, lookAt = { 10, 0, -10 }, fov = 50 }
		t.deepEqual(CameraLogic.panPose(from, to, 0), from)
		t.deepEqual(CameraLogic.panPose(from, to, 1), to)
		local middle = CameraLogic.panPose(from, to, 0.5, "linear")
		t.near((middle.position :: CameraLogic.Vec3)[1], 5, 1e-9)
		t.near(middle.fov :: number, 60, 1e-9)
		t.deepEqual(CameraLogic.panPose(from, to, 5), to) -- alpha is clamped

		local zoomed = CameraLogic.zoomPose({ position = { 0, 0, 20 }, lookAt = { 0, 0, 0 }, fov = 70 }, 2)
		t.near((zoomed.position :: CameraLogic.Vec3)[3], 10, 1e-9)
		t.near(CameraLogic.zoomFov(70, 1), 70, 1e-9)
		t.truthy(CameraLogic.zoomFov(70, 2) < 40)
		t.near(math.tan(math.rad(CameraLogic.zoomFov(70, 2)) / 2) * 2, math.tan(math.rad(70) / 2), 1e-9)

		-- At the fit distance the sphere's edge sits exactly on the padded frustum edge.
		local distance = CameraLogic.fitDistance(5, 60, 16 / 9, 1)
		t.near(distance * math.sin(math.rad(30)), 5, 1e-9)
		-- A portrait screen is limited by its width, so the camera must stand further back.
		local portrait = CameraLogic.fitDistance(5, 60, 9 / 16, 1)
		t.truthy(portrait > distance)
		local half = math.atan(math.tan(math.rad(30)) * 9 / 16)
		t.near(portrait * math.sin(half), 5, 1e-9)
		t.near(CameraLogic.fitDistance(5, 60, 1), distance * 1.1, 1e-9)
		t.equal(CameraLogic.fitDistance(0, 60, 1), 0)
	end,
	["stack: blends in over the base pose and back out to it"] = function()
		local stack = CameraLogic.newStack()
		local pose: CameraLogic.Pose = { position = { 100, 10, 20 }, lookAt = { 100, 5, 0 }, fov = 40 }
		local id = stack:push({ pose = pose, blendIn = 0.5, blendOut = 0.5, easing = "linear" })
		local start = stack:step(0, BASE)
		t.deepEqual(start.pose, BASE)
		t.truthy(start.active and start.takeover)
		local half = run(stack, 0.25, BASE)
		t.near((half.pose.position :: CameraLogic.Vec3)[1], 50, 1e-6)
		t.near(half.pose.fov :: number, 55, 1e-6)
		local full = run(stack, 0.5, BASE)
		t.near((full.pose.position :: CameraLogic.Vec3)[1], 100, 1e-6)
		t.truthy(stack:remove(id))
		t.truthy(stack:isEnding(id))
		local leaving = run(stack, 0.25, BASE)
		t.near((leaving.pose.position :: CameraLogic.Vec3)[1], 50, 1e-6)
		local done = run(stack, 0.5, BASE)
		t.falsy(done.active)
		t.falsy(done.takeover)
		t.deepEqual(done.pose, BASE)
		t.equal(stack:count(), 0)
		t.falsy(stack:remove(id))
	end,
	["stack: the highest priority wins and hands back to the next entry"] = function()
		local stack = CameraLogic.newStack()
		local low: CameraLogic.Pose = { position = { 10, 0, 0 }, lookAt = { 0, 0, 0 }, fov = 60 }
		local high: CameraLogic.Pose = { position = { 50, 0, 0 }, lookAt = { 0, 0, 0 }, fov = 30 }
		local lowId = stack:push({ pose = low, priority = 1, blendIn = 0, blendOut = 0.2 })
		local highId = stack:push({ pose = high, priority = 5, blendIn = 0.2, blendOut = 0.2 })
		t.equal(stack:top(), highId)
		local result = run(stack, 0.3, BASE)
		t.near((result.pose.position :: CameraLogic.Vec3)[1], 50, 1e-6)
		-- A lower priority entry added later stays underneath.
		local lowest = stack:push({ pose = BASE, priority = 0, blendIn = 0 })
		t.equal(stack:top(), highId)
		result = run(stack, 0.1, BASE)
		t.near((result.pose.position :: CameraLogic.Vec3)[1], 50, 1e-6)
		stack:remove(highId)
		result = run(stack, 0.3, BASE)
		t.near((result.pose.position :: CameraLogic.Vec3)[1], 10, 1e-6)
		t.near(result.pose.fov :: number, 60, 1e-6)
		t.equal(stack:top(), lowId)
		t.truthy(stack:has(lowest))
	end,
	["stack: equal priority replaces without a jump"] = function()
		local stack = CameraLogic.newStack()
		local first: CameraLogic.Pose = { position = { 10, 0, 0 }, lookAt = { 0, 0, 0 }, fov = 60 }
		local second: CameraLogic.Pose = { position = { 30, 0, 0 }, lookAt = { 0, 0, 0 }, fov = 60 }
		local firstId = stack:push({ pose = first, blendIn = 0, blendOut = 0.3 })
		run(stack, 0.1, BASE)
		local secondId = stack:push({ pose = second, blendIn = 0.4, blendOut = 0.3, easing = "linear" })
		local result = stack:step(0, BASE)
		t.near((result.pose.position :: CameraLogic.Vec3)[1], 10, 1e-6, "no jump on replace")
		result = run(stack, 0.2, BASE)
		t.near((result.pose.position :: CameraLogic.Vec3)[1], 20, 1e-6)
		result = run(stack, 0.3, BASE)
		t.near((result.pose.position :: CameraLogic.Vec3)[1], 30, 1e-6)
		t.falsy(stack:has(firstId), "the replaced entry is dropped")
		t.equal(stack:count(), 1)
		t.equal(stack:top(), secondId)
	end,
	["stack: timed entries end on their own and report it once"] = function()
		local stack = CameraLogic.newStack()
		local ages: { number } = {}
		local id = stack:push({
			duration = 0.5,
			blendIn = 0.1,
			blendOut = 0.1,
			pose = function(age: number, under: CameraLogic.Pose): CameraLogic.Pose
				table.insert(ages, age)
				t.truthy(under.fov ~= nil)
				return { position = { age, 0, 0 }, lookAt = { 0, 0, -1 }, fov = 50 }
			end,
		})
		local finished: { number } = {}
		for _ = 1, 60 do
			local result = stack:step(1 / 60, BASE)
			for _, done in result.finished do
				table.insert(finished, done)
			end
		end
		t.deepEqual(finished, { id })
		t.equal(stack:count(), 0)
		t.truthy(#ages > 10)
		-- finish() ends a timed entry early.
		local other = stack:push({ duration = 10, blendIn = 0, blendOut = 0, pose = BASE })
		stack:step(1 / 60, BASE)
		t.truthy(stack:finish(other))
		local result = stack:step(1 / 60, BASE)
		t.deepEqual(result.finished, { other })
		t.falsy(stack:finish(other))
	end,
	["stack: FOV-only entries never take the camera over"] = function()
		local stack = CameraLogic.newStack()
		stack:push({ takeover = false, blendIn = 0, pose = { fov = 40 } })
		local result = run(stack, 0.1, { fov = 70 })
		t.falsy(result.takeover)
		t.falsy(stack:hasTakeover())
		t.equal(result.pose.position, nil)
		t.near(result.pose.fov :: number, 40, 1e-9)
		-- A relative entry reads the pose beneath it.
		stack:push({
			takeover = false,
			priority = 5,
			blendIn = 0,
			pose = function(_age: number, under: CameraLogic.Pose): CameraLogic.Pose
				return { fov = (under.fov :: number) + 6 }
			end,
		})
		result = run(stack, 0.1, { fov = 70 })
		t.near(result.pose.fov :: number, 46, 1e-9)
		-- A takeover entry over a FOV-only base keeps the FOV change and adds a position.
		stack:push({ priority = 1, blendIn = 0, pose = { position = { 1, 2, 3 }, lookAt = { 0, 0, 0 } } })
		result = run(stack, 0.1, BASE)
		t.truthy(result.takeover)
		t.deepEqual(result.pose.position, { 1, 2, 3 })
		t.near(result.pose.fov :: number, 46, 1e-9)
	end,
	["stack: restoration keeps the first saved value and releases exactly once"] = function()
		local stack = CameraLogic.newStack()
		stack:save("fov", 70)
		stack:save("fov", 40) -- a nested move must not overwrite the original
		stack:save("cameraType", "Custom")
		stack:save("flag", false)
		t.equal(stack:saved("fov"), 70)
		t.equal(stack:saved("flag"), false)
		local partial = stack:release({ "cameraType", "missing" })
		t.deepEqual(partial, { cameraType = "Custom" })
		t.equal(stack:saved("cameraType"), nil)
		t.equal(stack:saved("fov"), 70)
		t.deepEqual(stack:release(), { fov = 70, flag = false })
		t.deepEqual(stack:release(), {})
		stack:save("fov", 55)
		t.equal(stack:saved("fov"), 55)
		-- clear() removes every entry and returns the ids.
		local a = stack:push({ pose = BASE })
		local b = stack:push({ pose = BASE, priority = 2 })
		t.deepEqual(stack:clear(), { a, b })
		t.falsy(stack:step(0.1, BASE).active)
	end,
	["punchFov: kicks, returns to zero and stays bounded"] = function()
		t.equal(CameraLogic.punchFov(8, 0, 0.4), 0)
		t.equal(CameraLogic.punchFov(8, 0.4, 0.4), 0)
		t.equal(CameraLogic.punchFov(8, 1, 0.4), 0)
		t.near(CameraLogic.punchFov(8, 0.4 * 0.18, 0.4), 8, 1e-6)
		for i = 0, 100 do
			t.truthy(math.abs(CameraLogic.punchFov(8, 0.4 * i / 100, 0.4)) <= 8 + 1e-9)
		end
		t.truthy(math.abs(CameraLogic.punchFov(8, 0.39, 0.4)) < 0.1)
	end,
	["cinematics: every recipe validates with increasing key times inside its duration"] = function()
		t.equal(#CameraLogic.CINEMATIC_NAMES, 4)
		for _, name in CameraLogic.CINEMATIC_NAMES do
			local recipe = CameraLogic.cinematic(name) :: CameraLogic.Cinematic
			t.truthy(recipe, name)
			t.deepEqual(CameraLogic.validateCinematic(recipe), {}, name)
			local previous = -1
			for _, key in recipe.keys do
				t.truthy(key.time > previous, name .. " key times increase")
				previous = key.time
			end
			t.truthy(previous <= recipe.duration, name .. " keys end inside the duration")
			t.truthy(recipe.duration >= recipe.blendIn, name .. " blend fits")
			local markers: { [string]: number } = recipe.markers or {}
			for _, at in markers do
				t.truthy(at >= 0 and at <= recipe.duration)
			end
		end
		local broken: any = {
			duration = 1,
			takeover = true,
			blendIn = 0,
			blendOut = 0,
			base = {},
			keys = { { time = 0 }, { time = 0.5, easing = "nope" }, { time = 0.4 }, { time = 3 } },
		}
		t.truthy(#CameraLogic.validateCinematic(broken) >= 3)
	end,
	["cinematics: poses follow the keys and reduced motion holds the settled framing"] = function()
		local recipe = CameraLogic.cinematic("PetReveal") :: CameraLogic.Cinematic
		local target = { 5, 2, 5 }
		local framing: CameraLogic.CinematicFraming = { distance = 10, angle = 0, elevation = 10, height = 0, fov = 70 }
		local first = CameraLogic.cinematicPose(recipe, target, framing, 0)
		t.near(CameraLogic.distance(first.position :: CameraLogic.Vec3, first.lookAt :: CameraLogic.Vec3), 13.5, 1e-6)
		t.near(first.fov :: number, 70, 1e-9)
		local last = CameraLogic.cinematicPose(recipe, target, framing, recipe.duration)
		t.near(CameraLogic.distance(last.position :: CameraLogic.Vec3, last.lookAt :: CameraLogic.Vec3), 8.2, 1e-6)
		t.near(last.fov :: number, 70 * 0.88, 1e-6)
		-- The push-in: the camera is closer at the reveal than at the start.
		local reveal = (recipe.markers :: { [string]: number }).reveal
		local atReveal = CameraLogic.cinematicState(recipe, reveal)
		t.truthy(atReveal.distance < 1)
		t.truthy(atReveal.fov < 1)
		-- Continuous: no jump across a key.
		local before = CameraLogic.cinematicState(recipe, 1.15 - 1e-6)
		local after = CameraLogic.cinematicState(recipe, 1.15 + 1e-6)
		t.near(before.distance, after.distance, 1e-3)
		-- Reduced motion: the same pose at every time.
		local still = CameraLogic.cinematicPose(recipe, target, framing, 0, true)
		t.deepEqual(still, CameraLogic.cinematicPose(recipe, target, framing, 2, true))
		t.deepEqual(still, last)

		local teleport = CameraLogic.cinematic("Teleport") :: CameraLogic.Cinematic
		local pose = CameraLogic.cinematicPose(teleport, target, { fov = 70 }, 0.32)
		t.equal(pose.position, nil)
		t.near(pose.fov :: number, 70 * 1.28, 1e-6)
		t.near(CameraLogic.cinematicPose(teleport, target, { fov = 70 }, teleport.duration).fov :: number, 70, 1e-6)
		t.near(CameraLogic.cinematicPose(teleport, target, { fov = 70 }, 0.32, true).fov :: number, 70, 1e-9)
		t.equal(CameraLogic.reducedBlend(0.9), 0.12)
		t.equal(CameraLogic.reducedBlend(0.05), 0.05)
	end,
	["registry: shakes, cinematics and moves are registered with valid metadata"] = function()
		local registry = CameraLogic.registry
		t.equal(registry.kind, "camera")
		t.equal(registry:count(), 18)
		t.equal(#registry:ids({ category = "shake" }), 8)
		t.equal(#registry:ids({ category = "cinematic" }), 4)
		t.equal(#registry:ids({ category = "move" }), 6)
		for _, preset in registry:list() do
			t.deepEqual(Registry.validate(preset), {}, preset.id)
			t.truthy(preset.usage and #preset.usage > 0, preset.id .. " usage")
			local described = registry:describe(preset.id)
			t.equal(described.kind, "camera")
			if preset.data.kind == "shake" then
				t.deepEqual(CameraLogic.validateShake(preset.data.shake), {}, preset.id)
				t.truthy(CameraLogic.shakeDef(preset.id) == preset.data.shake)
			elseif preset.data.kind == "cinematic" then
				t.deepEqual(CameraLogic.validateCinematic(preset.data.cinematic), {}, preset.id)
			end
		end
		t.equal(registry:params("Impact", { intensity = 9 }).intensity, 3)
		t.equal(registry:search("hatch")[1], "Hatch")
	end,
}
