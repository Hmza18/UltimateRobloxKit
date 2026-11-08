--!strict
-- Server helper shared by the 0.4 system adapters (Pets, Progression, Trading): one state value per
-- player, loaded from an injected store on join, saved on leave and at shutdown, with a load-failure
-- guard so a player whose data failed to load is never saved over. Also builds the remote folder.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Trove = require("./Trove")

export type Store = { load: (userId: number) -> any?, save: (userId: number, data: any) -> boolean }

export type Options<S> = {
	name: string, -- for warnings
	store: Store?,
	new: () -> S, -- fresh state
	decode: (raw: any) -> S, -- from untrusted saved data
	encode: (state: S) -> any, -- to saved data
	onLoaded: ((player: Player, state: S) -> ())?,
	autoLoad: boolean?, -- default true
}

export type PlayerState<S> = {
	get: (self: PlayerState<S>, player: Player) -> S?,
	set: (self: PlayerState<S>, player: Player, state: S) -> (),
	load: (self: PlayerState<S>, player: Player) -> (),
	save: (self: PlayerState<S>, player: Player) -> boolean,
	unload: (self: PlayerState<S>, player: Player) -> (),
	players: (self: PlayerState<S>) -> { Player },
	destroy: (self: PlayerState<S>) -> (),
}

local PlayerState = {}

function PlayerState.new<S>(options: Options<S>): PlayerState<S>
	local states: { [Player]: S } = {}
	local loadFailed: { [Player]: boolean } = {}
	local trove = Trove.new()
	local manager = {} :: PlayerState<S>

	function manager:get(player: Player): S?
		return states[player]
	end

	function manager:set(player: Player, state: S)
		if states[player] ~= nil then
			states[player] = state
		end
	end

	function manager:load(player: Player)
		local state = options.new()
		local store = options.store
		if store then
			local ok, raw = pcall(store.load, player.UserId)
			if ok then
				state = options.decode(raw)
			else
				loadFailed[player] = true
				warn("[" .. options.name .. "] load failed for", player.UserId, raw)
			end
		end
		if player.Parent == nil then
			return
		end
		states[player] = state
		if options.onLoaded then
			options.onLoaded(player, state)
		end
	end

	function manager:save(player: Player): boolean
		local state = states[player]
		local store = options.store
		if store == nil or state == nil or loadFailed[player] then
			return false
		end
		local ok, result = pcall(store.save, player.UserId, options.encode(state))
		if not ok then
			warn("[" .. options.name .. "] save failed for", player.UserId, result)
			return false
		end
		return result == true
	end

	function manager:unload(player: Player)
		self:save(player)
		states[player] = nil
		loadFailed[player] = nil
	end

	function manager:players(): { Player }
		local list: { Player } = {}
		for player in states do
			table.insert(list, player)
		end
		return list
	end

	function manager:destroy()
		trove:Clean()
		table.clear(states)
	end

	if options.autoLoad ~= false then
		trove:Connect(Players.PlayerAdded, function(player: Player)
			manager:load(player)
		end)
		trove:Connect(Players.PlayerRemoving, function(player: Player)
			manager:unload(player)
		end)
		for _, player in Players:GetPlayers() do
			task.spawn(manager.load, manager, player)
		end
		if options.store then
			game:BindToClose(function()
				for player in states do
					manager:save(player)
				end
			end)
		end
	end

	return manager
end

-- A ReplicatedStorage folder of RemoteEvents, created once. Returns the folder and a name -> remote map.
function PlayerState.remotes(folderName: string, names: { string }): (Folder, { [string]: RemoteEvent })
	local folder = Instance.new("Folder")
	folder.Name = folderName
	local map: { [string]: RemoteEvent } = {}
	for _, name in names do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		map[name] = remote
	end
	folder.Parent = ReplicatedStorage
	return folder, map
end

return PlayerState
