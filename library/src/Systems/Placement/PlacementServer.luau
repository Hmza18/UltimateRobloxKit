--!strict
-- Server adapter for Placement. Each player builds on their own plot part. Every request is validated
-- with PlacementLogic before a model is spawned, so a client cannot place out of bounds, overlap items,
-- skip limits or use items it was not allowed (options.canPlace).
-- Plot space: a BasePart whose top face is the build area; local x/z run from 0 to Size.X / Size.Z.
-- Templates: models named after item ids, with their pivot at the bottom centre.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlacementConfig = require("./PlacementConfig")
local PlacementLogic = require("./PlacementLogic")
local RateLimiter = require("../../Util/RateLimiter")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")
local Validate = require("../../Util/Validate")

export type Store = { load: (player: Player) -> any?, save: (player: Player, data: any) -> () }

export type Options = {
	catalog: PlacementLogic.Catalog,
	templates: Instance, -- folder of models named by item id
	getPlot: (player: Player) -> BasePart?, -- the player's plot part
	canPlace: ((player: Player, itemId: string) -> boolean)?, -- ownership or cost check
	store: Store?,
	config: { [string]: any }?,
}

export type Service = {
	layoutOf: (self: Service, player: Player) -> PlacementLogic.Layout?,
	clear: (self: Service, player: Player) -> (),
	reload: (self: Service, player: Player) -> (), -- call after assigning or moving the player's plot
	placed: Signal.Signal, -- (player, placed)
	removed: Signal.Signal, -- (player, placed)
	destroy: (self: Service) -> (),
}

type Session = {
	layout: PlacementLogic.Layout,
	models: { [string]: Model },
	folder: Folder,
	pending: any, -- saved data waiting for the player's plot to exist
}

local PlacementServer = {}

-- World CFrame for a plot-local position on top of the plot part.
function PlacementServer.toWorld(plot: BasePart, x: number, z: number, degrees: number): CFrame
	local offset = CFrame.new(x - plot.Size.X / 2, plot.Size.Y / 2, z - plot.Size.Z / 2)
	return plot.CFrame * offset * CFrame.Angles(0, math.rad(degrees), 0)
end

function PlacementServer.plotOf(plot: BasePart): PlacementLogic.Plot
	return { width = plot.Size.X, depth = plot.Size.Z }
end

local function getRemote(folder: Instance, name: string): RemoteEvent
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

function PlacementServer.new(options: Options): Service
	local settings: { [string]: any } = table.clone(PlacementConfig)
	for key, value in pairs(options.config or {}) do
		settings[key] = value
	end
	local config = PlacementLogic.resolveConfig(settings)
	local trove = Trove.new()
	local placedSignal = Signal.new()
	local removedSignal = Signal.new()
	trove:Add(function()
		placedSignal:DisconnectAll()
		removedSignal:DisconnectAll()
	end)
	local sessions: { [Player]: Session } = {}
	local limiter = RateLimiter.new({
		capacity = settings.requestCapacity,
		refillPerSecond = settings.requestRefillPerSecond,
	})

	local remoteFolder = ReplicatedStorage:FindFirstChild(settings.remoteFolder)
	if not remoteFolder then
		local created = Instance.new("Folder")
		created.Name = settings.remoteFolder
		created.Parent = ReplicatedStorage
		remoteFolder = created
	end
	local folder = remoteFolder :: Instance
	local placeRemote = getRemote(folder, "Place") -- (itemId, x, z, rotation)
	local moveRemote = getRemote(folder, "Move") -- (id, x, z, rotation)
	local removeRemote = getRemote(folder, "Remove") -- (id)
	local layoutRemote = getRemote(folder, "Layout") -- server to client: ({ Placed })
	local rejectedRemote = getRemote(folder, "Rejected") -- server to client: (reason)

	local coordinate = Validate.number({ min = -10000, max = 10000 })
	local rotation = Validate.integer(-64, 64)
	local id = Validate.string({ minLength = 1, maxLength = 12, pattern = "^%d+$" })
	local itemName = Validate.string({ minLength = 1, maxLength = 64 })
	local checkPlace = Validate.args({ itemName, coordinate, coordinate, rotation })
	local checkMove = Validate.args({ id, coordinate, coordinate, rotation })
	local checkRemove = Validate.args({ id })

	local function sync(player: Player)
		local session = sessions[player]
		if session then
			layoutRemote:FireClient(player, PlacementLogic.list(session.layout))
		end
	end

	local function spawnModel(player: Player, session: Session, placed: PlacementLogic.Placed)
		local plot = options.getPlot(player)
		local template = options.templates:FindFirstChild(placed.itemId)
		if plot == nil or template == nil or not template:IsA("Model") then
			return
		end
		local old = session.models[placed.id]
		if old then
			old:Destroy()
		end
		local model = template:Clone()
		local degrees = PlacementLogic.rotationDegrees(placed.rotation, config.rotationSteps)
		model:PivotTo(PlacementServer.toWorld(plot, placed.x, placed.z, degrees))
		model:SetAttribute("PlacementId", placed.id)
		model.Parent = session.folder
		session.models[placed.id] = model
	end

	local function rebuild(player: Player)
		local session = sessions[player]
		if session == nil then
			return
		end
		local plot = options.getPlot(player)
		if session.pending ~= nil and plot then
			local bounds = PlacementServer.plotOf(plot)
			local layout, dropped = PlacementLogic.deserialize(session.pending, options.catalog, bounds, config)
			if dropped > 0 then
				warn(string.format("PlacementServer: dropped %d invalid saved items for %s", dropped, player.Name))
			end
			session.layout = layout
			session.pending = nil
		end
		for _, model in session.models do
			model:Destroy()
		end
		table.clear(session.models)
		for _, placed in PlacementLogic.list(session.layout) do
			spawnModel(player, session, placed)
		end
	end

	local function reject(player: Player, reason: string?)
		rejectedRemote:FireClient(player, reason or "refused")
	end

	local function plotFor(player: Player): PlacementLogic.Plot?
		local plot = options.getPlot(player)
		if plot == nil then
			return nil
		end
		local session = sessions[player]
		if session and session.pending ~= nil then
			rebuild(player) -- the plot appeared after the player joined: load the saved layout first
		end
		return PlacementServer.plotOf(plot)
	end

	trove:Connect(placeRemote.OnServerEvent, function(player: Player, ...: any)
		local session = sessions[player]
		if session == nil or not limiter:allow(tostring(player.UserId), os.clock()) or not checkPlace(...) then
			return
		end
		local itemId, x, z, step = ...
		local plot = plotFor(player)
		if plot == nil then
			return reject(player, "no plot")
		end
		if options.canPlace and not options.canPlace(player, itemId) then
			return reject(player, "not allowed")
		end
		local request = { itemId = itemId, x = x, z = z, rotation = step }
		local ok, reason, newId = PlacementLogic.place(session.layout, request, options.catalog, plot, config)
		if not ok or newId == nil then
			return reject(player, reason)
		end
		local placed = session.layout.items[newId]
		spawnModel(player, session, placed)
		placedSignal:Fire(player, placed)
		sync(player)
	end)

	trove:Connect(moveRemote.OnServerEvent, function(player: Player, ...: any)
		local session = sessions[player]
		if session == nil or not limiter:allow(tostring(player.UserId), os.clock()) or not checkMove(...) then
			return
		end
		local placedId, x, z, step = ...
		local plot = plotFor(player)
		if plot == nil then
			return reject(player, "no plot")
		end
		local ok, reason = PlacementLogic.move(session.layout, placedId, x, z, step, options.catalog, plot, config)
		if not ok then
			return reject(player, reason)
		end
		spawnModel(player, session, session.layout.items[placedId])
		sync(player)
	end)

	trove:Connect(removeRemote.OnServerEvent, function(player: Player, ...: any)
		local session = sessions[player]
		if session == nil or not limiter:allow(tostring(player.UserId), os.clock()) or not checkRemove(...) then
			return
		end
		local placedId = ...
		local placed = PlacementLogic.remove(session.layout, placedId)
		if placed == nil then
			return reject(player, "unknown placement")
		end
		local model = session.models[placedId]
		if model then
			model:Destroy()
			session.models[placedId] = nil
		end
		removedSignal:Fire(player, placed)
		sync(player)
	end)

	local function onPlayerAdded(player: Player)
		local saved: any = nil
		if options.store then
			local ok, data = pcall(options.store.load, player)
			if ok then
				saved = data
			else
				warn("PlacementServer: load failed for " .. player.Name .. ": " .. tostring(data))
			end
		end
		if player.Parent ~= Players then
			return
		end
		local modelFolder = Instance.new("Folder")
		modelFolder.Name = "UrkPlacement_" .. player.UserId
		modelFolder.Parent = workspace
		sessions[player] = { layout = PlacementLogic.newLayout(), models = {}, folder = modelFolder, pending = saved }
		rebuild(player)
		sync(player)
	end

	local function save(player: Player)
		local session = sessions[player]
		if session and options.store then
			-- If the plot never appeared, keep the original saved data instead of an empty layout.
			local data = if session.pending ~= nil then session.pending else PlacementLogic.serialize(session.layout)
			local ok, err = pcall(options.store.save, player, data)
			if not ok then
				warn("PlacementServer: save failed for " .. player.Name .. ": " .. tostring(err))
			end
		end
	end

	local function close(player: Player)
		save(player)
		local session = sessions[player]
		if session then
			session.folder:Destroy()
			sessions[player] = nil
		end
		limiter:forget(tostring(player.UserId))
	end

	trove:Connect(Players.PlayerAdded, onPlayerAdded)
	trove:Connect(Players.PlayerRemoving, close)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	local service = {} :: Service
	service.placed = placedSignal
	service.removed = removedSignal

	function service.layoutOf(_self: Service, player: Player): PlacementLogic.Layout?
		local session = sessions[player]
		return if session then session.layout else nil
	end

	function service.clear(_self: Service, player: Player)
		local session = sessions[player]
		if session then
			session.layout = PlacementLogic.newLayout()
			rebuild(player)
			sync(player)
		end
	end

	function service.reload(_self: Service, player: Player)
		rebuild(player)
	end

	function service.destroy(_self: Service)
		for player in table.clone(sessions) do
			close(player)
		end
		trove:Clean()
	end

	return service
end

return PlacementServer
