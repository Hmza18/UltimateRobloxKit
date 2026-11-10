--!strict
-- Achievement card: a round icon, title, description, tier stars and a progress bar. Locked
-- achievements are dimmed. When `unlocked` turns true the card flashes gold with a shine and the
-- earned stars pop in one by one.
--   local card = AchievementCard.new({ title = "COLLECTOR", description = "Own 50 pets", icon = "trophy-color",
--       tier = 1, maxTier = 3, value = 20, max = 50 })
--   card:update({ tier = 2, unlocked = true, value = 50 })
--
-- Stars are drawn as small rotated squares in the gold palette (earned) or the gray palette, so
-- no image or special font glyph is needed.

local Base = require("./Base")
local Extra = require("./Extra")
local Kit = require("./Kit")
local Panel = require("./Panel")
local ProgressBar = require("./ProgressBar")
local Style = require("../Style/Style")

export type Props = {
	title: string?,
	description: string?,
	icon: string?,
	image: string?,
	tier: number?, -- stars earned, default 0
	maxTier: number?, -- stars shown, default 3 (0 hides them)
	value: number?,
	max: number?, -- no bar when nil
	unlocked: boolean?, -- default: tier > 0
	palette: string?, -- icon badge colour when unlocked, default "gold"
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

local AchievementCard = {}

function AchievementCard.unlocked(props: { [string]: any }): boolean
	if props.unlocked ~= nil then
		return props.unlocked == true
	end
	return (props.tier or 0) > 0
end

local function star(object: any, parent: Instance, index: number, earned: boolean): Frame
	local style = object.style
	local holder = Extra.frame(parent, "Star" .. index, {
		position = UDim2.new(0, (index - 1) * 22, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		size = UDim2.fromOffset(18, 18),
	})
	local gem = Instance.new("Frame")
	gem.Name = "Gem"
	gem.BorderSizePixel = 0
	gem.AnchorPoint = Vector2.new(0.5, 0.5)
	gem.Position = UDim2.fromScale(0.5, 0.5)
	gem.Size = UDim2.fromScale(0.72, 0.72)
	gem.Rotation = 45
	gem.BackgroundColor3 = Color3.new(1, 1, 1)
	Kit.corner(3).Parent = gem
	local swatch = Style.palette(style, if earned then "gold" else "gray")
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 45
	gradient.Color = Kit.sequence(swatch.top, swatch.bottom)
	gradient.Parent = gem
	Kit.stroke(style, "thin").Parent = gem
	gem.BackgroundTransparency = if earned then 0 else 0.4
	gem.Parent = holder
	return holder
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	local unlocked = AchievementCard.unlocked(props)
	local surfaceProps: Panel.SurfaceProps =
		{ surface = "window", radius = "lg", outline = "thick", gloss = false, pattern = false, shadow = true }
	local content = Panel.surface(object, root, surfaceProps).content
	local textColor = Style.surface(style, "window").text
	local pad = Kit.spacing(style, "md")

	local badge = Extra.frame(content, "Icon", {
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, pad, 0.5, 0),
		size = UDim2.fromScale(0.7, 0.7),
	})
	badge.SizeConstraint = Enum.SizeConstraint.RelativeYY
	local side = math.floor(root.Size.Y.Offset * 0.7)
	local badgeProps: Panel.SurfaceProps = {
		palette = if unlocked then props.palette or "gold" else "gray",
		radiusPixels = math.floor(side / 2),
		outline = "thick",
		gloss = true,
		shadow = false,
	}
	local badgeContent = Panel.surface(object, badge, badgeProps).content
	local picture = Extra.image(badgeContent, "Picture", props.icon, props.image, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromScale(0.66, 0.66),
	})
	if picture and not unlocked then
		picture.ImageTransparency = 0.5
	end
	object.badge = badge

	local left = side + pad * 2
	local title = Extra.label(
		object,
		content,
		"Title",
		{ text = props.title or "", role = "heading", align = "left" },
		{
			position = UDim2.fromOffset(left, pad - 4),
			size = UDim2.new(1, -(left + pad + 70), 0.3, 0),
		}
	)
	title.TextTransparency = if unlocked then 0 else 0.3
	Extra.label(object, content, "Description", {
		text = props.description or "",
		role = "caption",
		align = "left",
		color = textColor,
		stroke = false,
	}, { position = UDim2.new(0, left, 0.36, 0), size = UDim2.new(1, -(left + pad), 0.22, 0) })

	object.stars = {}
	local maxTier = math.clamp(math.floor(props.maxTier or 3), 0, 5)
	if maxTier > 0 then
		local row = Extra.frame(content, "Stars", {
			anchor = Vector2.new(1, 0),
			position = UDim2.new(1, -pad, 0, pad),
			size = UDim2.fromOffset(maxTier * 22 - 4, 20),
		})
		for index = 1, maxTier do
			local earned = index <= (props.tier or 0)
			local holder = star(object, row, index, earned)
			if earned then
				table.insert(object.stars, holder)
			end
		end
	end

	object.bar = nil
	if props.max ~= nil then
		local bar = ProgressBar.new({
			value = props.value,
			max = props.max,
			palette = if unlocked then "gold" else "blue",
			showText = true,
			style = props.style,
			anchor = Vector2.new(0, 1),
			position = UDim2.new(0, left, 1, -pad),
			size = UDim2.new(1, -(left + pad), 0.24, 0),
			parent = content,
		})
		object.parts:Add(bar)
		object.bar = bar
	end
end

local function apply(object: any, partial: { [string]: any }): boolean
	for key in pairs(partial) do
		if key ~= "value" and key ~= "max" then
			return false
		end
	end
	if object.bar == nil or object.props.max == nil then
		return false
	end
	object.bar:update({ value = object.props.value, max = object.props.max })
	return true
end

function AchievementCard.new(props: Props)
	return Base.new({
		className = "Frame",
		name = "AchievementCard",
		props = props,
		size = UDim2.new(1, 0, 0, 96),
		build = function(self: any)
			local was = self.wasUnlocked
			local tierBefore = self.tierBefore or 0
			build(self)
			local now = AchievementCard.unlocked(self.props)
			local tier = self.props.tier or 0
			-- Celebrate only a change after the first draw.
			if was ~= nil and ((now and not was) or tier > tierBefore) then
				Extra.UI.animate(self.Instance, "UpgradePulse", { intensity = 0.4 })
				local fresh: { GuiObject } = {}
				for index = tierBefore + 1, #self.stars do
					table.insert(fresh, self.stars[index])
				end
				Extra.UI.stagger(fresh, "BadgePop", { interval = 0.12, delay = 0.15 })
			end
			self.wasUnlocked = now
			self.tierBefore = tier
		end,
		apply = apply,
		setup = function(self: any)
			self.trove:Add(function()
				Extra.UI.stop(self.Instance, false)
			end)
		end,
	})
end

return AchievementCard
