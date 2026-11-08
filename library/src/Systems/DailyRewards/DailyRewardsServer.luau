--!strict
-- Server adapter for DailyRewardsLogic. The client asks to claim; the server reads its own clock
-- (os.time, UTC), grants through a callback and commits the new streak only after the grant
-- succeeds. One claim at a time per player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyRewardsLogic = require("./DailyRewardsLogic")
local RateLimiter = require("../../Util/RateLimiter")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Store = { load: (userId: number) -> any?, save: (userId: number, data: any) -> boolean }

export type Config = {
	config: DailyRewardsLogic.Config, -- from DailyRewardsLogic.newConfig
	grant: (player: Player, reward: any, streak: number) -> boolean, -- give the reward
	store: Store?, -- persists streaks
	clock: (() -> number)?, -- unix seconds (default os.time)
	remoteFolderName: string?, -- default "URK_DailyRewards"
	saveAfterClaim: boolean?, -- save right after each claim (default true)
}

local DailyRewardsServer = {}

function DailyRewardsServer.new(options: Config)
	local config = options.config
	local clock = options.clock or os.time
	local store = options.store
	local trove = Trove.new()
	local states: { [Player]: DailyRewardsLogic.State } = {}
	local loadFailed: { [Player]: boolean } = {}
	local busy: { [Player]: boolean } = {}
	local limiter = RateLimiter.new({ capacity = 3, refillPerSecond = 1 })

	local folder = Instance.new("Folder")
	folder.Name = options.remoteFolderName or "URK_DailyRewards"
	folder.Parent = ReplicatedStorage
	trove:Add(folder)
	local claimRemote = Instance.new("RemoteFunction")
	claimRemote.Name = "Claim"
	claimRemote.Parent = folder
	local statusRemote = Instance.new("RemoteFunction")
	statusRemote.Name = "GetStatus"
	statusRemote.Parent = folder

	local server = {}
	server.Claimed = Signal.new() -- (player, reward, streak)

	local function savePlayer(player: Player): boolean
		local state = states[player]
		if store == nil or state == nil or loadFailed[player] then
			return false
		end
		local ok, saved = pcall(store.save, player.UserId, DailyRewardsLogic.serialize(state))
		return ok and saved == true
	end

	function server:status(player: Player): DailyRewardsLogic.Status?
		local state = states[player]
		if state == nil then
			return nil
		end
		return DailyRewardsLogic.status(config, state, clock())
	end

	function server:claim(player: Player): DailyRewardsLogic.ClaimResult?
		local state = states[player]
		if state == nil or busy[player] then
			return nil
		end
		local result = DailyRewardsLogic.claim(config, state, clock())
		if not result.ok then
			return result
		end
		busy[player] = true
		local ok, granted = pcall(options.grant, player, result.reward, result.streak)
		busy[player] = nil
		if not ok or granted ~= true then
			warn("[DailyRewardsServer] grant failed", granted)
			return {
				ok = false,
				reason = "grant failed",
				state = state,
				streak = state.streak,
				rewardIndex = result.rewardIndex,
				reward = nil,
			}
		end
		if states[player] == nil then
			return nil
		end
		states[player] = result.state
		if options.saveAfterClaim ~= false then
			savePlayer(player)
		end
		server.Claimed:Fire(player, result.reward, result.streak)
		return result
	end

	function server:loadPlayer(player: Player)
		local state = DailyRewardsLogic.new()
		if store then
			local ok, raw = pcall(store.load, player.UserId)
			if ok then
				state = DailyRewardsLogic.deserialize(raw)
			else
				loadFailed[player] = true
				warn("[DailyRewardsServer] load failed for", player.UserId, raw)
			end
		end
		if player.Parent ~= nil then
			states[player] = state
		end
	end

	-- A player whose data failed to load must not claim: that could hand out a second reward.
	local function canUse(player: Player): boolean
		return not loadFailed[player] and limiter:allow(tostring(player.UserId), os.clock())
	end

	claimRemote.OnServerInvoke = function(player: Player)
		if not canUse(player) then
			return { ok = false, reason = "unavailable" }
		end
		local result = server:claim(player)
		if result == nil then
			return { ok = false, reason = "busy" }
		end
		return { ok = result.ok, reason = result.reason, reward = result.reward, streak = result.streak }
	end

	statusRemote.OnServerInvoke = function(player: Player)
		if not limiter:allow(tostring(player.UserId), os.clock()) then
			return nil
		end
		return server:status(player)
	end

	trove:Connect(Players.PlayerAdded, function(player: Player)
		server:loadPlayer(player)
	end)
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		savePlayer(player)
		states[player] = nil
		loadFailed[player] = nil
		busy[player] = nil
		limiter:forget(tostring(player.UserId))
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(server.loadPlayer, server, player)
	end
	if store then
		game:BindToClose(function()
			for player in states do
				savePlayer(player)
			end
		end)
	end

	function server:destroy()
		trove:Clean()
		server.Claimed:DisconnectAll()
		claimRemote.OnServerInvoke = nil
		statusRemote.OnServerInvoke = nil
	end

	return server
end

return DailyRewardsServer
