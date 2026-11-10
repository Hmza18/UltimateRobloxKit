--!strict
-- Pet card: a portrait slot, the pet's name, a rarity badge, a row of stat chips and an equipped
-- tick. It grows on hover and shows a glowing outline when selected.
--   local card = PetCard.new({ name = "pet_42", title = "Ember Fox", rarity = "epic", image = "rbxassetid://1",
--       stats = { { icon = "coin-color", text = "x2.5" }, { icon = "bolt", text = "+15%" } }, equipped = true })
--   card.Activated:Connect(function(id) selectPet(id) end)
--   card:update({ selected = true })
--
-- Portrait: pass `image` / `icon`, or parent your own ImageLabel or ViewportFrame to card.Content
-- (it survives updates; Visuals.Pets.preview can drive a ViewportFrame there). The card outline
-- takes the rarity colour. Motion is scale only, so cards work inside a Grid.

local Base = require("./Base")
local Extra = require("./Extra")
local Kit = require("./Kit")
local Panel = require("./Panel")
local RarityBadge = require("./RarityBadge")
local RarityFrame = require("./RarityFrame")
local Style = require("../Style/Style")

export type Stat = { icon: string?, image: string?, text: string }

export type Props = {
	title: string?, -- the pet's display name
	rarity: string?,
	icon: string?,
	image: string?,
	stats: { Stat }?, -- at most three are shown
	palette: string?, -- card colour, default "blue"
	selected: boolean?,
	equipped: boolean?,
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

local PetCard = {}

PetCard.MAX_STATS = 3

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: TextButton = object.Instance
	local enabled = props.enabled ~= false
	root.Active = enabled
	local rarity = if props.rarity then Style.rarity(style, props.rarity) else nil
	local surfaceProps: Panel.SurfaceProps = {
		palette = props.palette or "blue",
		enabled = enabled,
		radius = "lg",
		outline = "heavy",
		outlineColor = if rarity then rarity.color else nil,
		gloss = true,
		pattern = true,
		shadow = true,
	}
	local parts = Panel.surface(object, root, surfaceProps)
	if rarity and rarity.rainbow and parts.stroke then
		object.parts:Add(RarityFrame.attach(parts.stroke, style, props.rarity))
	end
	local content = parts.content
	local pad = Kit.spacing(style, "sm")

	-- Portrait: an inset square the caller can fill.
	local portrait = Extra.frame(content, "Portrait", {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, pad),
		size = UDim2.new(1, -pad * 2, 0.52, 0),
	})
	local insetProps: Panel.SurfaceProps =
		{ surface = "inset", radius = "md", outline = "regular", gloss = false, shadow = false }
	local slot = Panel.surface(object, portrait, insetProps).content
	slot:SetAttribute("UrkInternal", true)
	object.Content = slot
	local picture = Extra.image(slot, "Picture", props.icon, props.image, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromScale(0.86, 0.86),
	})
	if picture and not enabled then
		picture.ImageTransparency = 0.4
	end

	Extra.label(object, content, "Title", { text = props.title or "", role = "label", maxSize = 22 }, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0.56, pad),
		size = UDim2.new(1, -pad * 2, 0.14, 0),
	})

	if props.rarity then
		object.parts:Add(RarityBadge.new({
			rarity = props.rarity,
			style = props.style,
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.new(0.5, 0, 0.52, pad),
			size = UDim2.fromOffset(84, 22),
			parent = content,
		}))
	end

	local stats: { Stat } = props.stats or {}
	local shown = math.min(#stats, PetCard.MAX_STATS)
	if shown > 0 then
		local row = Extra.frame(content, "Stats", {
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -pad),
			size = UDim2.new(1, -pad * 2, 0.17, 0),
		})
		for index = 1, shown do
			local stat = stats[index]
			local cell = Extra.frame(row, "Stat" .. index, {
				position = UDim2.fromScale((index - 1) / shown, 0),
				size = UDim2.fromScale(1 / shown, 1),
			})
			local icon = Extra.image(cell, "Icon", stat.icon, stat.image, {
				anchor = Vector2.new(0, 0.5),
				position = UDim2.fromScale(0, 0.5),
				size = UDim2.fromScale(0.9, 0.9),
			})
			if icon then
				icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
			end
			Extra.label(object, cell, "Value", { text = stat.text, role = "caption", align = "left" }, {
				anchor = Vector2.new(1, 0.5),
				position = UDim2.fromScale(1, 0.5),
				size = if icon then UDim2.new(1, -22, 1, 0) else UDim2.fromScale(1, 1),
			})
		end
	end

	if props.equipped then
		local tick = Extra.frame(root, "Equipped", {
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.new(1, -8, 0, 8),
			size = UDim2.fromOffset(30, 30),
			zIndex = 5,
		})
		object.parts:Add(tick)
		local tickProps: Panel.SurfaceProps =
			{ palette = "green", radiusPixels = 15, outline = "regular", gloss = true, shadow = false }
		local tickContent = Panel.surface(object, tick, tickProps).content
		local mark = Extra.image(tickContent, "Mark", "check", nil, {
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(0.5, 0.5),
			size = UDim2.fromScale(0.7, 0.7),
		})
		if mark == nil then
			Extra.label(object, tickContent, "Mark", { text = "E", role = "caption" })
		end
	end
end

local function apply(object: any, partial: { [string]: any }): boolean
	for key in pairs(partial) do
		if key ~= "selected" then
			return false
		end
	end
	if object.binding then
		object.binding.setSelected(object.props.selected == true)
	end
	return true
end

function PetCard.new(props: Props)
	return Base.new({
		className = "TextButton",
		name = "PetCard",
		props = props,
		size = UDim2.fromOffset(156, 208),
		build = build,
		apply = apply,
		setup = function(self: any)
			Extra.wire(self, {
				style = "Soft",
				radius = Kit.radius(self.style, "lg"),
				selected = self.props.selected == true,
			})
		end,
	})
end

return PetCard
