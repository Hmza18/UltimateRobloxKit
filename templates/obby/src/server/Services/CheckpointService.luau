--!strict
-- CheckpointService: saved obby progress.
--   * Parts tagged "Checkpoint" with a whole-number "Stage" attribute (1 = start) save progress
--     when touched, but only one stage at a time (Logic/StageProgress).
--   * Parts tagged "KillPart" reset the character that touches them.
--   * Characters respawn on the checkpoint of their saved stage.
-- The stage is saved in data.progress["obby:stage"] and mirrored to the player's "Stage" attribute.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DataSchema = require(Shared:WaitForChild("Logic"):WaitForChild("DataSchema"))
local StageProgress = require(Shared:WaitForChild("Logic"):WaitForChild("StageProgress"))

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))

type PlayerData = DataSchema.PlayerData

local CHECKPOINT_TAG = "Checkpoint"
local KILL_TAG = "KillPart"
local STAGE_KEY = "obby:stage"

local CheckpointService = { Name = "CheckpointService", Priority = 30 }

local checkpoints: { [number]: BasePart } = {}
local maxStage = 1

local function rebuildStages()
	table.clear(checkpoints)
	maxStage = 1
	for _, instance in CollectionService:GetTagged(CHECKPOINT_TAG) do
		local stage = instance:GetAttribute("Stage")
		if instance:IsA("BasePart") and type(stage) == "number" and stage >= 1 and stage % 1 == 0 then
			checkpoints[stage] = instance
			maxStage = math.max(maxStage, stage)
		end
	end
end

local function humanoidOf(hit: BasePart): (Player?, Humanoid?)
	local character = hit.Parent
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not humanoid:IsA("Humanoid") then
		return nil, nil
	end
	return Players:GetPlayerFromCharacter(character), humanoid
end

function CheckpointService:GetStage(player: Player): number
	local data = PlayerDataService:Get(player)
	return StageProgress.clamp(if data then data.progress[STAGE_KEY] else nil, maxStage)
end

function CheckpointService:GetMaxStage(): number
	return maxStage
end

-- Saves `stage` for the player if it is the next one. Returns the result from StageProgress.advance.
function CheckpointService:Reach(player: Player, stage: number): StageProgress.Result
	local nextStage, result = StageProgress.advance(self:GetStage(player), stage, maxStage)
	if result == "advanced" then
		PlayerDataService:Update(player, function(data: PlayerData)
			data.progress[STAGE_KEY] = nextStage
		end)
		player:SetAttribute("Stage", nextStage)
	end
	return result
end

local function respawnAtCheckpoint(player: Player, character: Model)
	local checkpoint = checkpoints[CheckpointService:GetStage(player)] or checkpoints[1]
	if checkpoint and character:WaitForChild("HumanoidRootPart", 5) then
		character:PivotTo(checkpoint.CFrame + Vector3.new(0, 4, 0))
	end
end

local function watchCheckpoint(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local part = instance :: BasePart
	part.Touched:Connect(function(hit: BasePart)
		local player, humanoid = humanoidOf(hit)
		local stage = part:GetAttribute("Stage")
		if player and humanoid and humanoid.Health > 0 and type(stage) == "number" then
			CheckpointService:Reach(player, stage)
		end
	end)
end

local function watchKillPart(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local part = instance :: BasePart
	part.Touched:Connect(function(hit: BasePart)
		local _, humanoid = humanoidOf(hit)
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		respawnAtCheckpoint(player, character)
	end)
end

function CheckpointService:Init()
	PlayerDataService.Loaded:Connect(function(player: Player)
		player:SetAttribute("Stage", self:GetStage(player))
		local character = player.Character
		if character then
			respawnAtCheckpoint(player, character)
		end
	end)
end

function CheckpointService:Start()
	rebuildStages()
	for _, instance in CollectionService:GetTagged(CHECKPOINT_TAG) do
		watchCheckpoint(instance)
	end
	for _, instance in CollectionService:GetTagged(KILL_TAG) do
		watchKillPart(instance)
	end
	CollectionService:GetInstanceAddedSignal(CHECKPOINT_TAG):Connect(function(instance: Instance)
		rebuildStages()
		watchCheckpoint(instance)
	end)
	CollectionService:GetInstanceRemovedSignal(CHECKPOINT_TAG):Connect(rebuildStages)
	CollectionService:GetInstanceAddedSignal(KILL_TAG):Connect(watchKillPart)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return CheckpointService
