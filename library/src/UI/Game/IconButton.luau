--!strict
-- Square or round HUD rail button: big icon, optional outlined caption under it, optional badge.
--   IconButton.new({ icon = "cart-color", label = "Shop", palette = "orange",
--       badge = { kind = "attention" }, action = "TogglePanel:Shop", parent = hud:rail("left") })

local Badge = require("./Badge")
local Base = require("./Base")
local GameText = require("./GameText")
local Kit = require("./Kit")
local Panel = require("./Panel")

export type BadgeSpec = { kind: string, text: string? }

export type Props = {
	icon: string?,
	image: string?, -- asset id, used instead of icon
	palette: string?,
	label: string?,
	badge: BadgeSpec?,
	shape: string?, -- "square" (default) | "circle"
	enabled: boolean?,
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

local IconButton = {}

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: TextButton = object.Instance
	local side = (style.sizes and style.sizes.hudButton and style.sizes.hudButton.size) or 64
	if typeof(props.size) ~= "UDim2" then
		root.Size = UDim2.fromOffset(side, side)
	end
	root.Active = props.enabled ~= false
	local circle = props.shape == "circle"
	local surfaceProps: Panel.SurfaceProps = {
		palette = props.palette or "blue",
		enabled = props.enabled,
		radiusPixels = if circle then math.floor(side / 2) else Kit.radius(style, "md"),
		outline = "thick",
		gloss = true,
		shadow = true,
	}
	local parts = Panel.surface(object, root, surfaceProps)

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, if props.label then 0.44 else 0.5)
	icon.Size = UDim2.fromScale(0.72, 0.72)
	icon.Parent = parts.content
	if not Kit.icon(icon, props.icon, props.image) then
		icon:Destroy()
	end

	if props.label and props.label ~= "" then
		local caption = Instance.new("TextLabel")
		caption.Name = "Label"
		caption.BackgroundTransparency = 1
		caption.AnchorPoint = Vector2.new(0.5, 0.5)
		caption.Position = UDim2.new(0.5, 0, 1, -4)
		caption.Size = UDim2.new(1.3, 0, 0, 22)
		caption.ZIndex = 4
		local options: GameText.TextOptions = { text = props.label, role = "caption" }
		GameText.decorate(caption, style, options, object.parts)
		caption.Parent = root
		object.parts:Add(caption)
	end

	Badge.attach(object, root, props.badge)
end

function IconButton.new(props: Props)
	return Base.new({ className = "TextButton", name = "IconButton", props = props, build = build, interactive = true })
end

return IconButton
