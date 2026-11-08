--!strict
-- Example 1: HUD with animated currency counters, an XP bar and toasts.
-- Put this LocalScript in StarterPlayerScripts. The server owns the numbers: it sets attributes
-- on the player (player:SetAttribute("Cash", 120)), and the UI only mirrors them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = ReplicatedStorage:WaitForChild("UltimateRobloxKit")
local UrkUI = require(Kit:WaitForChild("UI"):WaitForChild("UrkUI"))

local player = Players.LocalPlayer

-- A store fed from the player's attributes: Cash -> Stats.Cash, Gems -> Stats.Gems, XP -> Stats.XP.
local store = UrkUI.Store.fromAttributes(player, "Stats")
UrkUI.start({ store = store, theme = "dark", maxToasts = 3 })

local Components = UrkUI.Components
local hud = Components.Hud.new({ name = "MainHud" })

Components.Currency.new({ icon = "coin", path = "Stats.Cash", parent = hud:rail("topRight"), layoutOrder = 1 })
Components.Currency.new({ icon = "gem", path = "Stats.Gems", parent = hud:rail("topRight"), layoutOrder = 2 })

local xpBar = Components.ProgressBar.new({
	max = 100,
	segments = 10,
	label = "XP {value} / {max}",
	size = UDim2.fromOffset(280, 20),
	parent = hud:rail("bottomCenter"),
})

local function refreshXp()
	local xp = store:get("Stats.XP")
	local xpMax = store:get("Stats.XPMax")
	xpBar:set(if type(xp) == "number" then xp else 0, if type(xpMax) == "number" then xpMax else 100)
end
store:subscribe("Stats.XP", refreshXp)
store:subscribe("Stats.XPMax", refreshXp)
refreshXp()

-- A toast whenever cash goes up. Several quick gains merge into one toast with a counter.
store:subscribe("Stats.Cash", function(newValue: any, oldValue: any)
	if type(newValue) == "number" and type(oldValue) == "number" and newValue > oldValue then
		local gained = UrkUI.Core.Format.abbrev(newValue - oldValue)
		UrkUI.toast({ text = "+" .. gained .. " cash", kind = "success", key = "cash-gain" })
	end
end)

-- Errors from the server (for example a failed purchase) as error toasts.
local notices = ReplicatedStorage:FindFirstChild("UINotice")
if notices and notices:IsA("RemoteEvent") then
	notices.OnClientEvent:Connect(function(text: string, kind: string?)
		UrkUI.toast({ text = text, kind = kind or "info" })
	end)
end
