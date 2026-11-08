--!strict
-- PurchaseButtonService: buttons (Parts tagged "PurchaseButton") that the plot owner steps on to buy things.
-- Each button reveals a child of the plot's "Purchases" folder. Purchases are saved in
-- data.progress["tycoon:<ButtonId>"] = 1 and rebuilt whenever the player claims a plot.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DataSchema = require(Shared:WaitForChild("Logic"):WaitForChild("DataSchema"))
local TycoonConfig = require(Shared:WaitForChild("TycoonConfig"))
local TycoonMath = require(Shared:WaitForChild("Logic"):WaitForChild("TycoonMath"))

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local EconomyService = require(Services:WaitForChild("EconomyService"))
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local PlotService = require(Services:WaitForChild("PlotService"))

type PlayerData = DataSchema.PlayerData
type ButtonInfo = { id: string, cost: number, unlocks: string?, requires: { string } }

local KEY_PREFIX = "tycoon:"

local PurchaseButtonService = { Name = "PurchaseButtonService", Priority = 40 }

local nextTouchAt: { [Instance]: number } = {}

local function readButton(button: Instance): ButtonInfo?
	local id = button:GetAttribute("ButtonId")
	local cost = button:GetAttribute("Cost")
	if type(id) ~= "string" or type(cost) ~= "number" or cost < 0 then
		warn("[PurchaseButtonService] " .. button:GetFullName() .. " needs ButtonId and Cost attributes")
		return nil
	end
	local unlocks = button:GetAttribute("Unlocks")
	return {
		id = id,
		cost = cost,
		unlocks = if type(unlocks) == "string" then unlocks else nil,
		requires = TycoonMath.parseList(button:GetAttribute("Requires")),
	}
end

-- Shows or hides an instance and every part inside it. Original values are kept in attributes.
local function setShown(target: Instance, shown: boolean)
	local items = target:GetDescendants()
	table.insert(items, target)
	for _, item in items do
		if item:IsA("BasePart") then
			if item:GetAttribute("BaseTransparency") == nil then
				item:SetAttribute("BaseTransparency", item.Transparency)
				item:SetAttribute("BaseCanCollide", item.CanCollide)
			end
			local baseTransparency = item:GetAttribute("BaseTransparency")
			item.Transparency = if shown and type(baseTransparency) == "number" then baseTransparency else 1
			item.CanCollide = shown and item:GetAttribute("BaseCanCollide") == true
			item.CanTouch = shown
			item.CanQuery = shown
		elseif item:IsA("LayerCollector") then
			item.Enabled = shown
		end
	end
end

local function purchasedSet(player: Player?): { [string]: boolean }
	local set: { [string]: boolean } = {}
	local data = if player then PlayerDataService:Get(player) else nil
	if data then
		for key, value in data.progress do
			if value == 1 and string.sub(key, 1, #KEY_PREFIX) == KEY_PREFIX then
				set[string.sub(key, #KEY_PREFIX + 1)] = true
			end
		end
	end
	return set
end

local function buttonsIn(plot: Instance): { BasePart }
	local buttons: { BasePart } = {}
	for _, item in plot:GetDescendants() do
		if item:IsA("BasePart") and item:HasTag(TycoonConfig.Tags.PurchaseButton) then
			table.insert(buttons, item)
		end
	end
	return buttons
end

-- Makes every button and purchase in the plot match what has been bought.
local function refreshPlot(plot: Instance, purchased: { [string]: boolean })
	local purchases = plot:FindFirstChild("Purchases")
	for _, button in buttonsIn(plot) do
		local info = readButton(button)
		if info then
			local bought = purchased[info.id] == true
			setShown(button, TycoonMath.buttonState(purchased, info.id, info.requires) == "Available")
			local unlocks = info.unlocks
			local target = if purchases and unlocks then purchases:FindFirstChild(unlocks) else nil
			if target then
				setShown(target, bought)
				target:SetAttribute("Purchased", bought)
			end
		end
	end
end

-- Buys a button for the player. Returns false and a reason when the purchase is not allowed.
function PurchaseButtonService:Buy(player: Player, button: Instance): (boolean, string?)
	local info = readButton(button)
	if not info then
		return false, "button is missing attributes"
	end
	local plot = PlotService:FindPlot(button)
	if not plot or PlotService:GetOwner(plot) ~= player then
		return false, "not your plot"
	end
	local purchased = purchasedSet(player)
	local state = TycoonMath.buttonState(purchased, info.id, info.requires)
	if state ~= "Available" then
		return false, if state == "Purchased" then "already bought" else "locked"
	end
	if not EconomyService:TrySpend(player, info.cost) then
		return false, "not enough coins"
	end
	PlayerDataService:Update(player, function(data: PlayerData)
		data.progress[KEY_PREFIX .. info.id] = 1
	end)
	purchased[info.id] = true
	refreshPlot(plot, purchased)
	return true, nil
end

local function onButtonTouched(button: BasePart, hit: BasePart)
	local character = hit.Parent
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local now = os.clock()
	if (nextTouchAt[button] or 0) > now then
		return
	end
	nextTouchAt[button] = now + TycoonConfig.ButtonDebounce
	PurchaseButtonService:Buy(player, button)
end

local function watchButton(instance: Instance)
	if instance:IsA("BasePart") then
		local button = instance
		button.Touched:Connect(function(hit: BasePart)
			onButtonTouched(button, hit)
		end)
	end
end

function PurchaseButtonService:Init()
	PlotService.PlotClaimed:Connect(function(player: Player, plot: Instance)
		refreshPlot(plot, purchasedSet(player))
	end)
	PlotService.PlotReleased:Connect(function(_player: Player, plot: Instance)
		refreshPlot(plot, {})
	end)
end

function PurchaseButtonService:Start()
	for _, plot in CollectionService:GetTagged(TycoonConfig.Tags.Plot) do
		refreshPlot(plot, purchasedSet(PlotService:GetOwner(plot)))
	end
	for _, button in CollectionService:GetTagged(TycoonConfig.Tags.PurchaseButton) do
		watchButton(button)
	end
	CollectionService:GetInstanceAddedSignal(TycoonConfig.Tags.PurchaseButton):Connect(watchButton)
	CollectionService:GetInstanceRemovedSignal(TycoonConfig.Tags.PurchaseButton):Connect(function(button: Instance)
		nextTouchAt[button] = nil
	end)
end

return PurchaseButtonService
