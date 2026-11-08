--!strict
-- Shop rules. Pure Luau. A catalog prices items in any CurrencyLogic currency, with optional
-- global stock, per-player purchase limits and timed sales (pass `now`, never read a clock).
-- `purchase` is one atomic transaction: price check, limits, stock and payment succeed together
-- or nothing changes. The second half handles Robux developer product receipts idempotently.

local CurrencyLogic = require("../Currency/CurrencyLogic")

export type Sale = {
	discount: number, -- fraction off, 0..1 (0.25 = 25% off)
	startsAt: number?, -- unix time the sale starts (default: always started)
	endsAt: number?, -- unix time the sale ends, exclusive (default: never ends)
}

export type ItemInput = {
	id: string, -- unique item id
	prices: { [string]: number }, -- currency -> whole price per unit; empty means free
	stock: number?, -- global stock shared by everyone in this server (default unlimited)
	perPlayerLimit: number?, -- most units one player can ever buy (default unlimited)
	maxQuantity: number?, -- most units in one purchase (default 99)
	sales: { Sale }?, -- the best active sale applies
}

export type Item = {
	id: string, -- unique item id
	prices: { [string]: number }, -- base unit prices
	stock: number?, -- starting global stock
	perPlayerLimit: number?, -- lifetime limit per player
	maxQuantity: number, -- per purchase
	sales: { Sale }, -- sale windows
}

export type Catalog = { items: { [string]: Item }, order: { string } }

export type Stock = { [string]: number }

export type History = { [string]: number }

export type Request = { itemId: string, quantity: number?, now: number }

export type PurchaseResult = {
	ok: boolean, -- whether everything was applied
	reason: string?, -- why not
	quantity: number, -- units bought
	cost: { [string]: number }, -- total paid per currency
	wallet: CurrencyLogic.Wallet, -- new wallet, or the input on failure
	stock: Stock, -- new stock, or the input on failure
	history: History, -- new purchase counts, or the input on failure
}

export type ReceiptHistory = { ids: { [string]: boolean }, order: { string }, max: number }

export type ReceiptInfo = { PurchaseId: string, PlayerId: number, ProductId: number }

export type ReceiptDeps = {
	-- The player's receipt history, or nil when their data is not loaded in this server.
	loadHistory: (userId: number) -> ReceiptHistory?,
	-- Gives the product. Returns true on success. Must not yield for long.
	grant: (userId: number, productId: number, receipt: ReceiptInfo) -> boolean,
	-- Stores the new history next to the granted effects. Returns true once stored.
	commit: (userId: number, history: ReceiptHistory) -> boolean,
}

export type ReceiptDecision = "PurchaseGranted" | "NotProcessedYet"

local ShopLogic = {}

ShopLogic.DEFAULT_MAX_QUANTITY = 99
ShopLogic.DEFAULT_RECEIPT_HISTORY = 100

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isCount(value: any): boolean
	return isFinite(value) and value >= 1 and value % 1 == 0
end

local function isWhole(value: any): boolean
	return isFinite(value) and value >= 0 and value % 1 == 0
end

function ShopLogic.newCatalog(inputs: { ItemInput }): Catalog
	assert(type(inputs) == "table", "inputs must be an array")
	local items: { [string]: Item } = {}
	local order: { string } = {}
	for _, input in inputs do
		local id = input.id
		assert(type(id) == "string" and id ~= "", "item id must be a non-empty string")
		assert(items[id] == nil, "duplicate item id " .. id)
		assert(type(input.prices) == "table", "prices must be a table for " .. id)
		for currency, price in input.prices do
			assert(type(currency) == "string" and isWhole(price), "invalid price for " .. id)
		end
		local stock, limit = input.stock, input.perPlayerLimit
		assert(stock == nil or isWhole(stock), "invalid stock for " .. id)
		assert(limit == nil or isCount(limit), "invalid perPlayerLimit for " .. id)
		local maxQuantity = input.maxQuantity or ShopLogic.DEFAULT_MAX_QUANTITY
		assert(isCount(maxQuantity), "invalid maxQuantity for " .. id)
		local sales: { Sale } = {}
		for _, sale in ipairs(input.sales or {}) do
			assert(isFinite(sale.discount) and sale.discount >= 0 and sale.discount <= 1, "invalid discount for " .. id)
			table.insert(sales, { discount = sale.discount, startsAt = sale.startsAt, endsAt = sale.endsAt })
		end
		items[id] = {
			id = id,
			prices = table.clone(input.prices),
			stock = stock,
			perPlayerLimit = limit,
			maxQuantity = maxQuantity,
			sales = sales,
		}
		table.insert(order, id)
	end
	return { items = items, order = order }
end

function ShopLogic.getItem(catalog: Catalog, itemId: string): Item?
	return catalog.items[itemId]
end

-- Starting global stock for every item that has one.
function ShopLogic.newStock(catalog: Catalog): Stock
	local stock: Stock = {}
	for id, item in catalog.items do
		if item.stock ~= nil then
			stock[id] = item.stock
		end
	end
	return stock
end

local function saleActive(sale: Sale, now: number): boolean
	local startsAt, endsAt = sale.startsAt, sale.endsAt
	if startsAt ~= nil and now < startsAt then
		return false
	end
	if endsAt ~= nil and now >= endsAt then
		return false
	end
	return true
end

-- The best discount active at `now`, 0 when there is none.
function ShopLogic.activeDiscount(item: Item, now: number): number
	local best = 0
	for _, sale in item.sales do
		if saleActive(sale, now) and sale.discount > best then
			best = sale.discount
		end
	end
	return best
end

-- Discounted unit prices (rounded half up per unit) times `quantity` (default 1).
function ShopLogic.priceFor(
	catalog: Catalog,
	itemId: string,
	now: number,
	quantity: number?
): ({ [string]: number }?, string?)
	local item = catalog.items[itemId]
	if item == nil then
		return nil, "unknown item"
	end
	local units = quantity or 1
	if not isCount(units) then
		return nil, "invalid quantity"
	end
	local discount = ShopLogic.activeDiscount(item, now)
	local total: { [string]: number } = {}
	for currency, price in item.prices do
		local unit = math.floor(price * (1 - discount) + 0.5)
		total[currency] = unit * units
	end
	return total, nil
end

-- Units this player can still buy, or nil when nothing limits them.
function ShopLogic.remaining(catalog: Catalog, stock: Stock, history: History, itemId: string): number?
	local item = catalog.items[itemId]
	if item == nil then
		return 0
	end
	local left: number? = nil
	if item.stock ~= nil then
		left = math.max(stock[itemId] or 0, 0)
	end
	local limit = item.perPlayerLimit
	if limit ~= nil then
		local personal = math.max(limit - (history[itemId] or 0), 0)
		left = if left == nil then personal else math.min(left, personal)
	end
	return left
end

local function fail(reason: string, stock: Stock, history: History, wallet: CurrencyLogic.Wallet): PurchaseResult
	return { ok = false, reason = reason, quantity = 0, cost = {}, wallet = wallet, stock = stock, history = history }
end

-- Validates and applies a purchase: limits, stock, server-side price and payment through
-- CurrencyLogic.spendMany. The caller grants the item and commits the returned state.
function ShopLogic.purchase(
	catalog: Catalog,
	currencyConfig: CurrencyLogic.Config,
	stock: Stock,
	history: History,
	wallet: CurrencyLogic.Wallet,
	request: Request
): PurchaseResult
	if type(request) ~= "table" or not isFinite(request.now) then
		return fail("invalid request", stock, history, wallet)
	end
	local item = if type(request.itemId) == "string" then catalog.items[request.itemId] else nil
	if item == nil then
		return fail("unknown item", stock, history, wallet)
	end
	local quantity = request.quantity or 1
	if not isCount(quantity) or quantity > item.maxQuantity then
		return fail("invalid quantity", stock, history, wallet)
	end
	if item.stock ~= nil and (stock[item.id] or 0) < quantity then
		return fail("out of stock", stock, history, wallet)
	end
	local limit = item.perPlayerLimit
	if limit ~= nil and (history[item.id] or 0) + quantity > limit then
		return fail("limit reached", stock, history, wallet)
	end
	local cost = ShopLogic.priceFor(catalog, item.id, request.now, quantity)
	if cost == nil then
		return fail("unknown item", stock, history, wallet)
	end
	local paid = CurrencyLogic.spendMany(currencyConfig, wallet, cost, "shop:" .. item.id, request.now)
	if not paid.ok then
		return fail(paid.reason or "payment failed", stock, history, wallet)
	end
	local nextStock = table.clone(stock)
	if item.stock ~= nil then
		nextStock[item.id] = (stock[item.id] or 0) - quantity
	end
	local nextHistory = table.clone(history)
	nextHistory[item.id] = (history[item.id] or 0) + quantity
	return {
		ok = true,
		reason = nil,
		quantity = quantity,
		cost = cost,
		wallet = paid.wallet,
		stock = nextStock,
		history = nextHistory,
	}
end

-- Purchase counts from untrusted saved data.
function ShopLogic.deserializeHistory(raw: any): History
	local history: History = {}
	if type(raw) ~= "table" then
		return history
	end
	for id, count in raw do
		if type(id) == "string" and isWhole(count) then
			history[id] = count
		end
	end
	return history
end

-- Robux receipts ---------------------------------------------------------------------------

function ShopLogic.newReceiptHistory(max: number?): ReceiptHistory
	local size = max or ShopLogic.DEFAULT_RECEIPT_HISTORY
	assert(isCount(size), "max must be a positive integer")
	return { ids = {}, order = {}, max = size }
end

function ShopLogic.hasReceipt(history: ReceiptHistory, purchaseId: string): boolean
	return history.ids[purchaseId] == true
end

-- Returns a new history with `purchaseId` added, forgetting the oldest ids past `max`.
function ShopLogic.recordReceipt(history: ReceiptHistory, purchaseId: string): ReceiptHistory
	if history.ids[purchaseId] then
		return history
	end
	local ids = table.clone(history.ids)
	local order = table.clone(history.order)
	ids[purchaseId] = true
	table.insert(order, purchaseId)
	while #order > history.max do
		local oldest = table.remove(order, 1)
		if oldest ~= nil then
			ids[oldest] = nil
		end
	end
	return { ids = ids, order = order, max = history.max }
end

function ShopLogic.serializeReceipts(history: ReceiptHistory): { string }
	return table.clone(history.order)
end

function ShopLogic.deserializeReceipts(raw: any, max: number?): ReceiptHistory
	local history = ShopLogic.newReceiptHistory(max)
	if type(raw) ~= "table" then
		return history
	end
	for _, id in raw do
		if type(id) == "string" then
			history = ShopLogic.recordReceipt(history, id)
		end
	end
	return history
end

local function validReceipt(receipt: any): boolean
	if type(receipt) ~= "table" or type(receipt.PurchaseId) ~= "string" then
		return false
	end
	return isCount(receipt.PlayerId) and isCount(receipt.ProductId)
end

-- Decides a ProcessReceipt callback. Returns the decision name (map it to
-- Enum.ProductPurchaseDecision) and a short reason. Grants at most once per PurchaseId as long as
-- `commit` stores the history in the same session data as the granted effects.
function ShopLogic.processReceipt(receipt: any, deps: ReceiptDeps): (ReceiptDecision, string)
	if not validReceipt(receipt) then
		return "NotProcessedYet", "invalid receipt"
	end
	local loadedOk, history = pcall(deps.loadHistory, receipt.PlayerId)
	if not loadedOk or history == nil then
		return "NotProcessedYet", "player data not loaded"
	end
	if ShopLogic.hasReceipt(history, receipt.PurchaseId) then
		return "PurchaseGranted", "already granted"
	end
	local grantedOk, granted = pcall(deps.grant, receipt.PlayerId, receipt.ProductId, receipt)
	if not grantedOk or granted ~= true then
		return "NotProcessedYet", "grant failed"
	end
	local nextHistory = ShopLogic.recordReceipt(history, receipt.PurchaseId)
	local committedOk, committed = pcall(deps.commit, receipt.PlayerId, nextHistory)
	if not committedOk or committed ~= true then
		return "NotProcessedYet", "commit failed"
	end
	return "PurchaseGranted", "granted"
end

return ShopLogic
