--!strict
-- Window / panel component: a themed frame with a title bar and close button, registered with the
-- panel router. Window.new builds it now; Window.define builds it the first time it is opened.
--   local shop = Window.new({ id = "Shop", title = "Shop", size = Vector2.new(520, 380) })
--   shop.Content -- put your content here; UrkUI.open("Shop") shows it

local Context = require("../Runtime/Context")
local Create = require("../Runtime/Create")

export type Props = {
	id: string,
	title: string?,
	titleKey: string?, -- localisation key for the title
	size: Vector2?,
	closable: boolean?, -- default true
	modal: boolean?,
	dismissible: boolean?,
	group: string?,
	transition: string?,
	parent: Instance?, -- defaults to a ScreenGui of its own in PlayerGui
	build: ((content: Frame) -> ())?, -- fills the content area
}

local Window = {}

local TITLE_HEIGHT = 44

local function construct(props: Props)
	local context = Context.get()
	local theme = context.theme
	local size = props.size or Vector2.new(480, 360)
	local parent = props.parent
	local ownGui: ScreenGui? = nil
	if parent == nil then
		local layer = if props.modal then theme:layer("modal") else theme:layer("panel")
		local gui = Create.screen("UrkWindow_" .. props.id, layer, context.playerGui)
		ownGui = gui
		parent = gui
	end
	local frame = Create.new("Frame", {
		Name = props.id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BorderSizePixel = 0,
		Visible = false,
		Tags = { "UrkTheme" },
		Attributes = { Role = "surface", StrokeRole = "border", Radius = "lg" },
	})
	Create.stroke(theme:color("border"), 1).Parent = frame
	local titleBar = Create.new("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, TITLE_HEIGHT),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local titleAttributes: { [string]: any } = { TextRole = "text", TextSize = "title" }
	local titleTags = { "UrkTheme" }
	if props.titleKey then
		titleAttributes.Key = props.titleKey
		table.insert(titleTags, "UrkLocalize")
	end
	Create.new("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -72, 1, 0),
		Text = props.title or props.id,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tags = titleTags,
		Attributes = titleAttributes,
		Parent = titleBar,
	})
	if props.closable ~= false then
		Create.new("TextButton", {
			Name = "Close",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(32, 32),
			Text = "X",
			Tags = { "UrkButton", "UrkTheme" },
			Attributes = { Variant = "ghost", Radius = "pill", TextSize = "label", Action = "ClosePanel:" .. props.id },
			Parent = titleBar,
		})
	end
	local content = Create.new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(0, TITLE_HEIGHT),
		Size = UDim2.new(1, 0, 1, -TITLE_HEIGHT),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	Create.padding(12, 16).Parent = content
	if props.build then
		props.build(content)
	end
	frame.Parent = parent
	if ownGui then
		frame.Destroying:Connect(function()
			if ownGui and ownGui.Parent then
				ownGui:Destroy()
			end
		end)
	end
	return frame, content
end

local function definition(props: Props): any
	return { group = props.group, modal = props.modal, dismissible = props.dismissible }
end

-- Builds and registers the window now. Returns a handle with Instance, Content, open, close, Destroy.
function Window.new(props: Props)
	local context = Context.get()
	local frame, content = construct(props)
	local options = { transition = props.transition }
	local unregister = context.panels:registerInstance(props.id, frame, definition(props), options)
	frame.Destroying:Connect(unregister)

	local handle = {}
	handle.Instance = frame
	handle.Content = content

	function handle.open(_self: any)
		context.panels:open(props.id)
	end

	function handle.close(_self: any)
		context.panels:close(props.id)
	end

	function handle.isOpen(_self: any): boolean
		return context.panels:isOpen(props.id)
	end

	function handle.Destroy(_self: any)
		frame:Destroy()
	end

	return handle
end

-- Registers the window lazily: nothing is created until UrkUI.open(props.id) is called.
function Window.define(props: Props)
	local context = Context.get()
	local function builder(): Instance
		local frame = construct(props)
		return frame
	end
	context.panels:define(props.id, builder, definition(props), { transition = props.transition })
end

return Window
