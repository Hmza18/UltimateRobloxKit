--!strict
-- Server adapter for Teams. Creates Team instances in the Teams service, assigns joining players,
-- answers friendly-fire questions for your damage code, keeps scores in a "Score" attribute on each
-- Team, and lets clients ask to switch teams through a validated, rate-limited remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeamsService = game:GetService("Teams")

local RateLimiter = require("../../Util/RateLimiter")
local Signal = require("../../Util/Signal")
local TeamsLogic = require("./TeamsLogic")
local Trove = require("../../Util/Trove")
local Validate = require("../../Util/Validate")

export type TeamSpec = { name: string, color: BrickColor?, maxSize: number? }

export type Options = {
	teams: { TeamSpec },
	autoAssign: boolean?, -- assign players as they join (default true)
	useSkill: boolean?, -- balance by skill as well as count
	skillOf: ((player: Player) -> number)?,
	friendlyFire: boolean?, -- default false
	selfDamage: boolean?, -- default false
	allowSwitching: boolean?, -- accept SwitchTeam requests from clients (default false)
	maxImbalance: number?, -- most players a switch may put one team ahead by (default 1)
	remoteFolder: string?, -- default "UrkTeams"
}

export type Service = {
	teamOf: (self: Service, player: Player) -> string?,
	setTeam: (self: Service, player: Player, team: string) -> (boolean, string?),
	canDamage: (self: Service, attacker: Player, victim: Player) -> boolean,
	addScore: (self: Service, team: string, amount: number) -> number?,
	leader: (self: Service) -> string?,
	shuffle: (self: Service) -> (),
	rebalance: (self: Service) -> (),
	state: (self: Service) -> TeamsLogic.State,
	changed: Signal.Signal, -- (player, teamName?)
	destroy: (self: Service) -> (),
}

local TeamsServer = {}

function TeamsServer.new(options: Options): Service
	assert(type(options.teams) == "table" and #options.teams > 0, "TeamsServer needs options.teams")
	local definitions: { any } = {}
	for _, spec in options.teams do
		table.insert(definitions, { name = spec.name, maxSize = spec.maxSize })
	end
	local state = TeamsLogic.new(definitions)
	local rules = { friendlyFire = options.friendlyFire == true, selfDamage = options.selfDamage == true }
	local trove = Trove.new()
	local changed = Signal.new()
	trove:Add(function()
		changed:DisconnectAll()
	end)
	local instances: { [string]: Team } = {}
	local byId: { [string]: Player } = {}

	for _, spec in options.teams do
		local team = Instance.new("Team")
		team.Name = spec.name
		team.TeamColor = spec.color or BrickColor.random()
		team.AutoAssignable = false -- assignment is decided here, not by the engine
		team:SetAttribute("Score", 0)
		team.Parent = TeamsService
		instances[spec.name] = team
		trove:Add(team)
	end

	local function key(player: Player): string
		return tostring(player.UserId)
	end

	local function skillOf(player: Player): number?
		local getter = options.skillOf
		if getter == nil then
			return nil
		end
		local ok, value = pcall(getter, player)
		return if ok and type(value) == "number" then value else nil
	end

	local function apply(player: Player)
		local teamName = TeamsLogic.teamOf(state, key(player))
		player.Team = if teamName then instances[teamName] else nil
		player.Neutral = teamName == nil
		changed:Fire(player, teamName)
	end

	local function onPlayerAdded(player: Player)
		byId[key(player)] = player
		if options.autoAssign ~= false then
			TeamsLogic.assign(state, key(player), skillOf(player), options.useSkill)
		end
		apply(player)
	end

	local service = {} :: Service
	service.changed = changed

	function service.teamOf(_self: Service, player: Player): string?
		return TeamsLogic.teamOf(state, key(player))
	end

	function service.setTeam(_self: Service, player: Player, team: string): (boolean, string?)
		local ok, reason = TeamsLogic.join(state, key(player), team, skillOf(player), math.huge)
		if ok then
			apply(player)
		end
		return ok, reason
	end

	function service.canDamage(_self: Service, attacker: Player, victim: Player): boolean
		local attackerTeam = TeamsLogic.teamOf(state, key(attacker))
		local victimTeam = TeamsLogic.teamOf(state, key(victim))
		return TeamsLogic.canDamage(rules, key(attacker), key(victim), attackerTeam, victimTeam)
	end

	function service.addScore(_self: Service, team: string, amount: number): number?
		local score = TeamsLogic.addScore(state, team, amount)
		if score and instances[team] then
			instances[team]:SetAttribute("Score", score)
		end
		return score
	end

	function service.leader(_self: Service): string?
		return TeamsLogic.leader(state)
	end

	-- Reassigns everyone from scratch (by skill when useSkill is set), for example between rounds.
	function service.shuffle(_self: Service)
		local roster: { TeamsLogic.PlayerSkill } = {}
		for id, player in byId do
			table.insert(roster, { id = id, skill = skillOf(player) })
		end
		local assignment = TeamsLogic.balance(roster, state.order, options.useSkill)
		for _, entry in roster do
			TeamsLogic.remove(state, entry.id)
		end
		for _, entry in roster do
			local target = assignment[entry.id]
			if not TeamsLogic.join(state, entry.id, target, entry.skill, math.huge) then
				TeamsLogic.assign(state, entry.id, entry.skill, options.useSkill) -- target was full
			end
		end
		for _, player in byId do
			apply(player)
		end
	end

	function service.rebalance(_self: Service)
		for _, move in TeamsLogic.rebalance(state, options.maxImbalance) do
			local player = byId[move.playerId]
			if player then
				apply(player)
			end
		end
	end

	function service.state(_self: Service): TeamsLogic.State
		return state
	end

	if options.allowSwitching then
		local folderName = options.remoteFolder or "UrkTeams"
		local folder = ReplicatedStorage:FindFirstChild(folderName)
		if not folder then
			local created = Instance.new("Folder")
			created.Name = folderName
			created.Parent = ReplicatedStorage
			folder = created
			trove:Add(created)
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = "SwitchTeam"
		remote.Parent = folder
		trove:Add(remote)
		local limiter = RateLimiter.new({ capacity = 3, refillPerSecond = 0.5 })
		local checkSwitch = Validate.args({ Validate.oneOf(state.order) })
		trove:Connect(remote.OnServerEvent, function(player: Player, ...: any)
			if not limiter:allow(key(player), os.clock()) or not checkSwitch(...) then
				return
			end
			local team = ...
			if TeamsLogic.join(state, key(player), team, skillOf(player), options.maxImbalance) then
				apply(player)
			end
		end)
		trove:Connect(Players.PlayerRemoving, function(player: Player)
			limiter:forget(key(player))
		end)
	end

	trove:Connect(Players.PlayerAdded, onPlayerAdded)
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		byId[key(player)] = nil
		TeamsLogic.remove(state, key(player))
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	function service.destroy(_self: Service)
		trove:Clean()
	end

	return service
end

return TeamsServer
