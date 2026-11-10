--!strict
-- Hotbar slot: an ability icon with a keybind label and a cooldown shown as a dark shade that
-- drains from the top down, with the seconds left on top. When the cooldown ends the slot flashes
-- and bounces to say it is ready.
--   local slot = HotbarSlot.new({ name = "dash", icon = "bolt", keybind = "Q", parent = hotbar })
--   slot.Activated:Connect(function(id) Net.fire("UseAbility", id) end)
--   slot:startCooldown(8)                 -- runs on the shared clock
--   slot:setCooldown(remaining, duration) -- or drive it yourself from a replicated time value
--
-- The sweep is vertical (one resized frame); a radial sweep is not implemented. Activated fires
-- while cooling down too (slot:isReady() tells you), so the game decides what a press means. The
-- cooldown is display only: the server owns the real timer.

local Base = require("./Base")
local Extra = require("./Extra")
local Host = require("../../Visuals/Runtime/Host")
local Kit = require("./Kit")
local Panel = require("./Panel")
local Signal = require("../../Util/Signal")
local UILogic = require("../../Visuals/UI/UILogic")

export type Props = {
	icon: string?,
	image: string?,
	keybind: string?, -- short label such as "Q", "1" or "RT"
	palette: string?, -- default: the dark surface
	enabled: boolean?,
	readyPulse: boolean?, -- flash when the cooldown ends (default true)
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

local HotbarSlot = {}

local function draw(object: any)
	local ratio = UILogic.cooldownRatio(object.remaining, object.duration)
	local shade: Frame? = object.shade
	if shade then
		shade.Size = UDim2.fromScale(1, ratio)
		shade.Visible = ratio > 0
	end
	local text = UILogic.cooldownText(object.remaining)
	if object.timeLabel and object.shownText ~= text then
		object.shownText = text
		object.timeLabel.Text = text
		object.timeLabel.Visible = text ~= ""
	end
	if object.icon then
		object.icon.ImageTransparency = if ratio > 0 or object.props.enabled == false then 0.35 else 0
	end
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: TextButton = object.Instance
	root.Active = props.enabled ~= false
	local radius = Kit.radius(style, "md")
	local surfaceProps: Panel.SurfaceProps = {
		palette = props.palette,
		surface = if props.palette then nil else "dark",
		enabled = props.enabled,
		radiusPixels = radius,
		outline = "thick",
		gloss = props.palette ~= nil,
		shadow = true,
	}
	local content = Panel.surface(object, root, surfaceProps).content
	content.ClipsDescendants = true

	object.icon = Extra.image(content, "Icon", props.icon, props.image, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromScale(0.72, 0.72),
	})

	-- Anchored to the bottom: as the cooldown runs out the shade's top edge sinks.
	local shade = Extra.frame(content, "Cooldown", {
		anchor = Vector2.new(0, 1),
		position = UDim2.fromScale(0, 1),
		size = UDim2.fromScale(1, 0),
		zIndex = 3,
	})
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.4
	Kit.corner(radius).Parent = shade
	object.shade = shade

	object.shownText = nil
	object.timeLabel = Extra.label(object, content, "Time", { text = "", role = "heading" }, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromScale(0.8, 0.5),
		zIndex = 4,
	})

	if props.keybind and props.keybind ~= "" then
		local key = Extra.frame(root, "Keybind", {
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.fromOffset(6, 6),
			size = UDim2.fromOffset(math.max(24, #props.keybind * 10 + 12), 22),
			zIndex = 6,
		})
		object.parts:Add(key)
		local keyProps: Panel.SurfaceProps =
			{ surface = "window", radiusPixels = 7, outline = "regular", gloss = false, shadow = false }
		local keyContent = Panel.surface(object, key, keyProps).content
		Extra.label(object, keyContent, "Text", { text = props.keybind, role = "caption" })
	end
	draw(object)
end

local function stopJob(object: any)
	if object.job then
		object.job()
		object.job = nil
	end
end

local function ready(object: any)
	object.Ready:Fire(object.props.name)
	if object.props.readyPulse ~= false and not object.destroyed then
		Extra.UI.animate(object.Instance, "UpgradePulse", { intensity = 0.7 })
	end
end

function HotbarSlot.new(props: Props)
	local object = Base.new({
		className = "TextButton",
		name = "HotbarSlot",
		props = props,
		size = UDim2.fromOffset(64, 64),
		build = function(self: any)
			if self.remaining == nil then
				self.remaining, self.duration = 0, 0
				self.Ready = Signal.new()
			end
			build(self)
		end,
		setup = function(self: any)
			Extra.wire(self, { style = "Snappy" })
			self.trove:Add(function()
				stopJob(self)
				self.Ready:DisconnectAll()
			end)
		end,
	})

	function object.isReady(self: any): boolean
		return self.remaining <= 0
	end

	-- Shows `remaining` of `duration` seconds. Reaching zero from above plays the ready pulse.
	function object.setCooldown(self: any, remaining: number, duration: number?)
		if self.destroyed then
			return
		end
		local was = self.remaining
		self.remaining = math.max(0, remaining)
		if duration then
			self.duration = math.max(0, duration)
		end
		draw(self)
		if was > 0 and self.remaining <= 0 then
			ready(self)
		end
	end

	-- Counts `duration` seconds down on the shared clock.
	function object.startCooldown(self: any, duration: number)
		if self.destroyed then
			return
		end
		stopJob(self)
		self:setCooldown(duration, duration)
		if duration <= 0 then
			return
		end
		self.job = Host.clock:add(function(dt: number): boolean?
			if self.destroyed then
				return false
			end
			self:setCooldown(self.remaining - dt)
			if self.remaining <= 0 then
				self.job = nil
				return false
			end
			return true
		end)
	end

	-- Ends the cooldown now, without the ready pulse.
	function object.clearCooldown(self: any)
		stopJob(self)
		self.remaining = 0
		draw(self)
	end

	return object
end

return HotbarSlot
