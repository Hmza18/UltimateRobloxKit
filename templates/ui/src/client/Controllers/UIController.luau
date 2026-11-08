--!strict
-- UIController (ui template): the base HUD rebuilt with the UI kit in Shared/UI.
-- Shows coins and rebirths from player attributes, plus a Rebirth button that works with
-- mouse, touch and gamepad. The whole HUD scales with the screen through Responsive.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Components = require(UI:WaitForChild("Components"))
local Economy = require(Shared:WaitForChild("Logic"):WaitForChild("Economy"))
local Net = require(Shared:WaitForChild("Net"))
local Responsive = require(UI:WaitForChild("Responsive"))
local Theme = require(UI:WaitForChild("Theme"))

local UIController = { Name = "UIController", Priority = 20 }

local player = Players.LocalPlayer

local function numberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

function UIController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	Responsive.attach(gui)

	local panel = Components.Panel({
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(260, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Direction = "Vertical",
		Gap = 8,
		Parent = gui,
	})
	Components.Label({
		Text = "Stats",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Title,
		LayoutOrder = 1,
		Parent = panel,
	})
	local coins = Components.Label({ Text = "", LayoutOrder = 2, Parent = panel })
	local rebirths = Components.Label({
		Text = "",
		TextColor3 = Theme.Colors.TextMuted,
		LayoutOrder = 3,
		Parent = panel,
	})
	Components.Button({
		Text = "Rebirth",
		Variant = "Secondary",
		Size = UDim2.new(1, 0, 0, 48),
		LayoutOrder = 4,
		Parent = panel,
		OnActivated = function()
			Net.fireServer("RequestRebirth")
		end,
	})

	local function refresh()
		coins.Text = "Coins: " .. Economy.abbreviate(numberAttribute("Coins"))
		rebirths.Text = "Rebirths: " .. tostring(numberAttribute("Rebirths"))
	end
	player:GetAttributeChangedSignal("Coins"):Connect(refresh)
	player:GetAttributeChangedSignal("Rebirths"):Connect(refresh)
	refresh()
end

return UIController
