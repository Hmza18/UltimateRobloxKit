--!strict
-- Server adapter for AnalyticsLogic. Validates and batches events, then sends them to Roblox
-- AnalyticsService (every call wrapped in pcall). In Studio, where AnalyticsService does not
-- record events, a debug sink prints them instead. Analytics calls are server-only on Roblox.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AnalyticsLogic = require("./AnalyticsLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Config = {
	logic: AnalyticsLogic.Config?, -- validation, batching, rate and sampling settings
	sink: AnalyticsLogic.Sink?, -- default: AnalyticsService, or the debug sink in Studio
	debugInStudio: boolean?, -- print events in Studio instead of sending them (default true)
	hasConsent: ((player: Player) -> boolean)?, -- return false to skip a player's events
	tickInterval: number?, -- seconds between flush checks (default 1)
	enabled: boolean?, -- master switch (default true)
}

local AnalyticsServer = {}

local function sendEvent(player: Player, event: AnalyticsLogic.Event)
	local fields = event.fields
	if event.kind == "economy" then
		local flow = Enum.AnalyticsEconomyFlowType.Source
		if event.flow == "Sink" then
			flow = Enum.AnalyticsEconomyFlowType.Sink
		end
		AnalyticsService:LogEconomyEvent(
			player,
			flow,
			event.currency :: string,
			event.amount :: number,
			event.balance :: number,
			event.transaction :: string,
			event.sku,
			fields
		)
	elseif event.kind == "funnel" then
		AnalyticsService:LogFunnelStepEvent(
			player,
			event.funnel :: string,
			event.sessionId,
			event.step,
			event.stepName,
			fields
		)
	elseif event.kind == "onboarding" then
		AnalyticsService:LogOnboardingFunnelStepEvent(player, event.step :: number, event.stepName, fields)
	elseif event.kind == "progression" then
		local path = event.path :: string
		local level = event.level :: number
		if event.status == "Start" then
			AnalyticsService:LogProgressionStartEvent(player, path, level, event.levelName, fields)
		elseif event.status == "Complete" then
			AnalyticsService:LogProgressionCompleteEvent(player, path, level, event.levelName, fields)
		else
			AnalyticsService:LogProgressionFailEvent(player, path, level, event.levelName, fields)
		end
	else
		AnalyticsService:LogCustomEvent(player, event.name :: string, event.value, fields)
	end
end

-- Sends each event to AnalyticsService. Events for players who already left are skipped,
-- because every AnalyticsService call needs the Player.
function AnalyticsServer.serviceSink(): AnalyticsLogic.Sink
	return {
		write = function(events: { AnalyticsLogic.Event })
			local failures = 0
			local lastError = ""
			for _, event in events do
				local player = Players:GetPlayerByUserId(event.userId)
				if player then
					local ok, err = pcall(sendEvent, player, event)
					if not ok then
						failures += 1
						lastError = tostring(err)
					end
				end
			end
			if failures > 0 then
				warn(string.format("[AnalyticsServer] %d event(s) failed: %s", failures, lastError))
			end
		end,
	}
end

local function describe(event: AnalyticsLogic.Event): string
	local label = event.name or event.funnel or event.path or event.currency or "onboarding"
	local detail = event.step or event.level or event.amount or event.value or ""
	return string.format("%s %s %s (user %d)", event.kind, label, tostring(detail), event.userId)
end

-- Prints a one-line summary per event. Used in Studio, where AnalyticsService records nothing.
function AnalyticsServer.debugSink(): AnalyticsLogic.Sink
	return {
		write = function(events: { AnalyticsLogic.Event })
			for _, event in events do
				print("[Analytics]", describe(event))
			end
		end,
	}
end

function AnalyticsServer.new(config: Config?)
	local cfg: Config = config or {}
	local random = Random.new()
	local logicConfig: AnalyticsLogic.Config = table.clone(cfg.logic or {})
	if logicConfig.sessionPrefix == nil then
		-- Generated funnel session ids stay unique across servers without containing user ids.
		logicConfig.sessionPrefix = string.format("%06x-", random:NextInteger(0, 16777215))
	end
	local state = AnalyticsLogic.new(logicConfig, os.clock())
	local trove = Trove.new()
	local interval = cfg.tickInterval or 1
	local enabled = cfg.enabled ~= false

	local sink = cfg.sink
	if sink == nil then
		if RunService:IsStudio() and cfg.debugInStudio ~= false then
			sink = AnalyticsServer.debugSink()
		else
			sink = AnalyticsServer.serviceSink()
		end
	end
	local activeSink = sink :: AnalyticsLogic.Sink

	local server = {}
	server.state = state
	server.Dropped = Signal.new() -- (player, reason)

	local function nextNumber(): number
		return random:NextNumber()
	end

	local function consents(player: Player): boolean
		local check = cfg.hasConsent
		if check == nil then
			return true
		end
		local ok, allowed = pcall(check, player)
		return ok and allowed == true
	end

	-- Low-level entry point: `input` is an AnalyticsLogic event table without userId.
	function server:track(player: Player, input: { [string]: any }): (boolean, string?)
		if not enabled then
			return false, "disabled"
		end
		if not consents(player) then
			return false, "no consent"
		end
		local event = table.clone(input)
		event.userId = player.UserId
		local ok, reason = AnalyticsLogic.track(state, event, os.clock(), nextNumber)
		if not ok then
			server.Dropped:Fire(player, reason)
		end
		return ok, reason
	end

	-- flow is "Source" or "Sink"; amount is always positive.
	function server:logEconomy(
		player: Player,
		flow: AnalyticsLogic.Flow,
		currency: string,
		amount: number,
		balance: number,
		transaction: string,
		sku: string?,
		fields: { [any]: any }?
	): (boolean, string?)
		local input = {
			kind = "economy",
			flow = flow,
			currency = currency,
			amount = amount,
			balance = balance,
			transaction = transaction,
			sku = sku,
			fields = fields,
		}
		return server:track(player, input)
	end

	function server:logFunnelStep(
		player: Player,
		funnel: string,
		step: number,
		stepName: string?,
		fields: { [any]: any }?,
		sessionId: string?
	): (boolean, string?)
		local input = {
			kind = "funnel",
			funnel = funnel,
			step = step,
			stepName = stepName,
			fields = fields,
			sessionId = sessionId,
		}
		return server:track(player, input)
	end

	function server:logOnboardingStep(
		player: Player,
		step: number,
		stepName: string?,
		fields: { [any]: any }?
	): (boolean, string?)
		return server:track(player, { kind = "onboarding", step = step, stepName = stepName, fields = fields })
	end

	-- status is "Start", "Complete" or "Fail".
	function server:logProgression(
		player: Player,
		path: string,
		status: AnalyticsLogic.ProgressionStatus,
		level: number,
		levelName: string?,
		fields: { [any]: any }?
	): (boolean, string?)
		local input = {
			kind = "progression",
			path = path,
			status = status,
			level = level,
			levelName = levelName,
			fields = fields,
		}
		return server:track(player, input)
	end

	function server:logCustom(player: Player, name: string, value: number?, fields: { [any]: any }?): (boolean, string?)
		return server:track(player, { kind = "custom", name = name, value = value, fields = fields })
	end

	function server:endFunnel(player: Player, funnel: string)
		AnalyticsLogic.endFunnel(state, player.UserId, funnel)
	end

	function server:flush(): number
		local sent, err = AnalyticsLogic.flush(state, activeSink, os.clock())
		if err then
			warn("[AnalyticsServer] sink error:", err)
		end
		return sent
	end

	local elapsed = 0
	trove:Connect(RunService.Heartbeat, function(deltaTime: number)
		elapsed += deltaTime
		if elapsed < interval then
			return
		end
		elapsed = 0
		local _, err = AnalyticsLogic.tick(state, activeSink, os.clock())
		if err then
			warn("[AnalyticsServer] sink error:", err)
		end
	end)

	-- Flush while the leaving player still resolves through GetPlayerByUserId.
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		server:flush()
		AnalyticsLogic.forgetPlayer(state, player.UserId)
	end)

	game:BindToClose(function()
		server:flush()
	end)

	function server:destroy()
		server:flush()
		trove:Clean()
		server.Dropped:DisconnectAll()
	end

	return server
end

return AnalyticsServer
