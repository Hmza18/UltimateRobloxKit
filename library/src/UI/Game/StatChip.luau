--!strict
-- Stat chip: a compact pill with an icon and a value ("x2.5", "+15%", 1250). When the value
-- changes the chip pops; a numeric value also rolls to the new number.
--   local luck = StatChip.new({ icon = "star-color", value = 120, suffix = "%", parent = statsRow })
--   luck:update({ value = 135 })
--   StatChip.new({ icon = "bolt", value = "MAX" })
--
-- Numbers are formatted with Core/Format (`format`, default "abbrev") plus `prefix` / `suffix`;
-- strings are shown as given.

local Base = require("./Base")
local Extra = require("./Extra")
local Kit = require("./Kit")
local Panel = require("./Panel")
local UILogic = require("../../Visuals/UI/UILogic")

export type Props = {
	icon: string?,
	image: string?,
	value: (number | string)?,
	format: string?, -- Core/Format spec for numbers, default "abbrev"
	prefix: string?,
	suffix: string?,
	palette: string?, -- default: the dark surface
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

local StatChip = {}

-- The chip's text for props.
function StatChip.text(props: { [string]: any }, value: any?): string
	local shown = if value ~= nil then value else props.value
	if type(shown) == "number" then
		return UILogic.countText(shown, {
			format = props.format or "abbrev",
			prefix = props.prefix,
			suffix = props.suffix,
		})
	end
	return (props.prefix or "") .. tostring(shown or "") .. (props.suffix or "")
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	local surfaceProps: Panel.SurfaceProps = {
		palette = props.palette,
		surface = if props.palette then nil else "dark",
		radius = "pill",
		outline = "regular",
		gloss = props.palette ~= nil,
		shadow = true,
	}
	local content = Panel.surface(object, root, surfaceProps).content
	local pad = Kit.spacing(style, "sm")
	local icon = Extra.image(content, "Icon", props.icon, props.image, {
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, pad, 0.5, 0),
		size = UDim2.fromScale(0.72, 0.72),
	})
	local left = pad
	if icon then
		icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
		left = math.floor(root.Size.Y.Offset * 0.72) + pad * 2
	end
	object.label = Extra.label(object, content, "Value", {
		text = StatChip.text(props, object.shown),
		role = "label",
		align = if icon then "left" else "center",
	}, {
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, left, 0.5, 0),
		size = UDim2.new(1, -(left + pad), 0.74, 0),
	})
end

local function stopRoll(object: any)
	if object.roll then
		object.roll.stop()
		object.roll = nil
	end
end

local function apply(object: any, partial: { [string]: any }): boolean
	for key in pairs(partial) do
		if key ~= "value" then
			return false
		end
	end
	local label: TextLabel? = object.label
	if label == nil then
		return false
	end
	stopRoll(object)
	local value = object.props.value
	local from = object.shown
	if type(value) == "number" and type(from) == "number" then
		-- countTo pops the label when the roll ends.
		object.roll = Extra.UI.countTo(label, value, {
			from = from,
			format = object.props.format or "abbrev",
			prefix = object.props.prefix,
			suffix = object.props.suffix,
			onStep = function(shown: number)
				object.shown = shown
			end,
		})
	else
		object.shown = value
		label.Text = StatChip.text(object.props)
		Extra.UI.animate(label, "TextBounce", { intensity = 0.7 })
	end
	Extra.UI.animate(object.Instance, "BouncyPress", { intensity = 0.5 })
	return true
end

function StatChip.new(props: Props)
	return Base.new({
		className = "Frame",
		name = "StatChip",
		props = props,
		size = UDim2.fromOffset(120, 36),
		build = function(self: any)
			stopRoll(self)
			self.shown = self.props.value
			build(self)
		end,
		apply = apply,
		setup = function(self: any)
			self.trove:Add(function()
				stopRoll(self)
				Extra.UI.stop(self.Instance, false)
			end)
		end,
	})
end

return StatChip
