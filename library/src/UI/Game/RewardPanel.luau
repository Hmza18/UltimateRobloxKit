--!strict
-- Reward panel: a titled panel with a grid of reward tiles and a claim button. `panel:reveal()`
-- pops the tiles in one after another from the centre out, then brings the claim button in and
-- lets it breathe until pressed. Claiming fires Claimed (and Activated) once.
--   local panel = RewardPanel.new({ title = "DAILY REWARDS", parent = window.Content, rewards = {
--       { icon = "coin-color", amount = "x500", rarity = "common" },
--       { icon = "gem-color", amount = "x25", rarity = "rare" },
--       { image = "rbxassetid://1", amount = "Ember Fox", rarity = "legendary" } } })
--   panel.Claimed:Connect(function() Net.fire("ClaimDaily") end)   -- the server grants
--   panel:reveal()
--
-- Tiles carry their rarity colour on the outline. The panel never grants anything.

local Base = require("./Base")
local Extra = require("./Extra")
local Kit = require("./Kit")
local Panel = require("./Panel")
local PremiumButton = require("./PremiumButton")
local RarityFrame = require("./RarityFrame")
local Signal = require("../../Util/Signal")
local Style = require("../Style/Style")

export type Reward = { icon: string?, image: string?, amount: string?, rarity: string? }

export type Props = {
	title: string?,
	rewards: { Reward }?,
	columns: number?, -- default: up to 4
	claimText: string?, -- default "CLAIM"
	claimed: boolean?, -- shows the button as done and disabled
	revealed: boolean?, -- false keeps tiles hidden until :reveal() (default true)
	palette: string?, -- panel colour; default the window surface
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

local RewardPanel = {}

local TITLE = 44
local FOOTER = 72

-- Columns and rows for `count` tiles: at most `columns` (default 4) per row.
function RewardPanel.grid(count: number, columns: number?): (number, number)
	local across = math.max(1, math.min(columns or 4, math.max(1, count)))
	return across, math.max(1, math.ceil(count / across))
end

local function tile(object: any, parent: Instance, reward: Reward, index: number): Frame
	local style = object.style
	local holder = Extra.frame(parent, "Reward" .. index, { order = index })
	local rarity = if reward.rarity then Style.rarity(style, reward.rarity) else nil
	local surfaceProps: Panel.SurfaceProps = {
		surface = "inset",
		radius = "md",
		outline = "thick",
		outlineColor = if rarity then rarity.color else nil,
		gloss = false,
		shadow = true,
	}
	local parts = Panel.surface(object, holder, surfaceProps)
	if rarity and rarity.rainbow and parts.stroke then
		object.parts:Add(RarityFrame.attach(parts.stroke, style, reward.rarity))
	end
	Extra.image(parts.content, "Icon", reward.icon, reward.image, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.fromScale(0.5, 0.08),
		size = UDim2.fromScale(0.62, 0.62),
	})
	if reward.amount and reward.amount ~= "" then
		Extra.label(object, parts.content, "Amount", { text = reward.amount, role = "caption" }, {
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -3),
			size = UDim2.new(1, -8, 0.28, 0),
		})
	end
	return holder
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	local surfaceProps: Panel.SurfaceProps = {
		palette = props.palette,
		surface = if props.palette then nil else "window",
		radius = "xl",
		outline = "heavy",
		gloss = false,
		pattern = true,
		shadow = true,
	}
	local content = Panel.surface(object, root, surfaceProps).content
	local pad = Kit.spacing(style, "md")
	Extra.label(object, content, "Title", { text = props.title or "", role = "title", maxSize = 30 }, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, pad),
		size = UDim2.new(1, -pad * 2, 0, TITLE - pad),
	})

	local rewards: { Reward } = props.rewards or {}
	local area = Extra.frame(content, "Rewards", {
		position = UDim2.fromOffset(pad, TITLE + pad),
		size = UDim2.new(1, -pad * 2, 1, -(TITLE + FOOTER + pad * 2)),
	})
	local columns, rows = RewardPanel.grid(#rewards, props.columns)
	local gap = Kit.spacing(style, "sm")
	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.CellPadding = UDim2.fromOffset(gap, gap)
	layout.CellSize = UDim2.new(1 / columns, -gap, 1 / rows, -gap)
	layout.Parent = area
	object.tiles = {}
	for index, reward in rewards do
		local holder = tile(object, area, reward, index)
		holder.Visible = object.revealed
		table.insert(object.tiles, holder)
	end

	local claimed = props.claimed == true
	local button = PremiumButton.new({
		text = if claimed then "CLAIMED" else props.claimText or "CLAIM",
		palette = "green",
		enabled = not claimed,
		style = props.style,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -pad),
		size = UDim2.new(0.6, 0, 0, FOOTER - pad * 2),
		parent = content,
	})
	button.Instance.Visible = object.revealed
	button.Activated:Connect(function()
		if object.props.claimed or object.destroyed then
			return
		end
		object.Claimed:Fire()
		object.Activated:Fire(object.props.name)
		Kit.runAction(object.props.action, button.Instance)
		object:update({ claimed = true })
	end)
	object.parts:Add(button)
	object.button = button
end

function RewardPanel.new(props: Props)
	local object: any
	object = Base.new({
		className = "Frame",
		name = "RewardPanel",
		props = props,
		size = UDim2.fromOffset(420, 300),
		build = function(self: any)
			if self.revealed == nil then
				self.revealed = self.props.revealed ~= false
				self.Claimed = Signal.new()
			end
			build(self)
		end,
		setup = function(self: any)
			self.trove:Add(function()
				if self.reveal_ then
					self.reveal_.stop()
				end
				self.Claimed:DisconnectAll()
			end)
		end,
	})

	-- Pops the tiles in from the centre out, then shows the claim button.
	function object.reveal(self: any)
		if self.destroyed then
			return
		end
		self.revealed = true
		if self.reveal_ then
			self.reveal_.stop()
		end
		local button = self.button
		if button then
			button.Instance.Visible = false
		end
		self.reveal_ = Extra.UI.stagger(self.tiles, "BadgePop", {
			interval = 0.08,
			order = "center",
			show = true,
			onDone = function()
				if self.destroyed or self.button ~= button or button == nil then
					return
				end
				Extra.UI.show(button.Instance, "PopIn")
			end,
		})
	end

	return object
end

return RewardPanel
