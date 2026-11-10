--!strict
-- Tooltip: a small dark bubble that appears next to a target after a short delay and follows it
-- while shown. It shows on pointer hover and on gamepad selection, and hides when either ends.
--   Tooltip.new({ target = button.Instance, text = "Doubles coins for 10 minutes", side = "top" })
--
-- The bubble is parented to the target's ScreenGui (or `parent`), so it is never clipped by a
-- scrolling frame. Its size comes from approximate text metrics (Core/TextFit), capped at
-- `maxWidth`. `tooltip:show()` / `tooltip:hide()` drive it from code.
--
-- The root is a CanvasGroup so the whole bubble fades as one; the bubble sits inside a small
-- margin because a CanvasGroup clips its outline and shadow at its edge.

local Base = require("./Base")
local Extra = require("./Extra")
local Host = require("../../Visuals/Runtime/Host")
local Kit = require("./Kit")
local Panel = require("./Panel")
local Style = require("../Style/Style")
local Trove = require("../../Util/Trove")
local TextFit = require("../Core/TextFit")

export type Props = {
	text: string?,
	target: GuiObject?,
	side: string?, -- "top" (default) | "bottom" | "left" | "right"
	delay: number?, -- seconds before it shows, default 0.4
	maxWidth: number?, -- pixels at 1x, default 240
	gap: number?, -- pixels between target and bubble, default 8
	style: string?,
	parent: Instance?, -- default: the target's ScreenGui
	name: string?,
	[string]: any,
}

local Tooltip = {}

local PAD = 10
local MARGIN = 8

-- Bubble size for `text` at `textSize`: one line when it fits `maxWidth`, wrapped lines otherwise.
function Tooltip.measure(text: string, textSize: number, maxWidth: number): (number, number)
	local charWidth = textSize * TextFit.CHAR_WIDTH
	local inner = math.max(charWidth, maxWidth - PAD * 2)
	local length = TextFit.length(text) * charWidth
	local lines = math.max(1, math.ceil(length * TextFit.WRAP_SLACK / inner))
	local width = if lines == 1 then length else inner
	return math.ceil(width) + PAD * 2, math.ceil(lines * textSize * TextFit.LINE_HEIGHT) + PAD * 2
end

-- Top-left corner of a bubble of `size` placed on `side` of a target box, with `gap` between.
function Tooltip.place(side: string?, targetPosition: Vector2, targetSize: Vector2, size: Vector2, gap: number): Vector2
	local centre = targetPosition + targetSize / 2
	if side == "bottom" then
		return Vector2.new(centre.X - size.X / 2, targetPosition.Y + targetSize.Y + gap)
	elseif side == "left" then
		return Vector2.new(targetPosition.X - size.X - gap, centre.Y - size.Y / 2)
	elseif side == "right" then
		return Vector2.new(targetPosition.X + targetSize.X + gap, centre.Y - size.Y / 2)
	end
	return Vector2.new(centre.X - size.X / 2, targetPosition.Y - size.Y - gap)
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: CanvasGroup = object.Instance
	local textSize = Style.textSize(style, "caption")
	local width, height = Tooltip.measure(props.text or "", textSize, props.maxWidth or 240)
	root.Size = UDim2.fromOffset(width + MARGIN * 2, height + MARGIN * 2)
	root.ZIndex = 100
	root.Active = false
	root.Visible = object.showing == true
	local bubble = Extra.frame(root, "Bubble", {
		position = UDim2.fromOffset(MARGIN, MARGIN),
		size = UDim2.new(1, -MARGIN * 2, 1, -MARGIN * 2),
	})
	object.parts:Add(bubble)
	local surfaceProps: Panel.SurfaceProps =
		{ surface = "dark", radius = "md", outline = "regular", gloss = false, shadow = true }
	local content = Panel.surface(object, bubble, surfaceProps).content
	Kit.padding(PAD - 4).Parent = content
	Extra.label(object, content, "Text", {
		text = props.text or "",
		role = "caption",
		color = Style.surface(style, "dark").text,
		wrap = true,
		stroke = false,
	})
end

local function reposition(object: any): boolean
	local target: GuiObject? = object.props.target
	local root: CanvasGroup = object.Instance
	local layer = root.Parent
	if target == nil or target.Parent == nil or layer == nil or not layer:IsA("GuiBase2d") then
		return false
	end
	local factor = Kit.scaleFactor(layer)
	local origin = layer.AbsolutePosition
	local size = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
	local corner = Tooltip.place(
		object.props.side,
		(target.AbsolutePosition - origin) / factor,
		target.AbsoluteSize / factor,
		size,
		(object.props.gap or 8) - MARGIN
	)
	-- Keep the bubble on screen.
	local bounds = layer.AbsoluteSize / factor
	local x = math.clamp(corner.X, 4, math.max(4, bounds.X - size.X - 4))
	local y = math.clamp(corner.Y, 4, math.max(4, bounds.Y - size.Y - 4))
	root.Position = UDim2.fromOffset(x, y)
	return true
end

local function cancelPending(object: any)
	if object.pending then
		object.pending()
		object.pending = nil
	end
end

local function hide(object: any)
	cancelPending(object)
	if not object.showing or object.destroyed then
		return
	end
	object.showing = false
	if object.follow then
		object.follow()
		object.follow = nil
	end
	Extra.UI.hide(object.Instance, "FadeOut")
end

local function show(object: any)
	cancelPending(object)
	if object.showing or object.destroyed or (object.props.text or "") == "" then
		return
	end
	local root: CanvasGroup = object.Instance
	if root.Parent == nil then
		local target: GuiObject? = object.props.target
		root.Parent = object.props.parent or (if target then Extra.layer(target) else nil)
	end
	if not reposition(object) then
		return
	end
	object.showing = true
	-- The position is set every frame while shown, so the entrance only fades and scales.
	Extra.UI.show(root, "PopIn", { intensity = 0.4 })
	object.follow = Host.clock:add(function(): boolean?
		if object.destroyed or not object.showing then
			return false
		end
		if not reposition(object) then
			object.follow = nil
			hide(object)
			return false
		end
		return true
	end)
end

local function attach(object: any)
	object.links:Clean()
	local target: GuiObject? = object.props.target
	if target == nil then
		return
	end
	local function enter()
		cancelPending(object)
		object.pending = Host.clock:after(object.props.delay or 0.4, function()
			object.pending = nil
			show(object)
		end)
	end
	local function leave()
		hide(object)
	end
	object.links:Connect(target.MouseEnter, enter)
	object.links:Connect(target.MouseLeave, leave)
	object.links:Connect(target.SelectionGained, enter)
	object.links:Connect(target.SelectionLost, leave)
	object.links:Connect(target.AncestryChanged, function()
		if target.Parent == nil then
			leave()
		end
	end)
end

function Tooltip.new(props: Props)
	local copy = table.clone(props)
	-- The bubble is parented on first show (to the target's ScreenGui unless a parent is given).
	local parent = copy.parent
	copy.parent = nil
	local object = Base.new({
		className = "CanvasGroup",
		name = "Tooltip",
		props = copy,
		build = build,
		setup = function(self: any)
			self.links = Trove.new()
			self.showing = false
			self.Instance.Visible = false
			self.props.parent = parent
			self.trove:Add(function()
				cancelPending(self)
				if self.follow then
					self.follow()
					self.follow = nil
				end
				self.links:Clean()
				Extra.UI.stop(self.Instance, false)
			end)
			attach(self)
		end,
	})
	local update = object.update
	function object.update(self: any, partial: { [string]: any })
		update(self, partial)
		if partial.target ~= nil then
			hide(self)
			attach(self)
		elseif self.showing then
			reposition(self)
		end
	end
	function object.show(self: any)
		show(self)
	end
	function object.hide(self: any)
		hide(self)
	end
	return object
end

return Tooltip
