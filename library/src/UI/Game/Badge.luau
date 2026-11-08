--!strict
-- Corner badges: sale and bonus pills, the red circular "!" attention badge, NEW and the tilted
-- BEST ribbon. Parent it to the object it decorates; it anchors to that object's corner.
--   Badge.new({ kind = "attention", parent = shopButton.Instance })
--   Badge.new({ kind = "bonus", text = "+50%", corner = "topLeft", parent = card.Instance })

local Base = require("./Base")
local GameText = require("./GameText")
local Motion = require("../Runtime/Motion")
local Panel = require("./Panel")
local Style = require("../Style/Style")

export type Props = {
	kind: string?, -- Style.badge kinds: sale, bonus, attention, new, best (default new)
	text: string?,
	corner: string?, -- "topRight" (default) | "topLeft"
	pulse: boolean?, -- loop the attention preset (default true for attention)
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

local Badge = {}

local HEIGHT = 26
local CIRCLE = 30
local INSET = 6

-- Text shown on a badge: the prop, else the style's text, else the kind in capitals.
function Badge.text(style: Style.StyleDef, props: { [string]: any }): string
	if props.text then
		return props.text
	end
	local def = Style.badge(style, props.kind)
	return def.text or string.upper(props.kind or "new")
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	local def = Style.badge(style, props.kind)
	local text = Badge.text(style, props)
	local circle = def.shape == "circle"
	local width = if circle then CIRCLE else math.max(HEIGHT, #text * 10 + 20)
	local height = if circle then CIRCLE else HEIGHT
	root.Size = UDim2.fromOffset(width, height)
	root.ZIndex = 5
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	if props.corner == "topLeft" then
		root.Position = UDim2.fromOffset(INSET, INSET)
	else
		root.Position = UDim2.new(1, -INSET, 0, INSET)
	end
	root.Rotation = if def.shape == "ribbon" then 12 else 0
	local surfaceProps: Panel.SurfaceProps = {
		palette = def.palette,
		radiusPixels = math.floor(height / 2),
		outline = "regular",
		gloss = true,
		shadow = false,
	}
	local parts = Panel.surface(object, root, surfaceProps)
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	local options: GameText.TextOptions = { text = text, role = if circle then "heading" else "caption" }
	GameText.decorate(label, style, options, object.parts)
	label.Parent = parts.content
	local pulse = if props.pulse ~= nil then props.pulse else props.kind == "attention"
	if pulse then
		object.parts:Add(Motion.play(root, "attention"))
	end
end

function Badge.new(props: Props)
	return Base.new({ className = "Frame", name = "Badge", props = props, build = build })
end

-- Adds a badge described by `spec` ({ kind, text? }) to `parent`, owned by a component's rebuild.
function Badge.attach(object: any, parent: Instance, spec: { kind: string, text: string? }?)
	if spec == nil then
		return
	end
	local badgeProps: Props = { kind = spec.kind, text = spec.text, style = object.props.style, parent = parent }
	object.parts:Add(Badge.new(badgeProps))
end

return Badge
