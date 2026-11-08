--!strict
-- Server adapter for TradingLogic. Runs invites and sessions, validates every intent, re-checks
-- ownership at the end of the countdown, and swaps pets and currency atomically: every new state is
-- computed first and committed only if all of them succeed. Trades end when a player leaves.
--
--   TradingServer.new({ pets = petsServer, petsConfig = petsConfig, currency = currencyServer,
--       currencyConfig = currencyConfig, trading = { currencies = { Gems = true } } })

local Players = game:GetService("Players")

local CurrencyLogic = require("../Currency/CurrencyLogic")
local PetsLogic = require("../Pets/PetsLogic")
local PlayerState = require("../../Util/PlayerState")
local RateLimiter = require("../../Util/RateLimiter")
local Signal = require("../../Util/Signal")
local TradingLogic = require("./TradingLogic")
local Validate = require("../../Util/Validate")

export type Config = {
	trading: TradingLogic.Config,
	pets: any, -- PetsServer
	petsConfig: PetsLogic.Config,
	currency: any?, -- CurrencyServer (getWallet/setWallet), needed to trade currency
	currencyConfig: CurrencyLogic.Config?,
	remoteFolderName: string?, -- default "URK_Trading"
	rateLimit: RateLimiter.Options?,
	canTrade: ((a: Player, b: Player) -> boolean)?, -- e.g. both above a level, not blocked
}

local TradingServer = {}

function TradingServer.new(config: Config)
	local cfg = config.trading
	local limiter = RateLimiter.new(config.rateLimit or { capacity = 10, refillPerSecond = 4 })
	local _, remotes = PlayerState.remotes(
		config.remoteFolderName or "URK_Trading",
		{ "Invite", "Respond", "SetOffer", "Accept", "Unaccept", "Cancel", "Update", "Invited" }
	)
	local invites: { [number]: TradingLogic.Invite } = {} -- keyed by invited user
	local sessions: { [string]: TradingLogic.Session } = {}
	local sessionOf: { [number]: string } = {}
	local counter = 0

	local server = {}
	server.Completed = Signal.new() -- (session)

	local function playerOf(userId: number): Player?
		return Players:GetPlayerByUserId(userId)
	end

	local function broadcast(session: TradingLogic.Session)
		for _, userId in session.players do
			local player = playerOf(userId)
			if player then
				remotes.Update:FireClient(player, session)
			end
		end
	end

	local function close(session: TradingLogic.Session)
		sessions[session.id] = nil
		for _, userId in session.players do
			if sessionOf[userId] == session.id then
				sessionOf[userId] = nil
			end
		end
		broadcast(session)
	end

	local function verify(userId: number, offer: TradingLogic.Offer): (boolean, string?)
		local player = playerOf(userId)
		local state = if player then config.pets:getState(player) else nil
		if state == nil then
			return false, "player left"
		end
		for _, id in offer.pets do
			local pet = state.pets[id]
			if pet == nil or not PetsLogic.isTradeable(config.petsConfig, pet) then
				return false, "a pet is no longer available"
			end
		end
		if next(offer.currency) ~= nil then
			local wallet = if config.currency then config.currency:getWallet(player) else nil
			if wallet == nil or not CurrencyLogic.canAfford(wallet, offer.currency) then
				return false, "not enough currency"
			end
		end
		return true, nil
	end

	-- Computes every new state, then commits all of them. Returns false without changes on any failure.
	local function swap(session: TradingLogic.Session, gives: { [number]: TradingLogic.Offer }): boolean
		local a, b = session.players[1], session.players[2]
		local pa, pb = playerOf(a), playerOf(b)
		if pa == nil or pb == nil then
			return false
		end
		local sa, sb = config.pets:getState(pa), config.pets:getState(pb)
		local function petsOf(state: PetsLogic.State, ids: { string }): { PetsLogic.Pet }
			local list = {}
			for _, id in ids do
				table.insert(list, state.pets[id])
			end
			return list
		end
		local ra = PetsLogic.exchange(config.petsConfig, sa, gives[a].pets, petsOf(sb, gives[b].pets))
		local rb = PetsLogic.exchange(config.petsConfig, sb, gives[b].pets, petsOf(sa, gives[a].pets))
		if not ra.ok or not rb.ok then
			return false
		end
		local wa, wb = nil, nil
		local hasCurrency = next(gives[a].currency) ~= nil or next(gives[b].currency) ~= nil
		if hasCurrency then
			local currencyConfig = config.currencyConfig
			if config.currency == nil or currencyConfig == nil then
				return false
			end
			wa, wb = config.currency:getWallet(pa), config.currency:getWallet(pb)
			for currency, amount in gives[a].currency do
				local moved = CurrencyLogic.transfer(currencyConfig, wa, wb, currency, amount, "trade:" .. session.id)
				if not moved.ok then
					return false
				end
				wa, wb = moved.from, moved.to
			end
			for currency, amount in gives[b].currency do
				local moved = CurrencyLogic.transfer(currencyConfig, wb, wa, currency, amount, "trade:" .. session.id)
				if not moved.ok then
					return false
				end
				wb, wa = moved.from, moved.to
			end
		end
		config.pets:setState(pa, ra.state)
		config.pets:setState(pb, rb.state)
		if hasCurrency then
			config.currency:setWallet(pa, wa)
			config.currency:setWallet(pb, wb)
		end
		return true
	end

	function server:invite(from: Player, to: Player): (boolean, string?)
		if sessionOf[from.UserId] or sessionOf[to.UserId] then
			return false, "already trading"
		end
		if config.canTrade and not config.canTrade(from, to) then
			return false, "cannot trade"
		end
		local ok, why, invite = TradingLogic.invite(cfg, from.UserId, to.UserId, os.time())
		if not ok or invite == nil then
			return false, why
		end
		invites[to.UserId] = invite
		remotes.Invited:FireClient(to, from.UserId)
		return true, nil
	end

	function server:respond(player: Player, accept: boolean)
		local invite = invites[player.UserId]
		invites[player.UserId] = nil
		if invite == nil or not accept or sessionOf[invite.from] or playerOf(invite.from) == nil then
			return
		end
		counter += 1
		local ok, _, session = TradingLogic.start(invite, tostring(counter), os.time())
		if ok and session then
			sessions[session.id] = session
			sessionOf[invite.from] = session.id
			sessionOf[invite.to] = session.id
			broadcast(session)
		end
	end

	local function withSession(player: Player, step: (session: TradingLogic.Session) -> TradingLogic.Result)
		local id = sessionOf[player.UserId]
		local session = if id then sessions[id] else nil
		if session == nil then
			return
		end
		local result = step(session)
		if result.ok then
			sessions[session.id] = result.session
			broadcast(result.session)
		end
	end

	function server:tick()
		local now = os.time()
		for id, session in sessions do
			local current = TradingLogic.tick(cfg, session, now)
			if current.stage == "cancelled" then
				close(current)
			elseif TradingLogic.isReady(current, now) then
				local settled = TradingLogic.settle(current, now, verify)
				if settled.ok and swap(settled.session, settled.gives) then
					close(settled.session)
					server.Completed:Fire(settled.session)
				else
					close(if settled.ok then TradingLogic.cancel(current, "swap failed") else settled.session)
				end
			else
				sessions[id] = current
			end
		end
	end

	local idList = Validate.array(Validate.string({ minLength = 1, maxLength = 16, pattern = "^%d+$" }), 50)
	local offerCheck = Validate.struct({
		pets = idList,
		currency = function(value: any): (boolean, string?)
			return type(value) == "table", "currency must be a table"
		end,
	})
	local connections: { RBXScriptConnection } = {}
	local function on(name: string, check: Validate.ArgsCheck, handler: (player: Player, ...any) -> ())
		table.insert(
			connections,
			remotes[name].OnServerEvent:Connect(function(player: Player, ...: any)
				if limiter:allow(tostring(player.UserId), os.clock()) and check(...) then
					handler(player, ...)
				end
			end)
		)
	end
	on("Invite", Validate.args({ Validate.integer(1, 1e12) }), function(player: Player, userId: number)
		local target = playerOf(userId)
		if target and target ~= player then
			server:invite(player, target)
		end
	end)
	on("Respond", Validate.args({ Validate.boolean() }), function(player: Player, accept: boolean)
		server:respond(player, accept)
	end)
	on("SetOffer", Validate.args({ offerCheck }), function(player: Player, offer: TradingLogic.Offer)
		local check = verify(player.UserId, offer)
		if not check then
			return
		end
		withSession(player, function(session)
			return TradingLogic.setOffer(cfg, session, player.UserId, offer)
		end)
	end)
	on("Accept", Validate.args({ Validate.integer(1, 1e9) }), function(player: Player, version: number)
		withSession(player, function(session)
			return TradingLogic.accept(cfg, session, player.UserId, version, os.time())
		end)
	end)
	on("Unaccept", Validate.args({}), function(player: Player)
		withSession(player, function(session)
			return TradingLogic.unaccept(session, player.UserId)
		end)
	end)
	on("Cancel", Validate.args({}), function(player: Player)
		local id = sessionOf[player.UserId]
		if id and sessions[id] then
			close(TradingLogic.cancel(sessions[id], "cancelled by player"))
		end
	end)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			invites[player.UserId] = nil
			local id = sessionOf[player.UserId]
			if id and sessions[id] then
				close(TradingLogic.cancel(sessions[id], "player left"))
			end
		end)
	)

	local running = true
	task.spawn(function()
		while running do
			task.wait(0.5)
			server:tick()
		end
	end)

	function server:destroy()
		running = false
		for _, connection in connections do
			connection:Disconnect()
		end
		server.Completed:DisconnectAll()
	end

	return server
end

return TradingServer
