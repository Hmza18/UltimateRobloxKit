--!strict
-- Server adapter for Dialogue. Runs one dialogue per player on the server, so conditions and
-- consequences are decided here. The client only sends "I picked choice N" or "advance".
-- Effects from "emit" actions go to options.onEffect, where your game gives items, starts quests and so on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DialogueLogic = require("./DialogueLogic")
local RateLimiter = require("../../Util/RateLimiter")
local Trove = require("../../Util/Trove")
local Validate = require("../../Util/Validate")

export type Options = {
	graphs: { [string]: DialogueLogic.Graph },
	getVars: ((player: Player, graphId: string) -> { [string]: any })?, -- table the dialogue reads and changes
	onEffect: ((player: Player, effect: DialogueLogic.Effect, graphId: string) -> ())?,
	onEnd: ((player: Player, graphId: string, vars: { [string]: any }) -> ())?,
	predicates: DialogueLogic.Predicates?,
	canTalk: ((player: Player, graphId: string) -> boolean)?, -- for example a distance check to the NPC
	remoteFolder: string?, -- default "UrkDialogue"
}

export type Service = {
	open: (self: Service, player: Player, graphId: string) -> (boolean, string?),
	close: (self: Service, player: Player) -> (),
	isTalking: (self: Service, player: Player) -> boolean,
	destroy: (self: Service) -> (),
}

type Session = { graphId: string, runner: DialogueLogic.Runner }

local DialogueServer = {}

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

function DialogueServer.new(options: Options): Service
	for graphId, graph in options.graphs do
		local ok, errors = DialogueLogic.validate(graph, options.predicates)
		if not ok then
			error("DialogueServer: graph " .. graphId .. " is invalid: " .. table.concat(errors, "; "))
		end
	end
	local folderName = options.remoteFolder or "UrkDialogue"
	local folder = ReplicatedStorage:FindFirstChild(folderName)
	if not folder then
		local created = Instance.new("Folder")
		created.Name = folderName
		created.Parent = ReplicatedStorage
		folder = created
	end
	local nodeRemote = getRemote(folder :: Instance, "Node") -- server to client: (view or nil)
	-- client to server: ("choose", index), ("advance") or ("close")
	local inputRemote = getRemote(folder :: Instance, "Input")
	local trove = Trove.new()
	local sessions: { [Player]: Session } = {}
	local limiter = RateLimiter.new({ capacity = 8, refillPerSecond = 4 })
	local checkInput = Validate.args({
		Validate.oneOf({ "choose", "advance", "close" }),
		Validate.optional(Validate.integer(1, 64)),
	})

	local function dispatch(player: Player, session: Session, effects: { DialogueLogic.Effect })
		local onEffect = options.onEffect
		if onEffect == nil then
			return
		end
		for _, effect in effects do
			local ok, err = pcall(onEffect, player, effect, session.graphId)
			if not ok then
				warn("DialogueServer: onEffect failed: " .. tostring(err))
			end
		end
	end

	local function finish(player: Player)
		local session = sessions[player]
		if session == nil then
			return
		end
		sessions[player] = nil
		if options.onEnd then
			task.spawn(options.onEnd, player, session.graphId, session.runner.vars)
		end
		if player.Parent then
			nodeRemote:FireClient(player, nil)
		end
	end

	local function push(player: Player, session: Session)
		local view = DialogueLogic.view(session.runner)
		if view == nil then
			finish(player)
		else
			nodeRemote:FireClient(player, view)
		end
	end

	local service = {} :: Service

	function service.open(_self: Service, player: Player, graphId: string): (boolean, string?)
		local graph = options.graphs[graphId]
		if graph == nil then
			return false, "unknown graph"
		end
		if options.canTalk and not options.canTalk(player, graphId) then
			return false, "cannot talk"
		end
		finish(player)
		local vars = if options.getVars then options.getVars(player, graphId) else {}
		local runner, effects = DialogueLogic.start(graph, vars, options.predicates)
		local session = { graphId = graphId, runner = runner }
		sessions[player] = session
		dispatch(player, session, effects)
		push(player, session)
		return true, nil
	end

	function service.close(_self: Service, player: Player)
		finish(player)
	end

	function service.isTalking(_self: Service, player: Player): boolean
		return sessions[player] ~= nil
	end

	trove:Connect(inputRemote.OnServerEvent, function(player: Player, ...: any)
		if not limiter:allow(tostring(player.UserId), os.clock()) or not checkInput(...) then
			return
		end
		local session = sessions[player]
		if session == nil then
			return
		end
		local action, index = ...
		if action == "close" then
			finish(player)
			return
		end
		if options.canTalk and not options.canTalk(player, session.graphId) then
			finish(player)
			return
		end
		local ok, _, effects
		if action == "choose" then
			if index == nil then
				return
			end
			ok, _, effects = DialogueLogic.choose(session.runner, index)
		else
			ok, _, effects = DialogueLogic.advance(session.runner)
		end
		if ok then
			dispatch(player, session, effects)
			push(player, session)
		end
	end)
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		finish(player)
		limiter:forget(tostring(player.UserId))
	end)

	function service.destroy(_self: Service)
		for player in sessions do
			finish(player)
		end
		trove:Clean()
	end

	return service
end

return DialogueServer
