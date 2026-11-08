--!strict
-- Roblox adapter for ZonesLogic. Builds zones from parts tagged "UrkZone" (CollectionService)
-- and polls character positions on Heartbeat at a fixed rate. Works on the server (every
-- player) or on the client (the local player only). Fires PlayerEntered, PlayerLeft and
-- PrimaryChanged.
--
-- Part attributes: Shape ("Box" default, "Sphere" or "Prism"), ZoneId (default the part name),
-- Priority (number, default 0), Hysteresis (studs, default config.hysteresis).
-- Prism zones take their XZ outline from the part's Attachment children, sorted by name, and
-- their height from the part's Y extent.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")
local ZonesLogic = require("./ZonesLogic")

export type Mode = "server" | "client"
export type Detection = "root" | "bounds"

export type Config = {
	tag: string?, -- CollectionService tag for zone parts (default "UrkZone")
	mode: Mode?, -- default "server" on the server, "client" on a client
	rate: number?, -- updates per second (default 10)
	detection: Detection?, -- "root" (root part position, default) or "bounds" (any body part)
	hysteresis: number?, -- default Hysteresis for tagged parts, in studs (default 1)
	logic: ZonesLogic.Config?, -- exclusive, leaveDelay
	rootName: string?, -- character part used as the position (default "HumanoidRootPart")
	workspaceOnly: boolean?, -- ignore tagged parts outside Workspace (default true)
}

local Zones = {}

local function toVec3(position: Vector3): ZonesLogic.Vec3
	return { x = position.X, y = position.Y, z = position.Z }
end

local function attributeNumber(part: Instance, name: string, fallback: number): number
	local value = part:GetAttribute(name)
	if typeof(value) == "number" and value == value then
		return value
	end
	return fallback
end

local function prismFromPart(part: BasePart): ZonesLogic.Shape
	local attachments: { Attachment } = {}
	for _, child in part:GetChildren() do
		if child:IsA("Attachment") then
			table.insert(attachments, child)
		end
	end
	table.sort(attachments, function(a: Attachment, b: Attachment): boolean
		return a.Name < b.Name
	end)
	local points: { ZonesLogic.Point2 } = {}
	for _, attachment in attachments do
		local world = attachment.WorldPosition
		table.insert(points, { x = world.X, z = world.Z })
	end
	local halfHeight = part.Size.Y / 2
	return ZonesLogic.prism(points, part.Position.Y - halfHeight, part.Position.Y + halfHeight)
end

-- Reads a zone shape from a part. Errors (caught by the caller) when the part is unusable.
function Zones.shapeFromPart(part: BasePart): ZonesLogic.Shape
	local raw = part:GetAttribute("Shape")
	local kind = if typeof(raw) == "string" then string.lower(raw) else "box"
	local size = part.Size
	if kind == "sphere" then
		return ZonesLogic.sphere(toVec3(part.Position), math.min(size.X, size.Y, size.Z) / 2)
	elseif kind == "prism" then
		return prismFromPart(part)
	end
	local pitch, yaw, roll = part.CFrame:ToEulerAnglesYXZ()
	if math.abs(pitch) > 1e-3 or math.abs(roll) > 1e-3 then
		warn("[Zones] only yaw is used for box zones; tilt is ignored on", part:GetFullName())
	end
	return ZonesLogic.box(toVec3(part.Position), toVec3(size / 2), yaw)
end

function Zones.new(config: Config?)
	local cfg: Config = config or {}
	local tag = cfg.tag or "UrkZone"
	local mode: Mode = if RunService:IsServer() then "server" else "client"
	if cfg.mode ~= nil then
		mode = cfg.mode
	end
	local rate = cfg.rate or 10
	assert(type(rate) == "number" and rate > 0, "rate must be a positive number")
	local interval = 1 / rate
	local detection: Detection = cfg.detection or "root"
	local defaultHysteresis = cfg.hysteresis or 1
	local rootName = cfg.rootName or "HumanoidRootPart"
	local workspaceOnly = cfg.workspaceOnly ~= false

	local state = ZonesLogic.new(cfg.logic)
	local trove = Trove.new()
	local partTroves: { [BasePart]: any } = {}
	local idOfPart: { [BasePart]: string } = {}
	local partOfId: { [string]: BasePart } = {}

	local zones = {}
	zones.state = state
	zones.PlayerEntered = Signal.new() -- (player, zoneId, part?)
	zones.PlayerLeft = Signal.new() -- (player, zoneId, part?)
	zones.PrimaryChanged = Signal.new() -- (player, zoneId?, previousZoneId?)

	local function fire(changes: { ZonesLogic.Change })
		for _, change in changes do
			local player = change.key
			if change.kind == "enter" then
				zones.PlayerEntered:Fire(player, change.zoneId, partOfId[change.zoneId :: string])
			elseif change.kind == "leave" then
				zones.PlayerLeft:Fire(player, change.zoneId, partOfId[change.zoneId :: string])
			else
				zones.PrimaryChanged:Fire(player, change.zoneId, change.previous)
			end
		end
	end

	local function uniqueId(base: string): string
		if state.zones[base] == nil then
			return base
		end
		local index = 2
		while state.zones[base .. "#" .. index] ~= nil do
			index += 1
		end
		return base .. "#" .. index
	end

	local function removePart(part: BasePart)
		local id = idOfPart[part]
		if id then
			idOfPart[part] = nil
			partOfId[id] = nil
			fire(ZonesLogic.removeZone(state, id))
		end
		local partTrove = partTroves[part]
		if partTrove then
			partTroves[part] = nil
			partTrove:Clean()
		end
	end

	local function registerPart(part: BasePart)
		if idOfPart[part] then
			return
		end
		if workspaceOnly and not part:IsDescendantOf(workspace) then
			return
		end
		local ok, shape = pcall(Zones.shapeFromPart, part)
		if not ok then
			warn("[Zones] skipped", part:GetFullName(), shape)
			return
		end
		local rawId = part:GetAttribute("ZoneId")
		local id = uniqueId(if typeof(rawId) == "string" and rawId ~= "" then rawId else part.Name)
		local options: ZonesLogic.ZoneOptions = {
			priority = attributeNumber(part, "Priority", 0),
			hysteresis = math.max(0, attributeNumber(part, "Hysteresis", defaultHysteresis)),
			data = part,
		}
		ZonesLogic.addZone(state, id, shape, options)
		idOfPart[part] = id
		partOfId[id] = part
	end

	local function watchPart(instance: Instance)
		if not instance:IsA("BasePart") or partTroves[instance] then
			return
		end
		local part = instance :: BasePart
		local partTrove = Trove.new()
		partTroves[part] = partTrove
		partTrove:Connect(part.AncestryChanged, function()
			if idOfPart[part] and workspaceOnly and not part:IsDescendantOf(workspace) then
				local id = idOfPart[part]
				idOfPart[part] = nil
				partOfId[id] = nil
				fire(ZonesLogic.removeZone(state, id))
			elseif idOfPart[part] == nil then
				registerPart(part)
			end
		end)
		registerPart(part)
	end

	trove:Connect(CollectionService:GetInstanceAddedSignal(tag), watchPart)
	trove:Connect(CollectionService:GetInstanceRemovedSignal(tag), function(instance: Instance)
		if instance:IsA("BasePart") then
			removePart(instance)
		end
	end)
	for _, instance in CollectionService:GetTagged(tag) do
		watchPart(instance)
	end

	local function trackedPlayers(): { Player }
		if mode == "client" then
			local localPlayer = Players.LocalPlayer
			return if localPlayer then { localPlayer } else {}
		end
		return Players:GetPlayers()
	end

	local function rootOf(player: Player): BasePart?
		local character = player.Character
		local root = character and character:FindFirstChild(rootName)
		if root and root:IsA("BasePart") then
			return root
		end
		return nil
	end

	-- "bounds" detection: a player is in a box or sphere zone when any character part overlaps it.
	-- Two queries per zone: the exact shape for new entries, the hysteresis-grown one for members.
	local function applyBounds(raw: { [any]: ZonesLogic.IdSet }, characters: { [Model]: Player })
		local list: { Instance } = {}
		for character in characters do
			table.insert(list, character)
		end
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = list
		local function playersTouching(parts: { BasePart }): { [Player]: boolean }
			local found: { [Player]: boolean } = {}
			for _, hit in parts do
				local model = hit:FindFirstAncestorOfClass("Model")
				local player = model and characters[model]
				if player then
					found[player] = true
				end
			end
			return found
		end
		for _, zone in state.order do
			local shape = zone.shape
			if shape.kind == "prism" then
				continue
			end
			local exact: { BasePart }
			local grown: { BasePart }
			if shape.kind == "box" then
				local box = shape :: ZonesLogic.Box
				local h = box.halfSize
				local frame = CFrame.new(box.center.x, box.center.y, box.center.z) * CFrame.Angles(0, box.yaw, 0)
				local size = Vector3.new(h.x * 2, h.y * 2, h.z * 2)
				local grow = Vector3.one * (zone.hysteresis * 2)
				exact = workspace:GetPartBoundsInBox(frame, size, params)
				grown = workspace:GetPartBoundsInBox(frame, size + grow, params)
			else
				local sphere = shape :: ZonesLogic.Sphere
				local center = Vector3.new(sphere.center.x, sphere.center.y, sphere.center.z)
				exact = workspace:GetPartBoundsInRadius(center, sphere.radius, params)
				grown = workspace:GetPartBoundsInRadius(center, sphere.radius + zone.hysteresis, params)
			end
			local inExact = playersTouching(exact)
			local inGrown = playersTouching(grown)
			for _, player in characters do
				local set = raw[player]
				if set then
					local member = ZonesLogic.isIn(state, player, zone.id)
					local inside = if member then inGrown[player] else inExact[player]
					set[zone.id] = if inside then true else nil
				end
			end
		end
	end

	local function step()
		local raw: { [any]: ZonesLogic.IdSet } = {}
		local characters: { [Model]: Player } = {}
		for _, player in trackedPlayers() do
			local root = rootOf(player)
			if root then
				raw[player] = ZonesLogic.zonesAt(state, toVec3(root.Position), player)
				characters[root.Parent :: Model] = player
			end
		end
		if detection == "bounds" then
			applyBounds(raw, characters)
		end
		fire(ZonesLogic.updateRaw(state, raw, os.clock()))
	end

	local elapsed = 0
	trove:Connect(RunService.Heartbeat, function(deltaTime: number)
		elapsed += deltaTime
		if elapsed < interval then
			return
		end
		elapsed = math.min(elapsed - interval, interval)
		step()
	end)

	trove:Connect(Players.PlayerRemoving, function(player: Player)
		fire(ZonesLogic.removeKey(state, player))
	end)

	-- Adds a zone from code (no part). Returns the zone id.
	function zones:addZone(id: string, shape: ZonesLogic.Shape, options: ZonesLogic.ZoneOptions?): string
		ZonesLogic.addZone(state, id, shape, options)
		return id
	end

	function zones:removeZone(id: string)
		local part = partOfId[id]
		if part then
			removePart(part)
		else
			fire(ZonesLogic.removeZone(state, id))
		end
	end

	-- Re-reads the shapes of tagged parts, for example after moving or resizing them.
	function zones:refresh()
		for part, id in table.clone(idOfPart) do
			idOfPart[part] = nil
			partOfId[id] = nil
			fire(ZonesLogic.removeZone(state, id))
			registerPart(part)
		end
	end

	-- Runs one update immediately instead of waiting for the next poll.
	function zones:update()
		step()
	end

	function zones:getZones(player: Player): { string }
		return ZonesLogic.zonesOf(state, player)
	end

	function zones:getPrimary(player: Player): string?
		return ZonesLogic.primaryOf(state, player)
	end

	function zones:isIn(player: Player, id: string): boolean
		return ZonesLogic.isIn(state, player, id)
	end

	function zones:getPlayers(id: string): { Player }
		local players: { Player } = {}
		for _, key in ZonesLogic.keysIn(state, id) do
			table.insert(players, key)
		end
		return players
	end

	function zones:destroy()
		trove:Clean()
		for part in table.clone(partTroves) do
			removePart(part)
		end
		zones.PlayerEntered:DisconnectAll()
		zones.PlayerLeft:DisconnectAll()
		zones.PrimaryChanged:DisconnectAll()
	end

	return zones
end

return Zones
