--!strict
-- "Lvl. 3  [=====    ] 40/100": an outlined level label next to a game ProgressBar.
--   local level = LevelBar.new({ level = 3, value = 40, max = 100, palette = "green" })
--   level:update({ value = 55 })

local Base = require("./Base")
local GameText = require("./GameText")
local ProgressBar = require("./ProgressBar")

export type Props = {
	level: number?,
	value: number?,
	max: number?,
	palette: string?,
	prefix: string?, -- default "Lvl. "
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

local LevelBar = {}

local LABEL_SHARE = 0.3

function LevelBar.text(level: number?, prefix: string?): string
	return (prefix or "Lvl. ") .. tostring(math.floor(level or 0))
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	local label = Instance.new("TextLabel")
	label.Name = "Level"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(LABEL_SHARE, 1)
	local options: GameText.TextOptions = { text = LevelBar.text(props.level, props.prefix), role = "heading" }
	options.align = "left"
	GameText.decorate(label, style, options, object.parts)
	label.Parent = root
	object.parts:Add(label)
	object.label = label
	local bar = ProgressBar.new({
		value = props.value,
		max = props.max,
		palette = props.palette or "green",
		showText = true,
		style = props.style,
		anchor = Vector2.new(1, 0.5),
		position = UDim2.fromScale(1, 0.5),
		size = UDim2.new(1 - LABEL_SHARE, -4, 0.8, 0),
		parent = root,
	})
	object.parts:Add(bar)
	object.bar = bar
end

local function apply(object: any, partial: { [string]: any }): boolean
	for key in pairs(partial) do
		if key ~= "value" and key ~= "max" and key ~= "level" then
			return false
		end
	end
	local props = object.props
	if partial.level ~= nil and object.label then
		object.label.Text = LevelBar.text(props.level, props.prefix)
	end
	if partial.value ~= nil or partial.max ~= nil then
		object.bar:update({ value = props.value, max = props.max })
	end
	return true
end

function LevelBar.new(props: Props)
	return Base.new({
		className = "Frame",
		name = "LevelBar",
		props = props,
		size = UDim2.fromOffset(320, 40),
		build = build,
		apply = apply,
	})
end

return LevelBar
