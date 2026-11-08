--!strict
local CurrencyLogic = require("../src/Systems/Currency/CurrencyLogic")
local ShopLogic = require("../src/Systems/Shop/ShopLogic")
local t = require("./lib/t")

local currencyConfig = CurrencyLogic.validateConfig({
	currencies = { Coins = { initial = 1000 }, Gems = { initial = 5 } },
})

local function catalog()
	return ShopLogic.newCatalog({
		{ id = "Potion", prices = { Coins = 50 } },
		{ id = "Hat", prices = { Coins = 200, Gems = 2 }, perPlayerLimit = 1 },
		{ id = "Relic", prices = { Coins = 100 }, stock = 2 },
		{ id = "Cape", prices = { Coins = 300 }, sales = { { discount = 0.5, startsAt = 100, endsAt = 200 } } },
		{ id = "Gift", prices = {} },
	})
end

local function buy(cat, stock, history, wallet, itemId: string, quantity: number?, now: number?)
	local request = { itemId = itemId, quantity = quantity, now = now or 0 }
	return ShopLogic.purchase(cat, currencyConfig, stock, history, wallet, request)
end

return {
	["newCatalog validates items"] = function()
		t.throws(function()
			ShopLogic.newCatalog({ { id = "A", prices = { Coins = -1 } } })
		end)
		t.throws(function()
			ShopLogic.newCatalog({ { id = "A", prices = {} }, { id = "A", prices = {} } })
		end)
		t.throws(function()
			ShopLogic.newCatalog({ { id = "A", prices = { Coins = 1.5 } } })
		end)
		t.throws(function()
			ShopLogic.newCatalog({ { id = "A", prices = {}, sales = { { discount = 2 } } } })
		end)
		t.throws(function()
			ShopLogic.newCatalog({ { id = "A", prices = {}, perPlayerLimit = 0 } })
		end)
		local cat = catalog()
		t.equal(#cat.order, 5)
		t.truthy(ShopLogic.getItem(cat, "Hat"))
		t.equal(ShopLogic.getItem(cat, "Nope"), nil)
	end,

	["sale windows apply the best active discount"] = function()
		local cat = catalog()
		local cape = ShopLogic.getItem(cat, "Cape")
		assert(cape, "missing cape")
		t.equal(ShopLogic.activeDiscount(cape, 99), 0)
		t.equal(ShopLogic.activeDiscount(cape, 100), 0.5)
		t.equal(ShopLogic.activeDiscount(cape, 199), 0.5)
		t.equal(ShopLogic.activeDiscount(cape, 200), 0)
		local multi = ShopLogic.newCatalog({
			{ id = "X", prices = { Coins = 10 }, sales = { { discount = 0.1 }, { discount = 0.3, endsAt = 50 } } },
		})
		local x = ShopLogic.getItem(multi, "X")
		assert(x, "missing x")
		t.equal(ShopLogic.activeDiscount(x, 10), 0.3)
		t.equal(ShopLogic.activeDiscount(x, 60), 0.1)
	end,

	["priceFor rounds per unit and multiplies by quantity"] = function()
		local cat = ShopLogic.newCatalog({ { id = "Odd", prices = { Coins = 15 }, sales = { { discount = 0.5 } } } })
		local price = ShopLogic.priceFor(cat, "Odd", 0, 3)
		t.deepEqual(price, { Coins = 24 })
		t.equal(select(2, ShopLogic.priceFor(cat, "Missing", 0)), "unknown item")
		t.equal(select(2, ShopLogic.priceFor(cat, "Odd", 0, 0)), "invalid quantity")
	end,

	["purchase deducts the server-side price"] = function()
		local cat = catalog()
		local wallet = CurrencyLogic.newWallet(currencyConfig)
		local result = buy(cat, ShopLogic.newStock(cat), {}, wallet, "Potion", 3)
		t.truthy(result.ok)
		t.equal(result.quantity, 3)
		t.deepEqual(result.cost, { Coins = 150 })
		t.equal(CurrencyLogic.balance(result.wallet, "Coins"), 850)
		t.equal(result.history.Potion, 3)
		t.equal(CurrencyLogic.balance(wallet, "Coins"), 1000)
	end,

	["purchase uses sale prices at the given time"] = function()
		local cat = catalog()
		local wallet = CurrencyLogic.newWallet(currencyConfig)
		local onSale = buy(cat, {}, {}, wallet, "Cape", 1, 150)
		t.equal(CurrencyLogic.balance(onSale.wallet, "Coins"), 850)
		local fullPrice = buy(cat, {}, {}, wallet, "Cape", 1, 250)
		t.equal(CurrencyLogic.balance(fullPrice.wallet, "Coins"), 700)
	end,

	["multi-currency purchases are atomic"] = function()
		local cat = catalog()
		local poor = CurrencyLogic.spend(currencyConfig, CurrencyLogic.newWallet(currencyConfig), "Gems", 4).wallet
		local result = buy(cat, {}, {}, poor, "Hat")
		t.falsy(result.ok)
		t.equal(result.reason, "insufficient funds")
		t.equal(CurrencyLogic.balance(result.wallet, "Coins"), 1000)
		t.equal(result.history.Hat, nil)
	end,

	["per-player limits are enforced"] = function()
		local cat = catalog()
		local wallet = CurrencyLogic.newWallet(currencyConfig)
		local first = buy(cat, {}, {}, wallet, "Hat")
		t.truthy(first.ok)
		t.equal(ShopLogic.remaining(cat, {}, first.history, "Hat"), 0)
		local second = buy(cat, {}, first.history, first.wallet, "Hat")
		t.falsy(second.ok)
		t.equal(second.reason, "limit reached")
		t.equal(buy(cat, {}, {}, wallet, "Hat", 2).reason, "limit reached")
	end,

	["global stock runs out"] = function()
		local cat = catalog()
		local stock = ShopLogic.newStock(cat)
		t.equal(stock.Relic, 2)
		t.equal(stock.Potion, nil)
		local wallet = CurrencyLogic.newWallet(currencyConfig)
		local first = buy(cat, stock, {}, wallet, "Relic", 2)
		t.truthy(first.ok)
		t.equal(first.stock.Relic, 0)
		t.equal(stock.Relic, 2)
		t.equal(buy(cat, first.stock, {}, first.wallet, "Relic").reason, "out of stock")
		t.equal(ShopLogic.remaining(cat, first.stock, {}, "Relic"), 0)
		t.equal(ShopLogic.remaining(cat, stock, {}, "Potion"), nil)
		t.equal(ShopLogic.remaining(cat, stock, {}, "Missing"), 0)
	end,

	["invalid requests are rejected"] = function()
		local cat = catalog()
		local wallet = CurrencyLogic.newWallet(currencyConfig)
		t.equal(buy(cat, {}, {}, wallet, "Nope").reason, "unknown item")
		t.equal(buy(cat, {}, {}, wallet, "Potion", 0).reason, "invalid quantity")
		t.equal(buy(cat, {}, {}, wallet, "Potion", 1.5).reason, "invalid quantity")
		t.equal(buy(cat, {}, {}, wallet, "Potion", 100).reason, "invalid quantity")
		local bad: any = { itemId = "Potion", now = math.huge }
		t.equal(ShopLogic.purchase(cat, currencyConfig, {}, {}, wallet, bad).reason, "invalid request")
		local wrongType: any = { itemId = 5, now = 0 }
		t.equal(ShopLogic.purchase(cat, currencyConfig, {}, {}, wallet, wrongType).reason, "unknown item")
	end,

	["free items succeed without payment"] = function()
		local cat = catalog()
		local wallet = CurrencyLogic.newWallet(currencyConfig)
		local result = buy(cat, {}, {}, wallet, "Gift")
		t.truthy(result.ok)
		t.equal(CurrencyLogic.balance(result.wallet, "Coins"), 1000)
	end,

	["deserializeHistory keeps only valid counts"] = function()
		local raw: any = { Potion = 3, Hat = -1, Cape = 1.5, [5] = 2 }
		t.deepEqual(ShopLogic.deserializeHistory(raw), { Potion = 3 })
		t.deepEqual(ShopLogic.deserializeHistory(nil), {})
	end,

	["receipt history records ids and forgets the oldest"] = function()
		local history = ShopLogic.newReceiptHistory(2)
		history = ShopLogic.recordReceipt(history, "a")
		history = ShopLogic.recordReceipt(history, "b")
		history = ShopLogic.recordReceipt(history, "a")
		t.equal(#history.order, 2)
		history = ShopLogic.recordReceipt(history, "c")
		t.falsy(ShopLogic.hasReceipt(history, "a"))
		t.truthy(ShopLogic.hasReceipt(history, "b"))
		t.truthy(ShopLogic.hasReceipt(history, "c"))
		local restored = ShopLogic.deserializeReceipts(ShopLogic.serializeReceipts(history), 2)
		t.truthy(ShopLogic.hasReceipt(restored, "c"))
		t.equal(#ShopLogic.deserializeReceipts("junk").order, 0)
		t.throws(function()
			ShopLogic.newReceiptHistory(0)
		end)
	end,

	["processReceipt grants once per purchase id"] = function()
		local stored = ShopLogic.newReceiptHistory()
		local grants = 0
		local deps: ShopLogic.ReceiptDeps = {
			loadHistory = function(_userId: number)
				return stored
			end,
			grant = function(_userId: number, _productId: number, _receipt: ShopLogic.ReceiptInfo)
				grants += 1
				return true
			end,
			commit = function(_userId: number, history: ShopLogic.ReceiptHistory)
				stored = history
				return true
			end,
		}
		local receipt = { PurchaseId = "p1", PlayerId = 1, ProductId = 42 }
		local decision, reason = ShopLogic.processReceipt(receipt, deps)
		t.equal(decision, "PurchaseGranted")
		t.equal(reason, "granted")
		local again, againReason = ShopLogic.processReceipt(receipt, deps)
		t.equal(again, "PurchaseGranted")
		t.equal(againReason, "already granted")
		t.equal(grants, 1)
	end,

	["processReceipt waits when data is missing or a step fails"] = function()
		local receipt = { PurchaseId = "p1", PlayerId = 1, ProductId = 42 }
		local function deps(loaded: boolean, grantOk: boolean, commitOk: boolean): ShopLogic.ReceiptDeps
			return {
				loadHistory = function(_userId: number)
					return if loaded then ShopLogic.newReceiptHistory() else nil
				end,
				grant = function(_userId: number, _productId: number, _receipt: ShopLogic.ReceiptInfo)
					return grantOk
				end,
				commit = function(_userId: number, _history: ShopLogic.ReceiptHistory)
					return commitOk
				end,
			}
		end
		t.equal(select(2, ShopLogic.processReceipt(receipt, deps(false, true, true))), "player data not loaded")
		t.equal(select(2, ShopLogic.processReceipt(receipt, deps(true, false, true))), "grant failed")
		t.equal(select(2, ShopLogic.processReceipt(receipt, deps(true, true, false))), "commit failed")
		local bad: any = { PurchaseId = 5, PlayerId = 1, ProductId = 1 }
		local decision = ShopLogic.processReceipt(bad, deps(true, true, true))
		t.equal(decision, "NotProcessedYet")
		local throwing: ShopLogic.ReceiptDeps = {
			loadHistory = function(_userId: number)
				return ShopLogic.newReceiptHistory()
			end,
			grant = function(_userId: number, _productId: number, _receipt: ShopLogic.ReceiptInfo): boolean
				error("boom")
			end,
			commit = function(_userId: number, _history: ShopLogic.ReceiptHistory)
				return true
			end,
		}
		t.equal(select(2, ShopLogic.processReceipt(receipt, throwing)), "grant failed")
	end,
}
