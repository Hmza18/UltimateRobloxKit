--!strict
-- UpgradeShop screen: one row per upgrade with level pips, the next level's cost and an upgrade
-- button (disabled when the balance the caller passed does not cover it, MAX when maxed). The
-- button raises Purchased(id, cost): a request. When an update arrives with a higher level, that
-- row pulses (UpgradePulse) and its new pip pops in.
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")
local Style = require("../../UI/Style/Style")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local ROW_H = 88
local PIP = 12

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local window = shell:window({ title = props.title, headerPalette = "green" })
	local ink = ScreenKit.ink(shell.style, "inset", "left")
	local objects: { any } = {}
	local rows: { [string]: { panel: any, pips: { Frame }, button: any } } = {}
	local order: { string } = {}
	local levels: { [string]: number } = {}
	local filled = Color3.fromHex(Style.palette(shell.style, "green").top)
	local emptyColor = Color3.fromHex(Style.surface(shell.style, "dark").top)

	local function clear()
		for _, object in ipairs(objects) do
			object:destroy()
		end
		table.clear(objects)
		table.clear(rows)
		table.clear(order)
	end
	shell.trove:Add(clear)

	local function build(announce: boolean)
		clear()
		local current: { [string]: any } = shell.props
		local view = ScreensLogic.upgrades(current.upgrades, current.balance)
		local focus: { GuiObject } = {}
		local raised: { string } = {}
		for i, upgrade in ipairs(view) do
			local entry = upgrade.entry
			local id = tostring(upgrade.id or i)
			local panel = Game.Panel.new({
				style = shell.styleName,
				parent = window.content,
				layoutOrder = i,
				name = "Upgrade_" .. id,
				surface = "inset",
				shadow = false,
				radius = "md",
				outline = "regular",
				size = UDim2.new(1, -10, 0, ROW_H),
			})
			table.insert(objects, panel)
			local inner: Instance = panel.Content or panel.Instance
			local image = Instance.new("ImageLabel")
			image.Name = "Icon"
			image.BackgroundTransparency = 1
			image.AnchorPoint = Vector2.new(0, 0.5)
			image.Position = UDim2.new(0, 8, 0.5, 0)
			image.Size = UDim2.fromOffset(56, 56)
			image.ScaleType = Enum.ScaleType.Fit
			image.Parent = inner
			ScreenKit.icon(image, entry.icon or (if entry.image == nil then "arrow-up" else nil), entry.image)
			table.insert(
				objects,
				Game.GameText.new({
					style = shell.styleName,
					parent = inner,
					text = string.format("%s  %d/%d", tostring(entry.title or id), upgrade.level, upgrade.maxLevel),
					role = "label",
					color = ink.color,
					stroke = false,
					align = "left",
					position = UDim2.fromOffset(74, 6),
					size = UDim2.new(1, -74 - 150, 0, 26),
				})
			)
			table.insert(
				objects,
				Game.GameText.new({
					style = shell.styleName,
					parent = inner,
					text = tostring(entry.description or ""),
					role = "caption",
					color = ink.color,
					stroke = false,
					align = "left",
					position = UDim2.fromOffset(74, 32),
					size = UDim2.new(1, -74 - 150, 0, 20),
				})
			)
			-- Level pips.
			local pipRow = Instance.new("Frame")
			pipRow.Name = "Pips"
			pipRow.BackgroundTransparency = 1
			pipRow.Position = UDim2.fromOffset(74, ROW_H - PIP - 14)
			pipRow.Size = UDim2.new(1, -74 - 150, 0, PIP)
			pipRow.Parent = inner
			ScreenKit.list(pipRow, true, 4, "left")
			local pips: { Frame } = {}
			for p, reached in ipairs(upgrade.pips) do
				local pip = Instance.new("Frame")
				pip.Name = "Pip" .. tostring(p)
				pip.LayoutOrder = p
				pip.Size = UDim2.fromOffset(PIP, PIP)
				pip.BorderSizePixel = 0
				pip.BackgroundColor3 = if reached then filled else emptyColor
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.5, 0)
				corner.Parent = pip
				pip.Parent = pipRow
				table.insert(pips, pip)
			end
			local button = Game.CartoonButton.new({
				style = shell.styleName,
				parent = inner,
				name = "Buy_" .. id,
				kind = if upgrade.maxed then "neutral" else "buy",
				text = if upgrade.maxed then "MAX" else ScreenKit.amount(upgrade.cost or 0),
				icon = if upgrade.maxed then nil else (entry.currencyIcon or current.currencyIcon),
				enabled = upgrade.affordable,
				anchor = Vector2.new(1, 0.5),
				position = UDim2.new(1, -8, 0.5, 0),
				size = UDim2.fromOffset(134, 52),
			})
			table.insert(objects, button)
			button.Activated:Connect(function()
				if upgrade.affordable then
					shell:fire("Purchased", upgrade.id, upgrade.cost)
				end
			end)
			rows[id] = { panel = panel, pips = pips, button = button }
			table.insert(order, id)
			table.insert(focus, button.Instance)
			if announce and levels[id] ~= nil and upgrade.level > levels[id] then
				table.insert(raised, id)
			end
			levels[id] = upgrade.level
		end
		shell:focusables(focus)
		for _, id in ipairs(raised) do
			local row = rows[id]
			UI.animate(row.panel.Instance, "UpgradePulse")
			-- The newest reached pip pops in.
			for p = #row.pips, 1, -1 do
				if row.pips[p].BackgroundColor3 == filled then
					UI.animate(row.pips[p], "BadgePop")
					break
				end
			end
		end
	end

	build(false)
	shell.onOpened = function()
		local instances: { GuiObject } = {}
		for _, id in ipairs(order) do
			table.insert(instances, rows[id].panel.Instance)
		end
		UI.stagger(instances, "SlideInUp", { interval = 0.04 })
	end

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			if partial.upgrades ~= nil or partial.balance ~= nil or partial.currencyIcon ~= nil then
				build(true)
			end
		end,
		methods = {
			-- Pulses a row by hand (for example when the server answers before the new levels arrive).
			pulse = function(id: any)
				local row = rows[tostring(id)]
				if row ~= nil then
					UI.animate(row.panel.Instance, "UpgradePulse")
				end
			end,
		},
	}
end
