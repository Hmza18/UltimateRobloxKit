--!strict
-- Shop-style window: white patterned body with a thick outline, a red header bar with a chunky
-- outlined title, a red rounded X close button and a scrolling content area.
--   local shop = GameWindow.new({ title = "SHOP", sizeClass = "lg", parent = playerGui })
--   ProductCard.new({ ..., parent = shop.Content })
--   shop:open()               -- animated ("open" preset); shop:close() plays "close"
--   shop.Closed:Connect(fn)
--
-- The window starts hidden unless `visible = true`. A PlayerGui parent gets a ScreenGui of its own.
-- The close button closes the window and runs `action` when set. Children of window.Content are
-- laid out top to bottom (UIListLayout by LayoutOrder) and survive :update().

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Base = require("./Base")
local CartoonButton = require("./CartoonButton")
local GameText = require("./GameText")
local Kit = require("./Kit")
local Motion = require("../Runtime/Motion")
local Panel = require("./Panel")
local Signal = require("../../Util/Signal")
local Style = require("../Style/Style")

export type Props = {
	title: string?,
	headerPalette: string?, -- default "red"
	width: number?, -- pixels at 1x, overrides sizeClass
	height: number?,
	closable: boolean?, -- default true
	scroll: boolean?, -- default true
	sizeClass: string?, -- "sm" | "md" (default) | "lg" | "full"
	style: string?,
	parent: Instance?,
	layoutOrder: number?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	name: string?,
	visible: boolean?,
	action: string?,
	[string]: any,
}

local GameWindow = {}

local HEADER = 64
local CLOSE = 54

local SIZES: { [string]: Vector2 } = {
	sm = Vector2.new(420, 320),
	md = Vector2.new(560, 420),
	lg = Vector2.new(760, 520),
}

-- The window size for props: explicit width / height, else the size class ("full" fills 94% x 90%).
function GameWindow.sizeFor(props: { [string]: any }): UDim2
	if props.sizeClass == "full" and props.width == nil and props.height == nil then
		return UDim2.fromScale(0.94, 0.9)
	end
	local base = SIZES[props.sizeClass or "md"] or SIZES.md
	return UDim2.fromOffset(props.width or base.X, props.height or base.Y)
end

local function header(object: any, root: Frame)
	local props = object.props
	local style = object.style
	local bar = Instance.new("Frame")
	bar.Name = "Header"
	bar.BackgroundTransparency = 1
	bar.Size = UDim2.new(1, 0, 0, HEADER)
	bar.ZIndex = 4
	local headerProps: Panel.SurfaceProps = {
		palette = props.headerPalette or "red",
		radius = "xl",
		outline = "heavy",
		gloss = true,
		pattern = false,
		shadow = false,
	}
	local parts = Panel.surface(object, bar, headerProps)
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.new(0, Kit.spacing(style, "xl"), 0.5, 0)
	title.Size = UDim2.new(1, -(CLOSE + Kit.spacing(style, "xl") * 2), 0.82, 0)
	local options: GameText.TextOptions = { text = props.title or "", role = "display", align = "left" }
	GameText.decorate(title, style, options, object.parts)
	title.Parent = parts.content
	bar.Parent = root
	object.parts:Add(bar)
end

local function closeButton(object: any, root: Frame)
	local button = CartoonButton.new({
		kind = "close",
		text = "X",
		style = object.props.style,
		size = UDim2.fromOffset(CLOSE, CLOSE),
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, 8, 0, -8),
		parent = root,
	})
	button.Instance.ZIndex = 6
	button.Activated:Connect(function()
		object:close()
		Kit.runAction(object.props.action, button.Instance)
	end)
	object.parts:Add(button)
	object.CloseButton = button
end

local function content(object: any, root: Frame)
	local props = object.props
	local style = object.style
	local top = HEADER + Kit.spacing(style, "xs")
	local area: GuiObject
	if props.scroll ~= false then
		local scrolling = Instance.new("ScrollingFrame")
		scrolling.BorderSizePixel = 0
		scrolling.ScrollBarThickness = 8
		scrolling.ScrollBarImageColor3 = Color3.fromHex(Style.outlineColor(style))
		scrolling.ScrollingDirection = Enum.ScrollingDirection.Y
		scrolling.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scrolling.CanvasSize = UDim2.fromOffset(0, 0)
		scrolling.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
		scrolling.Selectable = false
		area = scrolling
	else
		area = Instance.new("Frame")
	end
	area.Name = "Content"
	area.BackgroundTransparency = 1
	area.Position = UDim2.fromOffset(0, top)
	area.Size = UDim2.new(1, 0, 1, -top)
	area.ZIndex = 3
	local padding = Kit.padding(Kit.spacing(style, "lg"))
	padding.PaddingRight = UDim.new(0, Kit.spacing(style, "lg") + 6)
	padding.Parent = area
	local layout = Kit.internal(Instance.new("UIListLayout"))
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Kit.spacing(style, "md"))
	layout.Parent = area
	area.Parent = root
	object.parts:Add(area)
	object.Content = area
end

local function build(object: any)
	local props = object.props
	local root: Frame = object.Instance
	if typeof(props.size) ~= "UDim2" then
		root.Size = GameWindow.sizeFor(props)
	end
	if props.position == nil then
		root.Position = UDim2.fromScale(0.5, 0.5)
	end
	if props.anchor == nil then
		root.AnchorPoint = Vector2.new(0.5, 0.5)
	end
	root.Visible = object.opened == true
	local windowProps: Panel.SurfaceProps = {
		surface = "window",
		radius = "xl",
		outline = "heavy",
		gloss = false,
		pattern = true,
		shadow = true,
	}
	Panel.surface(object, root, windowProps)
	header(object, root)
	if props.closable ~= false then
		closeButton(object, root)
	end
	content(object, root)
end

local function gamepadActive(): boolean
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.Gamepad1 or GuiService:IsTenFootInterface()
end

local function firstSelectable(root: Instance): GuiObject?
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiButton") and descendant.Selectable and descendant.Visible then
			return descendant
		end
	end
	return nil
end

function GameWindow.new(props: Props)
	local copy = table.clone(props)
	local screen: ScreenGui? = nil
	if copy.parent then
		local parent, created = Kit.ensureScreen(copy.parent, "GameWindow_" .. (copy.name or "Window"), 10)
		copy.parent = parent
		screen = created
	end
	local startOpen = copy.visible == true
	copy.visible = nil
	local object = Base.new({
		className = "Frame",
		name = "GameWindow",
		props = copy,
		build = build,
		setup = function(self: any)
			self.Closed = Signal.new()
			self.Opened = Signal.new()
			self.trove:Add(function()
				Motion.stop(self.Instance)
				self.Closed:DisconnectAll()
				self.Opened:DisconnectAll()
			end)
			if screen then
				self.trove:Add(screen)
			end
		end,
	})
	object.opened = false

	function object.isOpen(self: any): boolean
		return self.opened == true
	end

	function object.open(self: any)
		if self.destroyed or self.opened then
			return
		end
		self.opened = true
		local root = self.Instance
		root.Visible = true
		Motion.play(root, "open")
		if gamepadActive() then
			local target = firstSelectable(self.Content or root) or (self.CloseButton and self.CloseButton.Instance)
			if target then
				GuiService.SelectedObject = target
			end
		end
		self.Opened:Fire()
	end

	function object.close(self: any)
		if self.destroyed or not self.opened then
			return
		end
		self.opened = false
		local root = self.Instance
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(root) then
			GuiService.SelectedObject = nil
		end
		local function hide()
			if not self.opened then
				root.Visible = false
				Motion.scaleOf(root).Scale = 1
			end
		end
		Motion.play(root, "close", { onDone = hide })
		self.Closed:Fire()
	end

	if startOpen then
		object.opened = true
		object.Instance.Visible = true
	end
	return object
end

return GameWindow
