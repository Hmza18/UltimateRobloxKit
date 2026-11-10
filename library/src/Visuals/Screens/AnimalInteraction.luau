--!strict
-- AnimalInteraction screen: feeding an animal. An animal card (portrait, name, mood and hunger
-- bars, a reaction area) next to a food tray of selectable items and a throw button. The throw
-- button raises ThrowRequested; after the server answers, the game calls screen:react("eat") and
-- updates the bars with screen:update({ animal = ... }).
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local FOOTER = 60
local BAR_H = 22

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local view = ScreensLogic.animalInteraction(props)
	if #view.issues > 0 then
		error("AnimalInteraction: " .. table.concat(view.issues, "; "), 0)
	end
	local window = shell:window({ title = props.title, headerPalette = "green", scroll = false })
	local content = window.content
	for _, child in ipairs(content:GetChildren()) do
		if child:IsA("UIListLayout") then
			child:Destroy() -- panes are placed by ScreensLogic.split
		end
	end
	local ink = ScreenKit.ink(shell.style, "inset", "left")

	-- Animal card.
	local card = shell:own(Game.Panel.new({
		style = shell.styleName,
		parent = content,
		name = "Animal",
		surface = "inset",
		padding = "sm",
		shadow = false,
	}))
	local cardInner: Instance = card.Content or card.Instance
	local column = shell:frame(cardInner, "Column")
	ScreenKit.list(column, false, 6, "center")
	-- The portrait sits in the reaction area: reactions animate it and pop text over it.
	local reaction = shell:frame(column, "Reaction")
	reaction.LayoutOrder = 1
	reaction.Size = UDim2.new(1, 0, 1, -(BAR_H * 2 + 28 * 3 + 6 * 5))
	local portrait = Instance.new("ImageLabel")
	portrait.Name = "Portrait"
	portrait.BackgroundTransparency = 1
	portrait.AnchorPoint = Vector2.new(0.5, 0.5)
	portrait.Position = UDim2.fromScale(0.5, 0.5)
	portrait.Size = UDim2.fromScale(0.8, 0.9)
	portrait.ScaleType = Enum.ScaleType.Fit
	portrait.Parent = reaction
	local nameText = shell:text(column, view.name, "heading", { layoutOrder = 2, color = ink.color, stroke = false })
	local moodText = shell:text(column, "", "caption", { layoutOrder = 3, color = ink.color, stroke = false })
	local moodBar = shell:own(Game.ProgressBar.new({
		style = shell.styleName,
		parent = column,
		layoutOrder = 4,
		name = "Mood",
		palette = "pink",
		value = view.mood,
		max = 1,
		size = UDim2.new(1, 0, 0, BAR_H),
	}))
	local hungerText = shell:text(column, "", "caption", { layoutOrder = 5, color = ink.color, stroke = false })
	local hungerBar = shell:own(Game.ProgressBar.new({
		style = shell.styleName,
		parent = column,
		layoutOrder = 6,
		name = "Hunger",
		palette = "orange",
		value = view.hunger,
		max = 1,
		size = UDim2.new(1, 0, 0, BAR_H),
	}))

	local function refreshAnimal()
		local animal: any = shell.props.animal
		ScreenKit.icon(portrait, animal.icon or (if animal.image == nil then "paw-color" else nil), animal.image)
		nameText:update({ text = view.name })
		moodText:update({ text = "Mood: " .. view.moodText })
		hungerText:update({ text = "Hunger: " .. view.hungerText })
		moodBar:update({ value = view.mood })
		hungerBar:update({ value = view.hunger })
	end

	-- Food tray.
	local tray = ScreenKit.scroller(content, "Tray", 8)
	local trayGrid, trayLayout = ScreenKit.grid(tray, "Grid", 1)
	local slots: { [string]: any } = {}
	local slotSize = 0

	local footer = window.setFooter(FOOTER)
	local throwButton = shell:button(footer, {
		name = "Throw",
		kind = "primary",
		text = props.throwText,
		icon = "arrow-up",
		enabled = view.canThrow,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.new(0.6, 0, 1, -8),
	})

	local function refreshSelection()
		local selectedId = if view.selected then view.selected.id else nil
		for id, slot in pairs(slots) do
			slot:update({ selected = id == selectedId })
		end
		throwButton:update({ enabled = view.canThrow })
	end

	local function focusList(): { GuiObject }
		local objects: { GuiObject } = {}
		for _, food in ipairs(view.foods) do
			if slots[food.id] ~= nil then
				table.insert(objects, slots[food.id].Instance)
			end
		end
		table.insert(objects, throwButton.Instance)
		return objects
	end

	local function buildTray()
		for _, slot in pairs(slots) do
			slot:destroy()
		end
		table.clear(slots)
		local selectedId = if view.selected then view.selected.id else nil
		for i, food in ipairs(view.foods) do
			local slot = Game.InventorySlot.new({
				style = shell.styleName,
				parent = trayGrid,
				layoutOrder = i,
				name = food.id,
				icon = food.icon,
				image = food.image,
				count = food.count,
				rarity = food.rarity,
				selected = food.id == selectedId,
				locked = not food.available,
				size = if slotSize > 0 then UDim2.fromOffset(slotSize, slotSize) else nil,
			})
			slots[food.id] = slot
			slot.Activated:Connect(function()
				shell.props.selectedFood = food.id
				view = ScreensLogic.animalInteraction(shell.props)
				refreshSelection()
				shell:fire("Selected", food.id)
			end)
		end
	end
	shell.trove:Add(function()
		for _, slot in pairs(slots) do
			slot:destroy()
		end
	end)

	shell.trove:Add(throwButton.Activated:Connect(function()
		local food = view.selected
		if food == nil or not view.canThrow then
			return
		end
		-- The selected food hops at once; whether the throw counts is the server's call.
		local slot = slots[food.id]
		if slot ~= nil then
			UI.animate(slot.Instance, "Bounce")
		end
		shell:fire("ThrowRequested", food.id)
	end))

	shell:onLayout(function(_env: ScreensLogic.Env)
		local size = content.AbsoluteSize
		local area = { x = 0, y = 0, w = size.X, h = size.Y }
		if area.w <= 0 then
			local body = window.body()
			area.w, area.h = body.content.w, body.content.h - FOOTER
		end
		local split =
			ScreensLogic.split(area, { ratio = 0.45, minPrimary = 220, minSecondary = 200, stackRatio = 0.55 })
		ScreenKit.rect(card.Instance, split.primary)
		ScreenKit.rect(tray, split.secondary)
		local grid = ScreensLogic.cards("slot", split.secondary.w - 8, #view.foods, split.secondary.h)
		ScreenKit.applyGrid(trayLayout, grid)
		if grid.cellW ~= slotSize then
			slotSize = grid.cellW
			for _, slot in pairs(slots) do
				slot:update({ size = UDim2.fromOffset(slotSize, slotSize) })
			end
		end
	end)

	buildTray()
	refreshAnimal()
	shell:focusables(focusList())

	return {
		update = function(partial: { [string]: any })
			view = ScreensLogic.animalInteraction(shell.props)
			if #view.issues > 0 then
				error("AnimalInteraction: " .. table.concat(view.issues, "; "), 0)
			end
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			if partial.animal ~= nil then
				refreshAnimal()
			end
			if partial.foods ~= nil then
				buildTray()
				shell:relayout()
				shell:focusables(focusList())
			end
			if partial.throwText ~= nil then
				throwButton:update({ text = partial.throwText })
			end
			refreshSelection()
		end,
		methods = {
			-- Plays a reaction on the animal card: "eat", "happy", "full" or "refuse". With a
			-- `context` ({ position = ..., target = ... }) the reaction's Feedback event fires too,
			-- so the world feedback (food trail, hearts) matches the card.
			react = function(kind: string, context: { [string]: any }?)
				local spec = ScreensLogic.REACTIONS[kind]
				if spec == nil then
					return
				end
				UI.animate(portrait, spec.preset)
				UI.popup(spec.text, portrait, { style = spec.popup })
				if context ~= nil and spec.event ~= nil then
					local ok, Feedback = pcall(function(): any
						return require("../Feedback/Feedback")
					end)
					if ok and type(Feedback) == "table" then
						Feedback.fire(spec.event, context)
					end
				end
			end,
		},
	}
end
