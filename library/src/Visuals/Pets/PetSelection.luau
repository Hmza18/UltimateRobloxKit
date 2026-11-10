--!strict
-- The pet selection screen ("choose your starter"): a full-screen backdrop with a slow animated
-- gradient and drifting sparkles, a title that drops in, and a row (or grid, or scroller) of large
-- cards, each with a live 3D preview, name, description, rarity badge and stat chips.
--
--   local screen = Pets.selection({
--       parent = playerGui,
--       title = "Choose your starter",
--       subtitle = "You can collect the others later",
--       pets = {
--           { id = "ember", name = "Ember", description = "Brave and warm.", rarity = "Rare",
--             color = "#FF8A3D", stats = { { label = "Power", value = 8 } }, model = emberModel },
--           { id = "moss", name = "Moss", description = "Calm and sturdy.", color = "#58C26A" },
--           { id = "drift", name = "Drift", description = "Quick and curious.", color = "#5AB0FF" },
--       },
--       onSelect = function(id) end,
--       onConfirm = function(id) end,       -- the server decides what the choice means
--   })
--
-- Interaction: hover or focus lifts a card and its pet; tap / click selects (the pet bounces and
-- celebrates, an indicator slides to the card, the others dim, the confirm button pops in);
-- tapping the selected card again, the button, Enter, Space or gamepad A confirms. Arrow keys,
-- A / D, the DPad and the left stick move the focus (wrapping). Entries without a model get the
-- kit's original demo pet in their colour.
--
-- Layout and navigation rules are in SelectionLogic (spec'd for desktop, tablet and phones).
-- Components come from UI/Game, so every UrkUI style and Visuals theme applies.
--
-- NOT run in Studio: see README.md.

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DemoPet = require("./DemoPet")
local Game = require("../../UI/Game/Game")
local Host = require("../Runtime/Host")
local Motion = require("../Runtime/Motion")
local PetAnimator = require("./PetAnimator")
local PetPreview = require("./PetPreview")
local Props = require("../Runtime/Props")
local SelectionLogic = require("./SelectionLogic")
local Style = require("../../UI/Style/Style")
local Trove = require("../../Util/Trove")

export type Stat = { label: string, value: (string | number)? }

export type PetEntry = {
	id: string,
	name: string,
	description: string?,
	rarity: string?,
	model: Model?,
	color: (Color3 | string)?,
	palette: string?, -- UrkUI palette for the card (default: the style's window surface)
	stats: ({ Stat } | { [string]: string | number })?,
}

export type Props = {
	parent: Instance, -- PlayerGui (a ScreenGui is created), a ScreenGui, or any GuiObject
	title: string?,
	subtitle: string?,
	pets: { PetEntry }, -- three or more
	style: string?, -- UrkUI style name
	theme: string?, -- Visuals theme id (used when no style is given)
	palette: string?, -- backdrop palette (default "purple")
	confirmText: string?,
	selected: string?, -- id selected when the screen opens
	onSelect: ((id: string) -> ())?,
	onConfirm: ((id: string) -> ())?,
	worldPosition: Vector3?, -- where to play Confetti on confirm (needs the VFX module)
	closeOnConfirm: boolean?, -- default true
	displayOrder: number?,
	insets: SelectionLogic.Insets?, -- overrides the measured safe area
}

export type SelectionScreen = {
	Instance: Frame,
	select: (self: SelectionScreen, id: string) -> boolean,
	confirm: (self: SelectionScreen) -> boolean,
	focus: (self: SelectionScreen, id: string?) -> (),
	selected: (self: SelectionScreen) -> string?,
	layout: (self: SelectionScreen) -> SelectionLogic.Layout,
	isDestroyed: (self: SelectionScreen) -> boolean,
	destroy: (self: SelectionScreen) -> (),
}

type Card = {
	index: number,
	entry: PetEntry,
	panel: any,
	root: GuiObject,
	home: UDim2,
	glow: Frame,
	viewport: ViewportFrame,
	preview: PetPreview.Preview,
	name: any,
	description: any?,
	stats: Frame?,
	dim: Frame,
	button: TextButton,
}

local PetSelection = {}

local bindCount = 0

local KEYS: { Enum.KeyCode } = {
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.A,
	Enum.KeyCode.D,
	Enum.KeyCode.W,
	Enum.KeyCode.S,
	Enum.KeyCode.Return,
	Enum.KeyCode.KeypadEnter,
	Enum.KeyCode.Space,
	Enum.KeyCode.DPadLeft,
	Enum.KeyCode.DPadRight,
	Enum.KeyCode.DPadUp,
	Enum.KeyCode.DPadDown,
	Enum.KeyCode.ButtonA,
	Enum.KeyCode.Thumbstick1,
}

-- Other agents' modules: used when present, skipped when not.
local function optional(load: () -> any): any
	local ok, module = pcall(load)
	return if ok and type(module) == "table" then module else nil
end

local uiModule: any = nil
local uiTried = false
local function UI(): any
	if not uiTried then
		uiTried = true
		uiModule = optional(function(): any
			return require("../UI/UIAnimations")
		end)
	end
	return uiModule
end

local function hasUiPreset(id: string): boolean
	local ui = UI()
	if ui == nil or type(ui.registry) ~= "table" then
		return false
	end
	local ok, found = pcall(function(): boolean
		return ui.registry:has(id)
	end)
	return ok and found == true
end

local function themeStyle(theme: string?): string?
	if theme == nil then
		return nil
	end
	local themes = optional(function(): any
		return require("../Themes/Themes")
	end)
	if themes == nil then
		return nil
	end
	local ok, found = pcall(themes.get, theme)
	if ok and type(found) == "table" and type(found.style) == "string" then
		return found.style
	end
	return nil
end

local function toColor(value: (Color3 | string)?, fallback: Color3): Color3
	if typeof(value) == "Color3" then
		return value :: Color3
	elseif type(value) == "string" then
		local ok, color = pcall(Color3.fromHex, value)
		if ok then
			return color
		end
	end
	return fallback
end

local function call(callback: ((id: string) -> ())?, id: string)
	if callback then
		local ok, err = pcall(callback, id)
		if not ok then
			warn("[UVK] pet selection callback failed: " .. tostring(err))
		end
	end
end

local function statList(stats: any): { Stat }
	local out: { Stat } = {}
	if type(stats) ~= "table" then
		return out
	end
	if #stats > 0 then
		for _, stat in stats do
			if type(stat) == "table" and stat.label ~= nil then
				table.insert(out, { label = tostring(stat.label), value = stat.value })
			end
		end
		return out
	end
	local keys: { string } = {}
	for key in stats do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	for _, key in keys do
		table.insert(out, { label = key, value = stats[key] })
	end
	return out
end

local function plain(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function round(radius: UDim, parent: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function setRect(object: GuiObject, rect: SelectionLogic.Rect)
	object.Position = UDim2.fromOffset(rect.x, rect.y)
	object.Size = UDim2.fromOffset(rect.width, rect.height)
end

-- Places a UI/Game component and keeps its props in step, so a later rebuild keeps the rect.
local function place(component: any, rect: SelectionLogic.Rect)
	setRect(component.Instance, rect)
	component.props.size = component.Instance.Size
	component.props.position = component.Instance.Position
end

function PetSelection.new(props: Props): SelectionScreen
	assert(type(props) == "table", "Pets.selection expects a props table")
	assert(typeof(props.parent) == "Instance", "Pets.selection: parent is required")
	assert(
		type(props.pets) == "table" and #props.pets >= SelectionLogic.MIN_PETS,
		"Pets.selection needs three or more pets"
	)
	local ids: { [string]: number } = {}
	for index, entry in props.pets do
		assert(type(entry.id) == "string" and entry.id ~= "", "Pets.selection: every pet needs an id")
		assert(ids[entry.id] == nil, "Pets.selection: duplicate pet id " .. entry.id)
		ids[entry.id] = index
	end

	local styleName = props.style or themeStyle(props.theme)
	local style = Style.get(styleName)
	local trove = Trove.new()
	local count = #props.pets
	local destroyed = false
	local confirming = false
	local focusIndex: number? = nil
	local selectedIndex: number? = nil
	local confirmShown = false
	local lastStick: string? = nil
	local celebrate: (() -> ())? = nil
	local layout: SelectionLogic.Layout

	-- Screen -------------------------------------------------------------------------------
	local host: Instance = props.parent
	local probe: Frame? = nil
	if host:IsA("BasePlayerGui") then
		local screen = Instance.new("ScreenGui")
		screen.Name = "UvkPetSelection"
		screen.ResetOnSpawn = false
		screen.IgnoreGuiInset = true
		screen.ScreenInsets = Enum.ScreenInsets.None
		screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screen.DisplayOrder = props.displayOrder or 50
		screen.Parent = host
		trove:Add(screen)
		-- A second, empty ScreenGui that Roblox insets to the safe area: its frame's rectangle
		-- is the safe area, whatever the device (notch, home indicator, top bar).
		local safeGui = Instance.new("ScreenGui")
		safeGui.Name = "UvkPetSelectionSafeArea"
		safeGui.ResetOnSpawn = false
		safeGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		safeGui.DisplayOrder = -1
		safeGui.Parent = host
		trove:Add(safeGui)
		local frame = plain("SafeArea", safeGui)
		frame.Size = UDim2.fromScale(1, 1)
		probe = frame
		host = screen
	end

	local holder = plain("PetSelection", host)
	holder.Size = UDim2.fromScale(1, 1)
	holder.ClipsDescendants = true
	holder.Active = true -- swallow clicks so the game underneath is not pressed through
	trove:Add(holder)

	-- Backdrop -----------------------------------------------------------------------------
	local swatch = Style.palette(style, props.palette or "purple")
	local backdrop = plain("Backdrop", holder)
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 0
	backdrop.BackgroundColor3 = Color3.new(1, 1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(
		Color3.fromHex(Style.darken(swatch.top, 0.2)),
		Color3.fromHex(Style.darken(swatch.bottom, 0.5))
	)
	gradient.Parent = backdrop

	local sparkleLayer = plain("Sparkles", holder)
	sparkleLayer.Size = UDim2.fromScale(1, 1)
	type Sparkle = { frame: Frame, x: number, y: number, speed: number, phase: number }
	local sparkles: { Sparkle } = {}
	local sparkleCount = if Host.profile().dropOptional then 6 else 14
	for index = 1, sparkleCount do
		-- Spread without Random: golden-ratio offsets give an even, repeatable scatter.
		local a = (index * 0.61803398875) % 1
		local b = (index * 0.41421356237) % 1
		local size = 6 + math.floor(a * 14)
		local frame = plain("Sparkle", sparkleLayer)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = UDim2.fromOffset(size, size)
		frame.Position = UDim2.fromScale(b, a)
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		frame.BackgroundTransparency = 0.85
		if index % 2 == 0 then
			frame.Rotation = 45 -- diamond
			round(UDim.new(0, 2), frame)
		else
			round(UDim.new(0.5, 0), frame)
		end
		table.insert(sparkles, { frame = frame, x = b, y = a, speed = 0.012 + 0.02 * b, phase = a * 6.283 })
	end
	if not Host.settings().reducedMotion then
		local elapsed = 0
		local tick = 0
		trove:Add(Host.clock:add(function(dt: number): boolean?
			elapsed += dt
			tick += 1
			if Host.profile().dropOptional and tick % 2 == 0 then
				return true
			end
			gradient.Rotation = 90 + 10 * math.sin(elapsed * 0.17)
			gradient.Offset = Vector2.new(0, 0.06 * math.sin(elapsed * 0.23))
			for _, sparkle in sparkles do
				local y = (sparkle.y - sparkle.speed * elapsed) % 1
				local x = sparkle.x + 0.015 * math.sin(elapsed * 0.4 + sparkle.phase)
				sparkle.frame.Position = UDim2.fromScale(x, y)
				sparkle.frame.BackgroundTransparency = 0.84 + 0.12 * math.sin(elapsed * 1.3 + sparkle.phase)
			end
			return true
		end))
	end

	-- Title, subtitle, confirm ---------------------------------------------------------------
	local title = Game.GameText.new({
		text = props.title or "Choose your pet",
		size = UDim2.fromOffset(100, 40),
		role = "display",
		style = styleName,
		name = "Title",
		parent = holder,
	})
	trove:Add(title)
	local subtitle: any = nil
	if props.subtitle and props.subtitle ~= "" then
		subtitle = Game.GameText.new({
			text = props.subtitle,
			size = UDim2.fromOffset(100, 20),
			role = "heading",
			style = styleName,
			name = "Subtitle",
			parent = holder,
		})
		trove:Add(subtitle)
	end

	local confirmHolder = plain("Confirm", holder)
	confirmHolder.Visible = false
	confirmHolder.ZIndex = 20
	local confirmButton = Game.CartoonButton.new({
		kind = "primary",
		text = props.confirmText or "CHOOSE",
		size = UDim2.fromScale(1, 1),
		shine = true,
		style = styleName,
		parent = confirmHolder,
	})
	trove:Add(confirmButton)

	-- Cards --------------------------------------------------------------------------------
	local cardArea = plain("Cards", holder)
	cardArea.ZIndex = 5
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Scroller"
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageTransparency = 0.4
	scroller.Visible = false
	scroller.Parent = cardArea
	local cardParent: GuiObject = cardArea

	local indicator = plain("SelectionIndicator", cardArea)
	indicator.ZIndex = 8
	indicator.Visible = false
	indicator.AnchorPoint = Vector2.new(0.5, 0.5)
	local cardRadius = Style.outline(style, "thick") + 14
	round(UDim.new(0, cardRadius + 6), indicator)
	local indicatorStroke = Instance.new("UIStroke")
	indicatorStroke.Color = Color3.new(1, 1, 1)
	indicatorStroke.Thickness = 5
	indicatorStroke.Parent = indicator
	local indicatorGlow = plain("Glow", indicator)
	indicatorGlow.Size = UDim2.new(1, 12, 1, 12)
	indicatorGlow.Position = UDim2.fromOffset(-6, -6)
	round(UDim.new(0, cardRadius + 12), indicatorGlow)
	local glowStroke = Instance.new("UIStroke")
	glowStroke.Color = Color3.new(1, 1, 1)
	glowStroke.Thickness = 6
	glowStroke.Transparency = 0.7
	glowStroke.Parent = indicatorGlow

	local cards: { Card } = {}
	local choose: (index: number) -> ()
	local confirm: () -> boolean
	local setFocus: (index: number?) -> ()

	for index, entry in props.pets do
		local color = toColor(entry.color, Color3.fromRGB(96, 170, 255))
		local panel = Game.Panel.new({
			palette = entry.palette,
			surface = if entry.palette then nil else "window",
			style = styleName,
			name = "Card_" .. entry.id,
			parent = cardArea,
		})
		trove:Add(panel)
		local root: GuiObject = panel.Instance
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.ZIndex = 6
		local content: Instance = panel.Content

		local glow = plain("Glow", content)
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.BackgroundColor3 = color
		glow.BackgroundTransparency = 0.72
		round(UDim.new(0.5, 0), glow)

		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "Preview"
		viewport.BackgroundTransparency = 1
		viewport.BorderSizePixel = 0
		viewport.Ambient = Color3.fromRGB(190, 190, 200)
		viewport.LightColor = Color3.new(1, 1, 1)
		viewport.LightDirection = Vector3.new(-0.4, -1, 0.6)
		viewport.ZIndex = 2
		viewport.Parent = content

		local model = entry.model
		local demo = model == nil
		if model == nil then
			local built = DemoPet.build({ color = color, variant = index, name = entry.name })
			trove:Add(built)
			model = built
		end
		local preview = PetPreview.new(viewport, model :: Model, { clone = not demo })
		trove:Add(function()
			preview:destroy()
		end)

		local name = Game.GameText.new({
			text = entry.name,
			size = UDim2.fromOffset(100, 24),
			role = "heading",
			style = styleName,
			name = "Name",
			parent = content,
		})
		trove:Add(name)
		local description: any = nil
		if entry.description and entry.description ~= "" then
			description = Game.GameText.new({
				text = entry.description,
				size = UDim2.fromOffset(100, 30),
				role = "caption",
				wrap = true,
				style = styleName,
				name = "Description",
				parent = content,
			})
			trove:Add(description)
		end

		local stats: Frame? = nil
		local list = statList(entry.stats)
		if #list > 0 then
			local row = plain("Stats", content)
			local flow = Instance.new("UIListLayout")
			flow.FillDirection = Enum.FillDirection.Horizontal
			flow.HorizontalAlignment = Enum.HorizontalAlignment.Center
			flow.VerticalAlignment = Enum.VerticalAlignment.Center
			flow.SortOrder = Enum.SortOrder.LayoutOrder
			flow.Padding = UDim.new(0, 6)
			flow.Parent = row
			for order, stat in list do
				local text = if stat.value ~= nil then stat.label .. " " .. tostring(stat.value) else stat.label
				local chip = plain("Chip", row)
				chip.LayoutOrder = order
				chip.BackgroundColor3 = Color3.new(0, 0, 0)
				chip.BackgroundTransparency = 0.72
				chip.Size = UDim2.new(0, #text * 7 + 18, 1, 0)
				round(UDim.new(0.5, 0), chip)
				local label = Instance.new("TextLabel")
				label.BackgroundTransparency = 1
				label.Size = UDim2.new(1, -10, 1, -4)
				label.Position = UDim2.fromOffset(5, 2)
				Game.GameText.decorate(label, style, { text = text, role = "caption", stroke = false }, trove)
				label.Parent = chip
			end
			stats = row
		end

		if entry.rarity and entry.rarity ~= "" then
			trove:Add(Game.RarityFrame.new({ rarity = string.lower(entry.rarity), style = styleName, parent = root }))
			trove:Add(Game.Badge.new({
				kind = "new",
				text = string.upper(entry.rarity),
				corner = "topLeft",
				pulse = false,
				style = styleName,
				parent = root,
			}))
		end

		local dim = plain("Dim", root)
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = 1
		dim.ZIndex = 9
		round(UDim.new(0, cardRadius), dim)

		local button = Instance.new("TextButton")
		button.Name = "Hit"
		button.BackgroundTransparency = 1
		button.Text = ""
		button.AutoButtonColor = false
		button.Selectable = false
		button.Size = UDim2.fromScale(1, 1)
		button.ZIndex = 10
		button.Parent = root

		local card: Card = {
			index = index,
			entry = entry,
			panel = panel,
			root = root,
			home = UDim2.fromOffset(0, 0),
			glow = glow,
			viewport = viewport,
			preview = preview,
			name = name,
			description = description,
			stats = stats,
			dim = dim,
			button = button,
		}
		table.insert(cards, card)

		trove:Connect(button.MouseEnter, function()
			setFocus(index)
		end)
		trove:Connect(button.MouseLeave, function()
			if focusIndex == index then
				setFocus(nil)
			end
		end)
		trove:Connect(button.Activated, function()
			if confirming or destroyed then
				return
			end
			if SelectionLogic.press(selectedIndex, index) == "confirm" then
				confirm()
			else
				choose(index)
			end
		end)
	end

	-- Layout -------------------------------------------------------------------------------
	local function measure(): (SelectionLogic.Viewport, SelectionLogic.Insets)
		local size = holder.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			local camera = Workspace.CurrentCamera
			size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		end
		local insets: SelectionLogic.Insets = { left = 0, top = 0, right = 0, bottom = 0 }
		if props.insets then
			insets = props.insets
		elseif probe and probe.AbsoluteSize.X > 0 then
			local origin = holder.AbsolutePosition
			local topLeft = probe.AbsolutePosition - origin
			local bottomRight = (origin + size) - (probe.AbsolutePosition + probe.AbsoluteSize)
			insets = {
				left = math.max(0, topLeft.X),
				top = math.max(0, topLeft.Y),
				right = math.max(0, bottomRight.X),
				bottom = math.max(0, bottomRight.Y),
			}
		end
		return { width = size.X, height = size.Y }, insets
	end

	local function indicatorRect(card: Card): (UDim2, UDim2)
		local size = card.root.Size
		return card.home, UDim2.fromOffset(size.X.Offset + 12, size.Y.Offset + 12)
	end

	local function applyLayout()
		local viewport, insets = measure()
		layout = SelectionLogic.layout(viewport, insets, count, subtitle ~= nil)
		place(title, layout.title)
		if subtitle then
			place(subtitle, layout.subtitle)
		end
		setRect(confirmHolder, layout.confirm)
		confirmHolder.AnchorPoint = Vector2.new(0.5, 0.5)
		confirmHolder.Position =
			UDim2.fromOffset(layout.confirm.x + layout.confirm.width / 2, layout.confirm.y + layout.confirm.height / 2)
		setRect(cardArea, layout.area)

		local wanted: GuiObject = if layout.scrolls then scroller else cardArea
		scroller.Visible = layout.scrolls
		scroller.CanvasSize = UDim2.fromOffset(layout.content.width, layout.content.height)
		scroller.ScrollingDirection = if layout.scrollAxis == "y"
			then Enum.ScrollingDirection.Y
			else Enum.ScrollingDirection.X
		if wanted ~= cardParent then
			cardParent = wanted
			for _, card in cards do
				card.root.Parent = wanted
			end
			indicator.Parent = wanted
		end

		local parts = layout.parts
		for index, card in cards do
			local rect = layout.cards[index]
			card.home = UDim2.fromOffset(rect.x + rect.width / 2, rect.y + rect.height / 2)
			card.root.Size = UDim2.fromOffset(rect.width, rect.height)
			card.root.Position = card.home
			card.panel.props.size = card.root.Size
			card.panel.props.position = card.home
			card.panel.props.anchor = card.root.AnchorPoint
			setRect(card.viewport, parts.preview)
			local glowSize = math.min(parts.preview.width, parts.preview.height) * 0.86
			card.glow.Size = UDim2.fromOffset(glowSize, glowSize)
			card.glow.Position =
				UDim2.fromOffset(parts.preview.x + parts.preview.width / 2, parts.preview.y + parts.preview.height / 2)
			place(card.name, parts.name)
			if card.description then
				card.description.Instance.Visible = parts.description ~= nil
				if parts.description then
					place(card.description, parts.description)
				end
			end
			if card.stats then
				card.stats.Visible = parts.stats ~= nil
				if parts.stats then
					setRect(card.stats, parts.stats)
				end
			end
		end
		if selectedIndex then
			local position, size = indicatorRect(cards[selectedIndex])
			indicator.Position = position
			indicator.Size = size
		end
	end

	applyLayout()
	trove:Connect(holder:GetPropertyChangedSignal("AbsoluteSize"), function()
		if not destroyed and not confirming then
			applyLayout()
		end
	end)
	if probe then
		trove:Connect(probe:GetPropertyChangedSignal("AbsoluteSize"), function()
			if not destroyed and not confirming then
				applyLayout()
			end
		end)
	end

	-- Behaviour ----------------------------------------------------------------------------
	local function lift(card: Card, on: boolean)
		local raised = on and card.index ~= selectedIndex
		local amount = if layout.scrolls then 1.03 else 1.05
		Motion.spring(card.root, {
			Scale = if raised then amount else 1,
			Position = if raised then card.home - UDim2.fromOffset(0, 8) else card.home,
		}, "Snappy")
		card.preview:setHover(on)
	end

	setFocus = function(index: number?)
		if destroyed or confirming or focusIndex == index then
			return
		end
		local previous = focusIndex
		focusIndex = index
		if previous and cards[previous] then
			lift(cards[previous], false)
		end
		if index and cards[index] then
			local card = cards[index]
			lift(card, true)
			if layout.scrolls then
				local rect = layout.cards[index]
				local current = scroller.CanvasPosition
				if layout.scrollAxis == "x" then
					scroller.CanvasPosition = Vector2.new(SelectionLogic.scrollTo(rect, layout, current.X), current.Y)
				else
					scroller.CanvasPosition = Vector2.new(current.X, SelectionLogic.scrollTo(rect, layout, current.Y))
				end
			end
		end
	end

	local function showConfirm()
		if confirmShown then
			return
		end
		confirmShown = true
		local ui = UI()
		if ui and hasUiPreset("PopIn") then
			ui.show(confirmHolder, "PopIn")
		else
			confirmHolder.Visible = true
			Motion.spring(confirmHolder, { Scale = 1 }, "Bouncy", { from = { Scale = 0.5 } })
		end
		-- A gentle pulse once the pop has settled (loops do not start under reduced motion).
		trove:Add(Motion.delay(0.45, function()
			if not destroyed and not confirming then
				Motion.tween(confirmHolder, { Scale = 1.04 }, {
					duration = 0.85,
					easing = "sineInOut",
					repeatCount = -1,
					reverses = true,
					from = { Scale = 1 },
				})
			end
		end))
	end

	choose = function(index: number)
		local card = cards[index]
		if destroyed or confirming or card == nil then
			return
		end
		local previous = selectedIndex
		if previous == index then
			return
		end
		selectedIndex = index
		if previous and cards[previous] then
			cards[previous].preview:setSelected(false)
		end
		-- Same frame: the pet answers, the card settles, the indicator moves.
		card.preview:setSelected(true)
		card.preview:react("SelectBounce")
		if celebrate then
			celebrate()
		end
		celebrate = Motion.delay(0.42, function()
			celebrate = nil
			if not destroyed and selectedIndex == index then
				card.preview:react("HappyReaction")
			end
		end)
		Motion.spring(card.root, { Scale = 1, Position = card.home }, "Bouncy", { from = { Scale = 0.94 } })
		for _, other in cards do
			Motion.tween(
				other.dim,
				{ BackgroundTransparency = if other.index == index then 1 else 0.55 },
				{ duration = 0.18, essential = true }
			)
		end
		local position, size = indicatorRect(card)
		if not indicator.Visible then
			indicator.Position = position
			indicator.Size = size
			indicator.Visible = true
			Motion.spring(indicator, { Scale = 1 }, "Overshoot", { from = { Scale = 1.12 } })
			Motion.tween(indicatorStroke, { Transparency = 0.4 }, {
				duration = 0.9,
				easing = "sineInOut",
				repeatCount = -1,
				reverses = true,
				from = { Transparency = 0 },
			})
		else
			Motion.spring(indicator, { Position = position, Size = size }, "Premium", { essential = true })
		end
		showConfirm()
		call(props.onSelect, card.entry.id)
	end

	local destroy: () -> ()

	local function close()
		if destroyed then
			return
		end
		for _, card in cards do
			Motion.tween(card.root, { Scale = 0 }, { duration = 0.2, easing = "backIn", priority = 10 })
		end
		Motion.tween(backdrop, { BackgroundTransparency = 1 }, { duration = 0.22, priority = 10 })
		sparkleLayer.Visible = false
		trove:Add(Motion.delay(0.24, function()
			destroy()
		end))
	end

	confirm = function(): boolean
		local index = selectedIndex
		if destroyed or confirming or index == nil then
			return false
		end
		confirming = true
		local chosen = cards[index]
		local reduced = Host.settings().reducedMotion
		if celebrate then
			celebrate()
			celebrate = nil
		end

		-- A soft flash; UI.flash already honours reducedFlashing.
		local ui = UI()
		if ui and type(ui.flash) == "function" then
			pcall(ui.flash, Color3.new(1, 1, 1), { alpha = 0.22, duration = 0.3 })
		end
		local vfx = PetAnimator.vfx()
		if props.worldPosition and vfx and type(vfx.play) == "function" then
			pcall(vfx.play, "Confetti", props.worldPosition)
		end

		indicator.Visible = false
		chosen.preview:react("HappyReaction")
		local centre = UDim2.fromOffset(layout.area.width / 2, layout.area.height / 2)
		if layout.scrolls then
			centre = chosen.home
		end
		chosen.root.ZIndex = 12
		Motion.tween(chosen.dim, { BackgroundTransparency = 1 }, { duration = 0.1, essential = true })
		Motion.spring(chosen.root, { Scale = 1.16, Position = centre }, "Overshoot", { priority = 5 })

		local others: { Card } = {}
		for _, card in cards do
			if card ~= chosen then
				table.insert(others, card)
			end
		end
		trove:Add(Motion.stagger(others, 0.05, function(card: Card)
			if destroyed then
				return
			end
			local tilt = if card.index < chosen.index then -14 else 14
			Motion.tween(card.root, {
				Position = card.home + UDim2.fromOffset(0, layout.area.height + layout.confirm.height + 160),
				Rotation = tilt,
			}, { duration = 0.45, easing = "backIn", priority = 5 })
		end))
		Motion.tween(
			title.Instance,
			{ Position = title.Instance.Position - UDim2.fromOffset(0, layout.title.height + layout.title.y + 60) },
			{ duration = 0.3, easing = "quadIn" }
		)
		if subtitle then
			subtitle.Instance.Visible = false
		end
		if ui and hasUiPreset("PopOut") then
			ui.hide(confirmHolder, "PopOut")
		else
			Motion.stop(confirmHolder)
			confirmHolder.Visible = false
		end

		trove:Add(Motion.delay(if reduced then 0.15 else 1, function()
			if destroyed then
				return
			end
			call(props.onConfirm, chosen.entry.id)
			if props.closeOnConfirm ~= false then
				close()
			end
		end))
		return true
	end

	-- Input: keyboard and gamepad through ContextActionService, sunk so the character does not
	-- walk while the screen is open. Focus is manual (GuiService selection is not used), which
	-- keeps one navigation rule for keys, DPad and stick.
	local function act(action: SelectionLogic.Action)
		if destroyed or confirming then
			return
		end
		if action == "confirm" then
			if focusIndex and focusIndex ~= selectedIndex then
				choose(focusIndex)
			elseif selectedIndex then
				confirm()
			end
			return
		end
		if focusIndex == nil then
			setFocus(SelectionLogic.initialFocus(count, selectedIndex))
		else
			setFocus(SelectionLogic.navigate(focusIndex, action, count, layout.columns))
		end
	end

	if RunService:IsClient() then
		bindCount += 1
		local actionName = "UvkPetSelection" .. tostring(bindCount)
		local function onAction(
			_name: string,
			state: Enum.UserInputState,
			input: InputObject
		): Enum.ContextActionResult?
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				local direction = SelectionLogic.stickDirection(input.Position.X, input.Position.Y)
				if direction ~= lastStick then
					lastStick = direction
					if direction then
						act(direction :: any)
					end
				end
				return Enum.ContextActionResult.Sink
			end
			if state == Enum.UserInputState.Begin then
				local action = SelectionLogic.keyAction(input.KeyCode.Name)
				if action then
					act(action :: any)
				end
			end
			return Enum.ContextActionResult.Sink
		end
		local ok, err = pcall(function()
			ContextActionService:BindActionAtPriority(actionName, onAction, false, 3000, table.unpack(KEYS))
		end)
		if ok then
			trove:Add(function()
				ContextActionService:UnbindAction(actionName)
			end)
		else
			warn("[UVK] pet selection input not bound: " .. tostring(err))
		end
	end

	-- Entrance -----------------------------------------------------------------------------
	local titleHome = title.Instance.Position
	Motion.tween(title.Instance, { Position = titleHome }, {
		from = { Position = titleHome - UDim2.fromOffset(0, layout.title.height + 40) },
		duration = 0.5,
		easing = "backOut",
	})
	local roots: { GuiObject } = {}
	for _, card in cards do
		table.insert(roots, card.root)
	end
	local ui = UI()
	if ui and hasUiPreset("PopIn") and type(ui.stagger) == "function" then
		ui.stagger(roots, "PopIn", { interval = 0.08, delay = 0.12 })
	else
		for _, card in cards do
			Props.scaleOf(card.root).Scale = 0
		end
		trove:Add(Motion.delay(0.12, function()
			trove:Add(Motion.stagger(cards, 0.08, function(card: Card)
				if not destroyed then
					Motion.spring(card.root, { Scale = 1 }, "Bouncy", { from = { Scale = 0.6 } })
				end
			end))
		end))
	end

	destroy = function()
		if destroyed then
			return
		end
		destroyed = true
		if celebrate then
			celebrate()
			celebrate = nil
		end
		for _, card in cards do
			Motion.stop(card.root)
			Motion.stop(card.dim)
		end
		Motion.stop(indicator)
		Motion.stop(indicatorStroke)
		Motion.stop(confirmHolder)
		Motion.stop(backdrop)
		Motion.stop(title.Instance)
		trove:Clean()
	end

	local screen: SelectionScreen = {
		Instance = holder,
		-- Selects a pet by id (as a tap would). Returns false for an unknown id.
		select = function(_self: SelectionScreen, id: string): boolean
			local index = ids[id]
			if index == nil or destroyed or confirming then
				return false
			end
			choose(index)
			return true
		end,
		-- Confirms the current selection. Returns false when nothing is selected.
		confirm = function(_self: SelectionScreen): boolean
			return confirm()
		end,
		focus = function(_self: SelectionScreen, id: string?)
			setFocus(if id then ids[id] else nil)
		end,
		selected = function(_self: SelectionScreen): string?
			return if selectedIndex then cards[selectedIndex].entry.id else nil
		end,
		layout = function(_self: SelectionScreen): SelectionLogic.Layout
			return layout
		end,
		isDestroyed = function(_self: SelectionScreen): boolean
			return destroyed
		end,
		destroy = function(_self: SelectionScreen)
			destroy()
		end,
	}

	trove:Connect(confirmButton.Activated, function()
		confirm()
	end)
	if props.selected and ids[props.selected] then
		choose(ids[props.selected])
	end
	return screen
end

return PetSelection
