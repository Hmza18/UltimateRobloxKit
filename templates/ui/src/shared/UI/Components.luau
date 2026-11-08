--!strict
-- Accessible UI building blocks: Label, Button and Panel.
--   * Text never goes below Theme.MinTextSize.
--   * Text colour is checked against its background. If it falls under Theme.MinContrast (WCAG AA),
--     the component switches to whichever theme text colour reads better.
--   * Buttons are at least Theme.MinTouchTarget pixels on each side and work with mouse, touch and gamepad.

local ColorContrast = require("../Logic/ColorContrast")
local Theme = require("./Theme")
local TweenUtil = require("./Tween")

export type Variant = "Primary" | "Secondary" | "Danger" | "Ghost"

export type LabelProps = {
	Text: string,
	TextSize: number?,
	TextColor3: Color3?,
	Font: Enum.Font?,
	Alignment: Enum.TextXAlignment?,
	Background: Color3?, -- colour behind the text, for the contrast check (default Theme.Colors.Surface)
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Parent: Instance?,
}

export type ButtonProps = {
	Text: string,
	Variant: Variant?, -- default "Primary"
	OnActivated: (() -> ())?,
	TextSize: number?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Parent: Instance?,
}

export type PanelProps = {
	Color: Color3?,
	Transparency: number?,
	Direction: ("Vertical" | "Horizontal")?, -- adds a UIListLayout when set
	Gap: number?, -- pixels between children when Direction is set (default 8)
	AutomaticSize: Enum.AutomaticSize?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Parent: Instance?,
}

local Components = {}

local function toRgb(color: Color3): ColorContrast.RGB
	return { r = color.R, g = color.G, b = color.B }
end

local function applyLayout(object: GuiObject, position: UDim2?, anchorPoint: Vector2?, layoutOrder: number?)
	if position then
		object.Position = position
	end
	if anchorPoint then
		object.AnchorPoint = anchorPoint
	end
	if layoutOrder then
		object.LayoutOrder = layoutOrder
	end
end

local function addCorner(object: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Radius
	corner.Parent = object
end

local function addStroke(object: GuiObject, transparency: number)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.Stroke
	stroke.Thickness = Theme.StrokeThickness
	stroke.Transparency = transparency
	stroke.Parent = object
end

-- `requested` (or the body size), but never below Theme.MinTextSize.
function Components.textSize(requested: number?): number
	return math.max(requested or Theme.TextSize.Body, Theme.MinTextSize)
end

-- `preferred` if it is readable on `background`, otherwise the theme text colour that reads best there.
function Components.readableTextColor(preferred: Color3, background: Color3): Color3
	local backgroundRgb = toRgb(background)
	if ColorContrast.ratio(toRgb(preferred), backgroundRgb) >= Theme.MinContrast then
		return preferred
	end
	local light, dark = Theme.Colors.Text, Theme.Colors.TextDark
	local lightRatio = ColorContrast.ratio(toRgb(light), backgroundRgb)
	local darkRatio = ColorContrast.ratio(toRgb(dark), backgroundRgb)
	return if lightRatio >= darkRatio then light else dark
end

local function variantColors(variant: Variant): (Color3, Color3)
	local colors = Theme.Colors
	if variant == "Secondary" then
		return colors.Secondary, colors.Text
	elseif variant == "Danger" then
		return colors.Danger, colors.Text
	elseif variant == "Ghost" then
		return colors.Surface, colors.Text
	end
	return colors.Primary, colors.TextDark
end

function Components.Label(props: LabelProps): TextLabel
	local textSize = Components.textSize(props.TextSize)
	local background = props.Background or Theme.Colors.Surface
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = props.Text
	label.Font = props.Font or Theme.Fonts.Body
	label.TextSize = textSize
	label.TextColor3 = Components.readableTextColor(props.TextColor3 or Theme.Colors.Text, background)
	label.TextWrapped = true
	label.TextXAlignment = props.Alignment or Enum.TextXAlignment.Left
	label.Size = props.Size or UDim2.new(1, 0, 0, textSize + 8)
	applyLayout(label, props.Position, props.AnchorPoint, props.LayoutOrder)
	label.Parent = props.Parent
	return label
end

function Components.Button(props: ButtonProps): TextButton
	local variant: Variant = props.Variant or "Primary"
	local background, preferredText = variantColors(variant)
	local onActivated = props.OnActivated

	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BackgroundColor3 = background
	button.BackgroundTransparency = if variant == "Ghost" then 0.6 else 0
	button.Font = Theme.Fonts.Button
	button.Text = props.Text
	button.TextSize = Components.textSize(props.TextSize or Theme.TextSize.Button)
	button.TextColor3 = Components.readableTextColor(preferredText, background)
	button.Size = props.Size or UDim2.fromOffset(180, 52)
	applyLayout(button, props.Position, props.AnchorPoint, props.LayoutOrder)
	addCorner(button)
	addStroke(button, 0.4)

	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(Theme.MinTouchTarget, Theme.MinTouchTarget)
	sizeLimit.Parent = button

	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		TweenUtil.play(scale, { Scale = 1.04 }, Theme.Motion.Fast)
	end)
	button.MouseLeave:Connect(function()
		TweenUtil.play(scale, { Scale = 1 }, Theme.Motion.Fast)
	end)
	-- Activated fires for mouse, touch and gamepad, unlike MouseButton1Click.
	button.Activated:Connect(function()
		TweenUtil.pop(scale)
		if onActivated then
			onActivated()
		end
	end)

	button.Parent = props.Parent
	return button
end

function Components.Panel(props: PanelProps): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = props.Color or Theme.Colors.Surface
	frame.BackgroundTransparency = props.Transparency or 0.05
	frame.Size = props.Size or UDim2.fromOffset(300, 200)
	local automaticSize = props.AutomaticSize
	if automaticSize then
		frame.AutomaticSize = automaticSize
	end
	applyLayout(frame, props.Position, props.AnchorPoint, props.LayoutOrder)
	addCorner(frame)
	addStroke(frame, 0.6)

	local padding = Instance.new("UIPadding")
	local inset = UDim.new(0, Theme.Padding)
	padding.PaddingTop = inset
	padding.PaddingBottom = inset
	padding.PaddingLeft = inset
	padding.PaddingRight = inset
	padding.Parent = frame

	if props.Direction then
		local layout = Instance.new("UIListLayout")
		local horizontal = props.Direction == "Horizontal"
		layout.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		layout.Padding = UDim.new(0, props.Gap or 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = frame
	end

	frame.Parent = props.Parent
	return frame
end

return Components
