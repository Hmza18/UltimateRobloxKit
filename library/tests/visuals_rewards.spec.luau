--!strict
local RewardsLogic = require("../src/Visuals/Rewards/RewardsLogic")
local t = require("./lib/t")

local ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

local function kinds(plan: RewardsLogic.Plan, kind: string): { RewardsLogic.Step }
	local found: { RewardsLogic.Step } = {}
	for _, step in plan.steps do
		if step.kind == kind then
			table.insert(found, step)
		end
	end
	return found
end

local function fresh()
	RewardsLogic.reset()
end

return {
	["all seven built-in rarities validate"] = function()
		fresh()
		t.deepEqual(RewardsLogic.list(), ORDER)
		for index, id in ORDER do
			local profile = RewardsLogic.get(id)
			local ok, message = RewardsLogic.validate(profile)
			t.truthy(ok, id .. ": " .. tostring(message))
			t.equal(profile.rank, index, id)
			t.equal(profile.id, id)
		end
	end,
	["hierarchy is monotonic in duration, particles, layers, anticipation and hold"] = function()
		fresh()
		for index = 2, #ORDER do
			local low, high = RewardsLogic.get(ORDER[index - 1]), RewardsLogic.get(ORDER[index])
			t.truthy(high.duration > low.duration, high.id .. " duration")
			t.truthy(high.particles > low.particles, high.id .. " particles")
			t.truthy(high.layers > low.layers, high.id .. " layers")
			t.truthy(high.anticipation > low.anticipation, high.id .. " anticipation")
			t.truthy(high.hold >= low.hold, high.id .. " hold")
			t.truthy(high.scalePunch >= low.scalePunch, high.id .. " punch")
			t.truthy(#high.vfx >= #low.vfx, high.id .. " vfx")
		end
		t.equal(RewardsLogic.get("Common").anticipation, 0)
		t.near(RewardsLogic.get("Common").duration, 1.2)
		t.near(RewardsLogic.get("Mythic").duration, 3.5)
	end,
	["every rarity has a distinct identity"] = function()
		fresh()
		local seen: { [string]: string } = {}
		local colors: { [string]: string } = {}
		local styles: { [string]: string } = {}
		for _, id in ORDER do
			local p = RewardsLogic.get(id)
			local key = p.color .. "|" .. p.revealStyle .. "|" .. p.background
			t.equal(seen[key], nil, id .. " shares an identity with " .. tostring(seen[key]))
			seen[key] = id
			t.equal(colors[p.color], nil, id .. " colour")
			colors[p.color] = id
			t.equal(styles[p.revealStyle], nil, id .. " reveal style")
			styles[p.revealStyle] = id
		end
	end,
	["no flash below Epic, one soft flash from Epic, soft shakes only"] = function()
		fresh()
		for _, id in ORDER do
			local profile = RewardsLogic.get(id)
			local plan = RewardsLogic.plan(id, { name = "X" })
			if profile.rank < 4 then
				t.equal(profile.flash, "none", id)
				t.equal(plan.flashes, 0, id)
				t.equal(profile.camera.shake, nil, id)
			else
				t.equal(profile.flash, "soft", id)
				t.equal(plan.flashes, 1, id)
				t.equal(#kinds(plan, "flash"), 1, id)
			end
			for _, step in kinds(plan, "shake") do
				t.truthy(table.find(RewardsLogic.SOFT_SHAKES, step.payload.preset), id .. " shake preset")
			end
			t.truthy(#kinds(plan, "shake") <= 2, id .. " shake count")
		end
	end,
	["vfx ids come from the contract"] = function()
		fresh()
		local allowed =
			{ "SparkleBurst", "RewardGlow", "RarityBurst", "RarityBeam", "Confetti", "Fireworks", "GoldenShine" }
		for _, id in ORDER do
			for _, entry in RewardsLogic.get(id).vfx do
				t.truthy(table.find(allowed, entry.id), id .. " uses " .. entry.id)
			end
		end
	end,
	["plan steps are ordered and timed from the profile"] = function()
		fresh()
		for _, id in ORDER do
			local profile = RewardsLogic.get(id)
			local plan = RewardsLogic.plan(id, { name = "Dragon", amount = 500 })
			local last = 0
			for _, step in plan.steps do
				t.truthy(step.time >= last, id .. " ordered")
				t.truthy(step.time <= plan.settledAt + 1e-9, id .. " inside the timed part")
				last = step.time
			end
			t.equal(plan.steps[1].kind, "open")
			t.equal(plan.steps[#plan.steps].kind, "settle")
			t.near(plan.revealAt, profile.anticipation, 1e-9, id)
			t.near(plan.settledAt, profile.duration, 1e-9, id)
			t.near(plan.dismissAt, profile.duration + profile.hold, 1e-9, id)
			t.truthy(plan.hintAt > plan.settledAt and plan.hintAt < plan.dismissAt, id .. " hint")
			t.near(plan.duration, plan.dismissAt + plan.dismissDuration, 1e-9)
			t.equal(#kinds(plan, "reveal"), 1)
			t.near(kinds(plan, "reveal")[1].time, plan.revealAt, 1e-9)
			t.equal(#kinds(plan, "label"), 1)
			t.equal(#kinds(plan, "count"), 1)
			t.equal(#kinds(plan, "anticipate"), if profile.anticipation > 0 then 1 else 0, id)
			t.equal(#kinds(plan, "vfx"), #profile.vfx, id)
			local settled, total = RewardsLogic.durations(id, { name = "Dragon", amount = 500 })
			t.near(settled, plan.settledAt)
			t.near(total, plan.duration)
		end
		t.equal(#kinds(RewardsLogic.plan("Rare", { name = "X" }), "count"), 0, "no amount, no counter")
	end,
	["rarity params and colours reach the vfx steps"] = function()
		fresh()
		local plan = RewardsLogic.plan("Legendary", { name = "X" })
		local burst: RewardsLogic.Step? = nil
		for _, step in kinds(plan, "vfx") do
			if step.payload.id == "RarityBurst" then
				burst = step
			end
		end
		assert(burst, "RarityBurst step")
		t.equal(burst.payload.params.rarity, "Legendary")
		t.equal(burst.payload.params.color, "#FFC02E")
		t.near(burst.payload.params.intensity, 1.15)
	end,
	["skipAnticipation, speed and compact"] = function()
		fresh()
		local base = RewardsLogic.plan("Mythic", { name = "X" })
		local skipped = RewardsLogic.plan("Mythic", { name = "X" }, { skipAnticipation = true })
		t.equal(skipped.revealAt, 0)
		t.equal(#kinds(skipped, "anticipate"), 0)
		t.near(skipped.settledAt, base.settledAt - base.revealAt, 1e-9)

		local fast = RewardsLogic.plan("Mythic", { name = "X" }, { speed = 2 })
		t.near(fast.settledAt, base.settledAt / 2, 1e-9)
		t.near(fast.revealAt, base.revealAt / 2, 1e-9)
		t.near(fast.duration, base.duration / 2, 1e-9)
		t.equal(#fast.steps, #base.steps)
		t.near(RewardsLogic.plan("Mythic", {}, { speed = -1 }).settledAt, base.settledAt, 1e-9, "bad speed ignored")

		local compact = RewardsLogic.plan("Mythic", { name = "X" }, { compact = true })
		t.equal(compact.revealAt, 0)
		t.truthy(compact.settledAt < base.settledAt / 2)
		t.equal(#kinds(compact, "shake"), 0)
		t.equal(#kinds(compact, "camera"), 0)
		t.truthy(#kinds(compact, "vfx") <= 2)
		t.equal(kinds(compact, "open")[1].payload.rayCount, 0)
		t.equal(#kinds(compact, "reveal"), 1)
	end,
	["reducedFlashing removes flashes"] = function()
		fresh()
		for _, id in ORDER do
			local plan = RewardsLogic.plan(id, { name = "X" }, { reducedFlashing = true })
			t.equal(plan.flashes, 0, id)
			t.equal(#kinds(plan, "flash"), 0, id)
			t.equal(#kinds(plan, "reveal"), 1, id)
		end
	end,
	["reducedMotion removes shakes and camera moves and shortens"] = function()
		fresh()
		for _, id in ORDER do
			local base = RewardsLogic.plan(id, { name = "X" })
			local plan = RewardsLogic.plan(id, { name = "X" }, { reducedMotion = true })
			t.equal(#kinds(plan, "shake"), 0, id)
			t.equal(#kinds(plan, "camera"), 0, id)
			t.truthy(plan.settledAt < base.settledAt, id .. " shorter")
			t.equal(kinds(plan, "reveal")[1].payload.punch, 0, id)
			t.equal(kinds(plan, "open")[1].payload.raySpeed, 0, id)
		end
	end,
	["low quality drops optional layers and halves rays"] = function()
		fresh()
		local base = RewardsLogic.plan("Legendary", { name = "X" })
		local low = RewardsLogic.plan("Legendary", { name = "X" }, { quality = "Low" })
		t.equal(#kinds(low, "vfx"), #kinds(base, "vfx") - 1)
		t.equal(kinds(low, "open")[1].payload.rayCount, 6)
	end,
	["essential steps survive a skip"] = function()
		fresh()
		local plan = RewardsLogic.plan("Secret", { name = "X", amount = 10 })
		local names: { string } = {}
		for _, step in RewardsLogic.essential(plan) do
			table.insert(names, step.kind)
		end
		t.deepEqual(names, { "open", "reveal", "label", "count", "settle" })
	end,
	["comparison, sorting and fallbacks"] = function()
		fresh()
		t.truthy(RewardsLogic.compare("Rare", "Epic") < 0)
		t.equal(RewardsLogic.compare("Epic", "Epic"), 0)
		t.truthy(RewardsLogic.compare("Secret", "Mythic") > 0)
		t.truthy(RewardsLogic.atLeast("Legendary", "Epic"))
		t.falsy(RewardsLogic.atLeast("Rare", "Epic"))
		t.equal(RewardsLogic.color("Nope"), RewardsLogic.color("Common"))
		t.equal(RewardsLogic.color(nil), "#B8C4D0")
		t.equal(RewardsLogic.rank(42), 1)
		t.equal(RewardsLogic.get("Nope").id, "Common")
		t.equal(RewardsLogic.plan("Nope", {}).rarity, "Common")
		t.deepEqual(
			RewardsLogic.sort({ "Epic", "Common", "Secret", "Rare", "Common" }),
			{ "Common", "Common", "Rare", "Epic", "Secret" }
		)
		local sorted =
			RewardsLogic.sort({ { rarity = "Mythic", n = 1 }, { rarity = "Rare", n = 2 }, { rarity = "Rare", n = 3 } })
		t.equal(sorted[1].n, 2)
		t.equal(sorted[2].n, 3)
		t.equal(sorted[3].n, 1)
		t.equal(RewardsLogic.countDuration(nil), 0)
		t.near(RewardsLogic.countDuration(10), 0.6)
		t.near(RewardsLogic.countDuration(1e9), 1.2)
	end,
	["batch sorts rarest last, groups low rarities and reveals the rest fully"] = function()
		fresh()
		local batch = RewardsLogic.planBatch({
			{ rarity = "Legendary", reward = { name = "L" } },
			{ rarity = "Common", reward = { name = "C1" } },
			{ rarity = "Rare", name = "R1" },
			{ rarity = "Common", reward = { name = "C2" } },
			{ rarity = "Epic", reward = { name = "E" } },
			{ rarity = "Common", reward = { name = "C3" } },
			{ rarity = "Unknown", reward = { name = "U" } },
		})
		t.equal(#batch.items, 7)
		for index = 2, #batch.items do
			t.truthy(batch.items[index].rank >= batch.items[index - 1].rank)
		end
		t.equal(batch.items[#batch.items].rarity, "Legendary")
		t.equal(batch.items[3].reward.name, "C3", "stable within a rarity")
		t.equal(batch.items[4].rarity, "Common", "unknown rarity falls back")
		t.equal(#batch.groups, 4)
		local grid = batch.groups[1]
		t.equal(grid.kind, "grid")
		t.equal(grid.rarity, "Common")
		t.equal(#grid.items, 4)
		t.equal(grid.columns, 2)
		t.equal(grid.rows, 2)
		t.truthy(grid.stagger >= 0.03 and grid.stagger <= 0.08)
		t.equal(batch.groups[2].kind, "grid")
		t.equal(batch.groups[2].rarity, "Rare")
		t.equal(batch.groups[2].items[1].reward.name, "R1")
		t.equal(batch.groups[3].kind, "full")
		t.equal(batch.groups[3].rarity, "Epic")
		t.truthy(batch.groups[3].plan)
		t.equal(batch.groups[4].rarity, "Legendary")
		local cursor = 0
		for _, group in batch.groups do
			t.near(group.startAt, cursor, 1e-9)
			cursor += group.duration
		end
		t.near(batch.duration, cursor, 1e-9)
	end,
	["batch threshold decides who gets the full treatment"] = function()
		fresh()
		local rewards = { { rarity = "Rare" }, { rarity = "Epic" }, { rarity = "Legendary" } }
		local high = RewardsLogic.planBatch(rewards, { threshold = "Legendary" })
		t.equal(high.groups[1].kind, "grid")
		t.equal(high.groups[2].kind, "grid")
		t.equal(high.groups[3].kind, "full")
		local all = RewardsLogic.planBatch(rewards, { threshold = "Common" })
		for _, group in all.groups do
			t.equal(group.kind, "full")
		end
		t.equal(#RewardsLogic.planBatch({}).groups, 0)
		t.equal(RewardsLogic.planBatch({}).duration, 0)
	end,
	["a big grid stays quick"] = function()
		fresh()
		local rewards: { any } = {}
		for _ = 1, 40 do
			table.insert(rewards, { rarity = "Common" })
		end
		local batch = RewardsLogic.planBatch(rewards)
		t.equal(#batch.groups, 1)
		t.equal(batch.groups[1].columns, 6)
		t.equal(batch.groups[1].rows, 7)
		t.truthy(batch.duration < 2.2, "40 tiles in about two seconds")
	end,
	["fast-forward compresses time and drops cosmetic steps"] = function()
		fresh()
		local rewards = { { rarity = "Common" }, { rarity = "Common" }, { rarity = "Mythic", reward = { name = "M" } } }
		local normal = RewardsLogic.planBatch(rewards)
		local fast = RewardsLogic.planBatch(rewards, { fastForward = true })
		t.equal(fast.fastForward, 3)
		t.equal(normal.fastForward, 1)
		t.truthy(fast.duration < normal.duration / 3 + 1e-9)
		local plan = fast.groups[2].plan
		assert(plan, "full plan")
		for _, step in plan.steps do
			t.truthy(step.kind ~= "vfx" and step.kind ~= "flash" and step.kind ~= "shake", step.kind)
		end
		t.equal(#kinds(plan, "reveal"), 1)
		t.equal(RewardsLogic.planBatch(rewards, { fastForward = 5 }).fastForward, 5)
		t.near(fast.groups[1].stagger, normal.groups[1].stagger / 3, 1e-9)
	end,
	["custom rarities register, extend a base and sort by rank"] = function()
		fresh()
		local profile = RewardsLogic.register("Divine", { extends = "Mythic", rank = 6.5, color = "#7DF9FF" })
		t.equal(profile.id, "Divine")
		t.equal(profile.label, "DIVINE")
		t.equal(profile.revealStyle, "shatter")
		t.equal(profile.color, "#7DF9FF")
		t.truthy(RewardsLogic.has("Divine"))
		t.deepEqual(
			RewardsLogic.list(),
			{ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Secret" }
		)
		t.truthy(RewardsLogic.compare("Divine", "Mythic") > 0)
		t.truthy(RewardsLogic.compare("Divine", "Secret") < 0)
		t.equal(RewardsLogic.plan("Divine", {}).rarity, "Divine")
		-- A stored profile cannot be changed through a returned copy.
		profile.color = "#000000"
		t.equal(RewardsLogic.color("Divine"), "#7DF9FF")
		local basic = RewardsLogic.register("Starter", { rank = 0 })
		t.equal(basic.revealStyle, "pop")
		t.equal(RewardsLogic.list()[1], "Starter")
		RewardsLogic.register("Rare", { override = true, label = "RARE!" })
		t.equal(RewardsLogic.label("Rare"), "RARE!")
		t.equal(#RewardsLogic.list(), 9)
		fresh()
		t.falsy(RewardsLogic.has("Divine"))
		t.equal(RewardsLogic.label("Rare"), "RARE")
	end,
	["invalid registrations raise"] = function()
		fresh()
		t.throws(function()
			RewardsLogic.register("", {})
		end, "empty id")
		t.throws(function()
			RewardsLogic.register("Rare", { label = "x" })
		end, "built-in without override")
		t.throws(function()
			RewardsLogic.register("A", { extends = "Nope" })
		end, "unknown base")
		t.throws(function()
			RewardsLogic.register("A", { color = "red" })
		end, "bad colour")
		t.throws(function()
			RewardsLogic.register("A", { revealStyle = "explode" })
		end, "bad style")
		t.throws(function()
			RewardsLogic.register("A", { background = "video" })
		end, "bad background")
		t.throws(function()
			RewardsLogic.register("A", { flash = "strobe" })
		end, "bad flash")
		t.throws(function()
			RewardsLogic.register("A", { camera = { shake = "Explosion" } })
		end, "hard shake")
		t.throws(function()
			RewardsLogic.register("A", { duration = 1, anticipation = 2 })
		end, "anticipation longer than duration")
		t.throws(function()
			RewardsLogic.register("A", { vfx = { { at = 1 } } })
		end, "vfx without id")
		t.throws(function()
			(RewardsLogic.register :: any)("A", "Epic")
		end, "not a table")
		t.falsy(RewardsLogic.has("A"))
		t.falsy((RewardsLogic.validate(nil)))
	end,
}
