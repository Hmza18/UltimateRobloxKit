--!strict
-- UIController: a small HUD showing the coins and rebirths the server mirrors to player attributes.
-- The ui template replaces this file with a version built from the UI kit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("Economy"))

local UIController = { Name = "UIController", Priority = 20 }

local player = Players.LocalPlayer

local function numberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function makeLabel(parent: Instance, name: string, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.fromOffset(240, 40)
	label.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	label.BackgroundTransparency = 0.15
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.Parent = label
	return label
end

function UIController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local column = Instance.new("Frame")
	column.Name = "Stats"
	column.BackgroundTransparency = 1
	column.Position = UDim2.fromOffset(16, 16)
	column.Size = UDim2.fromOffset(240, 88)
	column.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = column

	local coins = makeLabel(column, "Coins", 1)
	local rebirths = makeLabel(column, "Rebirths", 2)

	local function refresh()
		coins.Text = "Coins: " .. Economy.abbreviate(numberAttribute("Coins"))
		rebirths.Text = "Rebirths: " .. tostring(numberAttribute("Rebirths")) .. "  (R to rebirth)"
	end
	player:GetAttributeChangedSignal("Coins"):Connect(refresh)
	player:GetAttributeChangedSignal("Rebirths"):Connect(refresh)
	refresh()
end

return UIController
