--!strict
-- DropperService: droppers (Parts tagged "Dropper") on owned plots spawn drops on a timer.
-- A drop that touches a "Collector" on the same plot pays its value to the plot owner.
-- Drops are server-owned physics parts, capped per plot, and removed after TycoonConfig.DropLifetime.
-- A dropper inside a purchase that has not been bought (attribute Purchased = false) stays idle.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TycoonConfig = require(Shared:WaitForChild("TycoonConfig"))
local TycoonMath = require(Shared:WaitForChild("Logic"):WaitForChild("TycoonMath"))

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local EconomyService = require(Services:WaitForChild("EconomyService"))
local PlotService = require(Services:WaitForChild("PlotService"))

local TICK = 0.1

local DropperService = { Name = "DropperService", Priority = 50 }

local nextDropAt: { [Instance]: number } = {}
local activeDrops: { [Instance]: number } = {}
local dropsFolder: Folder? = nil

local function numberAttribute(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" and value > 0 then value else default
end

-- False when the dropper sits inside a purchase that has not been bought yet.
local function isActive(dropper: Instance, plot: Instance): boolean
	local current: Instance? = dropper
	while current and current ~= plot do
		if current:GetAttribute("Purchased") == false then
			return false
		end
		current = current.Parent
	end
	return true
end

local function spawnDrop(dropper: BasePart, plot: Instance, owner: Player, folder: Folder)
	local count = activeDrops[plot] or 0
	if count >= TycoonConfig.MaxDropsPerPlot then
		return
	end
	local value = TycoonMath.dropValue(numberAttribute(dropper, "DropValue", 1), EconomyService:GetMultiplier(owner))
	local drop = Instance.new("Part")
	drop.Name = "Drop"
	drop.Size = Vector3.new(1, 1, 1)
	drop.Color = Color3.fromRGB(255, 200, 60)
	drop.Material = Enum.Material.SmoothPlastic
	drop.CFrame = dropper.CFrame * CFrame.new(0, -(dropper.Size.Y / 2 + 1), 0)
	drop:SetAttribute("DropValue", value)
	drop:SetAttribute("OwnerUserId", owner.UserId)
	drop.Parent = folder
	-- Server-owned physics, so clients cannot fling drops into a collector.
	drop:SetNetworkOwner(nil)
	activeDrops[plot] = count + 1
	drop.Destroying:Connect(function()
		activeDrops[plot] = math.max((activeDrops[plot] or 1) - 1, 0)
	end)
	task.delay(TycoonConfig.DropLifetime, function()
		if drop.Parent then
			drop:Destroy()
		end
	end)
end

local function watchCollector(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local collector = instance :: BasePart
	collector.Touched:Connect(function(hit: BasePart)
		local value = hit:GetAttribute("DropValue")
		if type(value) ~= "number" or hit.Parent ~= dropsFolder then
			return
		end
		local ownerId = hit:GetAttribute("OwnerUserId")
		local plot = PlotService:FindPlot(collector)
		local owner = if plot then PlotService:GetOwner(plot) else nil
		hit:Destroy()
		if owner and owner.UserId == ownerId then
			EconomyService:AddCoins(owner, value)
		end
	end)
end

local function step(folder: Folder)
	local now = os.clock()
	for _, item in CollectionService:GetTagged(TycoonConfig.Tags.Dropper) do
		local plot = PlotService:FindPlot(item)
		local owner = if plot then PlotService:GetOwner(plot) else nil
		if item:IsA("BasePart") and plot and owner and now >= (nextDropAt[item] or 0) and isActive(item, plot) then
			nextDropAt[item] = now + numberAttribute(item, "Interval", 2)
			spawnDrop(item, plot, owner, folder)
		end
	end
end

function DropperService:Start()
	local folder = Instance.new("Folder")
	folder.Name = "Drops"
	folder.Parent = workspace
	dropsFolder = folder

	for _, collector in CollectionService:GetTagged(TycoonConfig.Tags.Collector) do
		watchCollector(collector)
	end
	CollectionService:GetInstanceAddedSignal(TycoonConfig.Tags.Collector):Connect(watchCollector)
	CollectionService:GetInstanceRemovedSignal(TycoonConfig.Tags.Dropper):Connect(function(dropper: Instance)
		nextDropAt[dropper] = nil
	end)

	while true do
		step(folder)
		task.wait(TICK)
	end
end

return DropperService
