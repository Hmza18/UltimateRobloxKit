--!strict
local HatchLogic = require("../src/Visuals/Eggs/HatchLogic")
local RewardsLogic = require("../src/Visuals/Rewards/RewardsLogic")
local t = require("./lib/t")

local ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

local function eggs(...: string): { any }
	local list: { any } = {}
	for _, rarity in { ... } do
		table.insert(list, { rarity = rarity })
	end
	return list
end

local function many(count: number, rarity: string): { any }
	local list: { any } = {}
	for _ = 1, count do
		table.insert(list, { rarity = rarity })
	end
	return list
end

local function kinds(plan: HatchLogic.Plan, kind: string): { HatchLogic.Step }
	local found: { HatchLogic.Step } = {}
	for _, step in plan.steps do
		if step.kind == kind then
			table.insert(found, step)
		end
	end
	return found
end

local function peak(egg: HatchLogic.EggPlan, from: number, to: number): number
	local best = 0
	local steps = 400
	for i = 0, steps do
		best = math.max(best, math.abs(HatchLogic.wobble(egg, from + (to - from) * i / steps)))
	end
	return best
end

local function checkLayout(count: number, aspect: number)
	local layout = HatchLogic.layout(count, aspect)
	local label = string.format("%d eggs at %.2f", count, aspect)
	t.equal(#layout.slots, count, label)
	for i, slot in layout.slots do
		t.truthy(slot.size > 0.02, label .. " size")
		t.truthy(math.abs(slot.x) + slot.size / 2 <= aspect / 2 + 1e-9, label .. " fits horizontally")
		t.truthy(math.abs(slot.y) + slot.size / 2 <= 0.5 + 1e-9, label .. " fits vertically")
		for j = i + 1, count do
			local other = layout.slots[j]
			local gap = (slot.size + other.size) / 2 - 1e-9
			t.truthy(
				math.abs(slot.x - other.x) >= gap or math.abs(slot.y - other.y) >= gap,
				label .. " slots " .. i .. " and " .. j .. " overlap"
			)
		end
	end
	return layout
end

return {
	["every rarity has all eleven beats in order"] = function()
		RewardsLogic.reset()
		for _, rarity in ORDER do
			local plan = HatchLogic.plan(eggs(rarity))
			t.equal(#plan.beats, 11, rarity)
			local last = -1
			for index, beat in plan.beats do
				t.equal(beat.index, index)
				t.equal(beat.name, HatchLogic.BEATS[index])
				t.truthy(beat.start >= last, rarity .. " " .. beat.name .. " starts after the previous beat")
				t.truthy(beat.duration > 0, rarity .. " " .. beat.name .. " has a duration")
				last = beat.start
			end
			-- Up to the crack the beats are back to back.
			for index = 1, 5 do
				t.near(plan.beats[index].start + plan.beats[index].duration, plan.beats[index + 1].start, 1e-9)
			end
			t.near(plan.beats[10].start, plan.resultAt, 1e-9)
			t.near(plan.beats[11].start, plan.finishAt, 1e-9)
			t.near(plan.duration, plan.finishAt + plan.finishDuration, 1e-9)
			local previous = 0
			local seen: { [number]: boolean } = {}
			for _, step in plan.steps do
				t.truthy(step.time >= previous, rarity .. " steps sorted")
				previous = step.time
				seen[step.beat] = true
			end
			for _, beat in { 1, 3, 4, 5, 6, 8, 9, 10, 11 } do
				t.truthy(seen[beat], rarity .. " has a step in beat " .. beat)
			end
			t.equal(plan.mode, "single")
			t.equal(plan.top, rarity)
		end
	end,
	["durations grow with rarity: about 2.2 s for Common up to 5.5 s for Mythic"] = function()
		RewardsLogic.reset()
		local last = 0
		local shakes = 0
		for _, rarity in ORDER do
			local plan = HatchLogic.plan(eggs(rarity))
			t.truthy(plan.resultAt > last, rarity .. " is longer than the rarity below")
			t.truthy(#plan.eggs[1].shakes > shakes, rarity .. " shakes more")
			last = plan.resultAt
			shakes = #plan.eggs[1].shakes
		end
		t.near(HatchLogic.plan(eggs("Common")).resultAt, 2.2, 1e-6)
		t.near(HatchLogic.plan(eggs("Mythic")).resultAt, 5.5, 1e-6)
		t.near(HatchLogic.plan(eggs("Secret")).resultAt, 5.7, 1e-6)
		t.equal(#HatchLogic.plan(eggs("Common")).eggs[1].shakes, 3)
		t.equal(#HatchLogic.plan(eggs("Secret")).eggs[1].shakes, 9)
		t.near(HatchLogic.total(1.5), 2.45)
		t.near(HatchLogic.total(99), 5.7)
	end,
	["speed scales every time"] = function()
		RewardsLogic.reset()
		local base = HatchLogic.plan(eggs("Legendary"))
		local fast = HatchLogic.plan(eggs("Legendary"), { speed = 2 })
		t.near(fast.resultAt, base.resultAt / 2, 1e-9)
		t.near(fast.duration, base.duration / 2, 1e-9)
		t.equal(#fast.steps, #base.steps)
		for index, step in base.steps do
			t.near(fast.steps[index].time, step.time / 2, 1e-9)
		end
		for index, beat in base.beats do
			t.near(fast.beats[index].duration, beat.duration / 2, 1e-9)
		end
		t.near(fast.eggs[1].crackAt, base.eggs[1].crackAt / 2, 1e-9)
		-- The wobble keeps its shape: same angle at the same fraction of the timeline.
		for i = 1, 20 do
			local at = base.eggs[1].crackAt * i / 21
			t.near(HatchLogic.wobble(fast.eggs[1], at / 2), HatchLogic.wobble(base.eggs[1], at), 1e-6)
		end
		t.near(HatchLogic.plan(eggs("Legendary"), { speed = 0 }).resultAt, base.resultAt, 1e-9)
	end,
	["hit-stop only for Epic and above, 60 to 100 ms"] = function()
		RewardsLogic.reset()
		t.equal(HatchLogic.hitStop(1), 0)
		t.equal(HatchLogic.hitStop(3), 0)
		t.near(HatchLogic.hitStop(4), 0.06)
		t.near(HatchLogic.hitStop(5), 0.08)
		t.near(HatchLogic.hitStop(6), 0.1)
		t.near(HatchLogic.hitStop(7), 0.1)
		t.equal(#kinds(HatchLogic.plan(eggs("Rare")), "hitStop"), 0)
		local stops = kinds(HatchLogic.plan(eggs("Epic")), "hitStop")
		t.equal(#stops, 1)
		t.near(stops[1].duration :: number, 0.06)
	end,
	["shakes are synchronised with cues, speed up and end before the crack"] = function()
		RewardsLogic.reset()
		local plan = HatchLogic.plan(eggs("Mythic"))
		local egg = plan.eggs[1]
		local steps = kinds(plan, "shake")
		t.equal(#steps, #egg.shakes)
		local lastGap = math.huge
		for index, step in steps do
			t.near(step.time, egg.shakes[index], 1e-9)
			t.equal(step.payload.cue, "egg.wobble")
			t.equal(step.payload.vfx, "EggShakeDust")
			if index > 1 then
				local gap = step.time - steps[index - 1].time
				t.truthy(gap < lastGap, "gaps shrink")
				t.truthy(step.payload.pitch > steps[index - 1].payload.pitch, "pitch rises")
				lastGap = gap
			end
			t.truthy(step.time >= plan.beats[4].start - 1e-9 and step.time < egg.crackAt)
		end
	end,
	["the wobble grows across the anticipation and ends at zero"] = function()
		RewardsLogic.reset()
		for _, rarity in ORDER do
			local plan = HatchLogic.plan(eggs(rarity))
			local egg = plan.eggs[1]
			t.equal(HatchLogic.wobble(egg, 0), 0, "still before the anticipation")
			t.equal(HatchLogic.wobble(egg, egg.wobbleStart), 0)
			t.equal(HatchLogic.wobble(egg, egg.crackAt), 0, "zero at the crack")
			t.equal(HatchLogic.wobble(egg, egg.crackAt + 1), 0)
			t.near(HatchLogic.wobble(egg, egg.crackAt - 1e-4), 0, 0.2, "eases to zero")
			local span = egg.crackAt - egg.wobbleStart
			local early = peak(egg, egg.wobbleStart, egg.wobbleStart + span * 0.25)
			local middle = peak(egg, egg.wobbleStart + span * 0.25, egg.wobbleStart + span * 0.6)
			local late = peak(egg, egg.wobbleStart + span * 0.6, egg.crackAt)
			t.truthy(early < middle, rarity .. " early < middle")
			t.truthy(middle < late, rarity .. " middle < late")
			t.truthy(late <= egg.amplitude * 1.6, rarity .. " bounded")
			t.truthy(late > egg.amplitude * 0.3, rarity .. " visible")
		end
		local common = HatchLogic.plan(eggs("Common")).eggs[1]
		local secret = HatchLogic.plan(eggs("Secret")).eggs[1]
		t.truthy(secret.amplitude > common.amplitude)
	end,
	["layouts for 1, 3, 8 and 25 eggs fit 16:9 and 9:16 without overlap"] = function()
		for _, count in { 1, 2, 3, 5, 8, 12, 25 } do
			checkLayout(count, 16 / 9)
			checkLayout(count, 9 / 16)
			checkLayout(count, 4 / 3)
		end
		t.equal(checkLayout(1, 16 / 9).kind, "row")
		local three = checkLayout(3, 16 / 9)
		t.equal(three.kind, "arc")
		t.equal(three.columns, 3)
		t.truthy(three.slots[2].y > three.slots[1].y, "the middle of the arc is raised")
		t.near(three.slots[1].y, three.slots[3].y, 1e-9)
		t.near(three.slots[1].x, -three.slots[3].x, 1e-9)
		local tall = checkLayout(3, 9 / 16)
		t.equal(tall.kind, "grid")
		t.equal(tall.columns, 2)
		t.near(tall.slots[3].x, 0, 1e-9, "the last row is centred")
		local grid = checkLayout(25, 16 / 9)
		t.equal(grid.kind, "grid")
		t.truthy(grid.columns > grid.rows, "wide frame, wide grid")
		local portrait = checkLayout(25, 9 / 16)
		t.truthy(portrait.rows >= portrait.columns, "tall frame, no wide grid")
		t.truthy(checkLayout(12, 9 / 16).rows > checkLayout(12, 9 / 16).columns, "tall frame, tall grid")
		t.truthy(checkLayout(1, 16 / 9).slots[1].size > checkLayout(8, 16 / 9).slots[1].size)
	end,
	["multi hatch reveals the rarest last with a 0.12-0.2 s stagger"] = function()
		RewardsLogic.reset()
		local input = eggs("Legendary", "Common", "Rare", "Common", "Secret", "Epic", "Common", "Rare")
		local plan = HatchLogic.plan(input)
		t.equal(plan.mode, "multi")
		t.equal(plan.count, 8)
		t.equal(plan.top, "Secret")
		t.deepEqual(plan.order, { 2, 4, 7, 3, 8, 6, 1, 5 })
		t.truthy(plan.stagger >= 0.12 and plan.stagger <= 0.2)
		local previous: HatchLogic.EggPlan? = nil
		for position, index in plan.order do
			local egg = plan.eggs[index]
			t.equal(egg.index, index)
			t.equal(egg.order, position)
			t.equal(egg.slot, plan.layout.slots[index], "eggs keep their own slot")
			if previous then
				t.truthy(egg.rank >= previous.rank)
				t.near(egg.crackAt - previous.crackAt, plan.stagger, 1e-9)
				t.truthy(egg.appearAt > previous.appearAt)
				t.truthy(egg.wobbleStart > previous.wobbleStart, "wobbles are staggered")
			end
			previous = egg
		end
		local revealed = kinds(plan, "revealed")
		t.equal(#revealed, 8)
		for position, step in revealed do
			t.equal(step.egg, plan.order[position])
		end
		t.equal(revealed[8].payload.rarity, "Secret")
		-- Compact: shorter than the same rarity alone, at most four shakes, one celebration.
		local single = HatchLogic.plan(eggs("Secret"))
		t.truthy(plan.beats[6].start < single.beats[6].start)
		for _, egg in plan.eggs do
			t.truthy(#egg.shakes <= 4)
		end
		local celebrations = 0
		for _, step in kinds(plan, "rarity") do
			if #step.payload.celebrate > 0 then
				celebrations += 1
				t.equal(step.egg, 5)
			end
		end
		t.equal(celebrations, 1)
		t.equal(#kinds(plan, "bloom"), 1, "one bloom for the whole batch")
		for _, count in { 2, 3, 10, 25, 60 } do
			local stagger = HatchLogic.plan(many(count, "Common")).stagger
			t.truthy(stagger >= 0.12 - 1e-9 and stagger <= 0.2 + 1e-9, count .. " eggs")
		end
	end,
	["triple mode"] = function()
		RewardsLogic.reset()
		local plan = HatchLogic.plan(eggs("Rare", "Common", "Rare"))
		t.equal(plan.mode, "triple")
		t.deepEqual(plan.order, { 2, 1, 3 })
		t.equal(plan.layout.kind, "arc")
		t.equal(#kinds(plan, "bloom"), 3)
		t.equal(#kinds(plan, "enter"), 3)
		t.truthy(plan.resultAt < HatchLogic.plan(eggs("Rare")).resultAt + 2 * plan.stagger)
	end,
	["auto mode is about a second, without camera, hold or flashes"] = function()
		RewardsLogic.reset()
		for _, count in { 1, 3, 8 } do
			local plan = HatchLogic.plan(many(count, "Legendary"), { mode = "auto" })
			t.equal(plan.mode, "auto")
			t.equal(#plan.beats, 11)
			t.truthy(plan.duration >= 0.8 and plan.duration <= 1.25, count .. " eggs take " .. plan.duration)
			t.equal(plan.hold, 0)
			t.equal(#kinds(plan, "cameraPush"), 0)
			t.equal(#kinds(plan, "cameraLand"), 0)
			t.equal(#kinds(plan, "bloom"), 0)
			t.equal(#kinds(plan, "hitStop"), 0)
			t.equal(#kinds(plan, "revealed"), count)
			t.truthy(kinds(plan, "result")[1].payload.auto)
			for _, step in kinds(plan, "rarity") do
				t.equal(step.payload.shake, nil)
			end
		end
		local mixed = HatchLogic.plan(eggs("Mythic", "Common"), { mode = "auto" })
		t.deepEqual(mixed.order, { 2, 1 })
	end,
	["the skip plan keeps only what must still happen"] = function()
		RewardsLogic.reset()
		local plan = HatchLogic.plan(eggs("Epic", "Common", "Rare"))
		local names: { string } = {}
		for _, step in HatchLogic.skipSteps(plan) do
			table.insert(names, step.kind .. ":" .. tostring(step.egg))
		end
		t.deepEqual(
			names,
			{ "appear:2", "revealed:2", "appear:3", "revealed:3", "appear:1", "revealed:1", "result:nil" }
		)
		for _, step in plan.steps do
			local essential = step.kind == "appear"
				or step.kind == "revealed"
				or step.kind == "result"
				or step.kind == "finish"
			t.equal(step.essential, essential, step.kind)
		end
		t.equal(plan.steps[#plan.steps].kind, "finish")
	end,
	["reducedMotion: no camera, small wobble, no spin, shorter"] = function()
		RewardsLogic.reset()
		local base = HatchLogic.plan(eggs("Legendary"))
		local plan = HatchLogic.plan(eggs("Legendary"), { reducedMotion = true })
		t.equal(#kinds(base, "cameraPush"), 1)
		t.equal(#kinds(base, "cameraLand"), 1)
		t.equal(kinds(base, "rarity")[1].payload.shake, "SoftImpact")
		t.equal(#kinds(plan, "cameraPush"), 0)
		t.equal(#kinds(plan, "cameraLand"), 0)
		t.equal(kinds(plan, "rarity")[1].payload.shake, nil)
		t.equal(kinds(plan, "appear")[1].payload.spin, 0)
		t.near(plan.eggs[1].amplitude, base.eggs[1].amplitude * 0.3, 1e-9)
		t.truthy(plan.resultAt < base.resultAt)
		t.equal(#kinds(HatchLogic.plan(eggs("Legendary"), { camera = false }), "cameraPush"), 0)
	end,
	["reducedFlashing removes the bloom and nothing else"] = function()
		RewardsLogic.reset()
		local base = HatchLogic.plan(eggs("Mythic"))
		local plan = HatchLogic.plan(eggs("Mythic"), { reducedFlashing = true })
		t.equal(#kinds(base, "bloom"), 1)
		t.equal(kinds(base, "bloom")[1].payload.color, RewardsLogic.get("Mythic").glow)
		t.equal(kinds(HatchLogic.plan(eggs("Common")), "bloom")[1].payload.color, "#FFFFFF")
		t.equal(#kinds(plan, "bloom"), 0)
		t.equal(#plan.steps, #base.steps - 1)
		t.near(plan.resultAt, base.resultAt, 1e-9)
	end,
	["low quality multi hatch drops lights, dust and energy and is shorter"] = function()
		RewardsLogic.reset()
		local input = many(8, "Epic")
		local base = HatchLogic.plan(input)
		local low = HatchLogic.plan(input, { quality = "Low" })
		t.truthy(low.resultAt < base.resultAt)
		t.equal(kinds(base, "energy")[1].payload.light, true)
		t.equal(kinds(low, "energy")[1].payload.light, false)
		t.equal(kinds(low, "energy")[1].payload.vfx, nil)
		for _, step in kinds(low, "rarity") do
			t.equal(step.payload.aura, nil)
		end
	end,
	["result hold and vfx ids"] = function()
		RewardsLogic.reset()
		local plan = HatchLogic.plan(eggs("Rare"), { hold = 4 })
		t.near(plan.finishAt - plan.resultAt, 4, 1e-9)
		t.near(HatchLogic.plan(eggs("Rare")).hold, 2.5)
		t.equal(kinds(plan, "crack")[1].payload.vfx, "EggCrack")
		t.equal(kinds(plan, "crack")[1].payload.flash, "EggFlash")
		t.equal(kinds(plan, "appear")[1].payload.vfx, "HatchBurst")
		t.equal(kinds(plan, "appear")[1].payload.params.rarity, "Rare")
		t.equal(kinds(plan, "energy")[1].payload.vfx, "EggEnergy")
		t.equal(kinds(plan, "rarity")[1].payload.aura, "RarityAura")
		t.equal(kinds(plan, "react")[1].payload.reaction, "HappyReaction")
		t.equal(kinds(plan, "appear")[1].payload.rarityCue, "rarity.rare")
	end,
	["unknown rarities fall back and invalid input raises"] = function()
		RewardsLogic.reset()
		local plan = HatchLogic.plan({ { rarity = "Glitched" }, {} })
		t.equal(plan.eggs[1].rarity, "Common")
		t.equal(plan.eggs[2].rarity, "Common")
		t.throws(function()
			HatchLogic.plan({})
		end)
		t.throws(function()
			HatchLogic.plan({ "Common" })
		end)
		RewardsLogic.register("Divine", { extends = "Mythic", rank = 6.5 })
		local custom = HatchLogic.plan(eggs("Divine", "Secret", "Mythic"))
		t.deepEqual(custom.order, { 3, 1, 2 })
		RewardsLogic.reset()
	end,
	["idle sampler sways and hops in a loop"] = function()
		local rest = HatchLogic.idle(0)
		t.equal(rest.angle, 0)
		t.equal(rest.offset, 0)
		local maxAngle, maxOffset, minSquash, maxSquash = 0, 0, 1, 1
		for i = 0, 2000 do
			local pose = HatchLogic.idle(i * 0.01)
			maxAngle = math.max(maxAngle, math.abs(pose.angle))
			maxOffset = math.max(maxOffset, pose.offset)
			minSquash = math.min(minSquash, pose.squash)
			maxSquash = math.max(maxSquash, pose.squash)
			t.truthy(pose.offset >= 0)
		end
		t.near(maxAngle, 4, 0.01)
		t.near(maxOffset, 0.08, 0.001)
		t.truthy(minSquash < 0.95 and minSquash > 0.9)
		t.truthy(maxSquash > 1.04 and maxSquash < 1.06)
		local cycle = 3.2 + 0.12 + 0.14
		t.near(HatchLogic.idle(1.3).offset, HatchLogic.idle(1.3 + cycle).offset, 1e-9)
		local still = HatchLogic.idle(0.3, { hopEvery = 0, angle = 2, period = 1.2 })
		t.equal(still.offset, 0)
		t.equal(still.squash, 1)
		t.near(still.angle, 2, 1e-9)
		t.near(HatchLogic.idle(0, { phase = 0.6, period = 2.4 }).angle, 4, 1e-9)
	end,
}
