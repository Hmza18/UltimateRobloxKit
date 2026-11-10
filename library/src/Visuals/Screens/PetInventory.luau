--!strict
-- PetInventory screen: a grid of PetCards with rarity filter tabs, and a detail panel for the
-- selected pet (portrait or live 3D preview, rarity, stats, equip / unequip). Equip and unequip
-- raise intents; the server owns the team, and the game then calls screen:update({ pets = ... }).
--
-- The filter tabs are built from the rarities present when the screen is created.
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local BUTTON_H = 52

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local view = ScreensLogic.petInventory(props)
	local tabs: { any } = {}
	for _, filter in ipairs(view.filters) do
		table.insert(tabs, { id = filter.id, text = string.format("%s %d", string.upper(filter.id), filter.count) })
	end
	local grid: ScreenKit.CardGrid
	local refresh: (animate: boolean) -> ()
	local window = shell:window({
		title = props.title,
		kind = "wide",
		headerPalette = "blue",
		tabs = tabs,
		tab = view.filter,
		scroll = false,
		onTab = function(id: string)
			shell.props.filter = id
			refresh(true)
			shell:fire("FilterChanged", id)
		end,
	})
	local content = window.content
	for _, child in ipairs(content:GetChildren()) do
		if child:IsA("UIListLayout") then
			child:Destroy() -- panes are placed by ScreensLogic.split
		end
	end
	local pane = ScreenKit.scroller(content, "Pets", 8)
	grid = ScreenKit.cards(pane, "pet", 1)
	shell.trove:Add(grid.destroy)

	-- Detail panel.
	local detail = shell:own(Game.Panel.new({
		style = shell.styleName,
		parent = content,
		name = "Detail",
		surface = "inset",
		padding = "sm",
		shadow = false,
	}))
	local inner: Instance = detail.Content or detail.Instance
	local ink = ScreenKit.ink(shell.style, "inset", "center")
	local stage = shell:frame(inner, "Preview")
	stage.Size = UDim2.new(1, 0, 1, -(BUTTON_H + 40 + 36 + 44 + 24))
	local portrait = Instance.new("ImageLabel")
	portrait.Name = "Portrait"
	portrait.BackgroundTransparency = 1
	portrait.Size = UDim2.fromScale(1, 1)
	portrait.ScaleType = Enum.ScaleType.Fit
	portrait.Parent = stage
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Visible = false
	viewport.Parent = stage
	local preview: any = nil
	local info = shell:frame(inner, "Info")
	info.AnchorPoint = Vector2.new(0, 1)
	info.Position = UDim2.fromScale(0, 1)
	info.Size = UDim2.new(1, 0, 0, BUTTON_H + 40 + 36 + 44 + 18)
	ScreenKit.list(info, false, 6, "center")
	local nameText = shell:text(info, "", "heading", { layoutOrder = 1, color = ink.color, stroke = false })
	local badgeHolder = shell:frame(info, "Badge")
	badgeHolder.LayoutOrder = 2
	badgeHolder.Size = UDim2.new(1, 0, 0, 28)
	local badge: any = nil
	local statsRow = shell:frame(info, "Stats")
	statsRow.LayoutOrder = 3
	statsRow.Size = UDim2.new(1, 0, 0, 38)
	ScreenKit.list(statsRow, true, 6, "center")
	local chips: { any } = {}
	local action = shell:button(info, {
		name = "Equip",
		kind = "primary",
		text = "EQUIP",
		layoutOrder = 4,
		size = UDim2.new(0.9, 0, 0, BUTTON_H),
	})

	local function clearDetail()
		if preview ~= nil then
			preview:destroy()
			preview = nil
		end
		if badge ~= nil then
			badge:destroy()
			badge = nil
		end
		for _, chip in ipairs(chips) do
			chip:destroy()
		end
		table.clear(chips)
	end
	shell.trove:Add(clearDetail)

	local function showDetail(animate: boolean)
		clearDetail()
		local pet = view.selected
		detail:update({ visible = pet ~= nil })
		if pet == nil then
			return
		end
		nameText:update({ text = tostring(pet.name or pet.id) })
		if typeof(pet.model) == "Instance" and pet.model:IsA("Model") then
			-- A live preview needs the Pets module; without it the portrait is used.
			local ok, made = pcall(function(): any
				local Pets = require("../Pets/Pets")
				return Pets.preview(viewport, pet.model)
			end)
			preview = if ok then made else nil
		end
		viewport.Visible = preview ~= nil
		portrait.Visible = preview == nil
		if preview == nil then
			ScreenKit.icon(portrait, pet.icon or (if pet.image == nil then "paw-color" else nil), pet.image)
		end
		if pet.rarity ~= nil then
			badge = Game.RarityBadge.new({
				style = shell.styleName,
				parent = badgeHolder,
				rarity = string.lower(pet.rarity),
				anchor = Vector2.new(0.5, 0.5),
				position = UDim2.fromScale(0.5, 0.5),
			})
		end
		for i, stat in ipairs(pet.stats or {}) do
			if i <= 3 then
				table.insert(
					chips,
					Game.StatChip.new({
						style = shell.styleName,
						parent = statsRow,
						layoutOrder = i,
						icon = stat.icon,
						image = stat.image,
						value = stat.value or stat.text,
						prefix = stat.prefix,
						suffix = stat.suffix,
					})
				)
			end
		end
		local equipped = pet.equipped == true
		action:update({
			kind = if equipped then "neutral" else "primary",
			text = if equipped then "UNEQUIP" else "EQUIP",
			enabled = equipped or view.canEquip,
		})
		if animate and shell:isOpen() then
			UI.animate(stage, "ScaleIn")
			if preview ~= nil then
				preview:react("SelectBounce")
			end
		end
	end

	local function focusList(): { GuiObject }
		local objects = grid.instances()
		table.insert(objects, action.Instance)
		return objects
	end

	local function choose(id: any, silent: boolean?)
		shell.props.selected = id
		view = ScreensLogic.petInventory(shell.props)
		for cardId, card in pairs(grid.cards) do
			card:update({ selected = cardId == tostring(id) })
		end
		showDetail(true)
		if not silent then
			shell:fire("Selected", id)
		end
	end

	refresh = function(animate: boolean)
		view = ScreensLogic.petInventory(shell.props)
		grid.set(view.pets, function(pet: any, index: number, size: UDim2?): any
			local card = Game.PetCard.new({
				style = shell.styleName,
				parent = grid.holder,
				layoutOrder = index,
				name = tostring(pet.id),
				title = tostring(pet.name or pet.id),
				rarity = if pet.rarity then string.lower(pet.rarity) else nil,
				icon = pet.icon or (if pet.image == nil then "paw-color" else nil),
				image = pet.image,
				palette = pet.palette,
				selected = pet.id == shell.props.selected,
				equipped = pet.equipped == true,
				size = size,
			})
			card.Activated:Connect(function()
				choose(pet.id)
			end)
			return card
		end)
		showDetail(false)
		shell:relayout()
		shell:focusables(focusList())
		if animate and shell:isOpen() then
			grid.reveal("ScrollReveal")
		end
	end

	shell.trove:Add(action.Activated:Connect(function()
		local pet = view.selected
		if pet == nil then
			return
		end
		if pet.equipped == true then
			shell:fire("UnequipRequested", pet.id)
		elseif view.canEquip then
			shell:fire("EquipRequested", pet.id)
		end
	end))

	shell:onLayout(function(_env: ScreensLogic.Env)
		local size = content.AbsoluteSize
		local area = { x = 0, y = 0, w = size.X, h = size.Y }
		if area.w <= 0 then
			local body = window.body()
			area.w, area.h = body.content.w, body.content.h
		end
		local split =
			ScreensLogic.split(area, { ratio = 0.62, minPrimary = 300, minSecondary = 220, stackRatio = 0.55 })
		ScreenKit.rect(pane, split.primary)
		ScreenKit.rect(detail.Instance, split.secondary)
		grid.layout(split.primary.w - 10, split.primary.h)
	end)

	refresh(false)
	shell.onOpened = function()
		grid.reveal("CardReveal")
	end

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			if partial.filter ~= nil then
				window.setTab(ScreensLogic.petInventory(shell.props).filter)
			end
			if partial.pets ~= nil or partial.filter ~= nil or partial.equipMax ~= nil then
				refresh(false)
			elseif partial.selected ~= nil then
				choose(partial.selected, true)
			end
		end,
	}
end
