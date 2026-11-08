--!strict
-- Section heading with a thick rounded divider line, like the separators between shop groups.
--   Section.new({ title = "GAMEPASSES", parent = window.Content, layoutOrder = 2 })
--   Section.new({ divider = true, parent = window.Content })            -- divider only

local Base = require("./Base")
local GameText = require("./GameText")
local Kit = require("./Kit")
local Style = require("../Style/Style")

export type Props = {
	title: string?,
	divider: boolean?, -- default true
	align: string?, -- title alignment, default "left"
	color: string?, -- title colour (hex), default white
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

local Section = {}

local LINE = 5

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	local titleHeight = if props.title then math.ceil(Style.textSize(style, "heading") * 1.4) else 0
	local hasDivider = props.divider ~= false
	if typeof(props.size) ~= "UDim2" then
		local gap = if props.title and hasDivider then Kit.spacing(style, "xs") else 0
		root.Size = UDim2.new(1, 0, 0, titleHeight + gap + (if hasDivider then LINE else 0))
	end
	if props.title then
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, 0, 0, titleHeight)
		local options: GameText.TextOptions = {
			text = props.title,
			role = "heading",
			align = props.align or "left",
			color = props.color,
		}
		GameText.decorate(title, style, options, object.parts)
		title.Parent = root
		object.parts:Add(title)
	end
	if hasDivider then
		local line = Instance.new("Frame")
		line.Name = "Divider"
		line.BorderSizePixel = 0
		line.AnchorPoint = Vector2.new(0.5, 1)
		line.Position = UDim2.fromScale(0.5, 1)
		line.Size = UDim2.new(1, 0, 0, LINE)
		line.BackgroundColor3 = Color3.fromHex(Style.outlineColor(style))
		line.BackgroundTransparency = 0.15
		Kit.corner(LINE).Parent = line
		line.Parent = root
		object.parts:Add(line)
	end
end

function Section.new(props: Props)
	return Base.new({ className = "Frame", name = "Section", props = props, build = build })
end

return Section
