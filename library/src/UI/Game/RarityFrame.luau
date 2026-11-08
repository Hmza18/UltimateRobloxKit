--!strict
-- Outline in the rarity's colour. "secret" (rainbow = true in the style) cycles a rainbow through
-- the shared ticker; under reduced motion it stays on one colour.
--   RarityFrame.new({ rarity = "legendary", parent = card.Instance })   -- overlay outline
--   RarityFrame.attach(stroke, style, "secret")                          -- recolour an existing UIStroke

local Base = require("./Base")
local Kit = require("./Kit")
local Motion = require("../Runtime/Motion")
local Style = require("../Style/Style")
local Ticker = require("./Ticker")

export type Props = {
	rarity: string?, -- common, uncommon, rare, epic, legendary, mythic, secret
	radius: string?, -- radius token, default "lg"
	outline: string?, -- outline weight, default "heavy"
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

local RarityFrame = {}

local RAINBOW_SPEED = 0.25

local function visible(instance: Instance): boolean
	local current: Instance? = instance.Parent
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("ScreenGui") then
			return current.Enabled
		end
		current = current.Parent
	end
	return false
end

-- Colours `stroke` for `rarity`. Returns a function that stops the rainbow (a no-op otherwise).
function RarityFrame.attach(stroke: UIStroke, style: Style.StyleDef, rarity: string?): () -> ()
	local def = Style.rarity(style, rarity)
	stroke.Color = Color3.fromHex(def.color)
	if not def.rainbow then
		return function() end
	end
	if Motion.isReduced() then
		stroke.Color = Motion.rainbowColor(0, RAINBOW_SPEED)
		return function() end
	end
	return Ticker.frame(function(now: number): boolean?
		if stroke.Parent == nil then
			return false
		end
		if visible(stroke) then
			stroke.Color = Motion.rainbowColor(now, RAINBOW_SPEED)
		end
		return true
	end)
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	root.ZIndex = 4
	if typeof(props.size) ~= "UDim2" then
		root.Size = UDim2.fromScale(1, 1)
	end
	local corner = Kit.corner(Kit.radius(style, props.radius or "lg"))
	corner.Parent = root
	object.parts:Add(corner)
	local stroke = Kit.stroke(style, props.outline or "heavy")
	stroke.Parent = root
	object.parts:Add(stroke)
	object.parts:Add(RarityFrame.attach(stroke, style, props.rarity))
end

function RarityFrame.new(props: Props)
	return Base.new({ className = "Frame", name = "RarityFrame", props = props, build = build })
end

return RarityFrame
