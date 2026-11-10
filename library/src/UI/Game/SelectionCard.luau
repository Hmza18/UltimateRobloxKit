--!strict
-- Selection card: a large selectable card with a preview slot, a title, a description and a tick
-- that shows when it is selected. The base of class, map, pet-team and game-mode pickers.
--   local cards = {}
--   for _, mode in modes do
--       local card = SelectionCard.new({ name = mode.id, title = mode.title, description = mode.blurb,
--           icon = mode.icon, parent = row })
--       card.Activated:Connect(function(id)
--           for _, other in cards do other:update({ selected = other.props.name == id }) end
--       end)
--       table.insert(cards, card)
--   end
--
-- The card does not select itself: the screen decides (single or multi select) and calls
-- update({ selected }). That update plays the animation without a rebuild. Put a custom preview
-- (ViewportFrame, image) in card.Content.

local Base = require("./Base")
local Extra = require("./Extra")
local Kit = require("./Kit")
local Panel = require("./Panel")
local Style = require("../Style/Style")

export type Props = {
	title: string?,
	description: string?,
	icon: string?,
	image: string?,
	palette: string?, -- default "blue"
	selected: boolean?,
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

local SelectionCard = {}

local TICK = 36

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: TextButton = object.Instance
	local enabled = props.enabled ~= false
	root.Active = enabled
	local surfaceProps: Panel.SurfaceProps = {
		palette = props.palette or "blue",
		enabled = enabled,
		radius = "xl",
		outline = "heavy",
		gloss = true,
		pattern = true,
		shadow = true,
	}
	local content = Panel.surface(object, root, surfaceProps).content
	local pad = Kit.spacing(style, "md")

	local preview = Extra.frame(content, "Preview", {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, pad),
		size = UDim2.new(1, -pad * 2, 0.5, 0),
	})
	local insetProps: Panel.SurfaceProps =
		{ surface = "inset", radius = "lg", outline = "regular", gloss = false, shadow = false }
	local slot = Panel.surface(object, preview, insetProps).content
	object.Content = slot
	Extra.image(slot, "Picture", props.icon, props.image, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromScale(0.8, 0.8),
	})

	Extra.label(object, content, "Title", { text = props.title or "", role = "heading" }, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0.5, pad + 4),
		size = UDim2.new(1, -pad * 2, 0.16, 0),
	})
	Extra.label(object, content, "Description", {
		text = props.description or "",
		role = "caption",
		wrap = true,
		color = Style.palette(style, props.palette or "blue").text,
	}, {
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -pad),
		size = UDim2.new(1, -pad * 2, 0.24, 0),
	})

	local tick = Extra.frame(root, "Selected", {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(1, -10, 0, 10),
		size = UDim2.fromOffset(TICK, TICK),
		zIndex = 6,
	})
	object.parts:Add(tick)
	tick.Visible = props.selected == true
	local tickProps: Panel.SurfaceProps =
		{ palette = "green", radiusPixels = TICK / 2, outline = "thick", gloss = true, shadow = false }
	local tickContent = Panel.surface(object, tick, tickProps).content
	local mark = Extra.image(tickContent, "Mark", "check", nil, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromScale(0.66, 0.66),
	})
	if mark == nil then
		Extra.label(object, tickContent, "Mark", { text = "OK", role = "caption" })
	end
	object.tick = tick
end

local function showSelected(object: any, animate: boolean)
	local selected = object.props.selected == true
	if object.binding then
		object.binding.setSelected(selected)
	end
	local tick: Frame? = object.tick
	if tick == nil then
		return
	end
	if not animate then
		tick.Visible = selected
	elseif selected then
		Extra.UI.show(tick, "BadgePop")
	else
		Extra.UI.hide(tick, "ScaleOut")
	end
end

local function apply(object: any, partial: { [string]: any }): boolean
	for key in pairs(partial) do
		if key ~= "selected" then
			return false
		end
	end
	if object.shownSelected ~= (object.props.selected == true) then
		object.shownSelected = object.props.selected == true
		showSelected(object, true)
	end
	return true
end

function SelectionCard.new(props: Props)
	return Base.new({
		className = "TextButton",
		name = "SelectionCard",
		props = props,
		size = UDim2.fromOffset(220, 280),
		build = function(self: any)
			build(self)
			self.shownSelected = self.props.selected == true
		end,
		apply = apply,
		setup = function(self: any)
			Extra.wire(self, {
				style = "Soft",
				radius = Kit.radius(self.style, "xl"),
				selected = self.props.selected == true,
			})
			self.trove:Add(function()
				if self.tick then
					Extra.UI.stop(self.tick, false)
				end
			end)
		end,
	})
end

return SelectionCard
