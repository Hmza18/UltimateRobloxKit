--!strict
-- Quest card: title, description, a progress bar, reward chips and a claim button whose state
-- follows the quest: "active" (button greyed, shows progress), "claimable" (green button that
-- breathes, the card flashes once when it becomes claimable) and "claimed" (done).
--   local quest = QuestCard.new({ name = "hatch10", title = "EGG COLLECTOR", description = "Hatch 10 eggs",
--       value = 4, max = 10, rewards = { { icon = "coin-color", text = "500" }, { icon = "gem-color", text = "5" } } })
--   quest:update({ value = 10 })                        -- becomes claimable at max
--   quest.Claimed:Connect(function(id) Net.fire("ClaimQuest", id) end)
--   quest:update({ state = "claimed" })                 -- after the server confirms
--
-- Without `state`, the card is claimable when value >= max. It never grants anything.

local Base = require("./Base")
local CartoonButton = require("./CartoonButton")
local Extra = require("./Extra")
local Kit = require("./Kit")
local Panel = require("./Panel")
local ProgressBar = require("./ProgressBar")
local Signal = require("../../Util/Signal")
local Style = require("../Style/Style")

export type Chip = { icon: string?, image: string?, text: string }

export type Props = {
	title: string?,
	description: string?,
	value: number?,
	max: number?,
	rewards: { Chip }?, -- at most three are shown
	state: string?, -- "active" | "claimable" | "claimed"; default from value and max
	claimText: string?, -- default "CLAIM"
	palette: string?, -- progress colour, default "green"
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

local QuestCard = {}

local BUTTON_WIDTH = 104

-- "active", "claimable" or "claimed" for props.
function QuestCard.state(props: { [string]: any }): string
	if props.state == "claimed" or props.state == "claimable" or props.state == "active" then
		return props.state
	end
	local max = props.max or 1
	return if max > 0 and (props.value or 0) >= max then "claimable" else "active"
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	local state = QuestCard.state(props)
	object.state = state
	local surfaceProps: Panel.SurfaceProps =
		{ surface = "window", radius = "lg", outline = "thick", gloss = false, pattern = false, shadow = true }
	local content = Panel.surface(object, root, surfaceProps).content
	local textColor = Style.surface(style, "window").text
	local pad = Kit.spacing(style, "md")
	local right = BUTTON_WIDTH + pad * 2

	Extra.label(object, content, "Title", { text = props.title or "", role = "heading", align = "left" }, {
		position = UDim2.fromOffset(pad, pad - 4),
		size = UDim2.new(1, -(right + pad), 0.3, 0),
	})
	Extra.label(object, content, "Description", {
		text = props.description or "",
		role = "caption",
		align = "left",
		color = textColor,
		stroke = false,
	}, { position = UDim2.new(0, pad, 0.34, 0), size = UDim2.new(1, -(right + pad), 0.2, 0) })

	local bar = ProgressBar.new({
		value = props.value,
		max = props.max,
		palette = props.palette or "green",
		showText = true,
		style = props.style,
		anchor = Vector2.new(0, 1),
		position = UDim2.new(0, pad, 1, -pad),
		size = UDim2.new(0.5, -pad, 0.26, 0),
		parent = content,
	})
	object.parts:Add(bar)
	object.bar = bar

	local chips: { Chip } = props.rewards or {}
	local shown = math.min(#chips, 3)
	if shown > 0 then
		local row = Extra.frame(content, "Rewards", {
			anchor = Vector2.new(0, 1),
			position = UDim2.new(0.5, pad, 1, -pad),
			size = UDim2.new(0.5, -(right + pad), 0.26, 0),
		})
		for index = 1, shown do
			local chip = chips[index]
			local cell = Extra.frame(row, "Reward" .. index, {
				position = UDim2.fromScale((index - 1) / shown, 0),
				size = UDim2.fromScale(1 / shown, 1),
			})
			local icon = Extra.image(cell, "Icon", chip.icon, chip.image, {
				anchor = Vector2.new(0, 0.5),
				position = UDim2.fromScale(0, 0.5),
			})
			if icon then
				icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
			end
			Extra.label(object, cell, "Amount", { text = chip.text, role = "caption", align = "left" }, {
				anchor = Vector2.new(1, 0.5),
				position = UDim2.fromScale(1, 0.5),
				size = if icon then UDim2.new(1, -28, 1, 0) else UDim2.fromScale(1, 1),
			})
		end
	end

	local button = CartoonButton.new({
		kind = if state == "claimed" then "neutral" else "buy",
		text = if state == "claimed" then "DONE" else props.claimText or "CLAIM",
		enabled = state == "claimable",
		style = props.style,
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -pad, 0.5, 0),
		size = UDim2.fromOffset(BUTTON_WIDTH, 48),
		parent = content,
	})
	button.Activated:Connect(function()
		if object.destroyed or object.state ~= "claimable" then
			return
		end
		object.Claimed:Fire(object.props.name)
		object.Activated:Fire(object.props.name)
		Kit.runAction(object.props.action, button.Instance)
	end)
	object.parts:Add(button)
	object.button = button
	if state == "claimable" then
		Extra.own(object, Extra.UI.animate(button.Instance, "Pulse"))
	end
end

local function apply(object: any, partial: { [string]: any }): boolean
	for key in pairs(partial) do
		if key ~= "value" and key ~= "max" then
			return false
		end
	end
	-- A value change that changes the state needs the button redrawn.
	if QuestCard.state(object.props) ~= object.state or object.bar == nil then
		return false
	end
	object.bar:update({ value = object.props.value, max = object.props.max })
	return true
end

function QuestCard.new(props: Props)
	local object = Base.new({
		className = "Frame",
		name = "QuestCard",
		props = props,
		size = UDim2.new(1, 0, 0, 104),
		build = function(self: any)
			if self.Claimed == nil then
				self.Claimed = Signal.new()
			end
			local before = self.state
			build(self)
			if before == "active" and self.state == "claimable" then
				Extra.UI.animate(self.Instance, "UpgradePulse", { intensity = 0.4 })
			end
		end,
		apply = apply,
		setup = function(self: any)
			self.trove:Add(function()
				Extra.UI.stop(self.Instance, false)
				self.Claimed:DisconnectAll()
			end)
		end,
	})
	return object
end

return QuestCard
