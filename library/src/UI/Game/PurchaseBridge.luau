--!strict
-- Client bridge from the "Purchase" intent to Roblox's purchase prompts. It never grants anything:
-- granting happens on the server (Systems/Shop: ProcessReceipt for developer products, ownership
-- checks for game passes).
--
--   local PurchaseBridge = require(path.to.UI.Game.PurchaseBridge)
--   local stop = PurchaseBridge.start(UrkUI.Intent)       -- or Game.Intent without UrkUI
--
-- Accepted intent arguments: { productId = n } or { gamePassId = n } (what the game components
-- fire), or the Fire action's list form: "Fire:Purchase,123" (product) or "Fire:Purchase,123,pass".
-- Ids must be positive whole numbers; 0 (the placeholder in example specs) only warns. A second
-- prompt for the same id within `cooldown` seconds is ignored, so double taps do not stack prompts.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

export type Request = { kind: string, id: number }

export type Options = {
	player: Player?, -- default Players.LocalPlayer
	cooldown: number?, -- seconds, default 1
	onPrompt: ((request: Request) -> ())?, -- called after a prompt opens (analytics, sounds)
}

local PurchaseBridge = {}

local function positiveId(value: any): number?
	local id = tonumber(value)
	if id == nil or id <= 0 or id % 1 ~= 0 then
		return nil
	end
	return id
end

-- Reads a purchase request from intent arguments. Returns nil and a reason when it is invalid.
function PurchaseBridge.parse(args: any): (Request?, string?)
	if type(args) ~= "table" then
		return nil, "arguments must be a table"
	end
	if args.gamePassId ~= nil then
		local id = positiveId(args.gamePassId)
		if id == nil then
			return nil, "gamePassId must be a positive whole number, got " .. tostring(args.gamePassId)
		end
		return { kind = "gamePass", id = id }, nil
	end
	local raw = if args.productId ~= nil then args.productId else args[1]
	if raw == nil then
		return nil, "needs productId or gamePassId"
	end
	local id = positiveId(raw)
	if id == nil then
		return nil, "productId must be a positive whole number, got " .. tostring(raw)
	end
	local kind = if args.productId == nil and args[2] == "pass" then "gamePass" else "product"
	return { kind = kind, id = id }, nil
end

-- Opens the Roblox prompt for a request. Returns true when the prompt call succeeded.
function PurchaseBridge.prompt(player: Player, request: Request): boolean
	local ok, err = pcall(function()
		if request.kind == "gamePass" then
			MarketplaceService:PromptGamePassPurchase(player, request.id)
		else
			MarketplaceService:PromptProductPurchase(player, request.id)
		end
	end)
	if not ok then
		warn("[UrkUI.Game] purchase prompt failed for " .. request.kind .. " " .. request.id .. ": " .. tostring(err))
	end
	return ok
end

-- Listens to `intentSignal` (UrkUI.Intent, Game.Intent or any signal fired with (name, args, source))
-- and prompts for every "Purchase" intent. Returns a function that stops listening.
function PurchaseBridge.start(intentSignal: any, options: Options?): () -> ()
	local opts: Options = options or {}
	local cooldown = opts.cooldown or 1
	local last: { [string]: number } = {}
	local connection = intentSignal:Connect(function(name: string, args: any)
		if name ~= "Purchase" then
			return
		end
		local request, problem = PurchaseBridge.parse(args)
		if request == nil then
			warn("[UrkUI.Game] Purchase intent ignored: " .. tostring(problem))
			return
		end
		local key = request.kind .. ":" .. request.id
		local now = os.clock()
		if last[key] and now - last[key] < cooldown then
			return
		end
		last[key] = now
		local player = opts.player or Players.LocalPlayer
		if player == nil then
			warn("[UrkUI.Game] PurchaseBridge runs on the client only")
			return
		end
		if PurchaseBridge.prompt(player, request) and opts.onPrompt then
			opts.onPrompt(request)
		end
	end)
	local function stop()
		connection:Disconnect()
	end
	return stop
end

return PurchaseBridge
