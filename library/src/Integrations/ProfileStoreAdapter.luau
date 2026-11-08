--!strict
-- Adapts ProfileStore (loleris, Apache-2.0, Wally "lm-loleris/profilestore@1.0.3") to the kit's
-- persistence interface { load, save, release }, so every *Server module that takes a `store`
-- (Currency, Inventory, Pets, Quests, SaveData...) can run on ProfileStore without changes.
--
-- The kit does not bundle ProfileStore: install it with `python3 urk.py packages --project <dir>`
-- (writes wally.toml and runs `wally install`), then pass the module in:
--
--   local ProfileStore = require(game.ServerScriptService.ServerPackages.ProfileStore)
--   local store = ProfileStoreAdapter.new({ ProfileStore = ProfileStore, name = "PlayerData_v1",
--       template = { coins = 0 } })
--   CurrencyServer.new({ currency = ..., store = store.section("currency") })
--
-- One ProfileStore session per player holds every system's data, split into named sections, so a
-- player has one session lock no matter how many systems use it.

local Players = game:GetService("Players")

export type Store = {
	load: (userId: number) -> any?,
	save: (userId: number, data: any) -> boolean,
	release: ((userId: number, data: any) -> boolean)?,
}

export type Options = {
	ProfileStore: any, -- the required ProfileStore module
	name: string, -- DataStore name passed to ProfileStore.New
	template: { [string]: any }?, -- defaults merged by Profile:Reconcile (default {})
	keyPrefix: string?, -- profile key = prefix .. userId (default "Player_")
	kickOnFailure: boolean?, -- kick when the session cannot start (default true)
}

export type Adapter = {
	section: (name: string) -> Store, -- a Store that reads and writes profile.Data[name]
	whole: Store, -- a Store over the whole profile.Data table
	profile: (userId: number) -> any?, -- the live Profile, for advanced use
	endSession: (userId: number) -> (),
}

local ProfileStoreAdapter = {}

function ProfileStoreAdapter.new(options: Options): Adapter
	assert(options.ProfileStore ~= nil, "ProfileStoreAdapter: pass the ProfileStore module")
	assert(type(options.name) == "string" and options.name ~= "", "ProfileStoreAdapter: name is required")
	local profileStore = options.ProfileStore.New(options.name, options.template or {})
	local prefix = options.keyPrefix or "Player_"
	local profiles: { [number]: any } = {}
	local starting: { [number]: boolean } = {}

	local function inGame(userId: number): boolean
		return Players:GetPlayerByUserId(userId) ~= nil
	end

	local function start(userId: number): any?
		local existing = profiles[userId]
		if existing then
			return existing
		end
		while starting[userId] do
			task.wait()
		end
		if profiles[userId] then
			return profiles[userId]
		end
		starting[userId] = true
		local profile = profileStore:StartSessionAsync(prefix .. tostring(userId), {
			Cancel = function()
				return not inGame(userId)
			end,
		})
		starting[userId] = nil
		if profile == nil then
			local player = Players:GetPlayerByUserId(userId)
			if player and options.kickOnFailure ~= false then
				player:Kick("Your data could not be loaded. Please rejoin.")
			end
			error("ProfileStore session could not start for " .. tostring(userId))
		end
		profile:AddUserId(userId)
		profile:Reconcile()
		profile.OnSessionEnd:Connect(function()
			profiles[userId] = nil
			local player = Players:GetPlayerByUserId(userId)
			if player then
				player:Kick("Your data session ended in another server. Please rejoin.")
			end
		end)
		if not inGame(userId) then
			profile:EndSession()
			error("player left while the session was starting")
		end
		profiles[userId] = profile
		return profile
	end

	local adapter = {} :: Adapter

	function adapter.profile(userId: number): any?
		return profiles[userId]
	end

	function adapter.endSession(userId: number)
		local profile = profiles[userId]
		profiles[userId] = nil
		if profile and profile:IsActive() then
			profile:EndSession()
		end
	end

	function adapter.section(name: string): Store
		return {
			load = function(userId: number): any?
				local profile = start(userId)
				return if profile then profile.Data[name] else nil
			end,
			save = function(userId: number, data: any): boolean
				local profile = profiles[userId]
				if profile == nil or not profile:IsActive() then
					return false
				end
				profile.Data[name] = data -- ProfileStore autosaves and saves on EndSession
				return true
			end,
			release = function(userId: number, data: any): boolean
				local profile = profiles[userId]
				if profile == nil or not profile:IsActive() then
					return false
				end
				profile.Data[name] = data
				return true -- the session ends once in endSession, after every section saved
			end,
		}
	end

	adapter.whole = {
		load = function(userId: number): any?
			local profile = start(userId)
			return if profile then profile.Data else nil
		end,
		save = function(userId: number, data: any): boolean
			local profile = profiles[userId]
			if profile == nil or not profile:IsActive() then
				return false
			end
			profile.Data = data
			return true
		end,
		release = function(userId: number, data: any): boolean
			local profile = profiles[userId]
			if profile == nil or not profile:IsActive() then
				return false
			end
			profile.Data = data
			adapter.endSession(userId)
			return true
		end,
	}

	-- Sections save on PlayerRemoving inside each system; end the session one frame later so
	-- those saves land first.
	Players.PlayerRemoving:Connect(function(player: Player)
		task.defer(adapter.endSession, player.UserId)
	end)

	return adapter
end

return ProfileStoreAdapter
