--!strict
-- ReceiptService.luau: idempotent developer product handling.
-- Depends on the DataService template from the roblox-data-persistence skill
-- (DataService.get, DataService.getProfile) and a server-side product table.
--
-- Rules this implements:
-- 1. Exactly one ProcessReceipt callback in the whole place.
-- 2. Grant only when the player is in this server and their data is loaded.
-- 3. Record the PurchaseId in the same saved document as the reward, so the grant
--    and the "already granted" marker are saved together.
-- 4. Return PurchaseGranted only after that document is saved; otherwise
--    NotProcessedYet so Roblox retries later (on join or in another server).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DataService = require(ServerScriptService.Server.Services.DataService)

type Data = DataService.PlayerData

-- Server-side product table. Never let the client choose the reward.
local PRODUCTS: { [number]: (Player, Data) -> () } = {
	[111111111] = function(player, data) -- placeholder id: replace with your real product id
		data.coins += 1000
		player:SetAttribute("Coins", data.coins)
	end,
	[222222222] = function(_player, data) -- placeholder id
		data.inventory["potion_heal"] = (data.inventory["potion_heal"] or 0) + 5
	end,
}

local HISTORY_LIMIT = 100 -- keep the newest ids; old receipts will not be retried

local function waitForSave(profile: any, timeout: number): boolean
	-- ProfileStore exposes Save() and an OnAfterSave signal; verify names for your version.
	if profile.Save == nil or profile.OnAfterSave == nil then
		return true -- library without explicit save; rely on its session-locked auto-save
	end
	local saved = false
	local conn = profile.OnAfterSave:Connect(function()
		saved = true
	end)
	profile:Save()
	local deadline = os.clock() + timeout
	while not saved and os.clock() < deadline do
		task.wait(0.1)
	end
	conn:Disconnect()
	return saved
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- retried when they rejoin
	end

	local data = DataService.waitFor(player, 15)
	local profile = DataService.getProfile(player)
	if not data or not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receipt.PurchaseId)
	if table.find(data.purchaseHistory, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted earlier
	end

	local grant = PRODUCTS[receipt.ProductId]
	if not grant then
		warn(`Unknown product {receipt.ProductId}; leaving receipt unprocessed`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, err = pcall(grant, player, data)
	if not ok then
		warn(`Grant failed for {purchaseId}: {err}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	table.insert(data.purchaseHistory, purchaseId)
	while #data.purchaseHistory > HISTORY_LIMIT do
		table.remove(data.purchaseHistory, 1)
	end

	if not waitForSave(profile, 10) then
		-- The grant and the id are both in memory and will be saved together later.
		-- Returning NotProcessedYet is safe: a retry finds the id and returns Granted.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.ProcessReceipt = processReceipt

return {}
