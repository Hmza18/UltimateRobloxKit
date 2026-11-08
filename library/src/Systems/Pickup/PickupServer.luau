--!strict
-- Server adapter for PickupLogic. Spawns world items as parts with a ProximityPrompt (and/or a
-- touch trigger), checks distance, ownership and cooldowns on the server and hands items to an
-- injected `give(player, itemId, count) -> leftover` function, such as InventoryServer:give.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PickupLogic = require("./PickupLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Config = {
	give: (player: Player, itemId: string, count: number) -> number, -- returns leftover
	makeVisual: ((itemId: string, count: number) -> BasePart)?, -- default: a small neon part
	parent: Instance?, -- where world items go (default a Folder "URK_Pickups" in Workspace)
	usePrompt: boolean?, -- ProximityPrompt trigger (default true)
	useTouch: boolean?, -- Touched trigger (default false)
	promptText: string?, -- ProximityPrompt ActionText (default "Pick up")
	holdDuration: number?, -- ProximityPrompt HoldDuration (default 0)
	logic: { [string]: any }?, -- PickupLogic.new overrides (maxDistance, cooldown, ...)
	expireInterval: number?, -- seconds between despawn sweeps (default 1)
}

local PickupServer = {}

local function toVec3(position: Vector3): PickupLogic.Vec3
	return { x = position.X, y = position.Y, z = position.Z }
end

local function defaultVisual(itemId: string, _count: number): BasePart
	local part = Instance.new("Part")
	part.Name = itemId
	part.Size = Vector3.new(1, 1, 1)
	part.Material = Enum.Material.Neon
	part.CanCollide = false
	part.Anchored = true
	return part
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

function PickupServer.new(config: Config)
	assert(type(config.give) == "function", "PickupServer needs a give function")
	local state = PickupLogic.new(config.logic)
	local trove = Trove.new()
	local visuals: { [number]: BasePart } = {}
	local makeVisual = config.makeVisual or defaultVisual

	local parent = config.parent
	if parent == nil then
		local folder = Instance.new("Folder")
		folder.Name = "URK_Pickups"
		folder.Parent = workspace
		trove:Add(folder)
		parent = folder
	end

	local server = {}
	server.PickedUp = Signal.new() -- (player, itemId, taken, uid)
	server.Despawned = Signal.new() -- (uid, itemId)
	server.state = state

	local function removeVisual(uid: number)
		local part = visuals[uid]
		visuals[uid] = nil
		if part then
			part:Destroy()
		end
	end

	local function tryPickup(player: Player, uid: number)
		local position = rootPosition(player)
		if position == nil then
			return
		end
		local item = PickupLogic.get(state, uid)
		if item == nil then
			return
		end
		local itemId = item.itemId
		local function give(id: string, count: number): number
			local ok, leftover = pcall(config.give, player, id, count)
			if ok and type(leftover) == "number" then
				return leftover
			end
			warn("[PickupServer] give failed", leftover)
			return count
		end
		local result = PickupLogic.pickup(state, uid, player.UserId, toVec3(position), os.clock(), give)
		if not result.ok then
			return
		end
		if result.removed then
			removeVisual(uid)
		else
			local part = visuals[uid]
			if part then
				part:SetAttribute("Count", result.remaining)
			end
		end
		server.PickedUp:Fire(player, itemId, result.taken, uid)
	end

	-- Spawns `count` of `itemId` at `position`. `owner` gets the ownership window (for drops).
	function server:spawnItem(itemId: string, count: number, position: Vector3, owner: Player?): number?
		local ownerId = if owner then owner.UserId else nil
		local uid = PickupLogic.spawn(state, itemId, count, toVec3(position), os.clock(), ownerId)
		if uid == nil then
			return nil
		end
		local part = makeVisual(itemId, count)
		part.Position = position
		part:SetAttribute("PickupUid", uid)
		part:SetAttribute("ItemId", itemId)
		part:SetAttribute("Count", count)
		if config.usePrompt ~= false then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = config.promptText or "Pick up"
			prompt.ObjectText = itemId
			prompt.HoldDuration = config.holdDuration or 0
			prompt.MaxActivationDistance = state.config.maxDistance
			prompt.RequiresLineOfSight = false
			prompt.Parent = part
			prompt.Triggered:Connect(function(player: Player)
				tryPickup(player, uid)
			end)
		end
		if config.useTouch then
			part.Touched:Connect(function(hit: BasePart)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				if player then
					tryPickup(player, uid)
				end
			end)
		end
		part.Parent = parent
		visuals[uid] = part
		return uid
	end

	function server:removeItem(uid: number)
		PickupLogic.remove(state, uid)
		removeVisual(uid)
	end

	-- Lets other code (a custom remote, a tool) request a pickup. All rules are still checked.
	function server:requestPickup(player: Player, uid: number)
		tryPickup(player, uid)
	end

	local elapsed = 0
	local interval = config.expireInterval or 1
	trove:Connect(RunService.Heartbeat, function(deltaTime: number)
		elapsed += deltaTime
		if elapsed < interval then
			return
		end
		elapsed = 0
		local now = os.clock()
		for _, uid in PickupLogic.expire(state, now) do
			local part = visuals[uid]
			local itemId = if part then part:GetAttribute("ItemId") else nil
			removeVisual(uid)
			server.Despawned:Fire(uid, itemId)
		end
		PickupLogic.pruneCooldowns(state, now)
	end)

	function server:destroy()
		trove:Clean()
		for uid in visuals do
			removeVisual(uid)
		end
		server.PickedUp:DisconnectAll()
		server.Despawned:DisconnectAll()
	end

	return server
end

return PickupServer
