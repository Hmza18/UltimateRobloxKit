--!strict
-- Inventory slot: a square inset tile with an item icon, a stack count, an outline in the item's
-- rarity colour and three states: selected (raised, glowing outline), equipped (green tick) and
-- locked (dimmed with a padlock; pressing it shakes and does not fire Activated).
--   local slot = InventorySlot.new({ name = "sword_3", icon = "sword-color", count = 12, rarity = "rare" })
--   slot.Activated:Connect(function(id) inventory:select(id) end)
--   slot:update({ selected = true })     -- no rebuild: plays the selection animation
--
-- An empty slot (no icon or image) draws the tile only. Slots are 72 px by default and work inside
-- a Grid or any UIGridLayout, because their motion is scale, never position.

local Base = require("./Base")
local Extra = require("./Extra")
local Format = require("../Core/Format")
local Kit = require("./Kit")
local Panel = require("./Panel")
local RarityFrame = require("./RarityFrame")
local Style = require("../Style/Style")

export type Props = {
	icon: string?,
	image: string?,
	count: number?, -- shown as "x12" when above 1
	rarity: string?,
	selected: boolean?,
	equipped: boolean?,
	locked: boolean?,
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

local InventorySlot = {}

-- Stack text: empty for 0 or 1, "x12", "x1.5K".
function InventorySlot.countText(count: number?): string
	if count == nil or count <= 1 then
		return ""
	end
	return "x" .. Format.abbrev(count)
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: TextButton = object.Instance
	root.Active = props.enabled ~= false and not props.locked
	local rarity = if props.rarity then Style.rarity(style, props.rarity) else nil
	local surfaceProps: Panel.SurfaceProps = {
		surface = "inset",
		radius = "md",
		outline = "thick",
		outlineColor = if rarity then rarity.color else nil,
		gloss = false,
		shadow = true,
	}
	local parts = Panel.surface(object, root, surfaceProps)
	if rarity and rarity.rainbow and parts.stroke then
		object.parts:Add(RarityFrame.attach(parts.stroke, style, props.rarity))
	end
	local content = parts.content

	local icon = Extra.image(content, "Icon", props.icon, props.image, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromScale(0.72, 0.72),
	})
	if icon and (props.locked or props.enabled == false) then
		icon.ImageTransparency = 0.5
	end

	local count = InventorySlot.countText(props.count)
	if count ~= "" then
		Extra.label(object, content, "Count", { text = count, role = "caption", align = "right" }, {
			anchor = Vector2.new(1, 1),
			position = UDim2.new(1, -4, 1, -2),
			size = UDim2.new(0.8, 0, 0.34, 0),
			zIndex = 3,
		})
	end

	if props.equipped then
		local tick = Extra.frame(root, "Equipped", {
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.fromOffset(6, 6),
			size = UDim2.fromOffset(24, 24),
			zIndex = 5,
		})
		object.parts:Add(tick)
		local tickProps: Panel.SurfaceProps =
			{ palette = "green", radiusPixels = 12, outline = "regular", gloss = true, shadow = false }
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

	if props.locked then
		local shade = Extra.frame(content, "Locked", { zIndex = 4 })
		shade.BackgroundTransparency = 0.45
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		Kit.corner(Kit.radius(style, "md")).Parent = shade
		local lock = Extra.image(shade, "Lock", "lock-color", nil, {
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(0.5, 0.5),
			size = UDim2.fromScale(0.5, 0.5),
			zIndex = 5,
		})
		if lock == nil then
			Extra.label(object, shade, "Lock", { text = "LOCKED", role = "caption" }, { zIndex = 5 })
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

function InventorySlot.new(props: Props)
	return Base.new({
		className = "TextButton",
		name = "InventorySlot",
		props = props,
		size = UDim2.fromOffset(72, 72),
		build = build,
		apply = apply,
		setup = function(self: any)
			Extra.wire(self, {
				style = "Snappy",
				selected = self.props.selected == true,
				gate = function(): boolean
					if self.props.locked then
						Extra.UI.animate(self.Instance, "Error", { intensity = 0.6 })
						return false
					end
					return true
				end,
			})
		end,
	})
end

return InventorySlot
