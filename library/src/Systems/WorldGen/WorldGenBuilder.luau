--!strict
-- Builds a WorldGenLogic layout as Parts in the workspace. Props are cloned from a folder of templates
-- (Models or BaseParts named after each prop kind); a missing template becomes a simple placeholder so
-- the layout is visible while art is in progress. Gates get a BillboardGui with the next zone's name and
-- are tagged "URK_Gate" with attributes ZoneFrom and ZoneTo, so Zones or Progression can lock them.
--
--   local layout = WorldGenLogic.generate({ seed = 42, zones = { "Spawn", "Forest", "Desert" },
--       props = { { kind = "Tree", weight = 3, radius = 4 }, { kind = "Rock", weight = 1, radius = 3 } } })
--   WorldGenBuilder.build(layout, { templates = ServerStorage.Props, palette = { "#7BC96F", "#E8C872" } })

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local WorldGenLogic = require("./WorldGenLogic")

export type Options = {
	parent: Instance?, -- default a new Folder "URK_World" in Workspace
	templates: Instance?, -- folder of prop templates named by kind
	palette: { string }?, -- floor colour per zone (cycles)
	pathColor: string?, -- default "#D9C7A3"
}

local WorldGenBuilder = {}

local DEFAULT_PALETTE = { "#7BC96F", "#E8C872", "#9AD0EC", "#C9A3E8", "#F2A07B" }

local function part(name: string, b: WorldGenLogic.Box, color: string, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(b.size[1], b.size[2], b.size[3])
	p.Position = Vector3.new(b.center[1], b.center[2], b.center[3])
	p.Color = Color3.fromHex(color)
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function placeholder(kind: string): BasePart
	local p = Instance.new("Part")
	p.Name = kind
	p.Anchored = true
	p.Size = Vector3.new(3, 4, 3)
	p.Color = Color3.fromHex("#5E8C5A")
	p.Material = Enum.Material.SmoothPlastic
	return p
end

function WorldGenBuilder.build(layout: WorldGenLogic.Layout, options: Options?): Folder
	local opts: Options = options or {}
	local folder = Instance.new("Folder")
	folder.Name = "URK_World"
	local palette = opts.palette or DEFAULT_PALETTE
	for _, zone in layout.zones do
		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = string.format("%02d_%s", zone.index, zone.name)
		zoneFolder.Parent = folder
		local floor = part("Floor", zone.floor, palette[(zone.index - 1) % #palette + 1], zoneFolder)
		floor:SetAttribute("Zone", zone.name)
		for _, prop in zone.props do
			local template = if opts.templates then opts.templates:FindFirstChild(prop.kind) else nil
			local clone: Instance = if template then template:Clone() else placeholder(prop.kind)
			local cf = CFrame.new(prop.position[1], prop.position[2], prop.position[3])
				* CFrame.Angles(0, math.rad(prop.rotation), 0)
			if clone:IsA("Model") then
				clone:ScaleTo(prop.scale)
				clone:PivotTo(cf)
			elseif clone:IsA("BasePart") then
				clone.Size *= prop.scale
				clone.CFrame = cf + Vector3.new(0, clone.Size.Y / 2, 0)
			end
			clone.Parent = zoneFolder
		end
	end
	for _, strip in layout.path do
		part("Path", strip, opts.pathColor or "#D9C7A3", folder)
	end
	local spawnPart = part("SpawnPad", layout.spawn, "#FFFFFF", folder)
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Anchored = true
	spawnLocation.Size = spawnPart.Size
	spawnLocation.CFrame = spawnPart.CFrame
	spawnLocation.Transparency = 1
	spawnLocation.Parent = folder
	for _, gate in layout.gates do
		local g = part("Gate", gate.box, "#FFD84D", folder)
		g.Transparency = 0.35
		g:SetAttribute("ZoneFrom", layout.zones[gate.between[1]].name)
		g:SetAttribute("ZoneTo", layout.zones[gate.between[2]].name)
		CollectionService:AddTag(g, "URK_Gate")
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(200, 50)
		billboard.StudsOffset = Vector3.new(0, gate.box.size[2] / 2 + 3, 0)
		billboard.AlwaysOnTop = true
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = layout.zones[gate.between[2]].name
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0
		label.Parent = billboard
		billboard.Parent = g
	end
	folder.Parent = opts.parent or Workspace
	return folder
end

return WorldGenBuilder
