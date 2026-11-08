--!strict
-- Rounded gradient container with a thick outline, optional checker pattern, gloss and drop
-- shadow. The base of every other game component.
--   local panel = Panel.new({ palette = "purple", pattern = true, size = UDim2.fromOffset(160, 160) })
--   panel.Content -- put children here (it carries the padding)

local Base = require("./Base")
local Kit = require("./Kit")
local Style = require("../Style/Style")
local Surface = require("./Surface")

export type Props = {
	palette: string?,
	surface: string?, -- "window" | "inset" | "dark", used instead of palette
	radius: string?, -- radius token, default "lg"
	outline: string?, -- outline weight, default "thick"
	gloss: boolean?, -- default true for palettes, false for surfaces
	pattern: boolean?, -- default false
	shadow: boolean?, -- default true
	padding: string?, -- spacing token for the content padding
	patternImage: string?,
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

export type SurfaceProps = {
	palette: string?,
	surface: string?,
	enabled: boolean?,
	radius: string?,
	radiusPixels: number?,
	outline: string?,
	gloss: boolean?,
	pattern: boolean?,
	shadow: boolean?,
	padding: string?,
	patternImage: string?,
	outlineColor: string?,
}

local Panel = {}

-- Draws a surface into `root` for a component object; it is cleaned on the object's next rebuild.
function Panel.surface(object: any, root: GuiObject, props: SurfaceProps, defaultPalette: string?): Surface.Parts
	local style = object.style
	local swatch = Kit.swatch(style, props, defaultPalette)
	local options: Surface.Options = {
		swatch = swatch,
		radius = props.radiusPixels or Kit.radius(style, props.radius or "lg"),
		outline = Style.outline(style, props.outline or "thick"),
		outlineColor = props.outlineColor,
		gloss = if props.gloss ~= nil then props.gloss else props.surface == nil,
		pattern = props.pattern == true,
		patternImage = props.patternImage,
		shadow = props.shadow ~= false,
		padding = if props.padding then Kit.spacing(style, props.padding) else nil,
	}
	local parts = Surface.build(style, root, options)
	object.parts:Add(function()
		Surface.clear(parts)
	end)
	return parts
end

local function build(object: any)
	local props = object.props
	local parts = Panel.surface(object, object.Instance, props)
	object.Content = parts.content
	object.Body = parts.body
	object.Surface = parts
end

function Panel.new(props: Props)
	return Base.new({
		className = "Frame",
		name = "Panel",
		props = props,
		size = UDim2.fromOffset(200, 120),
		build = build,
	})
end

return Panel
