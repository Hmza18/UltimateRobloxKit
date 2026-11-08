--!strict
-- Server adapter for CurrencyLogic. One wallet per player, replicated through player attributes
-- (and optional leaderstats), persisted through an injected store, with an analytics hook.
-- Clients never send amounts: every change starts in server code.

local Players = game:GetService("Players")

local CurrencyLogic = require("./CurrencyLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Store = { load: (userId: number) -> any?, save: (userId: number, data: any) -> boolean }

export type Config = {
	currency: CurrencyLogic.Config, -- currencies, log size, overflow mode
	store: Store?, -- optional persistence
	attributePrefix: string?, -- player attribute per currency (default "Currency_")
	leaderstats: { string }?, -- currencies to show in the player list (default none)
	onTransaction: ((player: Player, entry: CurrencyLogic.Entry) -> ())?, -- analytics hook
	autoLoad: boolean?, -- load on join, save on leave and BindToClose (default true)
}

local CurrencyServer = {}

function CurrencyServer.new(config: Config)
	local currencyConfig = CurrencyLogic.validateConfig(config.currency)
	local prefix = config.attributePrefix or "Currency_"
	local store = config.store
	local trove = Trove.new()
	local wallets: { [Player]: CurrencyLogic.Wallet } = {}
	local loadFailed: { [Player]: boolean } = {}

	local server = {}
	server.Changed = Signal.new() -- (player, currency, balance, delta)
	server.Loaded = Signal.new() -- (player, wallet)

	local function publish(player: Player, wallet: CurrencyLogic.Wallet)
		for name in currencyConfig.currencies do
			player:SetAttribute(prefix .. name, CurrencyLogic.balance(wallet, name))
		end
		local folder = player:FindFirstChild("leaderstats")
		if folder and config.leaderstats then
			for _, name in config.leaderstats do
				local value = folder:FindFirstChild(name)
				if value and value:IsA("NumberValue") then
					value.Value = CurrencyLogic.balance(wallet, name)
				end
			end
		end
	end

	local function makeLeaderstats(player: Player)
		local names = config.leaderstats
		if names == nil or #names == 0 then
			return
		end
		local folder = player:FindFirstChild("leaderstats")
		if folder == nil then
			local created = Instance.new("Folder")
			created.Name = "leaderstats"
			created.Parent = player
			folder = created
		end
		for _, name in names do
			if folder:FindFirstChild(name) == nil then
				local value = Instance.new("NumberValue")
				value.Name = name
				value.Parent = folder
			end
		end
	end

	local function commit(player: Player, result: CurrencyLogic.TxResult)
		if not result.ok then
			return
		end
		wallets[player] = result.wallet
		publish(player, result.wallet)
		local entries = CurrencyLogic.recent(result.wallet, 1)
		local entry = entries[1]
		if entry then
			server.Changed:Fire(player, entry.currency, entry.balance, entry.delta)
			if config.onTransaction then
				task.spawn(config.onTransaction, player, entry)
			end
		end
	end

	function server:getWallet(player: Player): CurrencyLogic.Wallet?
		return wallets[player]
	end

	-- Replaces a wallet after a multi-step transaction (Shop uses this). Publishes all balances.
	function server:setWallet(player: Player, wallet: CurrencyLogic.Wallet)
		if wallets[player] == nil then
			return
		end
		wallets[player] = wallet
		publish(player, wallet)
		for name in currencyConfig.currencies do
			server.Changed:Fire(player, name, CurrencyLogic.balance(wallet, name), 0)
		end
	end

	function server:balance(player: Player, currency: string): number
		local wallet = wallets[player]
		return if wallet then CurrencyLogic.balance(wallet, currency) else 0
	end

	function server:add(player: Player, currency: string, amount: number, source: string?): CurrencyLogic.TxResult?
		local wallet = wallets[player]
		if wallet == nil then
			return nil
		end
		local result = CurrencyLogic.add(currencyConfig, wallet, currency, amount, source, os.time())
		commit(player, result)
		return result
	end

	function server:spend(player: Player, currency: string, amount: number, sink: string?): CurrencyLogic.TxResult?
		local wallet = wallets[player]
		if wallet == nil then
			return nil
		end
		local result = CurrencyLogic.spend(currencyConfig, wallet, currency, amount, sink, os.time())
		commit(player, result)
		return result
	end

	function server:loadPlayer(player: Player)
		local wallet = CurrencyLogic.newWallet(currencyConfig)
		if store then
			local ok, raw = pcall(store.load, player.UserId)
			if ok then
				wallet = CurrencyLogic.deserialize(currencyConfig, raw)
			else
				loadFailed[player] = true
				warn("[CurrencyServer] load failed for", player.UserId, raw)
			end
		end
		if player.Parent == nil then
			return
		end
		wallets[player] = wallet
		makeLeaderstats(player)
		publish(player, wallet)
		server.Loaded:Fire(player, wallet)
	end

	function server:savePlayer(player: Player): boolean
		local wallet = wallets[player]
		if store == nil or wallet == nil or loadFailed[player] then
			return false
		end
		local ok, saved = pcall(store.save, player.UserId, CurrencyLogic.serialize(wallet))
		if not ok then
			warn("[CurrencyServer] save failed for", player.UserId, saved)
			return false
		end
		return saved == true
	end

	function server:unloadPlayer(player: Player)
		server:savePlayer(player)
		wallets[player] = nil
		loadFailed[player] = nil
	end

	if config.autoLoad ~= false then
		trove:Connect(Players.PlayerAdded, function(player: Player)
			server:loadPlayer(player)
		end)
		trove:Connect(Players.PlayerRemoving, function(player: Player)
			server:unloadPlayer(player)
		end)
		for _, player in Players:GetPlayers() do
			task.spawn(server.loadPlayer, server, player)
		end
		game:BindToClose(function()
			local pending = 0
			for player in wallets do
				pending += 1
				task.spawn(function()
					server:savePlayer(player)
					pending -= 1
				end)
			end
			local deadline = os.clock() + 25
			while pending > 0 and os.clock() < deadline do
				task.wait(0.1)
			end
		end)
	end

	function server:destroy()
		trove:Clean()
		server.Changed:DisconnectAll()
		server.Loaded:DisconnectAll()
		table.clear(wallets)
	end

	return server
end

return CurrencyServer
