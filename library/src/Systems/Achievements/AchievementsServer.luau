--!strict
-- Server adapter for AchievementsLogic. Game code reports events (`increment`) and stats
-- (`observe`); unlocks fire a signal, notify the owner and, when an achievement has a badgeId,
-- award the Roblox badge through an adapter with pcall and retries. Awarding is idempotent.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementsLogic = require("./AchievementsLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Store = { load: (userId: number) -> any?, save: (userId: number, data: any) -> boolean }

-- Returns true once the user owns the badge (awarded now or earlier).
export type BadgeAdapter = { award: (userId: number, badgeId: number) -> boolean }

export type Config = {
	defs: AchievementsLogic.Defs, -- from AchievementsLogic.newDefs
	store: Store?, -- optional persistence
	badges: BadgeAdapter?, -- default: AchievementsServer.badgeServiceAdapter()
	badgeRetries: number?, -- award attempts per badge (default 3)
	remoteFolderName: string?, -- default "URK_Achievements"
	clock: (() -> number)?, -- unlock timestamps (default os.time)
}

local AchievementsServer = {}

-- Default badge adapter: checks UserHasBadgeAsync first so a badge is never awarded twice, then
-- calls AwardBadge. Both calls can error and yield, so callers wrap them in pcall.
function AchievementsServer.badgeServiceAdapter(): BadgeAdapter
	local adapter = {}
	function adapter.award(userId: number, badgeId: number): boolean
		if BadgeService:UserHasBadgeAsync(userId, badgeId) then
			return true
		end
		return BadgeService:AwardBadge(userId, badgeId) == true
	end
	return adapter
end

function AchievementsServer.new(config: Config)
	local defs = config.defs
	local store = config.store
	local badges = config.badges or AchievementsServer.badgeServiceAdapter()
	local retries = config.badgeRetries or 3
	local clock = config.clock or os.time
	local trove = Trove.new()
	local states: { [Player]: AchievementsLogic.State } = {}
	local loadFailed: { [Player]: boolean } = {}
	local awarding: { [string]: boolean } = {}

	local folder = Instance.new("Folder")
	folder.Name = config.remoteFolderName or "URK_Achievements"
	folder.Parent = ReplicatedStorage
	trove:Add(folder)
	local unlockedRemote = Instance.new("RemoteEvent")
	unlockedRemote.Name = "Unlocked"
	unlockedRemote.Parent = folder
	local listRemote = Instance.new("RemoteFunction")
	listRemote.Name = "GetList"
	listRemote.Parent = folder

	local server = {}
	server.Unlocked = Signal.new() -- (player, achievementId)
	server.BadgeAwarded = Signal.new() -- (player, achievementId, badgeId)

	local function awardBadges(player: Player)
		local state = states[player]
		if state == nil then
			return
		end
		for _, pending in AchievementsLogic.pendingBadges(defs, state) do
			local key = tostring(player.UserId) .. ":" .. pending.id
			if not awarding[key] then
				awarding[key] = true
				task.spawn(function()
					local awarded = false
					for attempt = 1, retries do
						local ok, result = pcall(badges.award, player.UserId, pending.badgeId)
						if ok and result == true then
							awarded = true
							break
						end
						if attempt < retries then
							task.wait(2 ^ attempt)
						end
					end
					awarding[key] = nil
					local current = states[player]
					if awarded and current then
						states[player] = AchievementsLogic.markBadgeAwarded(current, pending.id)
						server.BadgeAwarded:Fire(player, pending.id, pending.badgeId)
					elseif not awarded then
						warn("[AchievementsServer] badge award failed", pending.badgeId)
					end
				end)
			end
		end
	end

	local function apply(player: Player, nextState: AchievementsLogic.State, unlocked: { string })
		states[player] = nextState
		for _, id in unlocked do
			server.Unlocked:Fire(player, id)
			unlockedRemote:FireClient(player, id)
		end
		if #unlocked > 0 then
			awardBadges(player)
		end
	end

	function server:get(player: Player): AchievementsLogic.State?
		return states[player]
	end

	-- Adds to an event counter, for example server:increment(player, "ZombieKilled").
	function server:increment(player: Player, counter: string, amount: number?): { string }
		local state = states[player]
		if state == nil then
			return {}
		end
		local nextState, unlocked = AchievementsLogic.increment(defs, state, counter, amount, clock())
		apply(player, nextState, unlocked)
		return unlocked
	end

	-- Records a stat value, for example server:observe(player, "Level", 10).
	function server:observe(player: Player, stat: string, value: number): { string }
		local state = states[player]
		if state == nil then
			return {}
		end
		local nextState, unlocked = AchievementsLogic.observe(defs, state, stat, value, clock())
		apply(player, nextState, unlocked)
		return unlocked
	end

	function server:unlock(player: Player, id: string): boolean
		local state = states[player]
		if state == nil then
			return false
		end
		local nextState, isNew = AchievementsLogic.unlock(defs, state, id, clock())
		if isNew then
			apply(player, nextState, { id })
		end
		return isNew
	end

	function server:list(player: Player): { AchievementsLogic.Entry }
		local state = states[player]
		return if state then AchievementsLogic.list(defs, state) else {}
	end

	function server:loadPlayer(player: Player)
		local state = AchievementsLogic.new()
		if store then
			local ok, raw = pcall(store.load, player.UserId)
			if ok then
				state = AchievementsLogic.deserialize(defs, raw)
			else
				loadFailed[player] = true
				warn("[AchievementsServer] load failed for", player.UserId, raw)
			end
		end
		if player.Parent == nil then
			return
		end
		states[player] = state
		-- Achievements added since the last session may already be earned; retry pending badges.
		local nextState, unlocked = AchievementsLogic.evaluate(defs, state, clock())
		apply(player, nextState, unlocked)
		awardBadges(player)
	end

	function server:savePlayer(player: Player): boolean
		local state = states[player]
		if store == nil or state == nil or loadFailed[player] then
			return false
		end
		local ok, saved = pcall(store.save, player.UserId, AchievementsLogic.serialize(state))
		return ok and saved == true
	end

	listRemote.OnServerInvoke = function(player: Player)
		return server:list(player)
	end

	trove:Connect(Players.PlayerAdded, function(player: Player)
		server:loadPlayer(player)
	end)
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		server:savePlayer(player)
		states[player] = nil
		loadFailed[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(server.loadPlayer, server, player)
	end
	if store then
		game:BindToClose(function()
			for player in states do
				server:savePlayer(player)
			end
		end)
	end

	function server:destroy()
		trove:Clean()
		server.Unlocked:DisconnectAll()
		server.BadgeAwarded:DisconnectAll()
		listRemote.OnServerInvoke = nil
	end

	return server
end

return AchievementsServer
