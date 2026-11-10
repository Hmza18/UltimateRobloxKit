--!strict
-- Notification toast: a card with an icon, a title, a line of text and a thin bar that runs down
-- until the toast dismisses itself. It drops in with "ToastIn", leaves with "ToastOut", then fires
-- Closed and destroys itself. Clicking it dismisses it early (and fires Activated).
--   local toast = Notification.new({ kind = "success", title = "QUEST COMPLETE", text = "+500 coins",
--       icon = "check-color", duration = 4, parent = toastStack })
--   toast.Closed:Connect(function() restack() end)
--
-- Stacking is the caller's job: parent toasts to a frame with a UIListLayout, or position them
-- yourself (Core/ToastQueue decides order and limits). `duration = 0` keeps it until dismissed.
-- The root is a CanvasGroup so the whole card fades; the card sits inside a small margin because
-- a CanvasGroup clips the outline and shadow at its edge. Inside a UIListLayout the entrance and
-- exit show their fade and scale; the layout controls position.

local Base = require("./Base")
local Extra = require("./Extra")
local Kit = require("./Kit")
local Motion = require("../../Visuals/Runtime/Motion")
local Panel = require("./Panel")
local Signal = require("../../Util/Signal")
local Style = require("../Style/Style")

export type Props = {
	kind: string?, -- "info" (default) | "success" | "warning" | "error": accent colour
	title: string?,
	text: string?,
	icon: string?,
	image: string?,
	palette: string?, -- overrides the kind's accent
	duration: number?, -- seconds before it dismisses itself, default 4; 0 keeps it
	destroyOnClose: boolean?, -- default true
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

local Notification = {}

local MARGIN = 8
local ACCENTS: { [string]: string } = { info = "blue", success = "green", warning = "orange", error = "red" }

-- Palette name for a toast kind.
function Notification.accent(kind: string?): string
	return ACCENTS[kind or "info"] or ACCENTS.info
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: CanvasGroup = object.Instance
	local accent = props.palette or Notification.accent(props.kind)
	local card = Extra.frame(root, "Card", {
		position = UDim2.fromOffset(MARGIN, MARGIN),
		size = UDim2.new(1, -MARGIN * 2, 1, -MARGIN * 2),
	})
	object.parts:Add(card)
	local surfaceProps: Panel.SurfaceProps =
		{ surface = "dark", radius = "lg", outline = "thick", gloss = false, shadow = true }
	local content = Panel.surface(object, card, surfaceProps).content
	local textColor = Style.surface(style, "dark").text
	local pad = Kit.spacing(style, "sm")

	local badge = Extra.frame(content, "Icon", {
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, pad, 0.5, -2),
		size = UDim2.fromScale(0.62, 0.62),
	})
	badge.SizeConstraint = Enum.SizeConstraint.RelativeYY
	local badgeProps: Panel.SurfaceProps =
		{ palette = accent, radius = "md", outline = "regular", gloss = true, shadow = false }
	local badgeContent = Panel.surface(object, badge, badgeProps).content
	local picture = Extra.image(badgeContent, "Picture", props.icon, props.image, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromScale(0.7, 0.7),
	})
	if picture == nil then
		Extra.label(object, badgeContent, "Mark", { text = "!", role = "heading" })
	end

	local left = math.floor((root.Size.Y.Offset - MARGIN * 2) * 0.62) + pad * 2
	local hasText = props.text ~= nil and props.text ~= ""
	Extra.label(object, content, "Title", { text = props.title or "", role = "label", align = "left" }, {
		position = UDim2.new(0, left, if hasText then 0.1 else 0.25, 0),
		size = UDim2.new(1, -(left + pad), if hasText then 0.4 else 0.5, 0),
	})
	if hasText then
		Extra.label(object, content, "Text", {
			text = props.text,
			role = "caption",
			align = "left",
			color = textColor,
			stroke = false,
		}, { position = UDim2.new(0, left, 0.5, 0), size = UDim2.new(1, -(left + pad), 0.32, 0) })
	end

	-- Time left: a thin bar along the bottom that shrinks to nothing.
	local timer = Instance.new("Frame")
	timer.Name = "Timer"
	timer.BorderSizePixel = 0
	timer.AnchorPoint = Vector2.new(0, 1)
	timer.Position = UDim2.new(0, pad, 1, -4)
	timer.Size = UDim2.new(1, -pad * 2, 0, 4)
	timer.BackgroundColor3 = Color3.fromHex(Style.palette(style, accent).top)
	timer.Visible = (props.duration or 4) > 0
	Kit.corner(2).Parent = timer
	Kit.internal(timer)
	timer.Parent = content
	object.timer = timer
	-- A redraw while the toast is up restarts its countdown on the new bar.
	if object.restart then
		object.restart()
	end
end

local function dismiss(object: any)
	if object.destroyed or object.closing then
		return
	end
	object.closing = true
	if object.timer then
		Motion.stop(object.timer, false)
	end
	Extra.UI.hide(object.Instance, "ToastOut", {
		onDone = function()
			if object.destroyed then
				return
			end
			object.Closed:Fire(object.props.name)
			if object.props.destroyOnClose ~= false then
				object:destroy()
			end
		end,
	})
end

local function countdown(object: any)
	local timer: Frame? = object.timer
	local duration = object.props.duration or 4
	if timer == nil or duration <= 0 then
		return
	end
	local full = timer.Size
	-- The bar is state (time left), so it still runs under reduced motion.
	Motion.tween(timer, { Size = UDim2.new(0, 0, full.Y.Scale, full.Y.Offset) }, {
		duration = duration,
		easing = "linear",
		essential = true,
		onDone = function(completed: boolean)
			if completed then
				dismiss(object)
			end
		end,
	})
end

function Notification.new(props: Props)
	local startHidden = props.visible == false
	local object = Base.new({
		className = "CanvasGroup",
		name = "Notification",
		props = props,
		size = UDim2.fromOffset(320, 84),
		build = build,
		setup = function(self: any)
			self.Closed = Signal.new()
			self.closing = false
			local root: CanvasGroup = self.Instance
			root.Active = true
			self.trove:Connect(root.InputBegan, function(input: InputObject)
				local kind = input.UserInputType
				if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
					self.Activated:Fire(self.props.name)
					Kit.runAction(self.props.action, root)
					dismiss(self)
				end
			end)
			self.trove:Add(function()
				if self.timer then
					Motion.stop(self.timer, false)
				end
				Extra.UI.stop(root, false)
				self.Closed:DisconnectAll()
			end)
		end,
	})

	-- Shows the toast and starts its countdown.
	function object.show(self: any)
		if self.destroyed then
			return
		end
		self.closing = false
		self.restart = function()
			if not self.closing and not self.destroyed then
				countdown(self)
			end
		end
		Extra.UI.show(self.Instance, "ToastIn")
		countdown(self)
	end

	function object.dismiss(self: any)
		dismiss(self)
	end

	if not startHidden then
		object:show()
	end
	return object
end

return Notification
