--!strict
-- Server adapter for ShopLogic. Prices are always computed here: the client only names an item
-- and a quantity. Payment goes through a CurrencyServer, the item is granted by a callback, and
-- Robux developer products go through an idempotent ProcessReceipt handler.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyLogic = require("../Currency/CurrencyLogic")
local RateLimiter = require("../../Util/RateLimiter")
local ShopLogic = require("./ShopLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")
local Validate = require("../../Util/Validate")

export type Store = { load: (userId: number) -> any?, save: (userId: number, data: any) -> boolean }

-- The parts of CurrencyServer the shop needs.
export type CurrencyAdapter = {
	getWallet: (self: any, player: Player) -> CurrencyLogic.Wallet?,
	setWallet: (self: any, player: Player, wallet: CurrencyLogic.Wallet) -> (),
}

export type Config = {
	catalog: ShopLogic.Catalog, -- from ShopLogic.newCatalog
	currencyConfig: CurrencyLogic.Config, -- the same config the CurrencyServer uses
	currency: CurrencyAdapter, -- usually a CurrencyServer
	grant: (player: Player, item: ShopLogic.Item, quantity: number) -> boolean, -- give the item
	store: Store?, -- persists purchase counts and Robux receipt ids
	products: { [number]: (player: Player, receipt: ShopLogic.ReceiptInfo) -> boolean }?, -- Robux
	receiptHistorySize: number?, -- receipt ids kept per player (default 100)
	remoteFolderName: string?, -- default "URK_Shop"
	rateLimit: RateLimiter.Options?, -- default 5 burst, 2 per second
	bindProcessReceipt: boolean?, -- set MarketplaceService.ProcessReceipt (default true when products)
}

type PlayerState = { history: ShopLogic.History, receipts: ShopLogic.ReceiptHistory, loadFailed: boolean }

local ShopServer = {}

local function getFolder(name: string): Instance
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = ReplicatedStorage
	return folder
end

function ShopServer.new(config: Config)
	local catalog = config.catalog
	local store = config.store
	local historySize = config.receiptHistorySize or ShopLogic.DEFAULT_RECEIPT_HISTORY
	local limiter = RateLimiter.new(config.rateLimit or { capacity = 5, refillPerSecond = 2 })
	local trove = Trove.new()
	local states: { [Player]: PlayerState } = {}
	local busy: { [Player]: boolean } = {}
	local stock = ShopLogic.newStock(catalog)

	local folder = getFolder(config.remoteFolderName or "URK_Shop")
	trove:Add(folder)
	local purchaseRemote = Instance.new("RemoteFunction")
	purchaseRemote.Name = "Purchase"
	purchaseRemote.Parent = folder
	local catalogRemote = Instance.new("RemoteFunction")
	catalogRemote.Name = "GetCatalog"
	catalogRemote.Parent = folder

	local server = {}
	server.Purchased = Signal.new() -- (player, itemId, quantity, cost)
	server.ReceiptGranted = Signal.new() -- (player, productId, purchaseId)

	local function savePlayer(player: Player): boolean
		local state = states[player]
		if store == nil or state == nil or state.loadFailed then
			return false
		end
		local data = { h = state.history, r = ShopLogic.serializeReceipts(state.receipts) }
		local ok, saved = pcall(store.save, player.UserId, data)
		return ok and saved == true
	end

	function server:loadPlayer(player: Player)
		local state: PlayerState = {
			history = {},
			receipts = ShopLogic.newReceiptHistory(historySize),
			loadFailed = false,
		}
		if store then
			local ok, raw = pcall(store.load, player.UserId)
			if ok and type(raw) == "table" then
				state.history = ShopLogic.deserializeHistory(raw.h)
				state.receipts = ShopLogic.deserializeReceipts(raw.r, historySize)
			elseif not ok then
				state.loadFailed = true
				warn("[ShopServer] load failed for", player.UserId, raw)
			end
		end
		if player.Parent ~= nil then
			states[player] = state
		end
	end

	function server:unloadPlayer(player: Player)
		savePlayer(player)
		states[player] = nil
		busy[player] = nil
		limiter:forget(tostring(player.UserId))
	end

	server.savePlayer = function(_self: any, player: Player): boolean
		return savePlayer(player)
	end

	-- Buys `quantity` of `itemId` for a player. Returns ok and a reason. Also used by the remote.
	function server:purchase(player: Player, itemId: string, quantity: number?): (boolean, string?)
		local state = states[player]
		local wallet = config.currency:getWallet(player)
		if state == nil or wallet == nil then
			return false, "not loaded"
		end
		if busy[player] then
			return false, "busy"
		end
		local request = { itemId = itemId, quantity = quantity, now = os.time() }
		local result = ShopLogic.purchase(catalog, config.currencyConfig, stock, state.history, wallet, request)
		if not result.ok then
			return false, result.reason
		end
		local item = ShopLogic.getItem(catalog, itemId)
		if item == nil then
			return false, "unknown item"
		end
		-- Commit before granting: nothing yields between the price check and the commit.
		busy[player] = true
		local previousStock, previousHistory = stock, state.history
		stock = result.stock
		state.history = result.history
		config.currency:setWallet(player, result.wallet)
		local ok, granted = pcall(config.grant, player, item, result.quantity)
		busy[player] = nil
		if not ok or granted ~= true then
			-- Roll back: refund on top of the current wallet and restore stock and limits.
			local current = config.currency:getWallet(player)
			if current then
				for currency, amount in result.cost do
					if amount > 0 then
						current = CurrencyLogic.add(config.currencyConfig, current, currency, amount, "refund").wallet
					end
				end
				config.currency:setWallet(player, current)
			end
			stock = previousStock
			state.history = previousHistory
			warn("[ShopServer] grant failed for", itemId, granted)
			return false, "grant failed"
		end
		server.Purchased:Fire(player, itemId, result.quantity, result.cost)
		return true, nil
	end

	-- A client-safe view of the catalog with current prices and what this player can still buy.
	function server:describe(player: Player): { any }
		local state = states[player]
		local history = if state then state.history else {}
		local now = os.time()
		local list = {}
		for _, id in catalog.order do
			local item = catalog.items[id]
			local price = ShopLogic.priceFor(catalog, id, now)
			table.insert(list, {
				id = id,
				price = price,
				basePrice = item.prices,
				discount = ShopLogic.activeDiscount(item, now),
				remaining = ShopLogic.remaining(catalog, stock, history, id),
			})
		end
		return list
	end

	local checkPurchase = Validate.args({
		Validate.string({ minLength = 1, maxLength = 100 }),
		Validate.optional(Validate.integer(1, 1000)),
	})

	purchaseRemote.OnServerInvoke = function(player: Player, ...: any)
		if not limiter:allow(tostring(player.UserId), os.clock()) then
			return false, "rate limited"
		end
		local valid = checkPurchase(...)
		if not valid then
			return false, "invalid request"
		end
		local itemId, quantity = ...
		return server:purchase(player, itemId, quantity)
	end

	catalogRemote.OnServerInvoke = function(player: Player)
		if not limiter:allow(tostring(player.UserId), os.clock()) then
			return nil
		end
		return server:describe(player)
	end

	-- Robux developer products.
	local products = config.products
	local function processReceipt(receipt: any)
		local decision = ShopLogic.processReceipt(receipt, {
			loadHistory = function(userId: number): ShopLogic.ReceiptHistory?
				local player = Players:GetPlayerByUserId(userId)
				local state = if player then states[player] else nil
				if state == nil or state.loadFailed then
					return nil
				end
				return state.receipts
			end,
			grant = function(userId: number, productId: number, info: ShopLogic.ReceiptInfo): boolean
				local player = Players:GetPlayerByUserId(userId)
				local handler = if products then products[productId] else nil
				if player == nil or handler == nil then
					return false
				end
				return handler(player, info) == true
			end,
			commit = function(userId: number, history: ShopLogic.ReceiptHistory): boolean
				local player = Players:GetPlayerByUserId(userId)
				local state = if player then states[player] else nil
				if player == nil or state == nil then
					return false
				end
				state.receipts = history
				server.ReceiptGranted:Fire(player, receipt.ProductId, receipt.PurchaseId)
				-- Without a store the receipt lives in session memory only; with one, save now.
				return store == nil or savePlayer(player)
			end,
		})
		if decision == "PurchaseGranted" then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	server.processReceipt = function(_self: any, receipt: any)
		return processReceipt(receipt)
	end

	local bind = config.bindProcessReceipt
	if bind == nil then
		bind = products ~= nil
	end
	if bind then
		MarketplaceService.ProcessReceipt = processReceipt
	end

	trove:Connect(Players.PlayerAdded, function(player: Player)
		server:loadPlayer(player)
	end)
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		server:unloadPlayer(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(server.loadPlayer, server, player)
	end
	if store then
		game:BindToClose(function()
			for player in states do
				savePlayer(player)
			end
		end)
	end

	function server:destroy()
		trove:Clean()
		server.Purchased:DisconnectAll()
		server.ReceiptGranted:DisconnectAll()
		purchaseRemote.OnServerInvoke = nil
		catalogRemote.OnServerInvoke = nil
	end

	return server
end

return ShopServer
