--!strict
local RebirthLogic = require("../src/Systems/Rebirth/RebirthLogic")
local UpgradesLogic = require("../src/Systems/Upgrades/UpgradesLogic")
local t = require("./lib/t")

local function rebirthConfig(): RebirthLogic.Config
	return RebirthLogic.validateConfig({
		currency = "Coins",
		cost = { kind = "exponential", base = 1000, growth = 2 },
		multiplierPerRebirth = 0.5,
		maxRebirths = 3,
		reset = { "Coins", "upgrades" },
		tokensPerRebirth = 1,
		tokenCurrency = "Tokens",
	})
end

local function upgradesConfig(): UpgradesLogic.Config
	return UpgradesLogic.validateConfig({
		upgrades = {
			Speed = {
				currency = "Coins",
				cost = { kind = "linear", base = 10, step = 10 },
				maxLevel = 5,
				effect = { base = 16, perLevel = 2 },
			},
			Bag = {
				currency = "Coins",
				cost = { kind = "table", values = { 50, 100, 400 } },
				maxLevel = 3,
				effect = { base = 10, values = { 20, 40, 80 } },
				requires = { Speed = 2 },
				resetOnRebirth = false,
			},
		},
	})
end

return {
	["curves cost what they say"] = function()
		t.equal(RebirthLogic.curveCost({ kind = "linear", base = 10, step = 5 }, 3), 20)
		t.equal(RebirthLogic.curveCost({ kind = "exponential", base = 100, growth = 1.5 }, 3), 225)
		t.equal(RebirthLogic.curveCost({ kind = "table", values = { 1, 2 } }, 9), 2)
		t.throws(function()
			RebirthLogic.validateCurve({ kind = "exponential", base = 1, growth = 0.5 }, "x")
		end)
	end,

	["rebirth plans one, several and max"] = function()
		local cfg = rebirthConfig()
		local s = RebirthLogic.newState()
		t.equal(RebirthLogic.plan(cfg, s, 999).reason, "not enough Coins")
		local one = RebirthLogic.plan(cfg, s, 1500)
		t.truthy(one.ok)
		t.equal(one.cost, 1000)
		t.equal(one.tokens, 1)
		t.deepEqual(one.reset, { "Coins", "upgrades" })
		t.equal(RebirthLogic.multiplier(cfg, one.state), 1.5)
		t.equal(RebirthLogic.plan(cfg, s, 2999, 2).reason, "not enough Coins")
		local max = RebirthLogic.plan(cfg, s, 1e9, "max")
		t.equal(max.count, 3, "capped by maxRebirths")
		t.equal(max.cost, 1000 + 2000 + 4000)
		t.equal(RebirthLogic.plan(cfg, max.state, 1e9).reason, "max rebirths")
		t.equal(RebirthLogic.plan(cfg, s, 1e9, 0).reason, "invalid count")
	end,

	["rebirth deserialize clamps"] = function()
		local cfg = rebirthConfig()
		t.equal(RebirthLogic.deserialize(cfg, { r = 99 }).rebirths, 3)
		t.equal(RebirthLogic.deserialize(cfg, { r = -1 }).rebirths, 0)
		t.equal(RebirthLogic.deserialize(cfg, RebirthLogic.serialize({ rebirths = 2 })).rebirths, 2)
	end,

	["upgrades buy, buy max and effects"] = function()
		local cfg = upgradesConfig()
		local s = UpgradesLogic.newState()
		t.equal(UpgradesLogic.value(cfg, s, "Speed"), 16)
		t.equal(UpgradesLogic.nextCost(cfg, s, "Speed"), 10)
		local one = UpgradesLogic.buy(cfg, s, "Speed", 10)
		t.truthy(one.ok)
		t.equal(UpgradesLogic.value(cfg, one.state, "Speed"), 18)
		local max = UpgradesLogic.buy(cfg, one.state, "Speed", 1000, "max")
		t.equal(max.levels, 4)
		t.equal(max.cost, 20 + 30 + 40 + 50)
		t.equal(UpgradesLogic.nextCost(cfg, max.state, "Speed"), nil)
		t.equal(UpgradesLogic.buy(cfg, max.state, "Speed", 1000).reason, "max level")
		t.equal(UpgradesLogic.buy(cfg, s, "Speed", 25, 2).reason, "not enough Coins")
	end,

	["upgrade requirements and rebirth reset"] = function()
		local cfg = upgradesConfig()
		local s = UpgradesLogic.newState()
		t.equal(UpgradesLogic.buy(cfg, s, "Bag", 1000).reason, "requires Speed 2")
		s = UpgradesLogic.buy(cfg, s, "Speed", 1000, 2).state
		s = UpgradesLogic.buy(cfg, s, "Bag", 1000, 2).state
		t.equal(UpgradesLogic.value(cfg, s, "Bag"), 40)
		local after = UpgradesLogic.afterRebirth(cfg, s)
		t.equal(UpgradesLogic.level(after, "Speed"), 0)
		t.equal(UpgradesLogic.level(after, "Bag"), 2)
		local hostile: any = { l = { Speed = 99, Ghost = 1, Bag = -3 } }
		t.deepEqual(UpgradesLogic.deserialize(cfg, hostile).levels, { Speed = 5 })
	end,
}
