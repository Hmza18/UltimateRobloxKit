--!strict
-- Chunky cartoon text with a UIStroke outline.
--   GameText.new({ text = "SHOP", size = "display", parent = header })
--
-- `size` is the text role ("display", "title", "heading", "label", "caption", "price"); a UDim2
-- `size` sets the frame size instead, with the role from `role` (default "label"). Text fits the
-- box: Core/TextFit picks the largest size between minSize and maxSize (default: the role's size)
-- from approximate metrics, then TextScaled + UITextSizeConstraint do the exact fit. When even the
-- minimum does not fit, the label uses the minimum with TextTruncate. Never below the style's
-- minimum text size (or UrkUI's accessibility minimum when it is running).

local Base = require("./Base")
local Kit = require("./Kit")
local Style = require("../Style/Style")
local TextFit = require("../Core/TextFit")

export type Props = {
	text: string?,
	size: (string | UDim2)?,
	role: string?,
	color: string?, -- hex, default white
	stroke: boolean?, -- default true
	align: string?, -- "left" | "center" (default) | "right"
	minSize: number?,
	maxSize: number?,
	wrap: boolean?,
	style: string?,
	parent: Instance?,
	layoutOrder: number?,
	position: UDim2?,
	anchor: Vector2?,
	name: string?,
	visible: boolean?,
	[string]: any,
}

export type TextOptions = {
	text: string?,
	role: string?,
	color: string?,
	stroke: boolean?,
	align: string?,
	minSize: number?,
	maxSize: number?,
	wrap: boolean?,
}

local GameText = {}

local ALIGN: { [string]: Enum.TextXAlignment } = {
	left = Enum.TextXAlignment.Left,
	center = Enum.TextXAlignment.Center,
	right = Enum.TextXAlignment.Right,
}

local SMALL_ROLES: { [string]: boolean } = { caption = true, label = true }

-- The text role from props: a string `size`, else `role`, else "label".
function GameText.role(props: { [string]: any }): string
	if type(props.size) == "string" then
		return props.size
	end
	return props.role or "label"
end

-- Styles an existing TextLabel / TextButton / TextBox as game text and keeps it fitted.
-- Instances and connections it creates go into `trove`.
function GameText.decorate(label: any, style: Style.StyleDef, options: TextOptions, trove: any)
	local role = options.role or "label"
	local roleSize = Style.textSize(style, role)
	local text = options.text or ""
	label.Text = text
	label.FontFace = Kit.font(style, role)
	label.TextColor3 = Color3.fromHex(options.color or "#FFFFFF")
	label.TextXAlignment = ALIGN[options.align or "center"] or Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = options.wrap == true
	label.RichText = false

	local strokeWidth = 0
	if options.stroke ~= false then
		local textStroke = style.textStroke or {}
		local stroke = Instance.new("UIStroke")
		stroke.Name = "TextStroke"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Color = Color3.fromHex(textStroke.color or Style.outlineColor(style))
		strokeWidth = if SMALL_ROLES[role] then textStroke.smallThickness or 2 else textStroke.thickness or 3
		stroke.Thickness = strokeWidth
		stroke.Parent = label
		trove:Add(stroke)
	end

	local floor = Kit.minTextSize(style)
	local low, high = TextFit.bounds(options.minSize, options.maxSize or roleSize, floor)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = math.min(low, 100)
	constraint.MaxTextSize = math.min(high, 100)
	constraint.Parent = label
	trove:Add(constraint)
	label.TextScaled = true
	label.TextSize = high

	local lastWidth, lastHeight = -1, -1
	local function fit()
		local factor = Kit.scaleFactor(label)
		local width = math.floor(label.AbsoluteSize.X / factor + 0.5)
		local height = math.floor(label.AbsoluteSize.Y / factor + 0.5)
		if (width == lastWidth and height == lastHeight) or width <= 0 or height <= 0 then
			return
		end
		lastWidth, lastHeight = width, height
		local result = TextFit.fit({
			width = width,
			height = height,
			text = text,
			min = low,
			max = high,
			floor = floor,
			wrap = options.wrap,
			padding = strokeWidth,
		})
		if result.truncate then
			label.TextScaled = false
			label.TextSize = result.size
			label.TextTruncate = Enum.TextTruncate.AtEnd
		else
			label.TextTruncate = Enum.TextTruncate.None
			constraint.MaxTextSize = math.min(result.size, 100)
			label.TextScaled = true
		end
	end
	trove:Connect(label:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()
end

local function build(object: any)
	local props = object.props
	local role = GameText.role(props)
	local root = object.Instance
	if typeof(props.size) ~= "UDim2" then
		root.Size = UDim2.new(1, 0, 0, math.ceil(Style.textSize(object.style, role) * 1.3))
	end
	local options: TextOptions = {
		text = props.text,
		role = role,
		color = props.color,
		stroke = props.stroke,
		align = props.align,
		minSize = props.minSize,
		maxSize = props.maxSize,
		wrap = props.wrap,
	}
	GameText.decorate(root, object.style, options, object.parts)
end

function GameText.new(props: Props)
	return Base.new({ className = "TextLabel", name = "GameText", props = props, build = build })
end

return GameText
