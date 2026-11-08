--!strict
-- Cartoon dropdown: a gradient button showing the value and an arrow; activating it opens a list of
-- outlined option buttons under it. Choosing one closes the list and fires Changed / onChanged.
-- With a gamepad the first option is selected when the list opens.
--   local quality = Dropdown.new({ options = { "Low", "Medium", "High" }, value = "High", onChanged = fn })
--
-- The list is a child of the dropdown (ZIndex above its siblings), so a clipping parent such as a
-- ScrollingFrame clips it; leave room below the dropdown or place it outside scrolling areas.

local GuiService = game:GetService("GuiService")

local Base = require("./Base")
local CartoonButton = require("./CartoonButton")
local GameText = require("./GameText")
local Kit = require("./Kit")
local Panel = require("./Panel")
local Signal = require("../../Util/Signal")

export type Props = {
	options: { string }?,
	value: string?,
	onChanged: ((string) -> ())?,
	palette: string?, -- default "blue"
	enabled: boolean?,
	style: string?,
	parent: Instance?,
	layoutOrder: number?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	name: string?,
	visible: boolean?,
	[string]: any,
}

local Dropdown = {}

local ROW = 40

local function closeList(object: any)
	if object.list then
		object.list:destroy()
		object.list = nil
	end
	object.Instance:SetAttribute("UrkOpen", false)
end

local function choose(object: any, value: string)
	local hadFocus = GuiService.SelectedObject ~= nil
	closeList(object)
	if hadFocus then
		GuiService.SelectedObject = object.Instance
	end
	if object.props.value == value then
		return
	end
	object.props.value = value
	if object.valueLabel then
		object.valueLabel.Text = value
	end
	object.Changed:Fire(value)
	if object.props.onChanged then
		task.spawn(object.props.onChanged, value)
	end
end

local function openList(object: any)
	local props = object.props
	local options: { string } = props.options or {}
	local root: TextButton = object.Instance
	local list = Panel.new({
		surface = "inset",
		radius = "md",
		outline = "thick",
		padding = "xs",
		style = props.style,
		anchor = Vector2.zero,
		position = UDim2.new(0, 0, 1, 6),
		size = UDim2.new(1, 0, 0, #options * (ROW + 4) + 12),
		parent = root,
	})
	list.Instance.ZIndex = 20
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list.Content
	local first: GuiObject? = nil
	for index, option in ipairs(options) do
		local selected = option == props.value
		local button = CartoonButton.new({
			kind = if selected then "primary" else "neutral",
			text = option,
			style = props.style,
			layoutOrder = index,
			size = UDim2.new(1, 0, 0, ROW),
			parent = list.Content,
		})
		button.Activated:Connect(function()
			choose(object, option)
		end)
		first = first or button.Instance
	end
	object.list = list
	root:SetAttribute("UrkOpen", true)
	if first and GuiService.SelectedObject == root then
		GuiService.SelectedObject = first
	end
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: TextButton = object.Instance
	closeList(object)
	root.Active = props.enabled ~= false
	local surfaceProps: Panel.SurfaceProps = {
		palette = props.palette or "blue",
		enabled = props.enabled,
		radius = "md",
		outline = "thick",
		gloss = true,
		shadow = true,
	}
	local content = Panel.surface(object, root, surfaceProps).content
	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(Kit.spacing(style, "md"), 0)
	label.Size = UDim2.new(1, -(Kit.spacing(style, "md") + 40), 1, 0)
	local options: GameText.TextOptions = { text = props.value or "", role = "label", align = "left" }
	GameText.decorate(label, style, options, object.parts)
	label.Parent = content
	object.valueLabel = label

	local arrow = Instance.new("ImageLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = Vector2.new(1, 0.5)
	arrow.Position = UDim2.new(1, -8, 0.5, 0)
	arrow.Size = UDim2.fromScale(0.55, 0.55)
	arrow.SizeConstraint = Enum.SizeConstraint.RelativeYY
	arrow.Parent = content
	if not Kit.icon(arrow, "arrow-down") then
		arrow:Destroy()
		local caret = Instance.new("TextLabel")
		caret.Name = "Arrow"
		caret.BackgroundTransparency = 1
		caret.AnchorPoint = Vector2.new(1, 0.5)
		caret.Position = UDim2.new(1, -8, 0.5, 0)
		caret.Size = UDim2.fromScale(0.6, 0.6)
		caret.SizeConstraint = Enum.SizeConstraint.RelativeYY
		local caretOptions: GameText.TextOptions = { text = "v", role = "label" }
		GameText.decorate(caret, style, caretOptions, object.parts)
		caret.Parent = content
	end
end

function Dropdown.new(props: Props)
	local object = Base.new({
		className = "TextButton",
		name = "Dropdown",
		props = props,
		size = UDim2.fromOffset(220, 44),
		build = build,
		interactive = true,
		setup = function(self: any)
			self.Changed = Signal.new()
			self.trove:Add(function()
				closeList(self)
				self.Changed:DisconnectAll()
			end)
		end,
		onPress = function(self: any)
			if self.list then
				closeList(self)
			else
				openList(self)
			end
		end,
	})
	-- Closes the option list if it is open.
	function object.close(self: any)
		closeList(self)
	end
	return object
end

return Dropdown
