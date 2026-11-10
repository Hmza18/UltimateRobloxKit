--!strict
local ObjectsLogic = require("../src/Visuals/Objects/ObjectsLogic")
local PetsLogic = require("../src/Visuals/Pets/PetsLogic")
local Registry = require("../src/Visuals/Core/Registry")
local t = require("./lib/t")

type Vec3 = PetsLogic.Vec3

local MODES: { PetsLogic.FormationMode } = { "rows", "arc", "circle", "orbit" }

local function distance(a: Vec3, b: Vec3): number
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end

local function isRest(offset: PetsLogic.Offset): boolean
	for i = 1, 3 do
		if offset.position[i] ~= 0 or offset.rotation[i] ~= 0 or offset.scale[i] ~= 1 then
			return false
		end
	end
	return true
end

return {
	["idle: periodic, centred on rest and finite"] = function()
		local options = { phase = 0.3, radius = 2 }
		local period = PetsLogic.idlePeriod(options)
		t.near(period, 2 / 0.55, 1e-9)
		local n = 4000
		local sumY, sumYaw, sumRoll, sumScale = 0, 0, 0, 0
		for i = 0, n - 1 do
			local time = period * i / n
			local a = PetsLogic.idle(time, options)
			sumY += a.position[2]
			sumYaw += a.rotation[2]
			sumRoll += a.rotation[3]
			sumScale += a.scale[2]
			t.equal(a.position[1], 0)
			t.equal(a.position[3], 0)
			t.falsy(a.done)
			if i % 400 == 0 then
				local b = PetsLogic.idle(time + period, options)
				local c = PetsLogic.idle(time + period * 5, options)
				for axis = 1, 3 do
					t.near(a.position[axis], b.position[axis], 1e-9)
					t.near(a.rotation[axis], b.rotation[axis], 1e-9)
					t.near(a.scale[axis], c.scale[axis], 1e-9)
				end
			end
		end
		t.near(sumY / n, 0, 1e-9)
		t.near(sumYaw / n, 0, 1e-9)
		t.near(sumRoll / n, 0, 1e-9)
		t.near(sumScale / n, 1, 1e-3)
	end,
	["idle: phases differ per pet, breathing keeps volume, options scale it"] = function()
		local seen: { [number]: boolean } = {}
		for index = 1, 24 do
			local phase = PetsLogic.phaseFor(index)
			t.truthy(phase >= 0 and phase < 1)
			local bucket = math.floor(phase * 500)
			t.falsy(seen[bucket], "phases are distinct")
			seen[bucket] = true
		end
		local a = PetsLogic.idle(1, { phase = PetsLogic.phaseFor(1) })
		local b = PetsLogic.idle(1, { phase = PetsLogic.phaseFor(2) })
		t.truthy(math.abs(a.position[2] - b.position[2]) > 0.01)
		for i = 0, 50 do
			local s = PetsLogic.idle(i * 0.1).scale
			t.near(s[1] * s[2] * s[3], 1, 1e-9)
			t.truthy(s[2] > 0.97 and s[2] < 1.03)
		end
		local still = PetsLogic.idle(0.7, { bob = 0, breathe = 0, sway = 0 })
		t.truthy(isRest(still))
		t.near(PetsLogic.idle(0.4, { bob = 2 }).position[2], PetsLogic.idle(0.4).position[2] * 2, 1e-9)
	end,
	["idle: bob height scales with pet size inside limits"] = function()
		t.near(PetsLogic.bobHeight(1), 0.12, 1e-9)
		t.near(PetsLogic.bobHeight(3), 0.36, 1e-9)
		t.equal(PetsLogic.bobHeight(0.1), 0.04)
		t.equal(PetsLogic.bobHeight(50), 0.6)
		t.near(PetsLogic.bobHeight(nil), 0.12, 1e-9)
		local quarter = PetsLogic.idlePeriod() / 8 -- a quarter of the bob cycle
		t.near(PetsLogic.idle(quarter, { radius = 3 }).position[2], 0.36, 1e-9)
		t.near(PetsLogic.idle(quarter, { radius = 1 }).position[2], 0.12, 1e-9)
	end,
	["reactions: every one starts at rest, moves, and ends exactly at rest"] = function()
		t.equal(#PetsLogic.REACTIONS, 4)
		for _, id in PetsLogic.REACTIONS do
			local duration = PetsLogic.reactionDuration(id)
			t.truthy(duration > 0.2 and duration < 2, id)
			t.truthy(isRest(PetsLogic.reaction(id, 0)), id .. " starts at rest")
			local moved = 0
			local previous = PetsLogic.reaction(id, 0)
			for i = 1, 300 do
				local sample = PetsLogic.reaction(id, duration * i / 300, { radius = 1.5 })
				moved = math.max(moved, math.abs(sample.position[2]) + math.abs(sample.scale[2] - 1))
				if i < 300 then
					t.falsy(sample.done, id)
					t.truthy(math.abs(sample.position[2] - previous.position[2]) < 0.2, id .. " height is continuous")
					t.truthy(math.abs(sample.scale[2] - previous.scale[2]) < 0.05, id .. " scale is continuous")
				end
				previous = sample
			end
			t.truthy(moved > 0.05, id .. " moves")
			local last = PetsLogic.reaction(id, duration)
			t.truthy(last.done, id)
			t.truthy(isRest(last), id .. " ends at rest")
			t.truthy(isRest(PetsLogic.reaction(id, duration + 3)), id)
			-- Just before the end it is already nearly home (no pop on the last frame).
			local nearly = PetsLogic.reaction(id, duration * 0.995)
			t.truthy(math.abs(nearly.position[2]) < 0.03, id)
			t.truthy(math.abs(nearly.scale[2] - 1) < 0.02, id)
			t.truthy(isRest(PetsLogic.reaction(id, 0.2, { intensity = 0 })), id .. " intensity 0")
		end
		t.throws(function()
			PetsLogic.reaction("Nope", 0)
		end)
		t.falsy(PetsLogic.isReaction("Spawn"))
	end,
	["reactions: happy hops twice with squash, stretch and a full spin"] = function()
		local radius = 2
		local peaks = 0
		local rising = false
		local previous = 0
		local lowest, highest = 1, 1
		for i = 0, 900 do
			local sample = PetsLogic.reaction("HappyReaction", i / 1000, { radius = radius })
			local y = sample.position[2]
			t.truthy(y >= 0, "never below the ground")
			if y > previous then
				rising = true
			elseif y < previous and rising then
				rising = false
				peaks += 1
			end
			previous = y
			lowest = math.min(lowest, sample.scale[2])
			highest = math.max(highest, sample.scale[2])
			t.near(sample.scale[1] * sample.scale[2] * sample.scale[3], 1, 1e-9)
		end
		t.equal(peaks, 2)
		t.near(lowest, 0.8, 1e-3)
		t.near(highest, 1.18, 1e-3)
		t.near(PetsLogic.reaction("HappyReaction", 0.27, { radius = radius }).position[2], 0.9 * radius, 0.01)
		t.near(PetsLogic.reaction("HappyReaction", 0.85).rotation[2], 360, 1e-6)
		t.truthy(PetsLogic.reaction("HappyReaction", 0.4).rotation[2] > 90)
		-- The squash comes before the first hop (anticipation).
		local early = PetsLogic.reaction("HappyReaction", 0.08)
		t.truthy(early.scale[2] < 0.85)
		t.equal(early.position[2], 0)
	end,
	["reactions: curious leans toward its point, select pops, hover lifts"] = function()
		local toward = PetsLogic.reaction("CuriousReaction", 0.5, { radius = 2, direction = { 3, 0, 0 } })
		t.near(toward.position[1], 0.6, 0.05)
		t.near(toward.position[3], 0, 1e-9)
		t.truthy(toward.rotation[3] > 13)
		local forward = PetsLogic.reaction("CuriousReaction", 0.5, { radius = 2 })
		t.truthy(forward.position[3] < -0.5)
		local degenerate = PetsLogic.reaction("CuriousReaction", 0.5, { radius = 2, direction = { 0, 5, 0 } })
		t.near(degenerate.position[3], forward.position[3], 1e-9)

		t.truthy(PetsLogic.reaction("SelectBounce", 0.07).scale[2] < 0.9)
		t.truthy(PetsLogic.reaction("SelectBounce", 0.18).scale[2] > 1.1)
		t.truthy(PetsLogic.reaction("SelectBounce", 0.19).position[2] > 0.2)

		local lifted = PetsLogic.reaction("HoverReaction", 0.25, { radius = 2 })
		t.near(lifted.position[2], 0.5, 1e-9)
		t.near(lifted.scale[1], 1.08, 1e-9)
		t.deepEqual(PetsLogic.hoverPose(1, 2).position, { 0, 0.5, 0 })
		t.truthy(isRest(PetsLogic.hoverPose(0, 2)))
	end,
	["combine: offsets add, scales multiply, models get a uniform scale"] = function()
		local a = PetsLogic.rest()
		a.position = { 1, 2, 3 }
		a.rotation = { 0, 90, 0 }
		a.scale = { 2, 2, 2 }
		local b = PetsLogic.rest()
		b.position = { 0, 1, 0 }
		b.rotation = { 5, 10, 0 }
		b.scale = { 0.5, 1.5, 0.5 }
		local sum = PetsLogic.combine({ a, b })
		t.deepEqual(sum.position, { 1, 3, 3 })
		t.deepEqual(sum.rotation, { 5, 100, 0 })
		t.deepEqual(sum.scale, { 1, 3, 1 })
		t.truthy(isRest(PetsLogic.combine({})))
		t.equal(PetsLogic.uniformScale({ 1.08, 1.08, 1.08 }), 1.08)
		t.equal(PetsLogic.uniformScale({ 1, 1, 1 }), 1)
		t.near(PetsLogic.uniformScale(ObjectsLogic.squash(0.8)), 0.88, 1e-9)
		t.near(PetsLogic.uniformScale(ObjectsLogic.squash(1.2)), 1.12, 1e-9)
	end,
	["formation: 1 to 12 pets in every mode get distinct slots that never overlap"] = function()
		for _, mode in MODES do
			t.truthy(PetsLogic.isMode(mode))
			for _, radius in { 0.6, 1, 2.5 } do
				local options: PetsLogic.FormationOptions = { radius = radius, time = 3.7 }
				local spacing = PetsLogic.spacing(options)
				t.near(spacing, math.max(0.5, radius * 2.6), 1e-9)
				for count = 1, 12 do
					local slots = PetsLogic.formation(mode, count, options)
					local label = string.format("%s x%d r%.1f", mode, count, radius)
					t.equal(#slots, count, label)
					for i = 1, count do
						t.equal(slots[i][2], 0, label)
						-- No pet stands inside the owner.
						t.truthy(
							math.sqrt(slots[i][1] ^ 2 + slots[i][3] ^ 2) >= radius + 1.5,
							label .. " clear of the owner"
						)
						for j = i + 1, count do
							t.truthy(distance(slots[i], slots[j]) >= spacing - 1e-6, label .. " spacing")
							-- Pets of this radius therefore never touch.
							t.truthy(distance(slots[i], slots[j]) > radius * 2, label .. " no overlap")
						end
					end
				end
			end
		end
		t.equal(#PetsLogic.formation("rows", 0), 0)
		t.falsy(PetsLogic.isMode("line"))
	end,
	["formation: rows and arc sit behind the owner, circle surrounds it, ordering is stable"] = function()
		for count = 1, 12 do
			for _, slot in PetsLogic.formation("rows", count) do
				t.truthy(slot[3] > 0, "rows are behind")
			end
			for _, slot in PetsLogic.formation("arc", count) do
				t.truthy(slot[3] > -1e-6 or math.abs(slot[1]) > 1, "arc wraps behind")
			end
			-- Left-right symmetric: the group is centred on the owner.
			local sum = 0
			for _, slot in PetsLogic.formation("rows", count) do
				sum += slot[1]
			end
			t.near(sum, 0, 1e-9)
		end
		local three = PetsLogic.formation("rows", 3)
		t.near(three[2][1], 0, 1e-9)
		t.truthy(three[1][1] < three[2][1] and three[2][1] < three[3][1])
		t.deepEqual(PetsLogic.formation("rows", 7), PetsLogic.formation("rows", 7))
		-- Five per row puts the sixth pet in a second row.
		local rows = PetsLogic.formation("rows", 6, { perRow = 5 })
		t.truthy(rows[6][3] > rows[1][3])
		t.near(rows[6][1], 0, 1e-9)

		local circle = PetsLogic.formation("circle", 8, { radius = 1 })
		local ring = math.sqrt(circle[1][1] ^ 2 + circle[1][3] ^ 2)
		local front, back = 0, 0
		for _, slot in circle do
			t.near(math.sqrt(slot[1] ^ 2 + slot[3] ^ 2), ring, 1e-9)
			if slot[3] > 0.1 then
				back += 1
			elseif slot[3] < -0.1 then
				front += 1
			end
		end
		t.equal(front, back)
		t.deepEqual(PetsLogic.formation("circle", 1)[1], { 0, 0, 3.5 })
	end,
	["formation: orbit turns over time at the given speed"] = function()
		local options: PetsLogic.FormationOptions = { radius = 1, orbitSpeed = 90, time = 0 }
		local start = PetsLogic.formation("orbit", 4, options)
		t.deepEqual(start, PetsLogic.formation("circle", 4, { radius = 1 }))
		options.time = 1
		local quarter = PetsLogic.formation("orbit", 4, options)
		-- After a quarter turn pet 1 stands where pet 2 was.
		t.near(quarter[1][1], start[2][1], 1e-9)
		t.near(quarter[1][3], start[2][3], 1e-9)
		options.time = 4
		local full = PetsLogic.formation("orbit", 4, options)
		t.near(full[3][1], start[3][1], 1e-9)
		t.near(full[3][3], start[3][3], 1e-9)
	end,
	["follow: converges on its slot without overshooting"] = function()
		local state = PetsLogic.newFollowState({ 0, 0, 0 })
		local target = { 10, 0, -4 }
		local start = distance(state.position, target)
		local previous = start
		for _ = 1, 240 do
			state = PetsLogic.followStep(state, target, 1 / 60)
			local remaining = distance(state.position, target)
			t.truthy(remaining <= previous + 1e-9, "always closing in")
			-- Never past the target along the line of travel.
			local along = (state.position[1] * 10 + state.position[3] * -4) / start
			t.truthy(along <= start + 1e-6, "no overshoot")
			previous = remaining
		end
		t.truthy(previous < 0.01)
		t.truthy(math.abs(state.velocity[1]) < 0.05)
		-- Different frame rates land in the same place.
		local slow = PetsLogic.newFollowState({ 0, 0, 0 })
		for _ = 1, 20 do
			slow = PetsLogic.followStep(slow, target, 1 / 20)
		end
		local fast = PetsLogic.newFollowState({ 0, 0, 0 })
		for _ = 1, 120 do
			fast = PetsLogic.followStep(fast, target, 1 / 120)
		end
		t.near(slow.position[1], fast.position[1], 1e-6)
		-- dt 0 changes nothing.
		local same = PetsLogic.followStep(fast, target, 0)
		t.deepEqual(same, fast)
	end,
	["follow: speed limit, teleport when far, and facing"] = function()
		local state = PetsLogic.newFollowState({ 0, 0, 0 })
		local target = { 40, 0, 0 }
		for _ = 1, 30 do
			local before = state.position[1]
			state = PetsLogic.followStep(state, target, 1 / 60, { maxSpeed = 12 })
			t.truthy(state.position[1] - before <= 12 / 60 + 1e-9, "speed limit")
		end
		t.truthy(state.position[1] > 2 and state.position[1] <= 6 + 1e-9)

		local moved, teleported = PetsLogic.followStep(state, { 500, 20, 0 }, 1 / 60, { faceYaw = 45 })
		t.truthy(teleported)
		t.deepEqual(moved.position, { 500, 20, 0 })
		t.deepEqual(moved.velocity, { 0, 0, 0 })
		t.equal(moved.yaw, 45)
		local _, near = PetsLogic.followStep(state, { 45, 0, 0 }, 1 / 60)
		t.falsy(near)
		local _, custom = PetsLogic.followStep(state, { 45, 0, 0 }, 1 / 60, { teleportDistance = 10 })
		t.truthy(custom)

		-- Moving toward +x means facing yaw -90 (Roblox looks down -z at yaw 0).
		local runner = PetsLogic.newFollowState({ 0, 0, 0 }, 0)
		for _ = 1, 40 do
			runner = PetsLogic.followStep(runner, { 30, 0, 0 }, 1 / 60)
		end
		t.near(runner.yaw, -90, 1)
		-- Standing still it turns to the owner's facing, the short way round.
		local idle = PetsLogic.newFollowState({ 0, 0, 0 }, 170)
		for _ = 1, 120 do
			idle = PetsLogic.followStep(idle, { 0, 0, 0 }, 1 / 60, { faceYaw = -170 })
		end
		t.near(PetsLogic.angleDelta(idle.yaw, -170), 0, 0.01)
		t.truthy(idle.yaw > 170, "turned through 180, not back through 0")
		t.equal(PetsLogic.angleDelta(350, 10), 20)
		t.equal(PetsLogic.angleDelta(10, 350), -20)
		t.equal(PetsLogic.angleDelta(0, 180), -180)
	end,
	["follow: walk bob grows with speed and is zero when standing"] = function()
		t.equal(PetsLogic.walkBob(0, 0.3, 1), 0)
		local slow, fast = 0, 0
		for i = 0, 100 do
			slow = math.max(slow, PetsLogic.walkBob(2, i / 100, 1))
			fast = math.max(fast, PetsLogic.walkBob(8, i / 100, 1))
			t.truthy(PetsLogic.walkBob(8, i / 100, 1) >= 0)
		end
		t.near(fast, 0.22, 1e-3)
		t.near(slow, 0.055, 1e-3)
		t.near(PetsLogic.walkBob(100, 0.15625, 2), 0.44, 1e-6) -- capped at full speed
	end,
	["ground: height, hover and tilt from the normal"] = function()
		local flat = PetsLogic.groundAlign(10, { 0, 1, 0 }, { pivotHeight = 1.5 })
		t.deepEqual(flat, { y = 11.5, pitch = 0, roll = 0, grounded = true })
		-- No ground found: stay level at the fallback height.
		local air = PetsLogic.groundAlign(nil, nil, { fallbackY = 7, hover = 2 })
		t.deepEqual(air, { y = 9, pitch = 0, roll = 0, grounded = false })
		-- Flying pets hover above the ground and never tilt.
		local flying = PetsLogic.groundAlign(10, { 0.5, 0.8, 0 }, { pivotHeight = 1, hover = 3 })
		t.deepEqual(flying, { y = 14, pitch = 0, roll = 0, grounded = true })

		-- A slope rising toward -z (the pet's forward at yaw 0) has a normal leaning to +z: nose up.
		local slope = math.rad(20)
		local uphill = PetsLogic.groundAlign(0, { 0, math.cos(slope), math.sin(slope) }, { yaw = 0 })
		t.near(uphill.pitch, 20, 1e-6)
		t.near(uphill.roll, 0, 1e-6)
		-- The same slope seen by a pet facing +x (yaw -90) is a sideways tilt.
		local sideways = PetsLogic.groundAlign(0, { 0, math.cos(slope), math.sin(slope) }, { yaw = -90 })
		t.near(sideways.pitch, 0, 1e-6)
		t.near(math.abs(sideways.roll), 20, 1e-6)
		-- Facing downhill pitches the nose down.
		local downhill = PetsLogic.groundAlign(0, { 0, math.cos(slope), math.sin(slope) }, { yaw = 180 })
		t.near(downhill.pitch, -20, 1e-6)
		-- Steep ground is clamped.
		local steep = PetsLogic.groundAlign(0, { 0, 0.3, 0.95 }, { yaw = 0 })
		t.equal(steep.pitch, 25)
		t.equal(PetsLogic.groundAlign(0, { 0, 0.3, 0.95 }, { yaw = 0, maxTilt = 10 }).pitch, 10)
	end,
	["ground: samples are cached and refreshed on a schedule or after moving"] = function()
		t.truthy(PetsLogic.groundStale(nil, 0, 0, 0))
		local cache: PetsLogic.GroundCache = { x = 0, z = 0, time = 10 }
		t.falsy(PetsLogic.groundStale(cache, 0.5, 0.5, 10.1))
		t.truthy(PetsLogic.groundStale(cache, 0, 0, 10.4))
		t.truthy(PetsLogic.groundStale(cache, 2.5, 0, 10.1))
		t.falsy(PetsLogic.groundStale(cache, 2.5, 0, 10.1, 1, 5))
		t.truthy(PetsLogic.groundStale(cache, 0, 0, 11, 1, 5))
	end,
	["scheduler: buckets cover every pet exactly once per cycle"] = function()
		t.equal(PetsLogic.buckets(20, 0, 60), 1) -- every frame
		t.equal(PetsLogic.buckets(20, 20, 60), 3)
		t.equal(PetsLogic.buckets(20, 30, 60), 2)
		t.equal(PetsLogic.buckets(1, 20, 60), 1)
		t.equal(PetsLogic.buckets(2, 20, 60), 2) -- never more buckets than pets
		t.equal(PetsLogic.buckets(100, 0, 60), 5) -- many pets are spread even at full rate
		t.equal(PetsLogic.buckets(100, 0, 60, 10), 10)
		t.equal(PetsLogic.buckets(0, 20, 60), 1)
		for _, count in { 1, 2, 5, 20, 37, 64 } do
			for _, hz in { 0, 20, 30 } do
				local buckets = PetsLogic.buckets(count, hz, 60)
				local updates: { [number]: number } = {}
				local perFrame: { number } = {}
				for frame = 0, buckets - 1 do
					perFrame[frame + 1] = 0
					for index = 1, count do
						if PetsLogic.isDue(index, frame, buckets) then
							updates[index] = (updates[index] or 0) + 1
							perFrame[frame + 1] += 1
							t.equal(PetsLogic.bucketOf(index, buckets), frame)
						end
					end
				end
				for index = 1, count do
					t.equal(updates[index], 1, "every pet updates once per cycle")
				end
				for _, n in perFrame do
					t.truthy(n <= math.ceil(count / buckets), "work is spread evenly")
				end
			end
		end
	end,
	["plans: every timeline is valid and names the contract's VFX ids"] = function()
		local vfx: { [string]: string } = {
			Spawn = "PetSpawn",
			Despawn = "PetDespawn",
			Equip = "PetEquip",
			Unequip = "PetUnequip",
			Evolve = "PetEvolve",
			Upgrade = "PetUpgrade",
		}
		t.equal(#PetsLogic.PLANS, 6)
		for _, id in PetsLogic.PLANS do
			local plan = PetsLogic.plan(id) :: PetsLogic.Plan
			t.truthy(plan, id)
			t.deepEqual(PetsLogic.validatePlan(plan), {}, id)
			local found = false
			local animated = false
			for _, step in plan.steps do
				found = found or (step.kind == "vfx" and step.id == vfx[id])
				animated = animated or step.kind == "object" or step.kind == "reaction"
				t.truthy(step.at >= 0 and step.at <= plan.duration, id)
			end
			t.truthy(found, id .. " plays " .. vfx[id])
			t.truthy(animated, id .. " animates the model")
		end
		-- Evolve builds up before the burst (anticipation).
		local evolve = PetsLogic.plan("Evolve") :: PetsLogic.Plan
		t.equal(evolve.steps[1].kind, "object")
		t.equal(evolve.steps[1].id, "Shake")
		t.equal(PetsLogic.plan("Nope"), nil)
		local broken: any = {
			duration = 1,
			steps = {
				{ at = 0.5, kind = "vfx" },
				{ at = 0.2, kind = "object", id = "Float" },
				{ at = 3, kind = "reaction", id = "Nope" },
				{ at = 3, kind = "dance" },
			},
		}
		t.truthy(#PetsLogic.validatePlan(broken) >= 5)
	end,
	["registry: the contract's ten pet presets with valid metadata"] = function()
		local registry = PetsLogic.registry
		t.equal(registry.kind, "pet")
		t.equal(registry:count(), 10)
		t.deepEqual(
			registry:ids({ category = "reaction" }),
			{ "CuriousReaction", "HappyReaction", "HoverReaction", "SelectBounce" }
		)
		t.deepEqual(
			registry:ids({ category = "timeline" }),
			{ "Despawn", "Equip", "Evolve", "Spawn", "Unequip", "Upgrade" }
		)
		for _, preset in registry:list() do
			t.deepEqual(Registry.validate(preset), {}, preset.id)
			t.truthy(preset.usage and string.find(preset.usage, preset.id, 1, true), preset.id)
			if preset.data.kind == "timeline" then
				t.truthy(#(preset.dependencies or {}) >= 1, preset.id)
				t.deepEqual(PetsLogic.validatePlan(preset.data.plan), {}, preset.id)
			else
				t.equal(preset.data.duration, PetsLogic.reactionDuration(preset.id))
			end
		end
		t.equal(registry:search("happy")[1], "HappyReaction")
	end,
}
