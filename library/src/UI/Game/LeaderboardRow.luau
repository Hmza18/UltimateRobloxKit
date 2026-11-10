--!strict
-- Leaderboard row: rank (a gold, silver or bronze medal for the top three, a plain number below),
-- an avatar slot, the player's name and a value. The local player's row is highlighted.
--   local row = LeaderboardRow.new({ rank = 1, title = "Builderman", value = 1250000, avatar = thumbnailUrl })
--   LeaderboardRow.new({ rank = 14, title = "You", value = 5200, highlight = true })
--   row:update({ value = 1300000 })      -- rolls the number
--
-- Avatar: pass `avatar` (an image id or content string such as a Players:GetUserThumbnailAsync
-- result fetched by your code), or parent your own image to row.Content.

local Base = require("./Base")
local Extra = require("./Extra")
local Format = require("../Core/Format")
local Kit = require("./Kit")
local Panel = require("./Panel")

export type Props = {
	rank: number?,
	title: string?, -- player name
	value: number?,
	format: string?, -- Core/Format spec, default "abbrev"
	avatar: string?,
	highlight: boolean?, -- the local player's row
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

local LeaderboardRow = {}

local MEDALS: { [number]: string } = { [1] = "gold", [2] = "gray", [3] = "orange" }

-- Palette of the medal for a rank, or nil below third place.
function LeaderboardRow.medal(rank: number?): string?
	return MEDALS[math.floor(rank or 0)]
end

function LeaderboardRow.valueText(value: number?, format: string?): string
	return Format.apply(format or "abbrev", value or 0)
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	local surfaceProps: Panel.SurfaceProps = {
		palette = if props.highlight then "yellow" else nil,
		surface = if props.highlight then nil else "inset",
		radius = "md",
		outline = if props.highlight then "thick" else "regular",
		gloss = props.highlight == true,
		shadow = props.highlight == true,
	}
	local content = Panel.surface(object, root, surfaceProps).content
	local pad = Kit.spacing(style, "sm")
	local height = root.Size.Y.Offset
	local side = math.max(24, height - pad * 2)

	local rankHolder = Extra.frame(content, "Rank", {
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, pad, 0.5, 0),
		size = UDim2.fromOffset(side, side),
	})
	local medal = LeaderboardRow.medal(props.rank)
	local rankParent: Instance = rankHolder
	if medal then
		local medalProps: Panel.SurfaceProps =
			{ palette = medal, radiusPixels = math.floor(side / 2), outline = "regular", gloss = true, shadow = false }
		rankParent = Panel.surface(object, rankHolder, medalProps).content
	end
	Extra.label(object, rankParent, "Number", {
		text = if props.rank then tostring(math.floor(props.rank)) else "-",
		role = if medal then "heading" else "label",
	}, { anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.5), size = UDim2.fromScale(0.8, 0.8) })

	local avatar = Extra.frame(content, "Avatar", {
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, pad * 2 + side, 0.5, 0),
		size = UDim2.fromOffset(side, side),
	})
	avatar.BackgroundTransparency = 0.6
	avatar.BackgroundColor3 = Color3.new(0, 0, 0)
	avatar.ClipsDescendants = true
	Kit.corner(math.floor(side / 2)).Parent = avatar
	avatar:SetAttribute("UrkInternal", nil)
	object.parts:Add(avatar)
	object.Content = avatar
	local picture = Extra.image(avatar, "Picture", nil, props.avatar)
	if picture then
		Kit.corner(math.floor(side / 2)).Parent = picture
	end

	local left = pad * 3 + side * 2
	Extra.label(object, content, "Name", { text = props.title or "", role = "label", align = "left" }, {
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, left, 0.5, 0),
		size = UDim2.new(0.62, -left, 0.7, 0),
	})
	object.valueLabel = Extra.label(object, content, "Value", {
		text = LeaderboardRow.valueText(object.shown or props.value, props.format),
		role = "price",
		align = "right",
	}, {
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -pad - 4, 0.5, 0),
		size = UDim2.new(0.38, -pad, 0.7, 0),
	})
end

local function apply(object: any, partial: { [string]: any }): boolean
	for key in pairs(partial) do
		if key ~= "value" then
			return false
		end
	end
	if object.valueLabel == nil then
		return false
	end
	local target = object.props.value or 0
	if object.roll then
		object.roll.stop()
	end
	object.roll = Extra.UI.countTo(object.valueLabel, target, {
		from = object.shown or 0,
		format = object.props.format or "abbrev",
		onStep = function(value: number)
			object.shown = value
		end,
	})
	return true
end

function LeaderboardRow.new(props: Props)
	return Base.new({
		className = "Frame",
		name = "LeaderboardRow",
		props = props,
		size = UDim2.new(1, 0, 0, 52),
		build = function(self: any)
			if self.shown == nil then
				self.shown = self.props.value or 0
			end
			if self.roll then
				self.roll.stop()
				self.roll = nil
				self.shown = self.props.value or 0
			end
			build(self)
		end,
		apply = apply,
		setup = function(self: any)
			self.trove:Add(function()
				if self.roll then
					self.roll.stop()
				end
			end)
		end,
	})
end

return LeaderboardRow
