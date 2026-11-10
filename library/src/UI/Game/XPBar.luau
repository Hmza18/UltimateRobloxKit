--!strict
-- XP bar: a round level badge, an animated fill and optional "40/100" text. `bar:gain(amount)`
-- plays the gain: the fill grows with a highlight flash, and a gain that overflows fills the bar,
-- pops the badge, fires LevelUp(level), empties and carries on into the next level.
--   local xp = XPBar.new({ level = 3, value = 40, max = 100, parent = hud })
--   xp:gain(250)                       -- may cross several levels
--   xp.LevelUp:Connect(function(level) Visuals.UI.popup("LEVEL " .. level, xp.Instance) end)
--
-- `maxForLevel(level)` gives each level's bar size; without it every level uses `max`.
-- `update({ value, max, level })` sets the state directly (tweened, no level-up sequence). The
-- gain is presentation only: award XP on the server and call gain with what it granted.

local Base = require("./Base")
local Extra = require("./Extra")
local Format = require("../Core/Format")
local Kit = require("./Kit")
local Motion = require("../../Visuals/Runtime/Motion")
local Panel = require("./Panel")
local Signal = require("../../Util/Signal")
local Style = require("../Style/Style")
local UILogic = require("../../Visuals/UI/UILogic")

export type Props = {
	level: number?,
	value: number?,
	max: number?,
	palette: string?, -- fill colour, default "blue"
	badgePalette: string?, -- default "gold"
	showText: boolean?, -- default true
	maxForLevel: ((level: number) -> number)?,
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

local XPBar = {}

function XPBar.ratio(value: number?, max: number?): number
	local top = max or 1
	if top <= 0 then
		return 0
	end
	return math.clamp((value or 0) / top, 0, 1)
end

function XPBar.text(value: number?, max: number?): string
	return Format.abbrev(math.floor(value or 0)) .. "/" .. Format.abbrev(math.floor(max or 1))
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	local height = root.Size.Y.Offset
	if typeof(props.size) == "UDim2" then
		height = props.size.Y.Offset
	end
	local badgeSize = math.max(Extra.MIN_TOUCH, height)

	local holder = Extra.frame(root, "Track", {
		anchor = Vector2.new(1, 0.5),
		position = UDim2.fromScale(1, 0.5),
		size = UDim2.new(1, -math.floor(badgeSize * 0.6), 0.72, 0),
	})
	object.parts:Add(holder)
	object.track = holder
	local trackProps: Panel.SurfaceProps =
		{ surface = "dark", radius = "pill", outline = "regular", gloss = false, shadow = false }
	local track = Panel.surface(object, holder, trackProps).content

	local ratio = XPBar.ratio(props.value, props.max)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.ZIndex = 2
	Kit.corner(Kit.radius(style, "pill")).Parent = fill
	local swatch = Style.palette(style, props.palette or "blue")
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = Kit.sequence(swatch.top, swatch.bottom)
	gradient.Parent = fill
	fill.Parent = track
	object.fill = fill

	object.text = nil
	if props.showText ~= false then
		object.text = Extra.label(
			object,
			track,
			"Text",
			{
				text = XPBar.text(props.value, props.max),
				role = "caption",
			},
			{
				zIndex = 5,
				position = UDim2.fromOffset(math.floor(badgeSize * 0.2), 0),
				size = UDim2.new(1, -math.floor(badgeSize * 0.2), 1, 0),
			}
		)
	end

	local badge = Extra.frame(root, "Badge", {
		anchor = Vector2.new(0, 0.5),
		position = UDim2.fromScale(0, 0.5),
		size = UDim2.fromOffset(badgeSize, badgeSize),
		zIndex = 6,
	})
	object.parts:Add(badge)
	object.badge = badge
	local badgeProps: Panel.SurfaceProps = {
		palette = props.badgePalette or "gold",
		radiusPixels = math.floor(badgeSize / 2),
		outline = "thick",
		gloss = true,
		shadow = true,
	}
	local badgeContent = Panel.surface(object, badge, badgeProps).content
	object.levelLabel = Extra.label(object, badgeContent, "Level", {
		text = tostring(math.floor(props.level or 1)),
		role = "heading",
	}, { anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.48), size = UDim2.fromScale(0.74, 0.7) })
end

local function setText(object: any, value: number, max: number)
	if object.text then
		object.text.Text = XPBar.text(value, max)
	end
end

local function fillTo(object: any, ratio: number, duration: number, onDone: ((completed: boolean) -> ())?)
	local fill: Frame? = object.fill
	if fill == nil then
		if onDone then
			onDone(false)
		end
		return
	end
	-- The fill shows state, so it still animates under reduced motion.
	Motion.tween(fill, { Size = UDim2.fromScale(ratio, 1) }, {
		duration = duration,
		easing = "cubicOut",
		essential = true,
		onDone = onDone,
	})
end

local function showLevel(object: any, level: number, celebrate: boolean)
	if object.levelLabel then
		object.levelLabel.Text = tostring(math.floor(level))
	end
	if celebrate and object.badge then
		Extra.UI.animate(object.badge, "UpgradePulse")
	end
end

local VALUE_KEYS: { [string]: boolean } = { value = true, max = true, level = true, maxForLevel = true }

local function apply(object: any, partial: { [string]: any }): boolean
	for key in pairs(partial) do
		if not VALUE_KEYS[key] then
			return false
		end
	end
	if object.fill == nil then
		return false
	end
	object.run += 1
	local props = object.props
	local ratio = XPBar.ratio(props.value, props.max)
	local grew = ratio > object.fill.Size.X.Scale
	fillTo(object, ratio, 0.35)
	setText(object, props.value or 0, props.max or 1)
	if grew and object.track then
		Extra.UI.animate(object.track, "Highlight")
	end
	if partial.level ~= nil then
		showLevel(object, props.level or 1, true)
	end
	return true
end

function XPBar.new(props: Props)
	local object = Base.new({
		className = "Frame",
		name = "XPBar",
		props = props,
		size = UDim2.fromOffset(320, 44),
		build = build,
		apply = apply,
		setup = function(self: any)
			self.run = 0
			self.LevelUp = Signal.new()
			self.trove:Add(function()
				self.run += 1
				if self.fill then
					Motion.stop(self.fill, false)
				end
				self.LevelUp:DisconnectAll()
			end)
		end,
	})

	-- Plays an XP gain, crossing as many levels as it covers. Props end at the new state.
	function object.gain(self: any, amount: number)
		if self.destroyed or amount <= 0 then
			return
		end
		local p = self.props
		local plan = UILogic.xpPlan(p.level or 1, p.value or 0, p.max or 1, amount, p.maxForLevel)
		p.level, p.value, p.max = plan.level, plan.value, plan.max
		self.run += 1
		local run = self.run
		if self.track then
			Extra.UI.animate(self.track, "Highlight")
		end
		local index = 0
		local function nextSegment()
			index += 1
			local segment = plan.segments[index]
			if segment == nil or self.destroyed or self.run ~= run then
				return
			end
			local share = (segment.to - segment.from) / segment.max
			setText(self, segment.to, segment.max)
			fillTo(self, segment.to / segment.max, 0.2 + 0.4 * share, function(completed: boolean)
				if not completed or self.destroyed or self.run ~= run then
					return
				end
				if segment.levelUp then
					local level = segment.level + 1
					showLevel(self, level, true)
					self.LevelUp:Fire(level)
					local following = plan.segments[index + 1]
					local max = if following then following.max else plan.max
					if self.fill then
						Motion.tween(self.fill, { Size = UDim2.fromScale(0, 1) }, { duration = 0, essential = true })
					end
					setText(self, 0, max)
				end
				nextSegment()
			end)
		end
		nextSegment()
	end

	return object
end

return XPBar
