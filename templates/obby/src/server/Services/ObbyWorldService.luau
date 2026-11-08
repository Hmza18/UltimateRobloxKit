--!strict
-- ObbyWorldService: builds a short sample course when the place has no Checkpoint-tagged parts,
-- so the template works the moment you press Play. Build your own course and this does nothing.

local CollectionService = game:GetService("CollectionService")

local STAGES = 5
local GAP = 14
local BUILD_DEMO_WORLD = true
local PLATFORM_COLOR = Color3.fromRGB(80, 120, 220)
local CHECKPOINT_COLOR = Color3.fromRGB(250, 200, 50)
local LAVA_COLOR = Color3.fromRGB(230, 60, 40)

local ObbyWorldService = { Name = "ObbyWorldService", Priority = 5 }

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

local function buildCourse()
	local course = Instance.new("Folder")
	course.Name = "DemoCourse"

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Anchored = true
	spawnLocation.Size = Vector3.new(12, 1, 12)
	spawnLocation.Position = Vector3.new(0, 0.5, 0)
	spawnLocation.Neutral = true
	spawnLocation.Parent = course

	for stage = 1, STAGES do
		local center = Vector3.new(0, stage * 2, -stage * GAP)
		makePart(course, "Stage" .. stage, Vector3.new(10, 1, 8), center, PLATFORM_COLOR)

		local pad = makePart(course, "Checkpoint" .. stage, Vector3.new(4, 0.4, 4), center, CHECKPOINT_COLOR)
		pad.Position = center + Vector3.new(0, 0.7, 0)
		pad.CanCollide = false
		pad:SetAttribute("Stage", stage)
		pad:AddTag("Checkpoint")

		if stage > 1 then
			-- A kill brick in the gap before every platform after the first.
			local lavaCenter = center + Vector3.new(0, -3, GAP / 2)
			local lava = makePart(course, "Lava" .. stage, Vector3.new(10, 1, GAP - 8), lavaCenter, LAVA_COLOR)
			lava.Material = Enum.Material.Neon
			lava:AddTag("KillPart")
		end
	end
	course.Parent = workspace
end

function ObbyWorldService:Init()
	if BUILD_DEMO_WORLD and #CollectionService:GetTagged("Checkpoint") == 0 then
		buildCourse()
	end
end

return ObbyWorldService
