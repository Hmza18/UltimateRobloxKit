--!strict
-- Tutorial screen: coach marks. Each step dims the screen except for a cutout around its
-- target (four dim frames around a hole, from ScreensLogic.cutout), shows a bubble with the
-- step's text beside it, and offers Next and Skip. A step's target is a GuiObject, a rectangle
-- { x, y, w, h } in screen pixels, or nothing (the bubble sits in the middle, fully dimmed).
--
-- The dim frames swallow clicks, so only the highlighted control can be used.
--
-- NOT run in Studio: see README.md.

local Motion = require("../Runtime/Motion")
local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local UI = ScreenKit.UI
local Game = ScreenKit.Game

local BUBBLE = { x = 300, y = 170 }
local SIDES = { "top", "bottom", "left", "right" }

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local root = shell.root
	local dims: { [string]: TextButton } = {}
	for _, side in ipairs(SIDES) do
		local dim = Instance.new("TextButton")
		dim.Name = "Dim_" .. side
		dim.Text = ""
		dim.AutoButtonColor = false
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = 0.45
		dim.BorderSizePixel = 0
		dim.Selectable = false
		dim.Parent = root
		dims[side] = dim
	end
	-- A ring around the hole that breathes, so the eye lands on the target.
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.Parent = root
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Parent = ring
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = ring

	local bubble = shell:own(Game.Panel.new({
		style = shell.styleName,
		parent = root,
		name = "Bubble",
		surface = "window",
		padding = "sm",
		size = UDim2.fromOffset(BUBBLE.x, BUBBLE.y),
	}))
	bubble.Instance.ZIndex = 5
	local inner: Instance = bubble.Content or bubble.Instance
	local ink = ScreenKit.ink(shell.style, "window", "left")
	local title = shell:text(
		inner,
		"",
		"label",
		{ color = ink.color, stroke = false, align = "left", size = UDim2.new(1, 0, 0, 26) }
	)
	local body = shell:text(inner, "", "caption", {
		color = ink.color,
		stroke = false,
		align = "left",
		wrap = true,
		size = UDim2.new(1, 0, 1, -(26 + 52)),
		position = UDim2.fromOffset(0, 28),
	})
	local skip = shell:button(inner, {
		name = "Skip",
		kind = "neutral",
		text = props.skipText,
		anchor = Vector2.new(0, 1),
		position = UDim2.fromScale(0, 1),
		size = UDim2.new(0.42, 0, 0, 44),
	})
	local nextButton = shell:button(inner, {
		name = "Next",
		kind = "primary",
		text = props.nextText,
		anchor = Vector2.new(1, 1),
		position = UDim2.fromScale(1, 1),
		size = UDim2.new(0.54, 0, 0, 44),
	})

	local index = math.max(1, math.floor(props.step))
	local pulse: any = nil

	local function steps(): { any }
		return shell.props.steps
	end

	-- The step's target in root-relative pixels, or nil.
	local function targetRect(step: any): ScreensLogic.Rect?
		local target = step.target
		if typeof(target) == "Instance" and target:IsA("GuiObject") and target.Parent ~= nil then
			local position = target.AbsolutePosition - root.AbsolutePosition
			return { x = position.X, y = position.Y, w = target.AbsoluteSize.X, h = target.AbsoluteSize.Y }
		elseif type(target) == "table" and type(target.x) == "number" then
			local offset = root.AbsolutePosition
			return { x = target.x - offset.X, y = target.y - offset.Y, w = target.w or 0, h = target.h or 0 }
		end
		return nil
	end

	local function place(animate: boolean)
		local step = steps()[index]
		if step == nil then
			return
		end
		local size = root.AbsoluteSize
		local bounds: ScreensLogic.Rect = { x = 0, y = 0, w = size.X, h = size.Y }
		local bubbleSize = { x = math.min(BUBBLE.x, bounds.w - 16), y = BUBBLE.y }
		local target = targetRect(step)
		-- No target: a hole of no size in the middle, so the whole screen is dimmed.
		local hole = target or { x = bounds.w / 2, y = bounds.h / 2 - bubbleSize.y / 2, w = 0, h = 0 }
		local cut = ScreensLogic.cutout(bounds, hole, if target then step.padding or 8 else 0)
		local options = { duration = 0.25, easing = "cubicOut" }
		for _, side in ipairs(SIDES) do
			local rect: ScreensLogic.Rect = (cut :: any)[side]
			local goals = { Position = UDim2.fromOffset(rect.x, rect.y), Size = UDim2.fromOffset(rect.w, rect.h) }
			if animate then
				Motion.tween(dims[side], goals, options)
			else
				dims[side].Position = goals.Position
				dims[side].Size = goals.Size
			end
		end
		ring.Visible = target ~= nil
		ScreenKit.rect(ring, cut.hole)
		local spot = ScreensLogic.coachMark(bounds, cut.hole, bubbleSize)
		bubble.Instance.Size = UDim2.fromOffset(spot.w, spot.h)
		bubble.Instance.Position = UDim2.fromOffset(spot.x, spot.y)
	end

	local function show(animate: boolean)
		local list = steps()
		index = math.clamp(index, 1, math.max(1, #list))
		local step = list[index]
		if step == nil then
			return
		end
		title:update({ text = tostring(step.title or string.format("Step %d of %d", index, #list)) })
		body:update({ text = tostring(step.text or "") })
		nextButton:update({ text = if index >= #list then shell.props.doneText else shell.props.nextText })
		skip:update({ visible = index < #list })
		place(animate)
		if animate then
			UI.animate(bubble.Instance, "PopIn")
		end
	end

	local function finish(skipped: boolean)
		shell:fire(if skipped then "Skipped" else "Completed", index)
		shell:close()
	end

	shell.trove:Add(nextButton.Activated:Connect(function()
		if index >= #steps() then
			finish(false)
			return
		end
		index += 1
		shell.props.step = index
		show(true)
		shell:fire("StepChanged", index)
	end))
	shell.trove:Add(skip.Activated:Connect(function()
		finish(true)
	end))
	for _, dim in pairs(dims) do
		shell.trove:Add(dim)
	end
	shell.trove:Add(ring)
	shell.trove:Add(function()
		if pulse ~= nil then
			pulse.stop(false)
		end
	end)

	shell:onLayout(function(_env: ScreensLogic.Env)
		place(false)
	end)
	show(false)
	shell:focusables({ nextButton.Instance, skip.Instance })
	shell.onOpened = function()
		show(false)
		UI.animate(bubble.Instance, "PopIn")
		if pulse == nil then
			pulse = UI.animate(ring, "Pulse")
		end
	end
	shell.onClosed = function()
		if pulse ~= nil then
			pulse.stop(true)
			pulse = nil
		end
	end

	return {
		update = function(partial: { [string]: any })
			if partial.step ~= nil then
				index = math.max(1, math.floor(partial.step))
			end
			show(partial.step ~= nil and shell:isOpen())
		end,
		methods = {
			step = function(): number
				return index
			end,
			-- Re-reads the target's position (call it after the highlighted control moved).
			refresh = function()
				place(false)
			end,
		},
	}
end
