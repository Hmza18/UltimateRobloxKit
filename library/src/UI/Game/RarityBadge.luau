--!strict
-- Rarity pill: the rarity's colour as a glossy gradient with its name in outlined capitals. High
-- rarities (legendary, mythic, secret) shimmer with a looping shine; "secret" also cycles its
-- outline through the rainbow.
--   RarityBadge.new({ rarity = "legendary", parent = card.Instance })
--   RarityBadge.new({ rarity = "epic", text = "EPIC PET", shimmer = true })
--
-- Colours come from the style's rarity table, so custom rarities added to styles.json work too.

local Base = require("./Base")
local Extra = require("./Extra")
local RarityFrame = require("./RarityFrame")
local Style = require("../Style/Style")

export type Props = {
	rarity: string?, -- common (default), uncommon, rare, epic, legendary, mythic, secret
	text: string?, -- default: the rarity in capitals
	shimmer: boolean?, -- default: true for legendary, mythic and secret
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

local RarityBadge = {}

local SHIMMER: { [string]: number } = { legendary = 3.2, mythic = 2.4, secret = 1.8 }

-- Seconds between shimmer sweeps for a rarity, or nil when it does not shimmer by default.
function RarityBadge.shimmerInterval(rarity: string?): number?
	return SHIMMER[rarity or "common"]
end

function RarityBadge.text(props: { [string]: any }): string
	return props.text or string.upper(props.rarity or "common")
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	local text = RarityBadge.text(props)
	local height = 26
	if typeof(props.size) ~= "UDim2" then
		root.Size = UDim2.fromOffset(math.max(56, #text * 10 + 24), height)
	else
		height = math.max(1, props.size.Y.Offset)
	end
	local def = Style.rarity(style, props.rarity)
	local parts = Extra.surface(object, root, Extra.swatch(def.color), {
		radius = math.floor(height / 2),
		outline = "regular",
		shadow = false,
	})
	Extra.label(object, parts.content, "Text", { text = text, role = "caption" }, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.new(1, -12, 0.86, 0),
	})
	if def.rainbow and parts.stroke then
		object.parts:Add(RarityFrame.attach(parts.stroke, style, props.rarity))
	end
	local interval = RarityBadge.shimmerInterval(props.rarity)
	local shimmer = if props.shimmer ~= nil then props.shimmer else interval ~= nil
	if shimmer then
		Extra.own(
			object,
			Extra.UI.shine(root, { loop = true, interval = interval or 3.2, duration = 0.7, delay = 0.4 })
		)
	end
end

function RarityBadge.new(props: Props)
	return Base.new({ className = "Frame", name = "RarityBadge", props = props, build = build })
end

return RarityBadge
