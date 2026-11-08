--!strict
-- Server adapter for ResourcesLogic. Every instance tagged "ResourceNode" (CollectionService) with
-- a string attribute "Kind" becomes a node. Players gather through a ProximityPrompt or a Gather
-- remote; the server checks distance, cooldown and tool tier, rolls drops with Random and gives
-- them through an injected `give(player, itemId, count) -> leftover`.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RateLimiter = require("../../Util/RateLimiter")
local ResourcesLogic = require("./ResourcesLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Config = {
	defs: ResourcesLogic.Defs, -- from ResourcesLogic.newDefs
	give: (player: Player, itemId: string, count: number) -> number, -- returns leftover
	getTool: ((player: Player) -> ResourcesLogic.Tool)?, -- default: equipped Tool's Tier/Damage attributes
	tag: string?, -- CollectionService tag (default "ResourceNode")
	maxDistance: number?, -- studs from HumanoidRootPart to the node pivot (default 12)
	gatherCooldown: number?, -- seconds between hits per player (default 0.5)
	tierBonus: number?, -- see ResourcesLogic.damageFor (default 0.25)
	usePrompt: boolean?, -- add a ProximityPrompt to each node (default true)
	onDepleted: ((instance: Instance) -> ())?, -- default: hide BaseParts
	onRespawned: ((instance: Instance) -> ())?, -- default: show BaseParts again
	remoteFolderName: string?, -- default "URK_Resources"
	seed: number?, -- Random seed (default: Random.new())
}

local ResourcesServer = {}

local function defaultTool(player: Player): ResourcesLogic.Tool
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool then
		local tier = tool:GetAttribute("Tier")
		local damage = tool:GetAttribute("Damage")
		return {
			tier = if type(tier) == "number" then tier else 0,
			damage = if type(damage) == "number" then damage else 1,
		}
	end
	return { tier = 0, damage = 1 } -- bare hands
end

local function setVisible(instance: Instance, visible: boolean)
	local parts: { Instance } = instance:GetDescendants()
	table.insert(parts, instance)
	for _, part in parts do
		if part:IsA("BasePart") then
			part.Transparency = if visible then 0 else 1
			part.CanCollide = visible
		end
	end
end

local function pivotOf(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return nil
end

function ResourcesServer.new(config: Config)
	local defs = config.defs
	local tag = config.tag or "ResourceNode"
	local maxDistance = config.maxDistance or 12
	local cooldownSeconds = config.gatherCooldown or 0.5
	local getTool = config.getTool or defaultTool
	local onDepleted = config.onDepleted or function(instance: Instance)
		setVisible(instance, false)
	end
	local onRespawned = config.onRespawned or function(instance: Instance)
		setVisible(instance, true)
	end
	local random = if config.seed then Random.new(config.seed) else Random.new()
	local function rng(): number
		return random:NextNumber()
	end

	local trove = Trove.new()
	local nodes: { [Instance]: ResourcesLogic.Node } = {}
	local prompts: { [Instance]: ProximityPrompt } = {}
	local cooldowns: ResourcesLogic.Cooldowns = {}
	local limiter = RateLimiter.new({ capacity = 8, refillPerSecond = 4 })

	local folder = Instance.new("Folder")
	folder.Name = config.remoteFolderName or "URK_Resources"
	folder.Parent = ReplicatedStorage
	trove:Add(folder)
	local gatherRemote = Instance.new("RemoteEvent")
	gatherRemote.Name = "Gather"
	gatherRemote.Parent = folder

	local server = {}
	server.Gathered = Signal.new() -- (player, instance, drops, damage)
	server.Depleted = Signal.new() -- (instance, player)
	server.Respawned = Signal.new() -- (instance)

	local function publish(instance: Instance, node: ResourcesLogic.Node)
		instance:SetAttribute("Health", node.health)
		instance:SetAttribute("Depleted", node.health <= 0)
		local prompt = prompts[instance]
		if prompt then
			prompt.Enabled = node.health > 0
		end
	end

	-- Applies one hit from `player` to `instance`. Returns ok and a reason.
	function server:gather(player: Player, instance: Instance): (boolean, string?)
		local node = nodes[instance]
		if node == nil then
			return false, "not a node"
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local pivot = pivotOf(instance)
		if root == nil or not root:IsA("BasePart") or pivot == nil then
			return false, "no character"
		end
		if (root.Position - pivot).Magnitude > maxDistance then
			return false, "too far"
		end
		local now = os.clock()
		local key = tostring(player.UserId)
		if not ResourcesLogic.ready(cooldowns, key, now) then
			return false, "cooldown"
		end
		local result = ResourcesLogic.hit(defs, node, getTool(player), now, rng, { tierBonus = config.tierBonus })
		if not result.ok then
			return false, result.reason
		end
		ResourcesLogic.markCooldown(cooldowns, key, now, cooldownSeconds)
		nodes[instance] = result.node
		publish(instance, result.node)
		for _, drop in result.drops do
			local ok, leftover = pcall(config.give, player, drop.id, drop.count)
			if not ok then
				warn("[ResourcesServer] give failed", leftover)
			end
		end
		server.Gathered:Fire(player, instance, result.drops, result.damage)
		if result.depleted then
			onDepleted(instance)
			server.Depleted:Fire(instance, player)
		end
		return true, nil
	end

	local function addNode(instance: Instance)
		local kind = instance:GetAttribute("Kind")
		if type(kind) ~= "string" or ResourcesLogic.getDef(defs, kind) == nil then
			warn("[ResourcesServer] node has no valid Kind attribute:", instance:GetFullName())
			return
		end
		local node = ResourcesLogic.newNode(defs, kind)
		nodes[instance] = node
		if config.usePrompt ~= false then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Gather"
			prompt.ObjectText = kind
			prompt.MaxActivationDistance = maxDistance
			prompt.RequiresLineOfSight = false
			local host = if instance:IsA("Model") then instance.PrimaryPart or instance else instance
			prompt.Parent = host
			prompts[instance] = prompt
			prompt.Triggered:Connect(function(player: Player)
				server:gather(player, instance)
			end)
		end
		publish(instance, node)
	end

	local function removeNode(instance: Instance)
		nodes[instance] = nil
		local prompt = prompts[instance]
		prompts[instance] = nil
		if prompt then
			prompt:Destroy()
		end
	end

	for _, instance in CollectionService:GetTagged(tag) do
		addNode(instance)
	end
	trove:Connect(CollectionService:GetInstanceAddedSignal(tag), addNode)
	trove:Connect(CollectionService:GetInstanceRemovedSignal(tag), removeNode)

	trove:Connect(gatherRemote.OnServerEvent, function(player: Player, instance: any)
		if not limiter:allow(tostring(player.UserId), os.clock()) then
			return
		end
		if typeof(instance) == "Instance" and nodes[instance] ~= nil then
			server:gather(player, instance)
		end
	end)

	trove:Connect(Players.PlayerRemoving, function(player: Player)
		cooldowns[tostring(player.UserId)] = nil
		limiter:forget(tostring(player.UserId))
	end)

	local elapsed = 0
	trove:Connect(RunService.Heartbeat, function(deltaTime: number)
		elapsed += deltaTime
		if elapsed < 1 then
			return
		end
		elapsed = 0
		local now = os.clock()
		for instance, node in nodes do
			if node.health <= 0 then
				local refreshed = ResourcesLogic.refresh(defs, node, now)
				if refreshed.health > 0 then
					nodes[instance] = refreshed
					publish(instance, refreshed)
					onRespawned(instance)
					server.Respawned:Fire(instance)
				end
			end
		end
		ResourcesLogic.pruneCooldowns(cooldowns, now)
	end)

	function server:getNode(instance: Instance): ResourcesLogic.Node?
		return nodes[instance]
	end

	function server:destroy()
		trove:Clean()
		for instance in prompts do
			removeNode(instance)
		end
		server.Gathered:DisconnectAll()
		server.Depleted:DisconnectAll()
		server.Respawned:DisconnectAll()
	end

	return server
end

return ResourcesServer
