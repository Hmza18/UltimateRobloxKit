--!strict
-- TycoonWorldService: builds two sample plots when the place has no Plot-tagged instances, so the
-- template works the moment you press Play. Build your own plots in Studio and this does nothing.
-- Turn it off with TycoonConfig.BuildDemoWorld = false.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TycoonConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TycoonConfig"))

local PLOT_COUNT = 2
local PLOT_SPACING = 80

local TycoonWorldService = { Name = "TycoonWorldService", Priority = 5 }

local function makePart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addSign(part: BasePart, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(180, 50)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 60
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.Text = text
	label.Parent = gui
end

local function makeDropper(parent: Instance, position: Vector3, value: number): Part
	local dropper = makePart(parent, "Dropper", Vector3.new(3, 3, 3), position, Color3.fromRGB(90, 90, 110))
	dropper:SetAttribute("DropValue", value)
	dropper:SetAttribute("Interval", 2)
	dropper:AddTag(TycoonConfig.Tags.Dropper)
	return dropper
end

local function makeButton(parent: Instance, id: string, cost: number, position: Vector3, requires: string?): Part
	local button = makePart(parent, "Buy" .. id, Vector3.new(5, 1, 5), position, Color3.fromRGB(60, 200, 90))
	button:SetAttribute("ButtonId", id)
	button:SetAttribute("Cost", cost)
	button:SetAttribute("Unlocks", id)
	if requires then
		button:SetAttribute("Requires", requires)
	end
	button:AddTag(TycoonConfig.Tags.PurchaseButton)
	addSign(button, string.format("%s: %d coins", id, cost))
	return button
end

local function buildPlot(index: number)
	local origin = Vector3.new((index - 1) * PLOT_SPACING, 0, 0)
	local plot = Instance.new("Model")
	plot.Name = "Plot" .. index
	plot:SetAttribute("PlotIndex", index)

	makePart(plot, "Base", Vector3.new(60, 1, 60), origin + Vector3.new(0, 0.5, 0), Color3.fromRGB(70, 130, 70))
	local spawnMarker = makePart(plot, "Spawn", Vector3.new(4, 1, 4), origin + Vector3.new(0, 1.5, 20), Color3.new())
	spawnMarker.Transparency = 1
	spawnMarker.CanCollide = false

	local collectorColor = Color3.fromRGB(40, 160, 220)
	local collectorPosition = origin + Vector3.new(0, 1.5, -12)
	local collector = makePart(plot, "Collector", Vector3.new(26, 1, 6), collectorPosition, collectorColor)
	collector:AddTag(TycoonConfig.Tags.Collector)

	-- The first dropper is free; the other two are bought with the buttons.
	makeDropper(plot, origin + Vector3.new(-8, 9, -12), 1)
	local purchases = Instance.new("Folder")
	purchases.Name = "Purchases"
	purchases.Parent = plot
	for _, item in { { id = "Dropper2", x = 0, value = 3 }, { id = "Dropper3", x = 8, value = 8 } } do
		local model = Instance.new("Model")
		model.Name = item.id
		model.Parent = purchases
		makeDropper(model, origin + Vector3.new(item.x, 9, -12), item.value)
	end

	makeButton(plot, "Dropper2", 25, origin + Vector3.new(-6, 1.1, 6), nil)
	makeButton(plot, "Dropper3", 150, origin + Vector3.new(6, 1.1, 6), "Dropper2")

	plot:AddTag(TycoonConfig.Tags.Plot)
	plot.Parent = workspace
end

function TycoonWorldService:Init()
	if not TycoonConfig.BuildDemoWorld or #CollectionService:GetTagged(TycoonConfig.Tags.Plot) > 0 then
		return
	end
	for index = 1, PLOT_COUNT do
		buildPlot(index)
	end
end

return TycoonWorldService
