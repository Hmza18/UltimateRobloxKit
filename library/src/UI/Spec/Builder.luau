--!strict
-- Builder: turns a screen spec (Spec/Screens/*.json, or a Luau table of the same shape) into real
-- Roblox UI made of the Game components. Client only.
--
--   local Builder = require(path.to.UI.Spec.Builder)
--   local screen = Builder.build(require(path.to.Screens.PetSimShop), { parent = playerGui, store = UrkUI.store })
--   screen.Intent:Connect(function(name, args, elementId) ... end)
--   screen:open()
--
-- Builder.build validates first and errors with every message; it never builds a half-valid screen.
-- Components are required lazily, so a screen only loads the components it uses.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Breakpoints = require("../Core/Breakpoints")
local Layout = require("../Core/Layout")
local Signal = require("../../Util/Signal")
local SpecSchema = require("./SpecSchema")
local Style = require("../Style/Style")
local Trove = require("../../Util/Trove")

export type Options = {
	parent: Instance?, -- PlayerGui (default) or a Folder gets a new ScreenGui; a GuiObject embeds the screen
	store: any?, -- an UrkUI Store (observe/subscribe); elements with `bind` follow it
	forwardTo: any?, -- a Signal (for example UrkUI.Intent) that also receives Builder's own intents
	writeBinds: boolean?, -- toggles, sliders and dropdowns also write their value to the store
	displayOrder: number?,
	startOpen: boolean?, -- default: true for hud screens, false for windows and popups
	style: string?, -- overrides spec.style
	breakpoint: string?, -- forces "phone", "tablet", "desktop" or "console" (previews)
}

export type Screen = {
	Instance: Instance,
	Intent: Signal.Signal, -- (name, args, elementId)
	spec: any, -- the spec with defaults filled in
	root: any, -- the GameWindow or popup component, nil for hud screens
	open: (self: Screen) -> (),
	close: (self: Screen) -> (),
	destroy: (self: Screen) -> (),
	find: (self: Screen, id: string) -> any,
	update: (self: Screen, id: string, props: { [string]: any }) -> boolean,
	ids: (self: Screen) -> { string },
}

type Ctx = {
	spec: any,
	styleName: string,
	style: Style.StyleDef,
	store: any?,
	options: Options,
	trove: Trove.Trove,
	elements: { [string]: any },
	intent: Signal.Signal,
	breakpoint: string,
	overlay: Instance?, -- the screen root: modals and loading screens cover it
	deferred: { () -> () }, -- run once every element exists (tooltips look up their target)
	motions: { Motion }, -- elements with a `motion` field, played when the screen opens
}

type Motion = { instance: GuiObject, preset: string, delay: number? }

local Builder = {}

Builder.validate = SpecSchema.validate
Builder.withDefaults = SpecSchema.withDefaults

-- Components -------------------------------------------------------------------------------------

local loaders: { [string]: () -> any } = {
	Badge = function()
		return require("../Game/Badge")
	end,
	CartoonButton = function()
		return require("../Game/CartoonButton")
	end,
	CurrencyCounter = function()
		return require("../Game/CurrencyCounter")
	end,
	Dropdown = function()
		return require("../Game/Dropdown")
	end,
	GameText = function()
		return require("../Game/GameText")
	end,
	GameWindow = function()
		return require("../Game/GameWindow")
	end,
	Grid = function()
		return require("../Game/Grid")
	end,
	IconButton = function()
		return require("../Game/IconButton")
	end,
	LevelBar = function()
		return require("../Game/LevelBar")
	end,
	Panel = function()
		return require("../Game/Panel")
	end,
	ProductCard = function()
		return require("../Game/ProductCard")
	end,
	ProgressBar = function()
		return require("../Game/ProgressBar")
	end,
	PromoBanner = function()
		return require("../Game/PromoBanner")
	end,
	RewardPopup = function()
		return require("../Game/RewardPopup")
	end,
	Section = function()
		return require("../Game/Section")
	end,
	Slider = function()
		return require("../Game/Slider")
	end,
	Timer = function()
		return require("../Game/Timer")
	end,
	Toggle = function()
		return require("../Game/Toggle")
	end,
	AchievementCard = function()
		return require("../Game/AchievementCard")
	end,
	HotbarSlot = function()
		return require("../Game/HotbarSlot")
	end,
	InventorySlot = function()
		return require("../Game/InventorySlot")
	end,
	LeaderboardRow = function()
		return require("../Game/LeaderboardRow")
	end,
	LoadingScreen = function()
		return require("../Game/LoadingScreen")
	end,
	Modal = function()
		return require("../Game/Modal")
	end,
	Notification = function()
		return require("../Game/Notification")
	end,
	PetCard = function()
		return require("../Game/PetCard")
	end,
	PremiumButton = function()
		return require("../Game/PremiumButton")
	end,
	QuestCard = function()
		return require("../Game/QuestCard")
	end,
	RarityBadge = function()
		return require("../Game/RarityBadge")
	end,
	RewardPanel = function()
		return require("../Game/RewardPanel")
	end,
	SelectionCard = function()
		return require("../Game/SelectionCard")
	end,
	StatChip = function()
		return require("../Game/StatChip")
	end,
	TabBar = function()
		return require("../Game/TabBar")
	end,
	Tooltip = function()
		return require("../Game/Tooltip")
	end,
	XPBar = function()
		return require("../Game/XPBar")
	end,
}

local loaded: { [string]: any } = {}

local function component(name: string): any
	local module = loaded[name]
	if module == nil then
		local loader = loaders[name]
		assert(loader ~= nil, "Builder: no Game component " .. name)
		module = loader()
		loaded[name] = module
	end
	return module
end

local iconsModule: any = nil

local function applyIcon(label: ImageLabel, name: string?)
	if name == nil then
		return
	end
	if iconsModule == nil then
		iconsModule = require("../../Icons/Icons")
	end
	if iconsModule.apply(label, name) then
		return
	end
	-- "pack:name" without Visuals.Icons.bridge(): ask the icon vault directly when it is installed.
	if string.find(name, ":", 1, true) ~= nil then
		local ok, vault = pcall(function(): any
			return require("../../Visuals/Icons/IconVault")
		end)
		if ok and type(vault) == "table" and type(vault.apply) == "function" then
			vault.apply(label, name)
		end
	end
end

-- Visuals/UI/UIAnimations, or nil when the Visuals module is not installed (specs still build,
-- `motion` fields are then ignored).
local animations: any = nil
local animationsTried = false

local function uiAnimations(): any
	if not animationsTried then
		animationsTried = true
		local ok, module = pcall(function(): any
			return require("../../Visuals/UI/UIAnimations")
		end)
		if ok and type(module) == "table" then
			animations = module
		end
	end
	return animations
end

-- Sizes ------------------------------------------------------------------------------------------

-- Window size per sizeClass: a fraction of the viewport, capped in pixels. Phones get almost the
-- whole screen for every class except "sm"; tablets get a little more than desktops.
Builder.WINDOW_SIZES = {
	sm = { w = 0.42, h = 0.52, maxW = 520, maxH = 460 },
	md = { w = 0.56, h = 0.7, maxW = 780, maxH = 640 },
	lg = { w = 0.72, h = 0.82, maxW = 1060, maxH = 780 },
	full = { w = 0.96, h = 0.94, maxW = 4000, maxH = 4000 },
}

-- Pixel width and height of a window of `sizeClass` in a viewport at `breakpoint`.
function Builder.windowSize(sizeClass: string?, breakpoint: string, viewport: Vector2): (number, number)
	local class = Builder.WINDOW_SIZES[sizeClass or "md"] or Builder.WINDOW_SIZES.md
	local w, h = class.w, class.h
	if breakpoint == "phone" then
		w = if sizeClass == "sm" then 0.8 else 0.96
		h = if sizeClass == "sm" then 0.82 else 0.94
	elseif breakpoint == "tablet" then
		w = math.min(0.96, w + 0.14)
		h = math.min(0.94, h + 0.08)
	end
	local width = math.min(viewport.X * w, class.maxW)
	local height = math.min(viewport.Y * h, class.maxH)
	return math.floor(math.max(width, 240)), math.floor(math.max(height, 200))
end

-- Height of full-width elements stacked in a column; widths are filled by the column.
local FULL_HEIGHT: { [string]: number } = {
	heading = 44,
	divider = 14,
	level = 40,
	progress = 28,
	toggle = 52,
	slider = 52,
	dropdown = 52,
	listRow = 80,
	tabBar = 52,
	xpBar = 44,
	questCard = 104,
	achievementCard = 96,
	leaderboardRow = 52,
}

-- Fixed pixel sizes for elements that keep their own size in columns, rows and rails.
local FIXED_SIZE: { [string]: Vector2 } = {
	button = Vector2.new(210, 56),
	iconButton = Vector2.new(72, 92),
	currency = Vector2.new(210, 52),
	timer = Vector2.new(170, 42),
	dayCard = Vector2.new(130, 156),
	product = Vector2.new(170, 220),
	premiumButton = Vector2.new(220, 64),
	inventorySlot = Vector2.new(72, 72),
	petCard = Vector2.new(156, 208),
	selectionCard = Vector2.new(220, 280),
	hotbarSlot = Vector2.new(64, 64),
	statChip = Vector2.new(120, 36),
	rewardPanel = Vector2.new(420, 300),
	notification = Vector2.new(320, 84),
}

-- Components that size or place themselves (overlays, and badges that fit their text).
local SELF_SIZED: { [string]: boolean } = { rarityBadge = true, modal = true, tooltip = true, loadingScreen = true }

local RAIL_WIDTH = 320
local HUD_PADDING = 12

local function spacing(ctx: Ctx, name: string?): number
	local values = ctx.style.spacing
	local value = if type(values) == "table" then values[name or "md"] else nil
	return if type(value) == "number" then value else 12
end

local function textHeight(ctx: Ctx, role: string?): number
	return math.floor(Style.textSize(ctx.style, role) * 1.5 + 0.5)
end

local function bannerHeight(ctx: Ctx): number
	local sizes = ctx.style.sizes
	local banner = if type(sizes) == "table" then sizes.banner else nil
	return if type(banner) == "table" and type(banner.height) == "number" then banner.height else 110
end

local function hudCell(ctx: Ctx): number
	local sizes = ctx.style.sizes
	local hud = if type(sizes) == "table" then sizes.hudButton else nil
	local size = if type(hud) == "table" and type(hud.size) == "number" then hud.size else 64
	return size + 8
end

local function columnsFor(ctx: Ctx, element: any): number
	local columns = element.columns
	if type(columns) ~= "table" then
		return 3
	end
	return columns[ctx.breakpoint] or columns.desktop or 3
end

-- "column": stacked full width (window body, popup body). "row": side by side, `count` siblings.
-- "rail": a HUD rail. "grid": inside a UIGridLayout, which sets the size itself.
-- Returns the size and whether the element should grow on Y with its content.
local function slotSize(ctx: Ctx, element: any, slot: string, count: number): (UDim2?, boolean)
	local kind: string = element.type
	if slot == "grid" or SELF_SIZED[kind] then
		return nil, false
	end
	if kind == "grid" and slot == "rail" then
		local columns = columnsFor(ctx, element)
		local cell = hudCell(ctx)
		local gap = spacing(ctx, element.gap)
		local items = if type(element.items) == "table" then #element.items else 0
		local rows = math.max(1, math.ceil(items / columns))
		local aspect = element.cellAspect or 1
		local width = columns * cell + (columns - 1) * gap
		local height = rows * cell * aspect + (rows - 1) * gap
		return UDim2.fromOffset(width, height), false
	end
	if kind == "grid" or kind == "row" then
		if slot == "row" then
			return UDim2.new(1 / count, -spacing(ctx, "md"), 0, 0), true
		elseif slot == "rail" then
			return UDim2.fromOffset(0, 0), true
		end
		return UDim2.fromScale(1, 0), true
	end
	local fixed: Vector2? = FIXED_SIZE[kind]
	if kind == "product" and element.layout == "wide" then
		fixed = nil
	end
	if fixed then
		return UDim2.fromOffset(fixed.X, fixed.Y), false
	end
	local height = FULL_HEIGHT[kind]
	if kind == "banner" or kind == "product" then
		height = bannerHeight(ctx)
	elseif kind == "text" then
		height = textHeight(ctx, element.size)
	elseif height == nil then
		height = 48
	end
	if slot == "row" then
		return UDim2.new(1 / count, -spacing(ctx, "sm"), 0, height), false
	elseif slot == "rail" then
		return UDim2.fromOffset(RAIL_WIDTH, height), false
	end
	return UDim2.new(1, 0, 0, height), false
end

-- Intents ----------------------------------------------------------------------------------------

-- The Game components raise these on UrkUI.Intent themselves (Kit.purchase), so they are never
-- forwarded: forwarding them would prompt a purchase twice.
local COMPONENT_INTENTS: { [string]: boolean } = { Purchase = true, Buy = true, Gift = true }

local function fire(ctx: Ctx, name: string, args: { [string]: any }, elementId: string?)
	ctx.intent:Fire(name, args, elementId)
	local forward = ctx.options.forwardTo
	if forward ~= nil and not COMPONENT_INTENTS[name] then
		forward:Fire(name, args, elementId)
	end
end

-- The intent a press sends when the element has no action: Purchase for Robux prices (the client
-- PurchaseBridge prompts), Buy for currency prices (the server validates and charges), else Select.
function Builder.intentFor(element: any): (string, { [string]: any })
	local id = element.id
	local price = element.price
	if type(price) == "table" and price.kind == "robux" then
		local args = { id = id, productId = price.productId, gamePassId = price.gamePassId, amount = price.amount }
		return "Purchase", args
	elseif type(price) == "table" and price.kind == "currency" then
		return "Buy", { id = id, itemId = id, amount = price.amount, currency = price.currency }
	end
	return "Select", { id = id }
end

local function press(ctx: Ctx, element: any)
	if element.owned == true then
		fire(ctx, "Select", { id = element.id, owned = true }, element.id)
		return
	end
	local name, args = Builder.intentFor(element)
	fire(ctx, name, args, element.id)
end

-- Connects obj.Activated. Elements with an `action` let the component run it (UrkUI actions);
-- the rest fire an intent.
local function wireActivation(ctx: Ctx, element: any, obj: any)
	local activated = obj.Activated
	if activated ~= nil then
		ctx.trove:Add(activated:Connect(function()
			if element.action == nil then
				press(ctx, element)
			end
		end))
	end
	-- ProductCard gift buttons, when the component exposes one.
	local gift = obj.GiftActivated
	if gift ~= nil and element.gift then
		ctx.trove:Add(gift:Connect(function()
			fire(ctx, "Gift", { id = element.id, price = element.price }, element.id)
		end))
	end
end

local function bindElement(ctx: Ctx, path: any, apply: (value: any) -> ())
	local store = ctx.store
	if store == nil or type(path) ~= "string" then
		return
	end
	local unsubscribe = store:observe(path, function(value: any)
		if value ~= nil then
			apply(value)
		end
	end)
	ctx.trove:Add(unsubscribe)
end

-- Helpers ----------------------------------------------------------------------------------------

local function own(ctx: Ctx, obj: any): any
	ctx.trove:Add(function()
		obj:destroy()
	end)
	return obj
end

local function register(ctx: Ctx, element: any, obj: any)
	local id = element.id
	if type(id) == "string" and ctx.elements[id] == nil then
		ctx.elements[id] = obj
	end
end

local function common(ctx: Ctx, element: any, parent: Instance, order: number, size: UDim2?): { [string]: any }
	return {
		style = ctx.styleName,
		parent = parent,
		layoutOrder = order,
		size = size,
		name = element.id or element.type,
		visible = element.visible,
		action = element.action,
	}
end

local function merge(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	for key, value in pairs(extra) do
		base[key] = value
	end
	return base
end

local function frame(name: string, parent: Instance?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	if parent then
		f.Parent = parent
	end
	return f
end

local function list(parent: Instance, horizontal: boolean, gap: number, align: string?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	if align == "left" then
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	elseif align == "right" then
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	else
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = parent
	return layout
end

local function growY(obj: any, grow: boolean)
	local instance = obj.Instance
	if grow and typeof(instance) == "Instance" and instance:IsA("GuiObject") then
		instance.AutomaticSize = Enum.AutomaticSize.Y
	end
end

local function text(ctx: Ctx, parent: Instance, value: string, role: string, order: number, size: UDim2, extra: any?)
	local props: { [string]: any } = {
		style = ctx.styleName,
		parent = parent,
		layoutOrder = order,
		text = value,
		role = role,
		size = size,
	}
	merge(props, extra or {})
	return own(ctx, component("GameText").new(props))
end

local function iconLabel(parent: Instance, name: string?, pixels: number, order: number): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = "Icon"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(pixels, pixels)
	label.LayoutOrder = order
	label.ScaleType = Enum.ScaleType.Fit
	label.Parent = parent
	applyIcon(label, name)
	return label
end

local function hitButton(parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Hit"
	button.Text = ""
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 20
	button.Parent = parent
	return button
end

-- Elements ---------------------------------------------------------------------------------------

type ElementBuilder = (ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number) -> any

local builders: { [string]: ElementBuilder } = {}

local function buildElement(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local build = builders[element.type]
	assert(build ~= nil, "Builder: no builder for element type " .. tostring(element.type))
	local obj = build(ctx, element, parent, order, slot, count)
	register(ctx, element, obj)
	local motion = element.motion
	local instance = if type(obj) == "table" then obj.Instance else nil
	if motion ~= nil and typeof(instance) == "Instance" and instance:IsA("GuiObject") then
		local preset: string = if type(motion) == "table" then motion.preset else motion
		local delay: number? = if type(motion) == "table" then motion.delay else nil
		table.insert(ctx.motions, { instance = instance, preset = preset, delay = delay })
	end
	return obj
end

local function buildChildren(ctx: Ctx, items: any, parent: Instance, slot: string)
	if type(items) ~= "table" then
		return
	end
	for i, child in ipairs(items) do
		buildElement(ctx, child, parent, i, slot, #items)
	end
end

local function simple(moduleName: string, fields: { string }, interactive: boolean): ElementBuilder
	return function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
		local size, grow = slotSize(ctx, element, slot, count)
		local props = common(ctx, element, parent, order, size)
		for _, field in ipairs(fields) do
			props[field] = element[field]
		end
		local obj = own(ctx, component(moduleName).new(props))
		growY(obj, grow)
		if interactive then
			wireActivation(ctx, element, obj)
		end
		return obj
	end
end

local BANNER_FIELDS = { "palette", "title", "subtitle", "icon", "image", "price", "badge", "timer" }
local PRODUCT_FIELDS = {
	"palette",
	"title",
	"subtitle",
	"icon",
	"image",
	"price",
	"badge",
	"gift",
	"rarity",
	"owned",
	"layout",
}

builders.banner = simple("PromoBanner", BANNER_FIELDS, true)

builders.product = simple("ProductCard", PRODUCT_FIELDS, true)

builders.button = simple("CartoonButton", { "kind", "palette", "text", "icon", "price" }, true)

builders.iconButton = simple("IconButton", { "icon", "palette", "label", "badge", "shape" }, true)

builders.timer = simple("Timer", { "seconds", "format", "icon" }, false)

builders.grid = function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local size, grow = slotSize(ctx, element, slot, count)
	local props = common(ctx, element, parent, order, size)
	props.columns = element.columns
	props.cellAspect = element.cellAspect
	props.gap = element.gap
	local grid = own(ctx, component("Grid").new(props))
	growY(grid, grow)
	local container = grid.Content or grid.Instance
	buildChildren(ctx, element.items, container, "grid")
	return grid
end

-- A plain horizontal list; there is no Game component for it.
builders.row = function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local size, grow = slotSize(ctx, element, slot, count)
	local container = frame("Row_" .. tostring(element.id or order), nil)
	container.LayoutOrder = order
	container.Size = size or UDim2.fromScale(1, 0)
	container.AutomaticSize = if slot == "rail" then Enum.AutomaticSize.XY else Enum.AutomaticSize.Y
	if not grow then
		container.AutomaticSize = Enum.AutomaticSize.None
	end
	container.Visible = element.visible ~= false
	list(container, true, spacing(ctx, element.gap), element.align)
	container.Parent = parent
	ctx.trove:Add(container)
	buildChildren(ctx, element.items, container, "row")
	local row = {
		Instance = container,
		update = function(_self: any, props: { [string]: any })
			if props.visible ~= nil then
				container.Visible = props.visible
			end
		end,
		destroy = function(_self: any)
			container:Destroy()
		end,
	}
	return row
end

builders.heading = function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local size = slotSize(ctx, element, slot, count)
	if element.size == nil or element.size == "heading" then
		local props = common(ctx, element, parent, order, size)
		props.title = element.text
		props.divider = true
		local section = own(ctx, component("Section").new(props))
		local heading = {
			Instance = section.Instance,
			section = section,
			update = function(_self: any, changes: { [string]: any })
				local mapped: { [string]: any } = table.clone(changes)
				if changes.text ~= nil then
					mapped.title = changes.text
					mapped.text = nil
				end
				section:update(mapped)
			end,
			destroy = function(_self: any)
				section:destroy()
			end,
		}
		return heading
	end
	return text(ctx, parent, element.text, element.size, order, size or UDim2.new(1, 0, 0, 44))
end

builders.divider = function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local size = slotSize(ctx, element, slot, count)
	local props = common(ctx, element, parent, order, size)
	props.divider = true
	return own(ctx, component("Section").new(props))
end

builders.text = function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local size = slotSize(ctx, element, slot, count)
	local extra: { [string]: any } = { color = element.color, visible = element.visible }
	if slot == "row" then
		extra.align = "left"
	end
	return text(ctx, parent, element.text, element.size or "label", order, size or UDim2.new(1, 0, 0, 28), extra)
end

builders.currency = function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local size = slotSize(ctx, element, slot, count)
	local props = common(ctx, element, parent, order, size)
	props.icon = element.icon
	props.value = element.value or 0
	props.format = element.format
	props.palette = element.palette
	props.plus = element.plus
	local counter = own(ctx, component("CurrencyCounter").new(props))
	wireActivation(ctx, element, counter)
	bindElement(ctx, element.bind, function(value: any)
		counter:update({ value = tonumber(value) or 0 })
	end)
	return counter
end

-- Level and progress binds take a number (the value) or a table { level?, value?, max? }.
local function barValues(value: any): { [string]: any }
	if type(value) == "number" then
		return { value = value }
	elseif type(value) == "table" then
		return { level = value.level, value = value.value, max = value.max }
	end
	return {}
end

builders.level = function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local size = slotSize(ctx, element, slot, count)
	local props = common(ctx, element, parent, order, size)
	props.level = element.level
	props.value = element.value
	props.max = element.max
	local bar = own(ctx, component("LevelBar").new(props))
	bindElement(ctx, element.bind, function(value: any)
		bar:update(barValues(value))
	end)
	return bar
end

builders.progress = function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local size = slotSize(ctx, element, slot, count)
	local props = common(ctx, element, parent, order, size)
	props.value = element.value
	props.max = element.max
	props.palette = element.palette
	props.showText = true
	local bar = own(ctx, component("ProgressBar").new(props))
	bindElement(ctx, element.bind, function(value: any)
		local values = barValues(value)
		values.level = nil
		bar:update(values)
	end)
	return bar
end

-- Toggle, slider and dropdown: a label on the left, the control on the right.
local CONTROL_MODULES: { [string]: string } = { toggle = "Toggle", slider = "Slider", dropdown = "Dropdown" }
local CONTROL_SIZES: { [string]: UDim2 } = {
	toggle = UDim2.fromOffset(76, 40),
	slider = UDim2.new(0.42, 0, 0, 32),
	dropdown = UDim2.new(0.42, 0, 0, 40),
}

local function buildControl(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local size = slotSize(ctx, element, slot, count)
	local container = frame("Control_" .. tostring(element.id), nil)
	container.LayoutOrder = order
	container.Size = size or UDim2.new(1, 0, 0, 52)
	container.Visible = element.visible ~= false
	container.Parent = parent
	ctx.trove:Add(container)
	local surface = Style.surface(ctx.style, "window")
	local labelInk = { align = "left", color = surface.text, stroke = false }
	local label = text(ctx, container, element.label, "label", 1, UDim2.fromScale(0.55, 1), labelInk)
	local function changed(value: any)
		fire(ctx, "Change", { id = element.id, value = value }, element.id)
		local store = ctx.store
		if ctx.options.writeBinds and store ~= nil and type(element.bind) == "string" then
			store:set(element.bind, value)
		end
	end
	local props: { [string]: any } = {
		style = ctx.styleName,
		parent = container,
		layoutOrder = 2,
		size = CONTROL_SIZES[element.type] or UDim2.new(0.42, 0, 1, -8),
		anchor = Vector2.new(1, 0.5),
		position = UDim2.fromScale(1, 0.5),
		name = element.id,
		value = element.value,
		onChanged = changed,
	}
	if element.type == "slider" then
		props.min = element.min
		props.max = element.max
		props.step = element.step
	elseif element.type == "dropdown" then
		props.options = element.options
	end
	local control = own(ctx, component(CONTROL_MODULES[element.type]).new(props))
	bindElement(ctx, element.bind, function(value: any)
		control:update({ value = value })
	end)
	local wrapper = {
		Instance = container,
		control = control,
		Changed = control.Changed,
		update = function(_self: any, changes: { [string]: any })
			local rest: { [string]: any } = table.clone(changes)
			if changes.label ~= nil then
				label:update({ text = changes.label })
				rest.label = nil
			end
			if changes.visible ~= nil then
				container.Visible = changes.visible
				rest.visible = nil
			end
			if next(rest) ~= nil then
				control:update(rest)
			end
		end,
		destroy = function(_self: any)
			container:Destroy()
		end,
	}
	return wrapper
end

builders.toggle = buildControl
builders.slider = buildControl
builders.dropdown = buildControl

-- Day card: a Panel with "DAY n", the reward icon and text, and a state overlay.
builders.dayCard = function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local size = slotSize(ctx, element, slot, count)
	local state: { [string]: any } = {
		day = element.day,
		reward = element.reward,
		state = element.state,
		premium = element.premium,
	}
	local function paletteFor(): string
		if state.premium then
			return "gold"
		elseif element.palette ~= nil then
			return element.palette
		elseif state.state == "today" then
			return "green"
		end
		return "blue"
	end
	local props = common(ctx, element, parent, order, size)
	props.action = nil
	props.palette = paletteFor()
	props.gloss = true
	props.shadow = true
	props.pattern = state.premium == true
	local panel = own(ctx, component("Panel").new(props))
	local root: Instance = panel.Content or panel.Instance
	local body = frame("Body", root)
	list(body, false, 4, "center")
	local dayText = text(ctx, body, "DAY " .. tostring(state.day), "label", 1, UDim2.fromScale(1, 0.22))
	iconLabel(body, element.icon, 56, 2)
	local rewardText = text(ctx, body, state.reward, "caption", 3, UDim2.fromScale(1, 0.2))
	local shade = frame("Claimed", panel.Instance)
	shade.BackgroundTransparency = 0.45
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.ZIndex = 10
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Style.outline(ctx.style, "heavy") * 2)
	corner.Parent = shade
	local check = iconLabel(shade, "check-color", 48, 1)
	check.AnchorPoint = Vector2.new(0.5, 0.5)
	check.Position = UDim2.fromScale(0.5, 0.5)
	local lock = iconLabel(panel.Instance, "lock-color", 22, 1)
	lock.AnchorPoint = Vector2.new(1, 1)
	lock.Position = UDim2.new(1, -6, 1, -6)
	lock.ZIndex = 11
	local badge: any = nil
	local function refresh()
		shade.Visible = state.state == "claimed"
		lock.Visible = state.state == "locked"
		panel:update({ palette = paletteFor(), pattern = state.premium == true })
		if badge then
			badge:destroy()
			badge = nil
		end
		if state.state == "today" then
			badge = component("Badge").new({
				style = ctx.styleName,
				parent = panel.Instance,
				kind = "attention",
				pulse = true,
			})
		elseif state.premium then
			badge = component("Badge").new({
				style = ctx.styleName,
				parent = panel.Instance,
				kind = "best",
				text = "BIG",
			})
		end
	end
	refresh()
	ctx.trove:Add(function()
		if badge then
			badge:destroy()
		end
	end)
	local activated = Signal.new()
	local hit = hitButton(panel.Instance)
	ctx.trove:Add(hit.Activated:Connect(function()
		activated:Fire()
	end))
	local card = {
		Instance = panel.Instance,
		panel = panel,
		Activated = activated,
		update = function(_self: any, changes: { [string]: any })
			for key, value in pairs(changes) do
				state[key] = value
			end
			if changes.day ~= nil then
				dayText:update({ text = "DAY " .. tostring(changes.day) })
			end
			if changes.reward ~= nil then
				rewardText:update({ text = changes.reward })
			end
			refresh()
		end,
		destroy = function(_self: any)
			activated:DisconnectAll()
			panel:destroy()
		end,
	}
	ctx.trove:Add(activated:Connect(function()
		fire(ctx, "Select", { id = element.id, day = state.day, state = state.state }, element.id)
	end))
	return card
end

-- List row: rank, icon, title and subtitle (with an optional progress bar), value and a button.
builders.listRow = function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local size = slotSize(ctx, element, slot, count)
	local props = common(ctx, element, parent, order, size)
	props.action = nil
	props.padding = "sm"
	if element.palette ~= nil then
		props.palette = element.palette
	else
		props.surface = "inset"
	end
	local panel = own(ctx, component("Panel").new(props))
	local root: Instance = panel.Content or panel.Instance
	local body = frame("Body", root)
	list(body, true, spacing(ctx, "md"), "left")
	local onPalette = element.palette ~= nil
	local inkColor = if onPalette then nil else Style.surface(ctx.style, "inset").text
	local ink: { [string]: any } = { color = inkColor, stroke = onPalette, align = "left" }
	local parts: { [string]: any } = {}
	if element.rank ~= nil then
		parts.rank = text(ctx, body, "#" .. tostring(element.rank), "heading", 1, UDim2.new(0, 56, 1, 0), ink)
	end
	if element.icon ~= nil then
		iconLabel(body, element.icon, 48, 2)
	end
	local reserved = 56 + 48 + 150 + (if element.button ~= nil then 190 else 0)
	local column = frame("Text", body)
	column.LayoutOrder = 3
	column.Size = UDim2.new(1, -reserved, 1, 0)
	list(column, false, 2, "left")
	parts.title = text(ctx, column, element.title, "label", 1, UDim2.new(1, 0, 0, 24), ink)
	if element.subtitle ~= nil then
		parts.subtitle = text(ctx, column, element.subtitle, "caption", 2, UDim2.new(1, 0, 0, 18), ink)
	end
	local progress = element.progress
	if type(progress) == "table" then
		local bar = component("ProgressBar").new({
			style = ctx.styleName,
			parent = column,
			layoutOrder = 3,
			size = UDim2.new(1, 0, 0, 14),
			value = progress.value,
			max = progress.max,
			palette = progress.palette,
			showText = false,
		})
		own(ctx, bar)
		parts.progress = bar
		bindElement(ctx, progress.bind, function(value: any)
			local values = barValues(value)
			values.level = nil
			bar:update(values)
		end)
	end
	if element.value ~= nil then
		local valueInk = table.clone(ink)
		valueInk.align = "right"
		parts.value = text(ctx, body, tostring(element.value), "price", 4, UDim2.new(0, 150, 1, 0), valueInk)
	end
	if type(element.button) == "table" then
		parts.button = buildElement(ctx, element.button, body, 5, "row", 1)
	end
	local activated = Signal.new()
	if element.button == nil then
		local hit = hitButton(panel.Instance)
		ctx.trove:Add(hit.Activated:Connect(function()
			activated:Fire()
		end))
		ctx.trove:Add(activated:Connect(function()
			fire(ctx, "Select", { id = element.id }, element.id)
		end))
	end
	local row = {
		Instance = panel.Instance,
		panel = panel,
		parts = parts,
		Activated = activated,
		update = function(_self: any, changes: { [string]: any })
			if changes.title ~= nil and parts.title then
				parts.title:update({ text = changes.title })
			end
			if changes.subtitle ~= nil and parts.subtitle then
				parts.subtitle:update({ text = changes.subtitle })
			end
			if changes.value ~= nil and parts.value then
				parts.value:update({ text = tostring(changes.value) })
			end
			if changes.rank ~= nil and parts.rank then
				parts.rank:update({ text = "#" .. tostring(changes.rank) })
			end
			if type(changes.progress) == "table" and parts.progress then
				parts.progress:update(changes.progress)
			end
			if changes.palette ~= nil then
				panel:update({ palette = changes.palette })
			end
			if changes.visible ~= nil then
				panel:update({ visible = changes.visible })
			end
		end,
		destroy = function(_self: any)
			activated:DisconnectAll()
			panel:destroy()
		end,
	}
	return row
end

-- Animated components (Game components that take their motion from Visuals/UI) --------------------

builders.premiumButton = simple("PremiumButton", { "text", "icon", "image", "palette", "shine", "glow" }, true)

builders.inventorySlot =
	simple("InventorySlot", { "icon", "image", "count", "rarity", "selected", "equipped", "locked" }, true)

builders.petCard =
	simple("PetCard", { "title", "icon", "image", "rarity", "stats", "palette", "selected", "equipped" }, true)

builders.selectionCard =
	simple("SelectionCard", { "title", "description", "icon", "image", "palette", "selected" }, true)

builders.rarityBadge = simple("RarityBadge", { "rarity", "text" }, false)

local ACHIEVEMENT_FIELDS =
	{ "title", "description", "icon", "image", "tier", "maxTier", "value", "max", "unlocked", "palette" }

builders.achievementCard = simple("AchievementCard", ACHIEVEMENT_FIELDS, false)

-- The common props of an element whose builder wires its own signals.
local function plain(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local size = slotSize(ctx, element, slot, count)
	return common(ctx, element, parent, order, size)
end

builders.tabBar = function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local props = plain(ctx, element, parent, order, slot, count)
	props.tabs = element.tabs
	props.value = element.value
	props.palette = element.palette
	local tabs = own(ctx, component("TabBar").new(props))
	ctx.trove:Add(tabs.Changed:Connect(function(tabId: string)
		fire(ctx, "Tab", { id = element.id, value = tabId }, element.id)
	end))
	return tabs
end

builders.xpBar = function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local props = plain(ctx, element, parent, order, slot, count)
	props.level = element.level
	props.value = element.value
	props.max = element.max
	props.palette = element.palette
	local bar = own(ctx, component("XPBar").new(props))
	bindElement(ctx, element.bind, function(value: any)
		bar:update(barValues(value))
	end)
	return bar
end

builders.statChip = function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
	local props = plain(ctx, element, parent, order, slot, count)
	for _, field in ipairs({ "icon", "image", "value", "format", "prefix", "suffix", "palette" }) do
		props[field] = element[field]
	end
	local chip = own(ctx, component("StatChip").new(props))
	bindElement(ctx, element.bind, function(value: any)
		chip:update({ value = value })
	end)
	return chip
end

builders.leaderboardRow = function(
	ctx: Ctx,
	element: any,
	parent: Instance,
	order: number,
	slot: string,
	count: number
): any
	local props = plain(ctx, element, parent, order, slot, count)
	for _, field in ipairs({ "rank", "title", "value", "format", "avatar", "highlight" }) do
		props[field] = element[field]
	end
	local row = own(ctx, component("LeaderboardRow").new(props))
	bindElement(ctx, element.bind, function(value: any)
		row:update({ value = tonumber(value) or 0 })
	end)
	return row
end

-- Reward panels and quest cards raise Claim; the server decides what the claim grants.
local function claimable(moduleName: string, fields: { string }): ElementBuilder
	return function(ctx: Ctx, element: any, parent: Instance, order: number, slot: string, count: number): any
		local props = plain(ctx, element, parent, order, slot, count)
		for _, field in ipairs(fields) do
			props[field] = element[field]
		end
		local obj = own(ctx, component(moduleName).new(props))
		ctx.trove:Add(obj.Claimed:Connect(function()
			if element.action == nil then
				fire(ctx, "Claim", { id = element.id }, element.id)
			end
		end))
		return obj
	end
end

builders.rewardPanel = claimable("RewardPanel", { "title", "rewards", "columns", "claimText", "claimed", "palette" })

builders.questCard =
	claimable("QuestCard", { "title", "description", "value", "max", "rewards", "state", "claimText", "palette" })

builders.notification = function(
	ctx: Ctx,
	element: any,
	parent: Instance,
	order: number,
	slot: string,
	count: number
): any
	local props = plain(ctx, element, parent, order, slot, count)
	for _, field in ipairs({ "kind", "title", "text", "icon", "image", "palette", "duration" }) do
		props[field] = element[field]
	end
	props.destroyOnClose = false -- the screen owns it, so it can be shown again
	local toast = own(ctx, component("Notification").new(props))
	wireActivation(ctx, element, toast)
	ctx.trove:Add(toast.Closed:Connect(function()
		fire(ctx, "Close", { id = element.id }, element.id)
	end))
	return toast
end

-- The slot shows `cooldown` seconds after each press while it is ready. That is presentation
-- only: the Select intent carries `ready`, and the server decides whether the ability ran.
builders.hotbarSlot = function(
	ctx: Ctx,
	element: any,
	parent: Instance,
	order: number,
	slot: string,
	count: number
): any
	local props = plain(ctx, element, parent, order, slot, count)
	for _, field in ipairs({ "icon", "image", "keybind", "palette" }) do
		props[field] = element[field]
	end
	local hotbar = own(ctx, component("HotbarSlot").new(props))
	ctx.trove:Add(hotbar.Activated:Connect(function()
		local ready = hotbar:isReady()
		if element.action == nil then
			fire(ctx, "Select", { id = element.id, ready = ready }, element.id)
		end
		if ready and type(element.cooldown) == "number" and element.cooldown > 0 then
			hotbar:startCooldown(element.cooldown)
		end
	end))
	return hotbar
end

-- Modals and loading screens cover the whole screen, so they are parented to the screen root, not
-- to the column they are listed in. Open a modal with screen:find(id):open().
builders.modal = function(ctx: Ctx, element: any, parent: Instance, _order: number, _slot: string, _count: number): any
	local modal = own(
		ctx,
		component("Modal").new({
			style = ctx.styleName,
			parent = ctx.overlay or parent,
			name = element.id,
			title = element.title,
			text = element.text,
			buttons = element.buttons,
			headerPalette = element.headerPalette,
			closable = element.closable,
		})
	)
	ctx.trove:Add(modal.Activated:Connect(function(buttonId: string)
		fire(ctx, "Select", { id = element.id, button = buttonId }, element.id)
	end))
	ctx.trove:Add(modal.Closed:Connect(function()
		fire(ctx, "Close", { id = element.id }, element.id)
	end))
	return modal
end

builders.loadingScreen = function(
	ctx: Ctx,
	element: any,
	parent: Instance,
	_order: number,
	_slot: string,
	_count: number
): any
	local loading = own(
		ctx,
		component("LoadingScreen").new({
			style = ctx.styleName,
			parent = ctx.overlay or parent,
			name = element.id or "Loading",
			title = element.title,
			icon = element.icon,
			logo = element.image,
			tips = element.tips,
			progress = element.progress,
			palette = element.palette,
			visible = element.visible,
			destroyOnClose = false,
		})
	)
	if loading.Closed ~= nil then
		ctx.trove:Add(loading.Closed:Connect(function()
			fire(ctx, "Close", { id = element.id }, element.id)
		end))
	end
	return loading
end

-- A tooltip describes another element, which may be listed after it: it is made once every
-- element exists. Until then the id maps to a small proxy.
builders.tooltip = function(
	ctx: Ctx,
	element: any,
	_parent: Instance,
	_order: number,
	_slot: string,
	_count: number
): any
	local proxy: { [string]: any } = {}
	function proxy.update(_self: any, changes: { [string]: any })
		if proxy.tooltip ~= nil then
			proxy.tooltip:update(changes)
		end
	end
	function proxy.destroy(_self: any)
		if proxy.tooltip ~= nil then
			proxy.tooltip:destroy()
			proxy.tooltip = nil
		end
	end
	table.insert(ctx.deferred, function()
		local target = ctx.elements[element.target]
		local instance = if type(target) == "table" then target.Instance else nil
		if typeof(instance) ~= "Instance" or not instance:IsA("GuiObject") then
			return
		end
		proxy.tooltip = component("Tooltip").new({
			style = ctx.styleName,
			target = instance,
			text = element.text,
			side = element.side,
		})
		proxy.Instance = proxy.tooltip.Instance
	end)
	ctx.trove:Add(function()
		proxy:destroy()
	end)
	return proxy
end

-- Viewport and breakpoint ------------------------------------------------------------------------

local function viewportOf(options: Options): Vector2
	local parent = options.parent
	if parent ~= nil and parent:IsA("GuiObject") and parent.AbsoluteSize.X > 0 then
		return parent.AbsoluteSize
	end
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		return camera.ViewportSize
	end
	return Vector2.new(1920, 1080)
end

function Builder.breakpoint(viewport: Vector2, forced: string?): string
	if forced ~= nil and Breakpoints.isValid(forced) then
		return forced
	end
	local input: Breakpoints.InputState = {
		touch = UserInputService.TouchEnabled,
		keyboard = UserInputService.KeyboardEnabled,
		gamepad = UserInputService.GamepadEnabled,
		tenFoot = GuiService:IsTenFootInterface(),
	}
	return Breakpoints.classify({ x = viewport.X, y = viewport.Y }, input)
end

-- Roots ------------------------------------------------------------------------------------------

local DISPLAY_ORDER: { [string]: number } = { hud = 0, window = 10, popup = 50 }

-- A ScreenGui under PlayerGui (or options.parent), or a full-size Frame when embedding in a GuiObject.
local function makeRoot(ctx: Ctx): (Instance, GuiObject?)
	local spec = ctx.spec
	local parent = ctx.options.parent
	if parent ~= nil and parent:IsA("GuiObject") then
		local holder = frame("Screen_" .. spec.id, nil)
		holder.ClipsDescendants = true
		holder.Parent = parent
		return holder, holder
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = spec.id
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = ctx.options.displayOrder or DISPLAY_ORDER[spec.kind] or 10
	if spec.kind == "hud" then
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	else
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end
	gui.Enabled = false
	if parent == nil then
		local player = Players.LocalPlayer
		assert(player ~= nil, "Builder.build needs options.parent outside a LocalScript")
		parent = player:WaitForChild("PlayerGui")
	end
	gui.Parent = parent
	return gui, nil
end

local function setShown(root: Instance, shown: boolean)
	if root:IsA("ScreenGui") then
		root.Enabled = shown
	elseif root:IsA("GuiObject") then
		root.Visible = shown
	end
end

local function bodyFrame(ctx: Ctx, parent: Instance): Frame
	local body = frame("Body", parent)
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	list(body, false, spacing(ctx, "md"), "center")
	local padding = Instance.new("UIPadding")
	local pad = UDim.new(0, spacing(ctx, "sm"))
	padding.PaddingTop = pad
	padding.PaddingBottom = pad
	padding.PaddingLeft = pad
	padding.PaddingRight = pad
	padding.Parent = body
	if parent:IsA("ScrollingFrame") then
		parent.AutomaticCanvasSize = Enum.AutomaticSize.Y
		parent.CanvasSize = UDim2.fromScale(0, 0)
	end
	return body
end

local function buildWindow(ctx: Ctx, root: Instance): any
	local spec = ctx.spec
	local config = spec.window
	local viewport = viewportOf(ctx.options)
	local width, height = Builder.windowSize(config.sizeClass, ctx.breakpoint, viewport)
	local window = component("GameWindow").new({
		style = ctx.styleName,
		parent = root,
		name = spec.id,
		title = config.title,
		headerPalette = config.headerPalette,
		sizeClass = config.sizeClass,
		width = config.width or width,
		height = config.height or height,
		closable = config.closable,
		scroll = config.scroll,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
	})
	own(ctx, window)
	local content: Instance = window.Content or window.Instance
	buildChildren(ctx, spec.body, bodyFrame(ctx, content), "column")
	if window.Closed ~= nil then
		ctx.trove:Add(window.Closed:Connect(function()
			fire(ctx, "Close", { id = spec.id }, nil)
		end))
	end
	-- Resize with the viewport unless the spec fixed a size.
	if config.width == nil or config.height == nil then
		local function resize()
			local w, h = Builder.windowSize(config.sizeClass, ctx.breakpoint, viewportOf(ctx.options))
			window:update({ width = config.width or w, height = config.height or h })
		end
		local camera = Workspace.CurrentCamera
		local parent = ctx.options.parent
		if parent ~= nil and parent:IsA("GuiObject") then
			ctx.trove:Add(parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize))
		elseif camera ~= nil then
			ctx.trove:Add(camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize))
		end
	end
	return window
end

-- Rail names in specs follow the contract; Layout names the centre rails topCenter / bottomCenter.
local RAIL_LAYOUT: { [string]: string } = { top = "topCenter", bottom = "bottomCenter" }

local function buildHud(ctx: Ctx, root: Instance)
	local spec = ctx.spec
	local safe = frame("Safe", root)
	local function place()
		local viewport = viewportOf(ctx.options)
		local rect = Layout.safeRect({ x = viewport.X, y = viewport.Y }, nil, HUD_PADDING)
		safe.Position = UDim2.fromOffset(rect.x, rect.y)
		safe.Size = UDim2.fromOffset(rect.w, rect.h)
	end
	place()
	local camera = Workspace.CurrentCamera
	local parent = ctx.options.parent
	if parent ~= nil and parent:IsA("GuiObject") then
		ctx.trove:Add(parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))
	elseif camera ~= nil then
		ctx.trove:Add(camera:GetPropertyChangedSignal("ViewportSize"):Connect(place))
	end
	for _, name in ipairs(SpecSchema.RULES.rails) do
		local elements = spec.rails[name]
		if type(elements) == "table" then
			local rail = Layout.rail(RAIL_LAYOUT[name] or name)
			assert(rail ~= nil, "Builder: no layout for rail " .. name)
			local holder = frame("Rail_" .. name, safe)
			holder.AnchorPoint = Vector2.new(rail.anchor.x, rail.anchor.y)
			holder.Position = UDim2.fromScale(rail.position.x, rail.position.y)
			holder.Size = UDim2.fromScale(0, 0)
			holder.AutomaticSize = Enum.AutomaticSize.XY
			local layout = list(holder, rail.direction == "horizontal", spacing(ctx, "sm"), rail.horizontal)
			if rail.vertical == "top" then
				layout.VerticalAlignment = Enum.VerticalAlignment.Top
			elseif rail.vertical == "bottom" then
				layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
			end
			buildChildren(ctx, elements, holder, "rail")
		end
	end
end

local function playIn(instance: Instance)
	local ok, Motion = pcall(function(): any
		return require("../Runtime/Motion")
	end)
	if not ok or not instance:IsA("GuiObject") then
		return
	end
	local play = Motion.play
	if type(play) == "function" then
		play(instance, "popIn")
	else
		Motion.pop(instance)
	end
end

local function buildConfirm(ctx: Ctx, root: Instance, close: () -> ()): any
	local spec = ctx.spec
	local popup = spec.popup
	local backdrop = frame("Backdrop", root)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Active = true
	local width, height = Builder.windowSize("sm", ctx.breakpoint, viewportOf(ctx.options))
	local panel = component("Panel").new({
		style = ctx.styleName,
		parent = root,
		name = "Dialog",
		surface = "window",
		shadow = true,
		padding = "lg",
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromOffset(width, height),
	})
	own(ctx, panel)
	local inner: Instance = panel.Content or panel.Instance
	local stack = frame("Stack", inner)
	list(stack, false, spacing(ctx, "md"), "center")
	local surface = Style.surface(ctx.style, "window")
	local header = component("Panel").new({
		style = ctx.styleName,
		parent = stack,
		layoutOrder = 1,
		palette = popup.palette,
		gloss = true,
		size = UDim2.new(1, 0, 0, 56),
	})
	own(ctx, header)
	text(ctx, header.Content or header.Instance, popup.title, "title", 1, UDim2.fromScale(1, 1))
	if popup.icon ~= nil then
		iconLabel(stack, popup.icon, 72, 2)
	end
	if popup.message ~= nil then
		text(ctx, stack, popup.message, "label", 3, UDim2.new(1, 0, 0, 48), { color = surface.text, stroke = false })
	end
	local body = frame("Body", stack)
	body.LayoutOrder = 4
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	list(body, false, spacing(ctx, "sm"), "center")
	buildChildren(ctx, spec.body, body, "column")
	local buttons = frame("Buttons", stack)
	buttons.LayoutOrder = 5
	buttons.Size = UDim2.new(1, 0, 0, 60)
	list(buttons, true, spacing(ctx, "lg"), "center")
	local price = popup.price
	local cancel = component("CartoonButton").new({
		style = ctx.styleName,
		parent = buttons,
		layoutOrder = 1,
		name = "Cancel",
		kind = "neutral",
		text = popup.cancelText,
		size = UDim2.fromOffset(170, 56),
	})
	own(ctx, cancel)
	local confirmKind = "primary"
	if type(price) == "table" and price.kind == "robux" then
		confirmKind = "robux"
	elseif type(price) == "table" and price.kind == "currency" then
		confirmKind = "buy"
	end
	local confirm = component("CartoonButton").new({
		style = ctx.styleName,
		parent = buttons,
		layoutOrder = 2,
		name = "Confirm",
		kind = confirmKind,
		text = popup.confirmText,
		price = price,
		size = UDim2.fromOffset(210, 56),
	})
	own(ctx, confirm)
	ctx.trove:Add(cancel.Activated:Connect(function()
		fire(ctx, "Cancel", { id = spec.id }, "cancel")
		close()
	end))
	ctx.trove:Add(confirm.Activated:Connect(function()
		if price ~= nil then
			press(ctx, { id = spec.id, price = price })
		else
			fire(ctx, "Confirm", { id = spec.id }, "confirm")
		end
		close()
	end))
	ctx.elements.confirm = ctx.elements.confirm or confirm
	ctx.elements.cancel = ctx.elements.cancel or cancel
	return panel
end

-- Build ------------------------------------------------------------------------------------------

-- Accepts a spec table or a ModuleScript that returns one (Rojo turns Screens/*.json into those).
local function resolveSpec(input: any): any
	if typeof(input) == "Instance" and input:IsA("ModuleScript") then
		return (require :: any)(input)
	end
	return input
end

function Builder.build(input: any, options: Options?): Screen
	local opts: Options = options or {}
	local raw = resolveSpec(input)
	if opts.style ~= nil and type(raw) == "table" then
		raw = table.clone(raw)
		raw.style = opts.style
	end
	local issues = SpecSchema.validate(raw)
	if #issues > 0 then
		local id = if type(raw) == "table" then tostring(raw.id) else "?"
		error("Builder: spec " .. id .. " is invalid:\n" .. SpecSchema.format(issues), 2)
	end
	local spec = SpecSchema.withDefaults(raw)
	local trove = Trove.new()
	local intent = Signal.new()
	local ctx: Ctx = {
		spec = spec,
		styleName = spec.style,
		style = Style.get(spec.style),
		store = opts.store,
		options = opts,
		trove = trove,
		elements = {},
		intent = intent,
		breakpoint = Builder.breakpoint(viewportOf(opts), opts.breakpoint),
		deferred = {},
		motions = {},
	}
	local root, holder = makeRoot(ctx)
	trove:Add(root)
	ctx.overlay = root

	local shown = false
	local rootComponent: any = nil
	local rewardPopup: any = nil

	local screen: Screen
	local function hide()
		shown = false
		if spec.kind == "window" and rootComponent ~= nil then
			rootComponent:close()
		else
			setShown(root, false)
		end
	end

	if spec.kind == "window" then
		rootComponent = buildWindow(ctx, root)
	elseif spec.kind == "hud" then
		buildHud(ctx, root)
	elseif spec.popup.variant == "confirm" then
		rootComponent = buildConfirm(ctx, root, function()
			screen:close()
		end)
	end
	if rootComponent ~= nil and ctx.elements[spec.id] == nil then
		ctx.elements[spec.id] = rootComponent
	end
	if rootComponent ~= nil and rootComponent.Closed ~= nil then
		trove:Add(rootComponent.Closed:Connect(function()
			shown = false
		end))
	end
	if holder ~= nil then
		holder.Visible = false
	end
	for _, run in ipairs(ctx.deferred) do
		run()
	end
	table.clear(ctx.deferred)

	-- `motion` fields: played on every open through Visuals.UI, which honours reduced motion.
	local function playMotions()
		local ui = uiAnimations()
		if ui == nil then
			return
		end
		for _, motion in ipairs(ctx.motions) do
			if motion.instance.Parent ~= nil then
				ui.animate(motion.instance, motion.preset, { delay = motion.delay })
			end
		end
	end
	local function stopMotions()
		local ui = animations
		if ui == nil then
			return
		end
		for _, motion in ipairs(ctx.motions) do
			ui.stop(motion.instance, true)
		end
	end
	trove:Add(stopMotions)

	local function showReward()
		if rewardPopup ~= nil then
			rewardPopup:destroy()
		end
		local popup = spec.popup
		rewardPopup = component("RewardPopup").new({
			style = ctx.styleName,
			parent = root,
			name = spec.id,
			title = popup.title,
			icon = popup.icon,
			amount = popup.amount,
			palette = popup.palette,
			rays = popup.rays,
		})
		ctx.elements[spec.id] = rewardPopup
		if type(rewardPopup.open) == "function" then
			rewardPopup:open()
		end
		local closed = rewardPopup.Closed
		if closed ~= nil then
			closed:Once(function()
				fire(ctx, "Close", { id = spec.id }, nil)
			end)
		end
	end
	trove:Add(function()
		if rewardPopup ~= nil then
			rewardPopup:destroy()
		end
	end)

	local destroyed = false
	screen = {
		Instance = root,
		Intent = intent,
		spec = spec,
		root = rootComponent,
		open = function(_self: Screen)
			if destroyed then
				return
			end
			shown = true
			setShown(root, true)
			if spec.kind == "window" then
				rootComponent:open()
			elseif spec.kind == "popup" then
				if spec.popup.variant == "reward" then
					showReward()
				elseif rootComponent ~= nil then
					playIn(rootComponent.Instance)
				end
			end
			playMotions()
		end,
		close = function(_self: Screen)
			if destroyed or not shown then
				return
			end
			stopMotions()
			hide()
		end,
		destroy = function(_self: Screen)
			if destroyed then
				return
			end
			destroyed = true
			trove:Destroy()
			intent:DisconnectAll()
			table.clear(ctx.elements)
		end,
		find = function(_self: Screen, id: string): any
			return ctx.elements[id]
		end,
		update = function(_self: Screen, id: string, props: { [string]: any }): boolean
			local obj = ctx.elements[id]
			if obj == nil or type(obj.update) ~= "function" then
				return false
			end
			obj:update(props)
			return true
		end,
		ids = function(_self: Screen): { string }
			local ids: { string } = {}
			for id in pairs(ctx.elements) do
				table.insert(ids, id)
			end
			table.sort(ids, function(a: string, b: string): boolean
				return a < b
			end)
			return ids
		end,
	}

	local startOpen = opts.startOpen
	if startOpen == nil then
		startOpen = spec.kind == "hud"
	end
	if startOpen then
		screen:open()
	end
	return screen
end

return Builder
