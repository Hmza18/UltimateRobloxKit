--!strict
-- PlotService: gives each player one plot (an instance tagged "Plot") once their data has loaded,
-- and frees it when they leave. Plots are handed out in PlotIndex attribute order, then by name.
-- The owner's UserId is mirrored to the plot's "OwnerUserId" attribute.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local TycoonConfig = require(Shared:WaitForChild("TycoonConfig"))
local TycoonMath = require(Shared:WaitForChild("Logic"):WaitForChild("TycoonMath"))

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))

local PlotService = {
	Name = "PlotService",
	Priority = 30,
	-- Fires (player, plot) after a player claims a plot.
	PlotClaimed = Signal.new(),
	-- Fires (player, plot) when a plot is released, before its owner is cleared.
	PlotReleased = Signal.new(),
}

local plotOwners: { [Instance]: Player } = {}
local playerPlots: { [Player]: Instance } = {}

local function orderOf(plot: Instance): number
	local index = plot:GetAttribute("PlotIndex")
	return if type(index) == "number" then index else math.huge
end

local function sortedPlots(): { Instance }
	local plots = CollectionService:GetTagged(TycoonConfig.Tags.Plot)
	table.sort(plots, function(a: Instance, b: Instance): boolean
		if orderOf(a) ~= orderOf(b) then
			return orderOf(a) < orderOf(b)
		end
		return a.Name < b.Name
	end)
	return plots
end

function PlotService:GetPlot(player: Player): Instance?
	return playerPlots[player]
end

function PlotService:GetOwner(plot: Instance): Player?
	return plotOwners[plot]
end

-- The plot an instance belongs to: the instance itself or its nearest ancestor tagged "Plot".
function PlotService:FindPlot(instance: Instance): Instance?
	local current: Instance? = instance
	while current do
		if current:HasTag(TycoonConfig.Tags.Plot) then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Where the owner's character appears: a child Part named "Spawn", or the plot itself.
function PlotService:GetSpawnCFrame(plot: Instance): CFrame?
	local marker = plot:FindFirstChild("Spawn")
	if marker and marker:IsA("BasePart") then
		return marker.CFrame + Vector3.new(0, 4, 0)
	end
	if plot:IsA("PVInstance") then
		return plot:GetPivot() + Vector3.new(0, 4, 0)
	end
	return nil
end

local function moveToPlot(player: Player)
	local plot = playerPlots[player]
	local character = player.Character
	if not plot or not character then
		return
	end
	local target = PlotService:GetSpawnCFrame(plot)
	if target and character:WaitForChild("HumanoidRootPart", 5) then
		character:PivotTo(target)
	end
end

-- Claims the first free plot. Returns the plot, or nil when every plot is taken.
function PlotService:Claim(player: Player): Instance?
	local existing = playerPlots[player]
	if existing then
		return existing
	end
	local plots = sortedPlots()
	local taken: { [number]: boolean } = {}
	for index, plot in plots do
		if plotOwners[plot] then
			taken[index] = true
		end
	end
	local index = TycoonMath.nextFreePlot(taken, #plots)
	if not index then
		warn("[PlotService] no free plot for " .. player.Name)
		return nil
	end
	local plot = plots[index]
	plotOwners[plot] = player
	playerPlots[player] = plot
	plot:SetAttribute("OwnerUserId", player.UserId)
	self.PlotClaimed:Fire(player, plot)
	task.spawn(moveToPlot, player)
	return plot
end

function PlotService:Release(player: Player)
	local plot = playerPlots[player]
	if not plot then
		return
	end
	self.PlotReleased:Fire(player, plot)
	plotOwners[plot] = nil
	playerPlots[player] = nil
	plot:SetAttribute("OwnerUserId", nil)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		moveToPlot(player)
	end)
end

function PlotService:Init()
	PlayerDataService.Loaded:Connect(function(player: Player)
		self:Claim(player)
	end)
end

function PlotService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		self:Release(player)
	end)
end

return PlotService
