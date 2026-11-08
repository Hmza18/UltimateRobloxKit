--!strict
local DailyRewardsLogic = require("../src/Systems/DailyRewards/DailyRewardsLogic")
local t = require("./lib/t")

local DAY = 86400
-- 2026-01-01 00:00:00 UTC, which is exactly day 20454.
local T0 = 1767225600

local function config(overrides: { [string]: any }?)
	local input: any = { rewards = { "A", "B", "C" } }
	for key, value in overrides or {} do
		input[key] = value
	end
	return DailyRewardsLogic.newConfig(input)
end

local function claimAt(cfg, state, now: number)
	local result = DailyRewardsLogic.claim(cfg, state, now)
	assert(result.ok, result.reason)
	return result
end

return {
	["newConfig validates input and applies defaults"] = function()
		local cfg = config()
		t.equal(cfg.graceDays, 0)
		t.truthy(cfg.cycle)
		t.equal(cfg.resetOffsetSeconds, 0)
		t.throws(function()
			DailyRewardsLogic.newConfig({ rewards = {} })
		end)
		t.throws(function()
			config({ graceDays = -1 })
		end)
		t.throws(function()
			config({ resetOffsetSeconds = DAY })
		end)
	end,

	["day index uses UTC and the reset offset"] = function()
		t.equal(DailyRewardsLogic.dayIndex(T0), 20454)
		t.equal(DailyRewardsLogic.dayIndex(T0 - 1), 20453)
		t.equal(DailyRewardsLogic.dayIndex(T0 + DAY - 1), 20454)
		t.equal(DailyRewardsLogic.dayIndex(T0 + 3599, 3600), 20453)
		t.equal(DailyRewardsLogic.dayIndex(T0 + 3600, 3600), 20454)
		t.equal(DailyRewardsLogic.nextReset(T0 + 10), T0 + DAY)
		t.equal(DailyRewardsLogic.nextReset(T0 + 10, 3600), T0 + 3600)
	end,

	["first claim starts a streak of one"] = function()
		local cfg = config()
		local result = claimAt(cfg, DailyRewardsLogic.new(), T0 + 100)
		t.equal(result.streak, 1)
		t.equal(result.reward, "A")
		t.equal(result.state.lastClaimDay, 20454)
		t.equal(result.state.totalClaims, 1)
	end,

	["a second claim on the same day is refused"] = function()
		local cfg = config()
		local first = claimAt(cfg, DailyRewardsLogic.new(), T0 + 100)
		local again = DailyRewardsLogic.claim(cfg, first.state, T0 + DAY - 1)
		t.falsy(again.ok)
		t.equal(again.reason, "already claimed")
		t.equal(again.state, first.state)
		t.equal(again.reward, nil)
	end,

	["consecutive days grow the streak and cycle the rewards"] = function()
		local cfg = config()
		local state = DailyRewardsLogic.new()
		local rewards: { any } = {}
		for day = 0, 4 do
			local result = claimAt(cfg, state, T0 + day * DAY + 5)
			state = result.state
			table.insert(rewards, result.reward)
		end
		t.deepEqual(rewards, { "A", "B", "C", "A", "B" })
		t.equal(state.streak, 5)
	end,

	["without cycling the last reward repeats"] = function()
		local cfg = config({ cycle = false })
		t.equal(DailyRewardsLogic.rewardIndex(cfg, 2), 2)
		t.equal(DailyRewardsLogic.rewardIndex(cfg, 3), 3)
		t.equal(DailyRewardsLogic.rewardIndex(cfg, 10), 3)
		t.equal(DailyRewardsLogic.rewardIndex(config(), 4), 1)
		t.equal(DailyRewardsLogic.rewardIndex(config(), 0), 1)
	end,

	["missing a day resets the streak"] = function()
		local cfg = config()
		local first = claimAt(cfg, DailyRewardsLogic.new(), T0)
		local second = claimAt(cfg, first.state, T0 + DAY)
		local status = DailyRewardsLogic.status(cfg, second.state, T0 + 3 * DAY)
		t.truthy(status.canClaim)
		t.truthy(status.streakWillReset)
		t.equal(status.streak, 1)
		local after = claimAt(cfg, second.state, T0 + 3 * DAY)
		t.equal(after.streak, 1)
		t.equal(after.reward, "A")
		t.equal(after.state.totalClaims, 3)
	end,

	["grace days keep the streak alive"] = function()
		local cfg = config({ graceDays = 1 })
		local first = claimAt(cfg, DailyRewardsLogic.new(), T0)
		local kept = claimAt(cfg, first.state, T0 + 2 * DAY)
		t.equal(kept.streak, 2)
		local lost = claimAt(cfg, kept.state, T0 + 5 * DAY)
		t.equal(lost.streak, 1)
	end,

	["the day boundary is exact at midnight UTC"] = function()
		local cfg = config()
		local late = claimAt(cfg, DailyRewardsLogic.new(), T0 + DAY - 1)
		local early = claimAt(cfg, late.state, T0 + DAY)
		t.equal(early.streak, 2)
		local status = DailyRewardsLogic.status(cfg, early.state, T0 + DAY + 60)
		t.equal(status.secondsUntilNext, DAY - 60)
	end,

	["a clock that goes backwards cannot claim"] = function()
		local cfg = config()
		local first = claimAt(cfg, DailyRewardsLogic.new(), T0 + 5 * DAY)
		local result = DailyRewardsLogic.claim(cfg, first.state, T0)
		t.falsy(result.ok)
		t.equal(result.reason, "clock went backwards")
		t.equal(DailyRewardsLogic.claim(cfg, first.state, math.huge).reason, "invalid time")
		t.equal(DailyRewardsLogic.claim(cfg, first.state, math.sqrt(-1)).reason, "invalid time")
	end,

	["claim never modifies the input state"] = function()
		local cfg = config()
		local state = DailyRewardsLogic.new()
		claimAt(cfg, state, T0)
		t.equal(state.streak, 0)
		t.equal(state.lastClaimDay, nil)
	end,

	["serialize and deserialize sanitize data"] = function()
		local cfg = config()
		local result = claimAt(cfg, DailyRewardsLogic.new(), T0)
		local saved = DailyRewardsLogic.serialize(result.state)
		t.deepEqual(saved, { v = 1, s = 1, d = 20454, t = 1 })
		t.deepEqual(DailyRewardsLogic.deserialize(saved), result.state)
		local raw: any = { s = -2, d = 1.5, t = "x" }
		t.deepEqual(DailyRewardsLogic.deserialize(raw), DailyRewardsLogic.new())
		t.deepEqual(DailyRewardsLogic.deserialize(nil), DailyRewardsLogic.new())
	end,
}
