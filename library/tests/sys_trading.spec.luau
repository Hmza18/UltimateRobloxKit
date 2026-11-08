--!strict
local TradingLogic = require("../src/Systems/Trading/TradingLogic")
local t = require("./lib/t")

local config: TradingLogic.Config = { countdown = 5, maxPets = 3, currencies = { Gems = true } }

local function open(): TradingLogic.Session
	local ok, _, invite = TradingLogic.invite(config, 1, 2, 0)
	assert(ok and invite, "invite")
	local started, _, session = TradingLogic.start(invite, "T1", 10)
	assert(started and session, "session")
	return session
end

local function always(): (boolean, string?)
	return true, nil
end

return {
	["invites expire and self trades are refused"] = function()
		t.falsy((TradingLogic.invite(config, 1, 1, 0)))
		local _, _, invite = TradingLogic.invite(config, 1, 2, 0)
		t.falsy((TradingLogic.start(invite :: any, "x", 31)))
	end,

	["both must accept the same version, then countdown, then settle"] = function()
		local s = open()
		s = TradingLogic.setOffer(config, s, 1, { pets = { "7" }, currency = {} }).session
		s = TradingLogic.setOffer(config, s, 2, { pets = {}, currency = { Gems = 50 } }).session
		local v = s.version
		s = TradingLogic.accept(config, s, 1, v, 20).session
		t.equal(s.stage, "open")
		s = TradingLogic.accept(config, s, 2, v, 21).session
		t.equal(s.stage, "countdown")
		t.falsy(TradingLogic.isReady(s, 25))
		t.truthy(TradingLogic.isReady(s, 26))
		local settled = TradingLogic.settle(s, 26, always)
		t.truthy(settled.ok)
		t.equal(settled.session.stage, "done")
		t.deepEqual(settled.gives[1].pets, { "7" })
		t.equal(settled.gives[2].currency.Gems, 50)
	end,

	["changing an offer clears acceptance and stops the countdown"] = function()
		local s = open()
		s = TradingLogic.setOffer(config, s, 1, { pets = { "7" }, currency = {} }).session
		local v = s.version
		s = TradingLogic.accept(config, s, 1, v, 20).session
		s = TradingLogic.accept(config, s, 2, v, 20).session
		t.equal(s.stage, "countdown")
		s = TradingLogic.setOffer(config, s, 1, { pets = {}, currency = {} }).session
		t.equal(s.stage, "open")
		t.deepEqual(s.accepted, {})
		t.equal(TradingLogic.accept(config, s, 2, v, 22).reason, "offer changed")
	end,

	["offers are validated"] = function()
		local s = open()
		t.equal(TradingLogic.setOffer(config, s, 3, { pets = {}, currency = {} }).reason, "not in trade")
		t.equal(
			TradingLogic.setOffer(config, s, 1, { pets = { "1", "2", "3", "4" }, currency = {} }).reason,
			"too many pets"
		)
		t.equal(TradingLogic.setOffer(config, s, 1, { pets = { "1", "1" }, currency = {} }).reason, "bad pet id")
		t.equal(
			TradingLogic.setOffer(config, s, 1, { pets = {}, currency = { Coins = 5 } }).reason,
			"currency not tradeable"
		)
		t.equal(TradingLogic.setOffer(config, s, 1, { pets = {}, currency = { Gems = -5 } }).reason, "bad amount")
		t.equal(TradingLogic.setOffer(config, s, 1, { pets = {}, currency = { Gems = 0 / 0 } }).reason, "bad amount")
		local bad: any = { pets = "7" }
		t.equal(TradingLogic.setOffer(config, s, 1, bad).reason, "bad offer")
	end,

	["empty trades cannot start a countdown"] = function()
		local s = open()
		s = TradingLogic.accept(config, s, 1, s.version, 11).session
		t.equal(TradingLogic.accept(config, s, 2, s.version, 11).reason, "empty trade")
	end,

	["settle cancels when items changed hands"] = function()
		local s = open()
		s = TradingLogic.setOffer(config, s, 1, { pets = { "7" }, currency = {} }).session
		s = TradingLogic.accept(config, s, 1, s.version, 20).session
		s = TradingLogic.accept(config, s, 2, s.version, 20).session
		local result = TradingLogic.settle(s, 30, function(user: number): (boolean, string?)
			return user ~= 1, "pet 7 is gone"
		end)
		t.falsy(result.ok)
		t.equal(result.session.stage, "cancelled")
		t.equal(result.reason, "pet 7 is gone")
	end,

	["unaccept, timeout and fairness"] = function()
		local s = open()
		s = TradingLogic.setOffer(config, s, 1, { pets = { "7" }, currency = {} }).session
		s = TradingLogic.accept(config, s, 1, s.version, 20).session
		s = TradingLogic.accept(config, s, 2, s.version, 20).session
		s = TradingLogic.unaccept(s, 2).session
		t.equal(s.stage, "open")
		t.equal(TradingLogic.tick({ sessionSeconds = 60 }, s, 100).stage, "cancelled")
		local ratio = TradingLogic.fairness(s, function(offer: TradingLogic.Offer): number
			return #offer.pets * 100
		end)
		t.equal(ratio, 0)
	end,
}
