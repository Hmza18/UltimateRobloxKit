--!strict
-- DataService.luau: player profiles on top of ProfileStore (MadStudioRoblox).
-- Copy to src/server/Services/DataService.luau. Adjust the require path to where
-- ProfileStore is installed (ServerPackages via Wally, or ServerStorage).
-- API names follow the ProfileStore README; verify against the version you install.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local ProfileStore = require(ServerStorage:WaitForChild("ProfileStore")) :: any

local CURRENT_VERSION = 1

export type PlayerData = {
	version: number,
	coins: number,
	inventory: { [string]: number },
	purchaseHistory: { string },   -- receipt PurchaseIds already granted (see roblox-inventory-economy)
	settings: { music: number, sfx: number },
}

local TEMPLATE: PlayerData = {
	version = CURRENT_VERSION,
	coins = 0,
	inventory = {},
	purchaseHistory = {},
	settings = { music = 0.5, sfx = 0.8 },
}

local migrations: { [number]: (any) -> any } = {
	-- [1] = function(d) ...; return d end,   -- v1 -> v2
}

local function migrate(data: any): boolean
	local v = data.version or 1
	if v > CURRENT_VERSION then
		return false -- saved by newer code; this server must not touch it
	end
	while v < CURRENT_VERSION do
		local step = migrations[v]
		assert(step, `missing migration from v{v}`)
		step(data)
		v += 1
	end
	data.version = CURRENT_VERSION
	return true
end

-- Use a separate store name in Studio so tests never touch live saves.
local STORE_NAME = if RunService:IsStudio() then "PlayerData_Studio" else "PlayerData"
local store = ProfileStore.New(STORE_NAME, TEMPLATE)

local profiles: { [Player]: any } = {}

local DataService = {}

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players -- stop waiting if the player left
		end,
	})

	if profile == nil then
		player:Kick("Your data could not be loaded. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId) -- needed for right-to-erasure requests

	if not migrate(profile.Data) then
		profile:EndSession()
		player:Kick("This server is out of date. Please rejoin.")
		return
	end
	profile:Reconcile() -- fill in fields added to TEMPLATE since this profile was created

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Your session was opened elsewhere. Please rejoin.")
	end)

	if player.Parent ~= Players then
		profile:EndSession() -- left while loading
		return
	end

	profiles[player] = profile
	player:SetAttribute("Coins", profile.Data.coins)
	player:SetAttribute("DataLoaded", true)
end

function DataService.Init(_deps: any) end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			profile:EndSession()
			profiles[player] = nil
		end
	end)
	-- ProfileStore ends sessions on server shutdown itself; no BindToClose needed here.
end

-- Returns the live data table, or nil if not loaded. Mutations are saved automatically.
function DataService.get(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile then profile.Data :: PlayerData else nil
end

-- Returns the ProfileStore profile object (for Save/OnAfterSave in receipt handling).
function DataService.getProfile(player: Player): any
	return profiles[player]
end

-- Waits up to `timeout` seconds for a player's data.
function DataService.waitFor(player: Player, timeout: number): PlayerData?
	local deadline = os.clock() + timeout
	while os.clock() < deadline and player.Parent == Players do
		local data = DataService.get(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return nil
end

function DataService.addCoins(player: Player, amount: number): boolean
	local data = DataService.get(player)
	if not data or amount ~= amount or amount % 1 ~= 0 then
		return false
	end
	if data.coins + amount < 0 then
		return false
	end
	data.coins += amount
	player:SetAttribute("Coins", data.coins)
	return true
end

return DataService
