--!strict
-- The pure helpers behind the UltimateVisualsKit demos (library/examples/visuals/DemoLogic.luau):
-- throw arcs, coin scatter, the stress-button tap stream, the simulator numbers and sample data.

local DemoLogic = require("../examples/visuals/DemoLogic")
local RewardsLogic = require("../src/Visuals/Rewards/RewardsLogic")
local t = require("./lib/t")

local vec = DemoLogic.vec

return {
	["an arc starts at the start, ends at the target and peaks at the apex"] = function()
		local start, target = vec(0, 3, 0), vec(12, 1, -8)
		local arc = DemoLogic.arc(start, target, 5)
		t.near(arc.apex, 8, 1e-9, "apex is 5 studs above the higher end")
		t.deepEqual(DemoLogic.arcPoint(arc, 0), start)
		local finish = DemoLogic.arcPoint(arc, arc.flightTime)
		t.near(finish.x, 12, 1e-9)
		t.near(finish.y, 1, 1e-9)
		t.near(finish.z, -8, 1e-9)
		local peak = DemoLogic.arcPoint(arc, arc.peakTime)
		t.near(peak.y, arc.apex, 1e-6, "highest at peakTime")
		-- Nothing on the path is higher than the apex, and the height rises then falls.
		local previous = start.y
		local rising = true
		for step = 1, 200 do
			local point = DemoLogic.arcPoint(arc, arc.flightTime * step / 200)
			t.truthy(point.y <= arc.apex + 1e-6, "never above the apex")
			if point.y < previous - 1e-9 then
				rising = false
			elseif not rising then
				t.truthy(point.y <= previous + 1e-9, "no second rise")
			end
			previous = point.y
		end
		t.falsy(rising, "the throw comes down")
	end,

	["an arc moves at constant horizontal speed"] = function()
		local arc = DemoLogic.arc(vec(-4, 2, 6), vec(10, 2, -2), 3)
		local half = DemoLogic.arcPoint(arc, arc.flightTime / 2)
		t.near(half.x, 3, 1e-9)
		t.near(half.z, 2, 1e-9)
		-- Level ends: the peak is in the middle of the flight.
		t.near(arc.peakTime, arc.flightTime / 2, 1e-9)
		t.near(half.y, arc.apex, 1e-6)
	end,

	["a higher lob takes longer and time is clamped to the flight"] = function()
		local start, target = vec(0, 0, 0), vec(10, 0, 0)
		local low = DemoLogic.arc(start, target, 2)
		local high = DemoLogic.arc(start, target, 8)
		t.truthy(high.flightTime > low.flightTime)
		t.deepEqual(DemoLogic.arcPoint(low, -1), start, "before the throw")
		t.deepEqual(DemoLogic.arcPoint(low, 99), target, "after the landing")
		-- A non-positive apex still clears the ends by a hair instead of dividing by zero.
		local flat = DemoLogic.arc(start, target, 0)
		t.truthy(flat.flightTime > 0)
	end,

	["an arc described by flight time lands on time"] = function()
		local start, target = vec(1, 2, 3), vec(9, 5, -3)
		local arc = DemoLogic.arcForTime(start, target, 0.8)
		t.near(arc.flightTime, 0.8, 1e-9)
		local finish = DemoLogic.arcPoint(arc, 0.8)
		t.near(finish.y, 5, 1e-9)
		local before = DemoLogic.arcPoint(arc, 0.8 - 1e-4)
		t.near(before.y, 5, 0.02, "the path arrives at the target height, not above it")
		t.near(DemoLogic.arcPoint(arc, arc.peakTime).y, arc.apex, 1e-6)
		-- Both descriptions agree: the time of an apex arc reproduces its apex.
		local lob = DemoLogic.arc(start, target, 4)
		local same = DemoLogic.arcForTime(start, target, lob.flightTime)
		t.near(same.apex, lob.apex, 1e-6)
		t.near(same.peakTime, lob.peakTime, 1e-6)
	end,

	["arc velocity points up at the start and down at the end"] = function()
		local arc = DemoLogic.arc(vec(0, 0, 0), vec(6, 0, 0), 3)
		t.truthy(DemoLogic.arcVelocity(arc, 0).y > 0)
		t.near(DemoLogic.arcVelocity(arc, arc.peakTime).y, 0, 1e-6)
		t.truthy(DemoLogic.arcVelocity(arc, arc.flightTime).y < 0)
		t.near(DemoLogic.arcVelocity(arc, 0.1).x, 6 / arc.flightTime, 1e-9)
	end,

	["the wind-up pulls away from the target and eases out"] = function()
		local start, target = vec(0, 3, 0), vec(10, 0, 0)
		t.deepEqual(DemoLogic.windUp(start, target, 0), start)
		local held = DemoLogic.windUp(start, target, 1, 1.2)
		t.near(held.x, -1.2, 1e-9, "pulled back along the throw line")
		t.near(held.z, 0, 1e-9)
		t.truthy(held.y < start.y, "dips")
		local half = DemoLogic.windUp(start, target, 0.5, 1.2)
		t.truthy(half.x < -0.6, "more than half the pull at half time (ease out)")
		-- Throwing straight down has no direction to pull along; it only dips.
		local down = DemoLogic.windUp(start, vec(0, 0, 0), 1)
		t.near(down.x, 0, 1e-9)
	end,

	["scatter stays inside the radius and outside the inner ring"] = function()
		for _, seed in { 1, 2, 77 } do
			local points = DemoLogic.scatter(12, 5, seed)
			t.equal(#points, 12)
			for _, point in points do
				local reach = math.sqrt(point.x * point.x + point.z * point.z)
				t.truthy(reach <= 5 + 1e-9, "inside the radius")
				t.truthy(reach >= 5 * 0.35 - 1e-9, "outside the inner ring")
				t.equal(point.y, 0)
			end
		end
		t.deepEqual(DemoLogic.scatter(6, 4, 9), DemoLogic.scatter(6, 4, 9), "deterministic")
		t.equal(#DemoLogic.scatter(0, 4), 0)
		t.equal(#DemoLogic.scatter(-3, 4), 0)
	end,

	["scatter spreads points around the centre"] = function()
		local points = DemoLogic.scatter(8, 6, 3)
		local sumX, sumZ = 0, 0
		for index, point in points do
			sumX += point.x
			sumZ += point.z
			for other = index + 1, #points do
				t.truthy(DemoLogic.distance(point, points[other]) > 0.2, "no two coins stack")
			end
		end
		t.truthy(math.abs(sumX / 8) < 3 and math.abs(sumZ / 8) < 3, "roughly centred")
	end,

	["the tap stream produces the asked rate"] = function()
		local tapper = DemoLogic.newTapper(20)
		local total = 0
		for _ = 1, 600 do -- 10 s at 60 fps
			total += DemoLogic.tapsDue(tapper, 1 / 60)
		end
		t.truthy(total >= 199 and total <= 200, "20 taps per second for 10 s, got " .. total)
		t.equal(DemoLogic.tapsDue(DemoLogic.newTapper(0), 1), 0, "rate 0 never taps")
		t.equal(DemoLogic.tapsDue(tapper, 0), 0)
		t.equal(DemoLogic.tapsDue(tapper, -1), 0)
	end,

	["the tap stream caps a long frame and does not catch up"] = function()
		local tapper = DemoLogic.newTapper(20, 4)
		t.equal(DemoLogic.tapsDue(tapper, 2), 4, "a 2 s hitch gives 4 taps, not 40")
		t.equal(DemoLogic.tapsDue(tapper, 1 / 60), 0, "the backlog was dropped")
		local total = 0
		for _ = 1, 60 do
			total += DemoLogic.tapsDue(tapper, 1 / 60)
		end
		t.truthy(total >= 19 and total <= 20, "back to the steady rate")
	end,

	["simulator numbers grow with upgrades and roll levels over"] = function()
		t.equal(DemoLogic.tapValue(0), 1)
		t.equal(DemoLogic.tapValue(3), 4)
		t.equal(DemoLogic.tapValue(3, 2), 12)
		t.truthy(DemoLogic.upgradeCost(1) > DemoLogic.upgradeCost(0))
		t.truthy(DemoLogic.upgradeCost(5) > DemoLogic.upgradeCost(4))
		t.equal(DemoLogic.xpForLevel(1), 20)
		local same = DemoLogic.gainXp(1, 5, 10)
		t.deepEqual(same, { level = 1, xp = 15, max = 20, levelsGained = 0 })
		local up = DemoLogic.gainXp(1, 15, 10)
		t.equal(up.level, 2)
		t.equal(up.xp, 5)
		t.equal(up.max, DemoLogic.xpForLevel(2))
		t.equal(up.levelsGained, 1)
		local many = DemoLogic.gainXp(1, 0, 20 + 35 + 50 + 3)
		t.equal(many.level, 4)
		t.equal(many.xp, 3)
		t.equal(many.levelsGained, 3)
	end,

	["demo pets are four original entries with valid rarities"] = function()
		local pets = DemoLogic.pets()
		t.equal(#pets, 4)
		local ids: { [string]: boolean } = {}
		for _, pet in pets do
			t.falsy(ids[pet.id], "unique id " .. pet.id)
			ids[pet.id] = true
			t.truthy(RewardsLogic.has(pet.rarity), pet.id .. " rarity " .. pet.rarity)
			t.truthy(string.match(pet.color, "^#%x%x%x%x%x%x$") ~= nil, pet.id .. " colour")
			t.truthy(#pet.description > 10 and #pet.name > 0)
			t.equal(#pet.stats, 3)
			t.equal(DemoLogic.pet(pet.id), pet)
		end
		t.equal(DemoLogic.pet("nobody"), nil)
		-- pets() hands out a copy of the list.
		table.remove(pets, 1)
		t.equal(#DemoLogic.pets(), 4)
	end,

	["rarity sample data covers every built-in rarity"] = function()
		t.deepEqual(table.clone(DemoLogic.RARITIES), table.clone(RewardsLogic.ORDER))
		for _, rarity in DemoLogic.RARITIES do
			t.truthy(string.match(DemoLogic.rarityColor(rarity), "^#%x%x%x%x%x%x$") ~= nil, rarity)
			t.truthy(#DemoLogic.petName(rarity, 1) > 0)
			t.truthy(#DemoLogic.petName(rarity, 99) > 0, "any index wraps")
		end
		t.equal(DemoLogic.rarityColor("Nope"), DemoLogic.rarityColor("Common"))
		t.equal(DemoLogic.petName("Nope"), DemoLogic.petName("Common"))
	end,

	["the custom rarity registers with Rewards"] = function()
		RewardsLogic.reset()
		local custom = DemoLogic.CUSTOM_RARITY
		local ok, err = pcall(function()
			local profile = RewardsLogic.register(custom.id, table.clone(custom.profile) :: any)
			t.equal(profile.label, "STARDUST")
			t.truthy(RewardsLogic.has(custom.id))
			t.truthy(RewardsLogic.atLeast(custom.id, "Legendary"))
			t.falsy(RewardsLogic.atLeast(custom.id, "Mythic"))
			local plan = RewardsLogic.plan(custom.id, { name = "Star Shard", amount = 3 })
			t.truthy(plan.duration > 0)
		end)
		RewardsLogic.reset()
		t.truthy(ok, tostring(err))
	end,

	["egg batches use the asked rarity or the stand-in roll"] = function()
		local eggs = DemoLogic.eggBatch(3, "Rare", 4)
		t.equal(#eggs, 3)
		for _, egg in eggs do
			t.equal(egg.rarity, "Rare")
			t.truthy(#egg.name > 0)
			t.equal(type(egg.isNew), "boolean")
		end
		local rolled = DemoLogic.eggBatch(8, nil, 11)
		t.equal(#rolled, 8)
		for _, egg in rolled do
			t.truthy(RewardsLogic.has(egg.rarity), egg.rarity)
		end
		t.deepEqual(DemoLogic.eggBatch(8, nil, 11), rolled, "deterministic for a seed")
		t.equal(#DemoLogic.eggBatch(0, "Common"), 1, "at least one egg")
	end,

	["the stand-in roll is weighted toward low tiers"] = function()
		local counts: { [string]: number } = {}
		for n = 1, 2000 do
			local rarity = DemoLogic.fakeRoll(3, n)
			counts[rarity] = (counts[rarity] or 0) + 1
		end
		t.truthy((counts.Common or 0) > (counts.Rare or 0))
		t.truthy((counts.Rare or 0) > (counts.Legendary or 0))
		t.truthy((counts.Common or 0) > 800 and (counts.Common or 0) < 1200)
		for rarity in counts do
			t.truthy(RewardsLogic.has(rarity), rarity)
		end
	end,

	["mixed rewards are six entries that plan as a batch"] = function()
		local rewards = DemoLogic.mixedRewards()
		t.equal(#rewards, 6)
		for _, reward in rewards do
			t.truthy(RewardsLogic.has(reward.rarity), reward.rarity)
			t.truthy(reward.amount >= 1)
		end
		local batch = RewardsLogic.planBatch(rewards)
		t.equal(#batch.items, 6)
		t.equal(batch.items[#batch.items].rarity, "Legendary", "rarest last")
		t.truthy(batch.duration > 0)
	end,

	["feeding raises both needs and stops at 100"] = function()
		local foods = DemoLogic.foods()
		t.equal(#foods, 3)
		local needs = DemoLogic.startingNeeds()
		local fed = DemoLogic.feed(needs, foods[1])
		t.equal(fed.hunger, needs.hunger + foods[1].hunger)
		t.equal(fed.happiness, needs.happiness + foods[1].happiness)
		t.equal(needs.hunger, DemoLogic.startingNeeds().hunger, "the input is not changed")
		for _ = 1, 20 do
			fed = DemoLogic.feed(fed, foods[2])
		end
		t.equal(fed.hunger, 100)
		t.truthy(fed.happiness <= 100)
		local hungry = DemoLogic.decay({ hunger = 1, happiness = 50 }, 10)
		t.equal(hungry.hunger, 0, "never below zero")
		t.near(hungry.happiness, 40, 1e-9)
		t.deepEqual(DemoLogic.decay(needs, -5), needs, "negative time does nothing")
		t.equal(#DemoLogic.animals(), 2)
	end,

	["every fourth throw misses and lands beside the animal"] = function()
		t.falsy(DemoLogic.throwMisses(1))
		t.falsy(DemoLogic.throwMisses(3))
		t.truthy(DemoLogic.throwMisses(4))
		t.truthy(DemoLogic.throwMisses(8))
		local animal = vec(10, 2, -5)
		local hit = DemoLogic.landing(animal, 0, false, 1)
		t.deepEqual(hit, animal)
		t.truthy(DemoLogic.isHit(hit, animal))
		local miss = DemoLogic.landing(animal, 0, true, 4)
		t.equal(miss.y, 0, "a miss lands on the ground")
		t.falsy(DemoLogic.isHit(miss, animal))
		local other = DemoLogic.landing(animal, 0, true, 8)
		t.truthy((miss.x - animal.x) * (other.x - animal.x) < 0, "misses alternate sides")
		t.near(DemoLogic.flatDistance(vec(0, 9, 0), vec(3, -2, 4)), 5, 1e-9)
	end,
}
