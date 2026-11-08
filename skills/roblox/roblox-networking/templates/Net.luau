--!strict
-- Net.luau: typed remote wrapper with server-side validation and per-player rate limits.
-- Place in ReplicatedStorage.Shared. Remotes are created by the server only, inside
-- a folder named "Remotes"; clients wait for them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

export type Validator = (...any) -> boolean
export type RateLimit = { perSecond: number, burst: number }

type Bucket = { tokens: number, last: number }

local Net = {}

local folder: Folder
if IS_SERVER then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local buckets: { [string]: { [Player]: Bucket } } = {}

if IS_SERVER then
	Players.PlayerRemoving:Connect(function(player)
		for _, perPlayer in buckets do
			perPlayer[player] = nil
		end
	end)
end

-- Token bucket: refills perSecond tokens per second up to burst.
local function take(name: string, limit: RateLimit, player: Player): boolean
	local perPlayer = buckets[name]
	if not perPlayer then
		perPlayer = {}
		buckets[name] = perPlayer
	end
	local now = os.clock()
	local b = perPlayer[player]
	if not b then
		b = { tokens = limit.burst, last = now }
		perPlayer[player] = b
	end
	b.tokens = math.min(limit.burst, b.tokens + (now - b.last) * limit.perSecond)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function getRemote(name: string, className: string): Instance
	if IS_SERVER then
		local r = folder:FindFirstChild(name)
		if not r then
			r = Instance.new(className)
			r.Name = name
			r.Parent = folder
		end
		assert(r:IsA(className), `remote {name} is not a {className}`)
		return r
	end
	local r = folder:WaitForChild(name, 10)
	assert(r, `remote {name} never replicated`)
	return r
end

-- Client -> server event. The server handler only runs if the rate limit and validator pass.
function Net.event(name: string, reliable: boolean?)
	local className = if reliable == false then "UnreliableRemoteEvent" else "RemoteEvent"
	local remote = getRemote(name, className) :: any

	local api = {}

	function api.onServer(limit: RateLimit, validate: Validator, handler: (Player, ...any) -> ())
		assert(IS_SERVER, "onServer is server-only")
		remote.OnServerEvent:Connect(function(player: Player, ...: any)
			if not take(name, limit, player) then
				return -- drop silently; log aggregated counts elsewhere if needed
			end
			local ok, valid = pcall(validate, ...)
			if not ok or valid ~= true then
				return
			end
			handler(player, ...)
		end)
	end

	function api.onClient(handler: (...any) -> ())
		assert(not IS_SERVER, "onClient is client-only")
		remote.OnClientEvent:Connect(handler)
	end

	function api.fireServer(...: any)
		remote:FireServer(...)
	end

	function api.fireClient(player: Player, ...: any)
		remote:FireClient(player, ...)
	end

	function api.fireAll(...: any)
		remote:FireAllClients(...)
	end

	return api
end

-- Client -> server request with a reply. Never invoke the client from the server.
function Net.request(name: string)
	local remote = getRemote(name, "RemoteFunction") :: RemoteFunction
	local api = {}

	function api.handle(limit: RateLimit, validate: Validator, handler: (Player, ...any) -> ...any)
		assert(IS_SERVER, "handle is server-only")
		remote.OnServerInvoke = function(player: Player, ...: any)
			if not take(name, limit, player) then
				return false, "rate limited"
			end
			local ok, valid = pcall(validate, ...)
			if not ok or valid ~= true then
				return false, "invalid request"
			end
			return handler(player, ...)
		end
	end

	function api.invoke(...: any): ...any
		return remote:InvokeServer(...)
	end

	return api
end

-- Validator helpers --------------------------------------------------------

local V = {}

function V.finiteNumber(x: any, min: number, max: number): boolean
	return type(x) == "number" and x == x and x >= min and x <= max -- x == x rejects NaN
end

function V.integer(x: any, min: number, max: number): boolean
	return V.finiteNumber(x, min, max) and x % 1 == 0
end

function V.shortString(x: any, maxLen: number): boolean
	return type(x) == "string" and #x <= maxLen and utf8.len(x) ~= nil
end

function V.oneOf(x: any, set: { [string]: true }): boolean
	return type(x) == "string" and set[x] == true
end

function V.vector3(x: any, maxMagnitude: number): boolean
	return typeof(x) == "Vector3" and x.X == x.X and x.Y == x.Y and x.Z == x.Z and x.Magnitude <= maxMagnitude
end

function V.instanceOf(x: any, className: string, ancestor: Instance): boolean
	return typeof(x) == "Instance" and x:IsA(className) and x:IsDescendantOf(ancestor)
end

Net.V = V

return Net
