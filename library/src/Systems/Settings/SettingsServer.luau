--!strict
-- Server adapter for Settings. Loads each player's settings through the injected store, validates every
-- change a client asks for against the schema, saves a short while after the last change and on leave,
-- and sends the cleaned values back so the client always shows what the server accepted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RateLimiter = require("../../Util/RateLimiter")
local SettingsConfig = require("./SettingsConfig")
local SettingsLogic = require("./SettingsLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")
local Validate = require("../../Util/Validate")

export type Store = { load: (player: Player) -> any?, save: (player: Player, data: any) -> () }

export type Options = {
	schema: SettingsLogic.Schema?, -- default SettingsConfig.schema
	store: Store?,
	version: number?, -- default SettingsConfig.version
	migrations: { [number]: SettingsLogic.Migration }?,
	config: { [string]: any }?, -- overrides for the other SettingsConfig keys
}

export type Service = {
	get: (self: Service, player: Player) -> SettingsLogic.Values?,
	set: (self: Service, player: Player, key: string, value: any) -> (boolean, string?),
	changed: Signal.Signal, -- (player, keys, values)
	destroy: (self: Service) -> (),
}

local SettingsServer = {}

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

function SettingsServer.new(options: Options?): Service
	local opts: Options = options or {}
	local settings: { [string]: any } = table.clone(SettingsConfig)
	for key, value in opts.config or {} do
		settings[key] = value
	end
	local schema: SettingsLogic.Schema = opts.schema or (SettingsConfig.schema :: any)
	local ok, errors = SettingsLogic.validateSchema(schema)
	assert(ok, "SettingsServer: invalid schema: " .. table.concat(errors, "; "))
	local version = opts.version or settings.version

	local trove = Trove.new()
	local changed = Signal.new()
	trove:Add(function()
		changed:DisconnectAll()
	end)
	local values: { [Player]: SettingsLogic.Values } = {}
	local saveTokens: { [Player]: number } = {}
	local limiter = RateLimiter.new({
		capacity = settings.requestCapacity,
		refillPerSecond = settings.requestRefillPerSecond,
	})

	local folder = ReplicatedStorage:FindFirstChild(settings.remoteFolder)
	if not folder then
		local created = Instance.new("Folder")
		created.Name = settings.remoteFolder
		created.Parent = ReplicatedStorage
		folder = created
	end
	local updateRemote = getRemote(folder :: Instance, "Update") -- client to server: (key, value)
	local snapshotRemote = getRemote(folder :: Instance, "Snapshot") -- server to client: (values)
	local keys: { string } = {}
	for key in schema do
		table.insert(keys, key)
	end
	-- Values are plain scalars; SettingsLogic checks them against the schema afterwards.
	local function scalar(value: any): (boolean, string?)
		local kind = type(value)
		if kind == "string" or kind == "number" or kind == "boolean" then
			return true, nil
		end
		return false, "unsupported value"
	end
	local checkUpdate = Validate.args({ Validate.oneOf(keys), scalar })

	local function save(player: Player)
		local current = values[player]
		if current and opts.store then
			local saved, err = pcall(opts.store.save, player, SettingsLogic.serialize(schema, current, version))
			if not saved then
				warn("SettingsServer: save failed for " .. player.Name .. ": " .. tostring(err))
			end
		end
	end

	local function scheduleSave(player: Player)
		local token = (saveTokens[player] or 0) + 1
		saveTokens[player] = token
		task.delay(settings.saveDelay, function()
			if saveTokens[player] == token and values[player] then
				save(player)
			end
		end)
	end

	local service = {} :: Service
	service.changed = changed

	function service.get(_self: Service, player: Player): SettingsLogic.Values?
		local current = values[player]
		return if current then table.clone(current) else nil
	end

	function service.set(_self: Service, player: Player, key: string, value: any): (boolean, string?)
		local current = values[player]
		if current == nil then
			return false, "not loaded"
		end
		local nextValues, rejected = SettingsLogic.apply(schema, current, { [key] = value })
		local reason = rejected[key]
		if reason then
			snapshotRemote:FireClient(player, current) -- undo the client's optimistic change
			return false, reason
		end
		local diff = SettingsLogic.diff(current, nextValues)
		values[player] = nextValues
		snapshotRemote:FireClient(player, nextValues)
		if #diff > 0 then
			changed:Fire(player, diff, nextValues)
			scheduleSave(player)
		end
		return true, nil
	end

	trove:Connect(updateRemote.OnServerEvent, function(player: Player, ...: any)
		if not limiter:allow(tostring(player.UserId), os.clock()) or not checkUpdate(...) then
			return
		end
		local key, value = ...
		service:set(player, key, value)
	end)

	local function onPlayerAdded(player: Player)
		local saved: any = nil
		if opts.store then
			local loaded, data = pcall(opts.store.load, player)
			if loaded then
				saved = data
			else
				warn("SettingsServer: load failed for " .. player.Name .. ": " .. tostring(data))
			end
		end
		if player.Parent ~= Players then
			return
		end
		values[player] = SettingsLogic.deserialize(schema, saved, version, opts.migrations)
		snapshotRemote:FireClient(player, values[player])
	end

	trove:Connect(Players.PlayerAdded, onPlayerAdded)
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		save(player)
		values[player] = nil
		saveTokens[player] = nil
		limiter:forget(tostring(player.UserId))
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	function service.destroy(_self: Service)
		for player in values do
			save(player)
		end
		table.clear(values)
		trove:Clean()
	end

	return service
end

return SettingsServer
