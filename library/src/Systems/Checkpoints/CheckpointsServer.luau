--!strict
-- Server adapter for Checkpoints.
--   * BaseParts tagged "UrkCheckpoint" with a whole-number "Stage" attribute save progress when touched.
--   * BaseParts tagged "UrkHazard" kill the character (or deal their "Damage" attribute) on touch.
--   * Characters respawn on the checkpoint of their respawn stage.
-- Progress is mirrored to the player's "Stage" attribute and, optionally, leaderstats.Stage.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local CheckpointsLogic = require("./CheckpointsLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Store = { load: (player: Player) -> any?, save: (player: Player, data: any) -> () }

export type Options = {
	config: { [string]: any }?, -- CheckpointsLogic config; maxStage defaults to the highest tagged stage
	store: Store?,
	checkpointTag: string?, -- default "UrkCheckpoint"
	hazardTag: string?, -- default "UrkHazard"
	spawnOffset: Vector3?, -- added to the checkpoint position, default (0, 4, 0)
	touchCooldown: number?, -- seconds between touches per player and part, default 0.5
	leaderstats: boolean?, -- create leaderstats.Stage (default true)
}

export type Service = {
	getState: (self: Service, player: Player) -> CheckpointsLogic.State?,
	grantSkip: (self: Service, player: Player) -> boolean,
	reset: (self: Service, player: Player) -> (),
	respawn: (self: Service, player: Player) -> (),
	reached: Signal.Signal, -- (player, stage, result)
	destroy: (self: Service) -> (),
}

local CheckpointsServer = {}

local function characterOf(hit: BasePart): (Player?, Humanoid?)
	local model = hit:FindFirstAncestorOfClass("Model")
	if model == nil then
		return nil, nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return Players:GetPlayerFromCharacter(model), humanoid
end

function CheckpointsServer.new(options: Options?): Service
	local opts: Options = options or {}
	local checkpointTag = opts.checkpointTag or "UrkCheckpoint"
	local hazardTag = opts.hazardTag or "UrkHazard"
	local spawnOffset = opts.spawnOffset or Vector3.new(0, 4, 0)
	local cooldown = opts.touchCooldown or 0.5
	local trove = Trove.new()
	local reached = Signal.new()
	trove:Add(function()
		reached:DisconnectAll()
	end)

	local parts: { [number]: BasePart } = {}
	local config = CheckpointsLogic.resolveConfig(opts.config)
	local states: { [Player]: CheckpointsLogic.State } = {}
	local lastTouch: { [Player]: { [BasePart]: number } } = {}

	local function rebuild()
		table.clear(parts)
		local highest = 1
		for _, instance in CollectionService:GetTagged(checkpointTag) do
			local stage = instance:GetAttribute("Stage")
			if instance:IsA("BasePart") and type(stage) == "number" and stage % 1 == 0 then
				parts[stage] = instance
				highest = math.max(highest, stage)
			end
		end
		local overrides: { [string]: any } = table.clone(opts.config or {})
		if overrides.maxStage == nil then
			overrides.maxStage = highest
		end
		config = CheckpointsLogic.resolveConfig(overrides)
	end

	local function publish(player: Player)
		local state = states[player]
		if state == nil then
			return
		end
		player:SetAttribute("Stage", state.highest)
		player:SetAttribute("RespawnStage", state.stage)
		local leaderstats = player:FindFirstChild("leaderstats")
		local value = leaderstats and leaderstats:FindFirstChild("Stage")
		if value and value:IsA("IntValue") then
			value.Value = state.highest
		end
	end

	local function respawn(player: Player)
		local state = states[player]
		local character = player.Character
		if state == nil or character == nil then
			return
		end
		local _, part = CheckpointsLogic.resolveSpawn(state.stage, parts)
		if part and character:WaitForChild("HumanoidRootPart", 5) then
			character:PivotTo(part.CFrame + spawnOffset)
		end
	end

	local function onCheckpointTouched(part: BasePart, hit: BasePart)
		local player, humanoid = characterOf(hit)
		if player == nil or humanoid == nil or humanoid.Health <= 0 then
			return
		end
		local state = states[player]
		local touches = lastTouch[player]
		if state == nil or touches == nil then
			return
		end
		local now = os.clock()
		if not CheckpointsLogic.cooldownReady(touches[part], now, cooldown) then
			return
		end
		touches[part] = now
		local stage = part:GetAttribute("Stage")
		local result = CheckpointsLogic.touch(state, stage, config)
		if result == "advanced" or result == "moved" then
			publish(player)
		end
		reached:Fire(player, stage, result)
	end

	local function onHazardTouched(part: BasePart, hit: BasePart)
		local _, humanoid = characterOf(hit)
		if humanoid == nil or humanoid.Health <= 0 then
			return
		end
		local damage = part:GetAttribute("Damage")
		if type(damage) == "number" then
			humanoid:TakeDamage(damage)
		else
			humanoid.Health = 0
		end
	end

	local function watch(instance: Instance, handler: (BasePart, BasePart) -> ())
		if instance:IsA("BasePart") then
			local part = instance
			trove:Connect(part.Touched, function(hit: BasePart)
				handler(part, hit)
			end)
		end
	end

	local function onPlayerAdded(player: Player)
		local saved: any = nil
		if opts.store then
			local ok, data = pcall(opts.store.load, player)
			if ok then
				saved = data
			else
				warn("CheckpointsServer: load failed for " .. player.Name .. ": " .. tostring(data))
			end
		end
		if player.Parent ~= Players then
			return
		end
		states[player] = CheckpointsLogic.deserialize(saved, config)
		lastTouch[player] = {}
		if opts.leaderstats ~= false and player:FindFirstChild("leaderstats") == nil then
			local folder = Instance.new("Folder")
			folder.Name = "leaderstats"
			local value = Instance.new("IntValue")
			value.Name = "Stage"
			value.Parent = folder
			folder.Parent = player
		end
		publish(player)
		trove:Connect(player.CharacterAdded, function()
			respawn(player)
		end)
		if player.Character then
			respawn(player)
		end
	end

	local function save(player: Player)
		local state = states[player]
		if state and opts.store then
			local ok, err = pcall(opts.store.save, player, CheckpointsLogic.serialize(state))
			if not ok then
				warn("CheckpointsServer: save failed for " .. player.Name .. ": " .. tostring(err))
			end
		end
	end

	rebuild()
	for _, instance in CollectionService:GetTagged(checkpointTag) do
		watch(instance, onCheckpointTouched)
	end
	for _, instance in CollectionService:GetTagged(hazardTag) do
		watch(instance, onHazardTouched)
	end
	trove:Connect(CollectionService:GetInstanceAddedSignal(checkpointTag), function(instance: Instance)
		rebuild()
		watch(instance, onCheckpointTouched)
	end)
	trove:Connect(CollectionService:GetInstanceRemovedSignal(checkpointTag), rebuild)
	trove:Connect(CollectionService:GetInstanceAddedSignal(hazardTag), function(instance: Instance)
		watch(instance, onHazardTouched)
	end)
	trove:Connect(Players.PlayerAdded, onPlayerAdded)
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		save(player)
		states[player] = nil
		lastTouch[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	local service = {} :: Service
	service.reached = reached

	function service.getState(_self: Service, player: Player): CheckpointsLogic.State?
		return states[player]
	end

	function service.grantSkip(_self: Service, player: Player): boolean
		local state = states[player]
		if state == nil or not CheckpointsLogic.grantSkip(state, config) then
			return false
		end
		publish(player)
		respawn(player)
		return true
	end

	function service.reset(_self: Service, player: Player)
		local state = states[player]
		if state then
			CheckpointsLogic.reset(state, config)
			publish(player)
		end
	end

	function service.respawn(_self: Service, player: Player)
		respawn(player)
	end

	function service.destroy(_self: Service)
		for player in states do
			save(player)
		end
		trove:Clean()
	end

	return service
end

return CheckpointsServer
