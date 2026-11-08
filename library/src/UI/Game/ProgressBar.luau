--!strict
-- Chunky progress bar: dark outlined track, gradient fill in a palette, optional "value/max" text
-- and segment dividers. Value changes tween the fill (cancelled on destroy) and pulse the bar with
-- the "progress" preset. This is the game-style version; Components/ProgressBar stays the themed one.
--   local bar = ProgressBar.new({ value = 30, max = 100, palette = "green", showText = true })
--   bar:update({ value = 45 })

local Base = require("./Base")
local Format = require("../Core/Format")
local GameText = require("./GameText")
local Kit = require("./Kit")
local Motion = require("../Runtime/Motion")
local Panel = require("./Panel")
local Style = require("../Style/Style")

export type Props = {
	value: number?,
	max: number?,
	palette: string?, -- fill palette, default "green"
	showText: boolean?,
	segments: number?,
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

local ProgressBar = {}

-- Fill ratio in 0..1 (0 when max is not positive).
function ProgressBar.ratio(value: number?, max: number?): number
	local top = max or 1
	if top <= 0 then
		return 0
	end
	return math.clamp((value or 0) / top, 0, 1)
end

function ProgressBar.text(value: number?, max: number?): string
	return Format.number(math.floor(value or 0)) .. "/" .. Format.number(math.floor(max or 1))
end

local function fillSize(ratio: number): UDim2
	return UDim2.fromScale(ratio, 1)
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	local trackProps: Panel.SurfaceProps = {
		surface = "dark",
		radius = "pill",
		outline = "regular",
		gloss = false,
		shadow = false,
	}
	local track = Panel.surface(object, root, trackProps).content
	local ratio = ProgressBar.ratio(props.value, props.max)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.Size = fillSize(ratio)
	fill.Visible = ratio > 0
	fill.ZIndex = 2
	Kit.corner(Kit.radius(style, "pill")).Parent = fill
	local swatch = Style.palette(style, props.palette or "green")
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = Kit.sequence(swatch.top, swatch.bottom)
	gradient.Parent = fill
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BorderSizePixel = 0
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.7
	gloss.Position = UDim2.fromOffset(4, 3)
	gloss.Size = UDim2.new(1, -8, 0.32, 0)
	gloss.ZIndex = 3
	Kit.corner(Kit.radius(style, "pill")).Parent = gloss
	gloss.Parent = fill
	fill.Parent = track
	object.fill = fill

	local segments = math.floor(props.segments or 0)
	for index = 1, segments - 1 do
		local line = Instance.new("Frame")
		line.Name = "Segment"
		line.BorderSizePixel = 0
		line.AnchorPoint = Vector2.new(0.5, 0)
		line.BackgroundColor3 = Color3.fromHex(Style.outlineColor(style))
		line.BackgroundTransparency = 0.4
		line.Position = UDim2.fromScale(index / segments, 0)
		line.Size = UDim2.new(0, 3, 1, 0)
		line.ZIndex = 4
		line.Parent = track
	end

	object.label = nil
	if props.showText then
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = 5
		local options: GameText.TextOptions = { text = ProgressBar.text(props.value, props.max), role = "label" }
		GameText.decorate(label, style, options, object.parts)
		label.Parent = track
		object.label = label
	end
end

local VALUE_KEYS: { [string]: boolean } = { value = true, max = true }

local function apply(object: any, partial: { [string]: any }): boolean
	for key in pairs(partial) do
		if not VALUE_KEYS[key] then
			return false
		end
	end
	local fill: Frame? = object.fill
	if fill == nil then
		return false
	end
	local props = object.props
	local ratio = ProgressBar.ratio(props.value, props.max)
	local grew = ratio > fill.Size.X.Scale
	fill.Visible = true
	Motion.tween(fill, { Size = fillSize(ratio) }, "slow", Enum.EasingStyle.Quint, nil, function()
		fill.Visible = ratio > 0
	end)
	if grew then
		Motion.play(object.Instance, "progress")
	end
	if object.label then
		object.label.Text = ProgressBar.text(props.value, props.max)
	end
	return true
end

function ProgressBar.new(props: Props)
	return Base.new({
		className = "Frame",
		name = "ProgressBar",
		props = props,
		size = UDim2.fromOffset(240, 28),
		build = build,
		apply = apply,
		setup = function(self: any)
			self.trove:Add(function()
				if self.fill then
					Motion.cancel(self.fill)
				end
				Motion.stop(self.Instance)
			end)
		end,
	})
end

return ProgressBar
