--!strict
-- Shared runtime for the screen templates: the root every screen lives in, the responsive window
-- frame (header, close button, tabs, scrolling content), open / close animation through
-- Visuals.UI, intents, keyboard / gamepad focus and cleanup. Each `Screens/<Name>.luau` builds its
-- content with a Shell and stays small.
--
-- Layout numbers come from ScreensLogic (pure, Lune-tested); this file only applies them.
--
-- NOT run in Studio: everything here creates Instances and NEEDS MANUAL REVIEW.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Format = require("../../UI/Core/Format")
local Game = require("../../UI/Game/Game")
local Host = require("../Runtime/Host")
local Kit = require("../../UI/Game/Kit")
local ScreensData = require("./ScreensData")
local ScreensLogic = require("./ScreensLogic")
local Signal = require("../../Util/Signal")
local Style = require("../../UI/Style/Style")
local Trove = require("../../Util/Trove")
local UI = require("../UI/UIAnimations")

export type WindowOptions = {
	title: string?,
	kind: string?, -- ScreensLogic.WINDOW_KINDS, default "window"
	headerPalette: string?,
	tabs: { any }?, -- { { id, text?, icon? } }
	tab: string?,
	closable: boolean?, -- default true
	scroll: boolean?, -- default true
	onTab: ((id: string) -> ())?,
}

export type Window = {
	frame: Frame, -- the object that animates in and out
	content: GuiObject, -- scrolling column for the screen's children
	footer: Frame, -- fixed strip under the content (hidden until setFooter)
	title: any,
	tab: string?,
	body: () -> ScreensLogic.Body,
	rect: () -> ScreensLogic.Window,
	setTitle: (text: string) -> (),
	setTab: (id: string) -> (),
	setFooter: (height: number) -> Frame,
}

export type Shell = {
	def: ScreensData.Screen,
	props: { [string]: any },
	trove: Trove.Trove,
	styleName: string,
	style: Style.StyleDef,
	gui: ScreenGui?,
	root: Frame,
	Intent: Signal.Signal,
	signals: { [string]: Signal.Signal },
	animated: GuiObject, -- what open / close animates (the window frame, or the root)
	backdrop: boolean, -- dim the game behind the screen while open
	env: (self: Shell) -> ScreensLogic.Env,
	fire: (self: Shell, name: string, ...any) -> (),
	own: (self: Shell, object: any) -> any,
	frame: (self: Shell, parent: Instance, name: string) -> Frame,
	text: (self: Shell, parent: Instance, text: string, role: string, extra: { [string]: any }?) -> any,
	button: (self: Shell, parent: Instance, props: { [string]: any }) -> any,
	window: (self: Shell, options: WindowOptions) -> Window,
	onLayout: (self: Shell, callback: (env: ScreensLogic.Env) -> ()) -> (),
	relayout: (self: Shell) -> (),
	focusables: (self: Shell, list: { GuiObject }) -> (),
	isOpen: (self: Shell) -> boolean,
	open: (self: Shell) -> (),
	close: (self: Shell) -> (),
	destroy: (self: Shell) -> (),
	onOpened: (() -> ())?,
	onClosed: (() -> ())?,
}

local ScreenKit = {}

ScreenKit.Game = Game
ScreenKit.UI = UI
ScreenKit.Logic = ScreensLogic

local DISPLAY_ORDER: { [string]: number } = {
	hud = 5,
	window = 20,
	sheet = 20,
	dialog = 40,
	banner = 45,
	overlay = 60,
	fullscreen = 80,
}

-- Kinds that dim the game behind them.
local DIMMED: { [string]: boolean } = { window = true, dialog = true, sheet = true }

local GAMEPAD: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
}

-- "touch", "gamepad" or "mouse": the input in use right now.
function ScreenKit.input(): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "touch"
	elseif GAMEPAD[last] then
		return "gamepad"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "gamepad"
	end
	return "mouse"
end

-- The UrkUI style a screen uses: props.style, else the style of props.theme, else the default.
function ScreenKit.styleName(props: { [string]: any }): string
	if type(props.style) == "string" and table.find(Style.names(), props.style) ~= nil then
		return props.style
	end
	if type(props.theme) == "string" then
		local ok, name = pcall(function(): any
			local Themes = require("../Themes/Themes")
			return Themes.style(props.theme)
		end)
		if ok and type(name) == "string" and table.find(Style.names(), name) ~= nil then
			return name
		end
	end
	return Style.default()
end

-- GameText options for plain text on a surface ("window", "inset", "dark"): the surface's own
-- text colour without an outline, so dark styles stay readable.
function ScreenKit.ink(style: Style.StyleDef, surface: string?, align: string?): { [string]: any }
	return { color = Style.surface(style, surface or "window").text, stroke = false, align = align or "left" }
end

-- Shows an icon name (kit or "pack:name") or an asset id in an image. Returns false when neither resolves.
function ScreenKit.icon(label: ImageLabel | ImageButton, icon: string?, image: string?): boolean
	return Kit.icon(label, icon, image)
end

-- A short price or amount: 1250 -> "1.3K".
function ScreenKit.amount(value: number): string
	return Format.apply("abbrev", value)
end

function ScreenKit.rect(object: GuiObject, rect: ScreensLogic.Rect)
	object.Position = UDim2.fromOffset(rect.x, rect.y)
	object.Size = UDim2.fromOffset(rect.w, rect.h)
end

-- A vertical or horizontal UIListLayout by LayoutOrder.
function ScreenKit.list(parent: Instance, horizontal: boolean, gap: number, align: string?): UIListLayout
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
	layout.VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top
	layout.Parent = parent
	return layout
end

-- A transparent frame with a UIGridLayout; ScreenKit.applyGrid sets its cells from ScreensLogic.
function ScreenKit.grid(parent: Instance, name: string, order: number?): (Frame, UIGridLayout)
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.LayoutOrder = order or 0
	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = holder
	holder.Parent = parent
	return holder, layout
end

function ScreenKit.applyGrid(layout: UIGridLayout, grid: ScreensLogic.Grid)
	layout.CellSize = UDim2.fromOffset(grid.cellW, grid.cellH)
	layout.CellPadding = UDim2.fromOffset(grid.gap, grid.gap)
	layout.FillDirectionMaxCells = grid.columns
end

-- A scrolling column: content taller than the frame scrolls instead of overflowing.
function ScreenKit.scroller(parent: Instance, name: string, gap: number, horizontal: boolean?): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.fromScale(0, 0)
	scroll.AutomaticCanvasSize = if horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.Y
	scroll.ScrollingDirection = if horizontal then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.Selectable = false
	ScreenKit.list(scroll, horizontal == true, gap, "center")
	scroll.Parent = parent
	return scroll
end

export type CardGrid = {
	holder: Frame,
	cards: { [string]: any }, -- id -> component
	set: (items: { any }, make: (item: any, index: number, size: UDim2?) -> any) -> (),
	layout: (width: number, height: number?) -> ScreensLogic.Grid,
	instances: () -> { GuiObject }, -- in item order, for focus and staggered entrances
	reveal: (preset: string?) -> (),
	destroy: () -> (),
}

-- A grid of cards of one of ScreensLogic.CARDS kinds. `set` rebuilds the cards from items (each
-- needs an `id`); `layout` sizes the cells for the width it is given and resizes the cards, which
-- lay themselves out from an offset size.
function ScreenKit.cards(parent: Instance, kind: string, order: number?): CardGrid
	local holder, layout = ScreenKit.grid(parent, "Cards", order)
	local cards: { [string]: any } = {}
	local ids: { string } = {}
	local cell = Vector2.zero
	local grid: CardGrid

	local function clear()
		for _, card in pairs(cards) do
			card:destroy()
		end
		table.clear(cards)
		table.clear(ids)
	end

	grid = {
		holder = holder,
		cards = cards,
		set = function(items: { any }, make: (item: any, index: number, size: UDim2?) -> any)
			clear()
			local size = if cell.X > 0 then UDim2.fromOffset(cell.X, cell.Y) else nil
			for i, item in ipairs(items) do
				local id = tostring(if type(item) == "table" and item.id ~= nil then item.id else i)
				local card = make(item, i, size)
				if card ~= nil then
					cards[id] = card
					table.insert(ids, id)
				end
			end
		end,
		layout = function(width: number, height: number?): ScreensLogic.Grid
			local result = ScreensLogic.cards(kind, width, #ids, height)
			ScreenKit.applyGrid(layout, result)
			if result.cellW ~= cell.X or result.cellH ~= cell.Y then
				cell = Vector2.new(result.cellW, result.cellH)
				for _, card in pairs(cards) do
					card:update({ size = UDim2.fromOffset(cell.X, cell.Y) })
				end
			end
			return result
		end,
		instances = function(): { GuiObject }
			local out: { GuiObject } = {}
			for _, id in ipairs(ids) do
				table.insert(out, cards[id].Instance)
			end
			return out
		end,
		reveal = function(preset: string?)
			UI.stagger(grid.instances(), preset or "CardReveal", { interval = 0.04 })
		end,
		destroy = clear,
	}
	return grid
end

-- Width available to children of a scrolling content column (leaves room for the scroll bar).
function ScreenKit.innerWidth(content: GuiObject, fallback: number): number
	local width = content.AbsoluteSize.X
	return math.max(1, (if width > 0 then width else fallback) - 10)
end

function ScreenKit.new(def: ScreensData.Screen, props: { [string]: any }): Shell
	local trove = Trove.new()
	local styleName = ScreenKit.styleName(props)
	local style = Style.get(styleName)

	-- Root: a ScreenGui under PlayerGui (or the given ScreenGui / folder), or a frame inside a GuiObject.
	local parent: Instance? = props.parent
	if parent == nil then
		local player = Players.LocalPlayer
		assert(player ~= nil, "Screens.create needs props.parent outside a LocalScript")
		parent = player:WaitForChild("PlayerGui")
	end
	local gui: ScreenGui? = nil
	local host: Instance = parent :: Instance
	if not host:IsA("GuiObject") and not host:IsA("ScreenGui") then
		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = "Urk" .. def.id
		screenGui.ResetOnSpawn = false
		screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screenGui.DisplayOrder = props.displayOrder or DISPLAY_ORDER[def.kind] or 20
		-- HUDs avoid Roblox's top bar; other screens only avoid the device's notch and corners.
		screenGui.ScreenInsets = if def.kind == "hud"
			then Enum.ScreenInsets.CoreUISafeInsets
			else Enum.ScreenInsets.DeviceSafeInsets
		screenGui.Enabled = false
		screenGui.Parent = host
		trove:Add(screenGui)
		gui = screenGui
		host = screenGui
	end
	local root = Instance.new("Frame")
	root.Name = "Screen_" .. def.id
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = gui ~= nil
	root.Parent = host
	trove:Add(root)

	local intent = Signal.new()
	local signals: { [string]: Signal.Signal } = {}
	for _, entry in ipairs(def.intents) do
		signals[entry.name] = Signal.new()
	end

	local layouts: { (env: ScreensLogic.Env) -> () } = {}
	local focusList: { GuiObject } = {}
	local opened = false
	local destroyed = false
	local dim: any = nil
	local shell: Shell

	local function env(_self: Shell): ScreensLogic.Env
		local size = root.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			local camera = Workspace.CurrentCamera
			size = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
		end
		-- The ScreenGui's ScreenInsets already keep the root inside the safe area, so insets are
		-- zero unless the caller embeds the screen and passes its own.
		return ScreensLogic.env({ x = size.X, y = size.Y }, props.insets, props.input or ScreenKit.input())
	end

	local function relayout(self: Shell)
		if destroyed then
			return
		end
		local current = env(self)
		for _, callback in ipairs(layouts) do
			callback(current)
		end
	end

	-- Directional links for keyboard and gamepad, from where the objects really are on screen.
	local function applyFocus(select: boolean)
		local nodes = {}
		local byId: { [string]: GuiObject } = {}
		for i, object in ipairs(focusList) do
			if object.Parent ~= nil and object.Visible then
				local id = tostring(i)
				byId[id] = object
				local position, size = object.AbsolutePosition, object.AbsoluteSize
				table.insert(nodes, { id = id, x = position.X, y = position.Y, w = size.X, h = size.Y })
			end
		end
		local focus = ScreensLogic.focus(nodes, true)
		for id, links in pairs(focus.links) do
			local object: any = byId[id]
			if object ~= nil then
				object.NextSelectionUp = if links.up then byId[links.up] else nil
				object.NextSelectionDown = if links.down then byId[links.down] else nil
				object.NextSelectionLeft = if links.left then byId[links.left] else nil
				object.NextSelectionRight = if links.right then byId[links.right] else nil
			end
		end
		if select and focus.first ~= nil and ScreenKit.input() == "gamepad" then
			GuiService.SelectedObject = byId[focus.first]
		end
	end

	local function setShown(shown: boolean)
		if gui ~= nil then
			gui.Enabled = shown
		else
			root.Visible = shown
		end
	end

	shell = {
		def = def,
		props = props,
		trove = trove,
		styleName = styleName,
		style = style,
		gui = gui,
		root = root,
		Intent = intent,
		signals = signals,
		animated = root,
		backdrop = DIMMED[def.kind] == true,
		env = env,
		relayout = relayout,

		fire = function(_self: Shell, name: string, ...: any)
			local signal = signals[name]
			if signal ~= nil then
				signal:Fire(...)
			end
			intent:Fire(name, ...)
		end,

		own = function(_self: Shell, object: any): any
			trove:Add(function()
				if type(object.destroy) == "function" then
					object:destroy()
				end
			end)
			return object
		end,

		frame = function(_self: Shell, into: Instance, name: string): Frame
			local frame = Instance.new("Frame")
			frame.Name = name
			frame.BackgroundTransparency = 1
			frame.BorderSizePixel = 0
			frame.Size = UDim2.fromScale(1, 1)
			frame.Parent = into
			return frame
		end,

		text = function(self: Shell, into: Instance, value: string, role: string, extra: { [string]: any }?): any
			local options: { [string]: any } = {
				style = styleName,
				parent = into,
				text = value,
				role = role,
				size = UDim2.new(1, 0, 0, math.floor(Style.textSize(style, role) * 1.4 + 0.5)),
			}
			for key, item in pairs(extra or {}) do
				options[key] = item
			end
			return self:own(Game.GameText.new(options))
		end,

		button = function(self: Shell, into: Instance, options: { [string]: any }): any
			local merged: { [string]: any } = { style = styleName, parent = into }
			for key, item in pairs(options) do
				merged[key] = item
			end
			local component = if merged.premium then Game.PremiumButton else Game.CartoonButton
			merged.premium = nil
			return self:own(component.new(merged))
		end,

		onLayout = function(_self: Shell, callback: (env: ScreensLogic.Env) -> ())
			table.insert(layouts, callback)
		end,

		focusables = function(_self: Shell, objects: { GuiObject })
			focusList = objects
			if opened then
				applyFocus(false)
			end
		end,

		isOpen = function(_self: Shell): boolean
			return opened
		end,

		open = function(self: Shell)
			if destroyed or opened then
				return
			end
			opened = true
			setShown(true)
			relayout(self)
			if self.backdrop and dim == nil then
				dim = UI.backdrop(root, { zIndex = 0, modal = true })
			end
			local reduced = Host.settings().reducedMotion
			UI.show(self.animated, ScreensLogic.animation(def.kind, true, reduced))
			applyFocus(true)
			if self.onOpened then
				self.onOpened()
			end
		end,

		close = function(self: Shell)
			if destroyed or not opened then
				return
			end
			opened = false
			if dim ~= nil then
				dim.stop()
				dim = nil
			end
			local reduced = Host.settings().reducedMotion
			UI.hide(self.animated, ScreensLogic.animation(def.kind, false, reduced), {
				onDone = function()
					if destroyed or opened then
						return
					end
					-- UI.hide hid the animated object; hide the whole screen and reset it for the next open.
					setShown(false)
					if gui ~= nil or self.animated ~= root then
						self.animated.Visible = true
					end
					if self.onClosed then
						self.onClosed()
					end
					self:fire("Closed")
				end,
			})
		end,

		destroy = function(self: Shell)
			if destroyed then
				return
			end
			destroyed = true
			opened = false
			if dim ~= nil then
				dim.finish()
				dim = nil
			end
			UI.stop(self.animated, false)
			trove:Destroy()
			intent:DisconnectAll()
			for _, signal in pairs(signals) do
				signal:DisconnectAll()
			end
			table.clear(layouts)
			table.clear(focusList)
		end,

		window = nil :: any,
	}

	-- Follow the viewport: one relayout a moment after the size settles.
	local pending: (() -> ())? = nil
	trove:Add(root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if pending then
			pending()
		end
		pending = Host.clock:after(0.05, function()
			pending = nil
			relayout(shell)
			if opened then
				applyFocus(false)
			end
		end)
	end))
	trove:Add(function()
		if pending then
			pending()
		end
	end)

	-- Gamepad B closes screens that can be closed.
	if signals.Closed ~= nil and def.kind ~= "hud" then
		trove:Add(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if opened and not processed and input.KeyCode == Enum.KeyCode.ButtonB then
				shell:close()
			end
		end))
	end

	shell.window = function(self: Shell, options: WindowOptions): Window
		local kind = options.kind or "window"
		local tabs = options.tabs or {}
		local frame = Instance.new("Frame")
		frame.Name = "Window"
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Parent = root
		self.animated = frame

		self:own(Game.Panel.new({
			style = styleName,
			parent = frame,
			name = "Surface",
			surface = "window",
			shadow = true,
			size = UDim2.fromScale(1, 1),
		}))
		local header = self:own(Game.Panel.new({
			style = styleName,
			parent = frame,
			name = "Header",
			palette = options.headerPalette or "blue",
			gloss = true,
			shadow = false,
		}))
		header.Instance.ZIndex = 2
		local title = self:text(header.Content or header.Instance, options.title or def.name, "title", {
			size = UDim2.new(1, -56, 1, 0),
			position = UDim2.fromOffset(8, 0),
			align = "left",
		})
		local closeButton: any = nil
		if options.closable ~= false then
			closeButton = self:button(frame, {
				name = "Close",
				kind = "close",
				anchor = Vector2.new(1, 0),
				size = UDim2.fromOffset(ScreensLogic.MIN_TOUCH, ScreensLogic.MIN_TOUCH),
			})
			closeButton.Instance.ZIndex = 3
			trove:Add(closeButton.Activated:Connect(function()
				self:close()
			end))
		end

		local content: GuiObject
		if options.scroll == false then
			content = self:frame(frame, "Content")
			ScreenKit.list(content, false, 8, "center")
		else
			content = ScreenKit.scroller(frame, "Content", 8)
		end
		content.ZIndex = 2
		local footer = self:frame(frame, "Footer")
		footer.ZIndex = 2
		footer.Visible = false
		local footerHeight = 0

		local navHolder: Frame? = nil
		local tabBar: any = nil
		local tabButtons: { [string]: any } = {}
		local current: string? = options.tab or (if tabs[1] then tabs[1].id else nil)
		local lastNavigation: string? = nil
		local rect = ScreensLogic.window(self:env(), kind)
		local body = ScreensLogic.body(self:env(), rect, #tabs)

		local window: Window

		local function choose(id: string, silent: boolean?)
			if current == id then
				return
			end
			current = id
			window.tab = id
			for tabId, button in pairs(tabButtons) do
				button:update({ kind = if tabId == id then "primary" else "neutral" })
			end
			if not silent and options.onTab then
				options.onTab(id)
			end
		end

		-- Tabs are a TabBar (top / bottom) or a column of buttons (sidebar); rebuilt only when the
		-- placement changes, for example when a phone rotates.
		local function buildNav(navigation: string, tabSize: ScreensLogic.Size)
			if navHolder ~= nil then
				if tabBar ~= nil then
					tabBar:destroy()
					tabBar = nil
				end
				for _, button in pairs(tabButtons) do
					button:destroy()
				end
				table.clear(tabButtons)
				navHolder:Destroy()
				navHolder = nil
			end
			if navigation == "none" then
				return
			end
			local holder = self:frame(frame, "Navigation")
			holder.ZIndex = 2
			navHolder = holder
			if navigation == "sidebar" then
				local column = ScreenKit.scroller(holder, "Tabs", 6)
				for i, tab in ipairs(tabs) do
					local button = Game.CartoonButton.new({
						style = styleName,
						parent = column,
						layoutOrder = i,
						name = tab.id,
						kind = if tab.id == current then "primary" else "neutral",
						text = if tabSize.x >= 120 then tab.text else nil,
						icon = tab.icon,
						size = UDim2.new(1, -8, 0, tabSize.y),
					})
					tabButtons[tab.id] = button
					button.Activated:Connect(function()
						choose(tab.id)
					end)
				end
			else
				tabBar = Game.TabBar.new({
					style = styleName,
					parent = holder,
					tabs = tabs,
					value = current,
					size = UDim2.fromScale(1, 1),
				})
				tabBar.Changed:Connect(function(id: string)
					choose(id)
				end)
			end
		end
		trove:Add(function()
			if tabBar ~= nil then
				tabBar:destroy()
			end
			for _, button in pairs(tabButtons) do
				button:destroy()
			end
		end)

		local function apply(current_: ScreensLogic.Env)
			rect = ScreensLogic.window(current_, kind)
			body = ScreensLogic.body(current_, rect, #tabs)
			frame.Position = UDim2.fromOffset(rect.x, rect.y)
			frame.Size = UDim2.fromOffset(rect.w, rect.h)
			header.Instance.Position = UDim2.fromOffset(0, 0)
			header.Instance.Size = UDim2.new(1, 0, 0, rect.header)
			if closeButton ~= nil then
				local inset = math.max(2, math.floor((rect.header - ScreensLogic.MIN_TOUCH) / 2))
				closeButton.Instance.Position = UDim2.new(1, -inset, 0, inset)
			end
			if body.navigation ~= lastNavigation then
				lastNavigation = body.navigation
				buildNav(body.navigation, body.tab)
			end
			if navHolder ~= nil and body.nav ~= nil then
				ScreenKit.rect(navHolder, body.nav)
			end
			local area = table.clone(body.content)
			if footerHeight > 0 then
				area.h = math.max(1, area.h - footerHeight - rect.padding)
				footer.Position = UDim2.fromOffset(area.x, area.y + area.h + rect.padding)
				footer.Size = UDim2.fromOffset(area.w, footerHeight)
			end
			ScreenKit.rect(content, area)
		end
		table.insert(layouts, 1, apply)

		window = {
			frame = frame,
			content = content,
			footer = footer,
			title = title,
			tab = current,
			body = function(): ScreensLogic.Body
				return body
			end,
			rect = function(): ScreensLogic.Window
				return rect
			end,
			setTitle = function(text: string)
				title:update({ text = text })
			end,
			setTab = function(id: string)
				if tabBar ~= nil then
					tabBar:select(id, true)
				end
				choose(id, true)
			end,
			setFooter = function(height: number): Frame
				footerHeight = math.max(ScreensLogic.MIN_TOUCH, height)
				footer.Visible = true
				apply(self:env())
				return footer
			end,
		}
		apply(self:env())
		return window
	end

	return shell
end

return ScreenKit
