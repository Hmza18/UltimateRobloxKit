--!strict
-- EggHatching screen: the egg stand. Egg cards on one side, the selected egg's odds on the
-- other, and hatch x1 / x3 / auto buttons in the footer. The buttons raise intents; the server
-- rolls and charges, and the game then plays the cinematic with screen:hatch(config), which is
-- Eggs.hatch.
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local ODDS_ROW = 44
local FOOTER = 56

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local view = ScreensLogic.eggHatching(props)
	if #view.issues > 0 then
		error("EggHatching: " .. table.concat(view.issues, "; "), 0)
	end
	local window = shell:window({ title = props.title, kind = "wide", headerPalette = "purple", scroll = false })
	local ink = ScreenKit.ink(shell.style, "window")
	local content = window.content
	for _, child in ipairs(content:GetChildren()) do
		if child:IsA("UIListLayout") then
			child:Destroy() -- the two panes are placed by ScreensLogic.split, not stacked
		end
	end
	local eggsPane = ScreenKit.scroller(content, "Eggs", 8)
	local eggGrid, eggLayout = ScreenKit.grid(eggsPane, "Grid", 1)
	local oddsPane = ScreenKit.scroller(content, "Odds", 4)
	local footer = window.setFooter(FOOTER)
	ScreenKit.list(footer, true, 8, "center")

	local cards: { [string]: any } = {}
	local cardSize = Vector2.zero
	local oddsObjects: { any } = {}
	local buttons: { any } = {}
	local autoButton: any = nil
	local selectedId: string? = if view.selected then view.selected.id else nil

	local function priceText(egg: any): string
		return if egg.price > 0 then ScreenKit.amount(egg.price) else "FREE"
	end

	local function clearOdds()
		for _, object in ipairs(oddsObjects) do
			object:destroy()
		end
		table.clear(oddsObjects)
	end

	-- One row per possible pet: rarity badge, name and chance, rarest first.
	local function buildOdds(animate: boolean)
		clearOdds()
		local current = ScreensLogic.eggHatching(shell.props)
		view = current
		local egg = current.selected
		if egg == nil then
			return
		end
		local heading = Game.Section.new({
			style = shell.styleName,
			parent = oddsPane,
			layoutOrder = 0,
			title = string.upper(egg.name) .. " ODDS",
			color = ink.color,
			size = UDim2.new(1, -8, 0, 40),
		})
		table.insert(oddsObjects, heading)
		local rows: { GuiObject } = {}
		for i, entry in ipairs(egg.odds) do
			local row = Game.Panel.new({
				style = shell.styleName,
				parent = oddsPane,
				layoutOrder = i,
				name = "Odds_" .. tostring(i),
				surface = "inset",
				shadow = false,
				radius = "md",
				outline = "thin",
				size = UDim2.new(1, -8, 0, ODDS_ROW),
			})
			table.insert(oddsObjects, row)
			local inner: Instance = row.Content or row.Instance
			local rowInk = ScreenKit.ink(shell.style, "inset")
			if entry.rarity ~= nil then
				table.insert(
					oddsObjects,
					Game.RarityBadge.new({
						style = shell.styleName,
						parent = inner,
						rarity = entry.rarity,
						anchor = Vector2.new(0, 0.5),
						position = UDim2.new(0, 8, 0.5, 0),
					})
				)
			end
			table.insert(
				oddsObjects,
				Game.GameText.new({
					style = shell.styleName,
					parent = inner,
					text = entry.name,
					role = "label",
					color = rowInk.color,
					stroke = false,
					align = "left",
					size = UDim2.new(1, -190, 1, 0),
					position = UDim2.fromOffset(if entry.rarity ~= nil then 110 else 12, 0),
				})
			)
			table.insert(
				oddsObjects,
				Game.GameText.new({
					style = shell.styleName,
					parent = inner,
					text = entry.text,
					role = "price",
					color = rowInk.color,
					stroke = false,
					align = "right",
					size = UDim2.new(0, 76, 1, 0),
					anchor = Vector2.new(1, 0),
					position = UDim2.new(1, -8, 0, 0),
				})
			)
			table.insert(rows, row.Instance)
		end
		if animate and shell:isOpen() then
			UI.stagger(rows, "ScrollReveal", { interval = 0.03 })
		end
	end

	local function refreshButtons()
		local current = ScreensLogic.eggHatching(shell.props)
		for i, button in ipairs(buttons) do
			local option = current.counts[i]
			if option ~= nil then
				button:update({ enabled = option.affordable, text = option.text })
			end
		end
		if autoButton ~= nil then
			local on = shell.props.autoActive == true
			autoButton:update({ kind = if on then "danger" else "neutral", text = if on then "STOP AUTO" else "AUTO" })
		end
	end

	local function choose(id: string, silent: boolean?)
		if cards[id] == nil or selectedId == id then
			return
		end
		selectedId = id
		shell.props.selected = id
		for cardId, card in pairs(cards) do
			card:update({ selected = cardId == id })
		end
		buildOdds(true)
		refreshButtons()
		if not silent then
			shell:fire("Selected", id)
		end
	end

	local function focusList(): { GuiObject }
		local objects: { GuiObject } = {}
		for _, egg in ipairs(view.eggs) do
			local card = cards[egg.id]
			if card ~= nil then
				table.insert(objects, card.Instance)
			end
		end
		for _, button in ipairs(buttons) do
			table.insert(objects, button.Instance)
		end
		if autoButton ~= nil then
			table.insert(objects, autoButton.Instance)
		end
		return objects
	end

	local function buildCards()
		for _, card in pairs(cards) do
			card:destroy()
		end
		table.clear(cards)
		for i, egg in ipairs(view.eggs) do
			local card = Game.SelectionCard.new({
				style = shell.styleName,
				parent = eggGrid,
				layoutOrder = i,
				name = egg.id,
				title = string.upper(egg.name),
				description = priceText(egg),
				icon = egg.icon or (if egg.image == nil then "egg-color" else nil),
				image = egg.image,
				palette = egg.palette or "purple",
				selected = egg.id == selectedId,
				size = if cardSize.X > 0 then UDim2.fromOffset(cardSize.X, cardSize.Y) else nil,
			})
			cards[egg.id] = card
			card.Activated:Connect(function()
				choose(egg.id)
			end)
		end
	end

	local function buildButtons()
		for _, button in ipairs(buttons) do
			button:destroy()
		end
		table.clear(buttons)
		if autoButton ~= nil then
			autoButton:destroy()
			autoButton = nil
		end
		local total = #view.counts + (if view.auto then 1 else 0)
		local width = UDim2.new(1 / math.max(1, total), -8, 1, -4)
		for i, option in ipairs(view.counts) do
			local button = Game.CartoonButton.new({
				style = shell.styleName,
				parent = footer,
				layoutOrder = i,
				name = "Hatch" .. tostring(option.count),
				kind = "buy",
				text = option.text,
				enabled = option.affordable,
				size = width,
			})
			table.insert(buttons, button)
			button.Activated:Connect(function()
				if selectedId ~= nil then
					shell:fire("HatchRequested", selectedId, option.count)
				end
			end)
		end
		if view.auto then
			autoButton = Game.CartoonButton.new({
				style = shell.styleName,
				parent = footer,
				layoutOrder = 99,
				name = "Auto",
				kind = "neutral",
				text = "AUTO",
				size = width,
			})
			autoButton.Activated:Connect(function()
				if selectedId ~= nil then
					shell:fire("AutoToggled", selectedId, shell.props.autoActive ~= true)
				end
			end)
		end
		refreshButtons()
	end

	shell.trove:Add(function()
		clearOdds()
		for _, card in pairs(cards) do
			card:destroy()
		end
		for _, button in ipairs(buttons) do
			button:destroy()
		end
		if autoButton ~= nil then
			autoButton:destroy()
		end
	end)

	shell:onLayout(function(_env: ScreensLogic.Env)
		local size = content.AbsoluteSize
		local area = { x = 0, y = 0, w = size.X, h = size.Y }
		if area.w <= 0 then
			local body = window.body()
			area.w, area.h = body.content.w, body.content.h - FOOTER
		end
		local split = ScreensLogic.split(area, { ratio = 0.58, minPrimary = 320, minSecondary = 240 })
		ScreenKit.rect(eggsPane, split.primary)
		ScreenKit.rect(oddsPane, split.secondary)
		local grid = ScreensLogic.cards("egg", split.primary.w - 8, #view.eggs, split.primary.h)
		ScreenKit.applyGrid(eggLayout, grid)
		if grid.cellW ~= cardSize.X or grid.cellH ~= cardSize.Y then
			cardSize = Vector2.new(grid.cellW, grid.cellH)
			for _, card in pairs(cards) do
				card:update({ size = UDim2.fromOffset(grid.cellW, grid.cellH) })
			end
		end
	end)

	buildCards()
	buildOdds(false)
	buildButtons()
	shell:focusables(focusList())

	shell.onOpened = function()
		local list: { GuiObject } = {}
		for _, egg in ipairs(view.eggs) do
			table.insert(list, cards[egg.id].Instance)
		end
		UI.stagger(list, "CardReveal", { interval = 0.05 })
	end

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			view = ScreensLogic.eggHatching(shell.props)
			if #view.issues > 0 then
				error("EggHatching: " .. table.concat(view.issues, "; "), 0)
			end
			if partial.eggs ~= nil then
				selectedId = if view.selected then view.selected.id else nil
				buildCards()
				buildOdds(false)
				shell:relayout()
			elseif partial.selected ~= nil then
				choose(partial.selected, true)
			end
			if partial.counts ~= nil or partial.auto ~= nil then
				buildButtons()
			else
				refreshButtons()
			end
			shell:focusables(focusList())
		end,
		methods = {
			-- Plays the hatch cinematic (Eggs.hatch) for a result the server sent.
			hatch = function(config: { [string]: any }): any
				local Eggs = require("../Eggs/Eggs")
				return Eggs.hatch(config :: any)
			end,
		},
	}
end
