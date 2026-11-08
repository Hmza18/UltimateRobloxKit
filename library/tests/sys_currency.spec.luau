--!strict
local CurrencyLogic = require("../src/Systems/Currency/CurrencyLogic")
local t = require("./lib/t")

local function config(overflow: ("clamp" | "reject")?): CurrencyLogic.Config
	return CurrencyLogic.validateConfig({
		currencies = { Coins = { initial = 100 }, Gems = { max = 500 } },
		logSize = 3,
		overflow = overflow,
	})
end

return {
	["new wallets start at the initial balances"] = function()
		local wallet = CurrencyLogic.newWallet(config())
		t.equal(CurrencyLogic.balance(wallet, "Coins"), 100)
		t.equal(CurrencyLogic.balance(wallet, "Gems"), 0)
		t.equal(CurrencyLogic.balance(wallet, "Missing"), 0)
	end,

	["validateConfig rejects bad configs"] = function()
		local noCurrencies: any = {}
		t.throws(function()
			CurrencyLogic.validateConfig(noCurrencies)
		end)
		t.throws(function()
			CurrencyLogic.validateConfig({ currencies = { Coins = { max = -1 } } })
		end)
		local badOverflow: any = { currencies = { Coins = {} }, overflow = "wrap" }
		t.throws(function()
			CurrencyLogic.validateConfig(badOverflow)
		end)
		t.throws(function()
			CurrencyLogic.validateConfig({ currencies = { Coins = {} }, logSize = 1.5 })
		end)
	end,

	["add and spend return new wallets"] = function()
		local cfg = config()
		local wallet = CurrencyLogic.newWallet(cfg)
		local added = CurrencyLogic.add(cfg, wallet, "Coins", 50, "quest", 10)
		t.truthy(added.ok)
		t.equal(added.amount, 50)
		t.equal(CurrencyLogic.balance(added.wallet, "Coins"), 150)
		t.equal(CurrencyLogic.balance(wallet, "Coins"), 100)
		local spent = CurrencyLogic.spend(cfg, added.wallet, "Coins", 30, "shop", 11)
		t.truthy(spent.ok)
		t.equal(CurrencyLogic.balance(spent.wallet, "Coins"), 120)
	end,

	["spend never goes below zero"] = function()
		local cfg = config()
		local wallet = CurrencyLogic.newWallet(cfg)
		local result = CurrencyLogic.spend(cfg, wallet, "Coins", 101)
		t.falsy(result.ok)
		t.equal(result.reason, "insufficient funds")
		t.equal(result.wallet, wallet)
		t.equal(CurrencyLogic.balance(result.wallet, "Coins"), 100)
	end,

	["invalid amounts and currencies are rejected"] = function()
		local cfg = config()
		local wallet = CurrencyLogic.newWallet(cfg)
		t.equal(CurrencyLogic.add(cfg, wallet, "Coins", 0).reason, "invalid amount")
		t.equal(CurrencyLogic.add(cfg, wallet, "Coins", -5).reason, "invalid amount")
		t.equal(CurrencyLogic.add(cfg, wallet, "Coins", 1.5).reason, "invalid amount")
		t.equal(CurrencyLogic.add(cfg, wallet, "Coins", math.huge).reason, "invalid amount")
		t.equal(CurrencyLogic.add(cfg, wallet, "Coins", math.sqrt(-1)).reason, "invalid amount")
		t.equal(CurrencyLogic.spend(cfg, wallet, "Coins", -1).reason, "invalid amount")
		t.equal(CurrencyLogic.add(cfg, wallet, "Tokens", 5).reason, "unknown currency")
		t.equal(CurrencyLogic.spend(cfg, wallet, "Tokens", 5).reason, "unknown currency")
	end,

	["add clamps at max by default"] = function()
		local cfg = config()
		local wallet = CurrencyLogic.newWallet(cfg)
		local result = CurrencyLogic.add(cfg, wallet, "Gems", 800)
		t.truthy(result.ok)
		t.equal(result.amount, 500)
		t.equal(CurrencyLogic.balance(result.wallet, "Gems"), 500)
		local again = CurrencyLogic.add(cfg, result.wallet, "Gems", 1)
		t.falsy(again.ok)
		t.equal(again.reason, "over max")
	end,

	["add rejects overflow in reject mode"] = function()
		local cfg = config("reject")
		local wallet = CurrencyLogic.newWallet(cfg)
		local result = CurrencyLogic.add(cfg, wallet, "Gems", 501)
		t.falsy(result.ok)
		t.equal(result.reason, "over max")
		t.truthy(CurrencyLogic.add(cfg, wallet, "Gems", 500).ok)
	end,

	["spendMany is all or nothing"] = function()
		local cfg = config()
		local wallet = CurrencyLogic.add(cfg, CurrencyLogic.newWallet(cfg), "Gems", 10).wallet
		local tooMuch = CurrencyLogic.spendMany(cfg, wallet, { Coins = 50, Gems = 11 }, "craft")
		t.falsy(tooMuch.ok)
		t.equal(CurrencyLogic.balance(tooMuch.wallet, "Coins"), 100)
		local paid = CurrencyLogic.spendMany(cfg, wallet, { Coins = 50, Gems = 10 }, "craft")
		t.truthy(paid.ok)
		t.equal(paid.amount, 60)
		t.equal(CurrencyLogic.balance(paid.wallet, "Coins"), 50)
		t.equal(CurrencyLogic.balance(paid.wallet, "Gems"), 0)
		t.equal(CurrencyLogic.spendMany(cfg, wallet, { Coins = 1.5 }).reason, "invalid amount")
		t.equal(CurrencyLogic.spendMany(cfg, wallet, { Tokens = 1 }).reason, "unknown currency")
		t.truthy(CurrencyLogic.spendMany(cfg, wallet, { Coins = 0 }).ok)
	end,

	["canAfford checks every currency"] = function()
		local cfg = config()
		local wallet = CurrencyLogic.newWallet(cfg)
		t.truthy(CurrencyLogic.canAfford(wallet, { Coins = 100 }))
		t.falsy(CurrencyLogic.canAfford(wallet, { Coins = 100, Gems = 1 }))
		t.falsy(CurrencyLogic.canAfford(wallet, { Coins = -1 }))
		t.truthy(CurrencyLogic.canAfford(wallet, {}))
	end,

	["transfer moves money between wallets"] = function()
		local cfg = config()
		local alice = CurrencyLogic.newWallet(cfg)
		local bob = CurrencyLogic.newWallet(cfg)
		local result = CurrencyLogic.transfer(cfg, alice, bob, "Coins", 40, "trade", 5)
		t.truthy(result.ok)
		t.equal(CurrencyLogic.balance(result.from, "Coins"), 60)
		t.equal(CurrencyLogic.balance(result.to, "Coins"), 140)
		local failed = CurrencyLogic.transfer(cfg, alice, bob, "Coins", 1000)
		t.falsy(failed.ok)
		t.equal(failed.reason, "insufficient funds")
		t.equal(failed.from, alice)
	end,

	["transfer refuses to overflow the receiver"] = function()
		local cfg = config()
		local rich = CurrencyLogic.add(cfg, CurrencyLogic.newWallet(cfg), "Gems", 500).wallet
		local full = CurrencyLogic.add(cfg, CurrencyLogic.newWallet(cfg), "Gems", 450).wallet
		local result = CurrencyLogic.transfer(cfg, rich, full, "Gems", 100)
		t.falsy(result.ok)
		t.equal(result.reason, "receiver over max")
		t.equal(CurrencyLogic.balance(result.from, "Gems"), 500)
	end,

	["the log is a ring buffer, newest first"] = function()
		local cfg = config()
		local wallet = CurrencyLogic.newWallet(cfg)
		for index = 1, 5 do
			wallet = CurrencyLogic.add(cfg, wallet, "Coins", index, "tick", index).wallet
		end
		local entries = CurrencyLogic.recent(wallet)
		t.equal(#entries, 3)
		t.equal(entries[1].delta, 5)
		t.equal(entries[2].delta, 4)
		t.equal(entries[3].delta, 3)
		t.equal(entries[1].balance, 115)
		t.equal(entries[1].time, 5)
		t.equal(#CurrencyLogic.recent(wallet, 1), 1)
		t.equal(#CurrencyLogic.recent(CurrencyLogic.newWallet(cfg)), 0)
	end,

	["a zero log size disables the log"] = function()
		local cfg = CurrencyLogic.validateConfig({ currencies = { Coins = {} }, logSize = 0 })
		local wallet = CurrencyLogic.add(cfg, CurrencyLogic.newWallet(cfg), "Coins", 5).wallet
		t.equal(CurrencyLogic.balance(wallet, "Coins"), 5)
		t.equal(#CurrencyLogic.recent(wallet), 0)
	end,

	["summarize splits sources and sinks by tag"] = function()
		local cfg = CurrencyLogic.validateConfig({ currencies = { Coins = {} }, logSize = 10 })
		local wallet = CurrencyLogic.newWallet(cfg)
		wallet = CurrencyLogic.add(cfg, wallet, "Coins", 30, "quest").wallet
		wallet = CurrencyLogic.add(cfg, wallet, "Coins", 20, "quest").wallet
		wallet = CurrencyLogic.spend(cfg, wallet, "Coins", 15, "shop").wallet
		local summary = CurrencyLogic.summarize(CurrencyLogic.recent(wallet))
		t.equal(summary.sources.quest.Coins, 50)
		t.equal(summary.sinks.shop.Coins, 15)
		t.equal(summary.sources.shop, nil)
	end,

	["abbreviate and withCommas format amounts"] = function()
		t.equal(CurrencyLogic.abbreviate(999), "999")
		t.equal(CurrencyLogic.abbreviate(1000), "1K")
		t.equal(CurrencyLogic.abbreviate(1234567), "1.23M")
		t.equal(CurrencyLogic.abbreviate(-1500), "-1.5K")
		t.equal(CurrencyLogic.abbreviate(2.5e15), "2.5Qa")
		t.equal(CurrencyLogic.abbreviate(math.huge), "0")
		t.equal(CurrencyLogic.withCommas(1234567), "1,234,567")
		t.equal(CurrencyLogic.withCommas(100), "100")
		t.equal(CurrencyLogic.withCommas(-1000), "-1,000")
		t.equal(CurrencyLogic.withCommas(0), "0")
	end,

	["serialize and deserialize sanitize balances"] = function()
		local cfg = config()
		local wallet = CurrencyLogic.add(cfg, CurrencyLogic.newWallet(cfg), "Gems", 42).wallet
		local saved = CurrencyLogic.serialize(wallet)
		t.equal(saved.v, CurrencyLogic.SAVE_VERSION)
		local restored = CurrencyLogic.deserialize(cfg, saved)
		t.equal(CurrencyLogic.balance(restored, "Gems"), 42)
		t.equal(CurrencyLogic.balance(restored, "Coins"), 100)
		local raw: any = { b = { Coins = -50, Gems = 9999, Tokens = 5 } }
		local cleaned = CurrencyLogic.deserialize(cfg, raw)
		t.equal(CurrencyLogic.balance(cleaned, "Coins"), 0)
		t.equal(CurrencyLogic.balance(cleaned, "Gems"), 500)
		t.equal(cleaned.balances.Tokens, nil)
		local nanSave: any = { b = { Coins = math.sqrt(-1) } }
		t.equal(CurrencyLogic.balance(CurrencyLogic.deserialize(cfg, nanSave), "Coins"), 100)
		t.equal(CurrencyLogic.balance(CurrencyLogic.deserialize(cfg, "junk"), "Coins"), 100)
	end,
}
