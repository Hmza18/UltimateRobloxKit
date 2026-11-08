--!strict
-- RemoteEvents in one folder (ReplicatedStorage.Remotes), created on demand by the server.
-- Every server listener must pass a validator, and each player gets a token bucket per remote,
-- so spam and malformed payloads are dropped before game code sees them.
--
-- Server:  Net.onServerEvent("BuyItem", { validate = Validate.args({ isItemId }) }, function(player, itemId) end)
-- Client:  Net.fireServer("BuyItem", "Apple")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RateLimiter = require("./Logic/RateLimiter")
local Types = require("./Types")
local Validate = require("./Logic/Validate")

export type ServerOptions = {
	validate: Validate.ArgsCheck, -- required: rejects bad payloads before the handler runs
	rateLimit: RateLimiter.Options?, -- per player; defaults to DEFAULT_RATE_LIMIT
}

local FOLDER_NAME = "Remotes"
local CLIENT_TIMEOUT = 15
local DEFAULT_RATE_LIMIT: RateLimiter.Options = { capacity = 10, refillPerSecond = 5 }

local Net = {}

local remotes: { [string]: RemoteEvent } = {}
local limiters: { RateLimiter.Limiter } = {}
local cleanupConnected = false

local function getFolder(): Instance
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, CLIENT_TIMEOUT)
	if not folder then
		error("Net: ReplicatedStorage." .. FOLDER_NAME .. " never appeared. Is the server running?")
	end
	return folder :: Instance
end

-- Returns the RemoteEvent called `name`. The server creates it if needed; the client waits for it.
function Net.remote(name: string): RemoteEvent
	local cached = remotes[name]
	if cached then
		return cached
	end
	local folder = getFolder()
	local instance: Instance?
	if RunService:IsServer() then
		instance = folder:FindFirstChild(name)
		if not instance then
			local created = Instance.new("RemoteEvent")
			created.Name = name
			created.Parent = folder
			instance = created
		end
	else
		instance = folder:WaitForChild(name, CLIENT_TIMEOUT)
	end
	if not instance or not instance:IsA("RemoteEvent") then
		error("Net: no RemoteEvent called " .. name)
	end
	local remote = instance :: RemoteEvent
	remotes[name] = remote
	return remote
end

local function connectCleanup()
	if cleanupConnected then
		return
	end
	cleanupConnected = true
	Players.PlayerRemoving:Connect(function(player: Player)
		local key = tostring(player.UserId)
		for _, limiter in limiters do
			limiter:forget(key)
		end
	end)
end

-- Server only. Runs `handler(player, ...)` for requests that pass the rate limit and `options.validate`.
function Net.onServerEvent(name: string, options: ServerOptions, handler: Types.RemoteHandler): RBXScriptConnection
	assert(RunService:IsServer(), "Net.onServerEvent is server-only")
	assert(type(options.validate) == "function", "Net.onServerEvent needs options.validate")
	connectCleanup()
	local limiter = RateLimiter.new(options.rateLimit or DEFAULT_RATE_LIMIT)
	table.insert(limiters, limiter)
	local validate = options.validate
	return Net.remote(name).OnServerEvent:Connect(function(player: Player, ...: any)
		if not limiter:allow(tostring(player.UserId), os.clock()) then
			return
		end
		local ok, reason = validate(...)
		if not ok then
			if RunService:IsStudio() then
				warn(string.format("[Net] %s rejected from %s: %s", name, player.Name, reason or "invalid"))
			end
			return
		end
		handler(player, ...)
	end)
end

function Net.fireClient(name: string, player: Player, ...: any)
	Net.remote(name):FireClient(player, ...)
end

function Net.fireAllClients(name: string, ...: any)
	Net.remote(name):FireAllClients(...)
end

function Net.fireServer(name: string, ...: any)
	Net.remote(name):FireServer(...)
end

function Net.onClientEvent(name: string, handler: (...any) -> ()): RBXScriptConnection
	return Net.remote(name).OnClientEvent:Connect(handler)
end

return Net
