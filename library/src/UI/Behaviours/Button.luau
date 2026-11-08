--!strict
-- UrkButton: hover / press / gamepad-selection feedback through a UIScale, optional themed
-- Variant with hover and pressed colours, hover and click sounds, a tooltip, a cooldown, and an
-- Action string run through the action registry.

local Motion = require("../Runtime/Motion")
local Sounds = require("../Runtime/Sounds")

local Button = {}

Button.tags = { "UrkButton" }

function Button.bind(context: any, _tag: string, instance: Instance, trove: any, values: { [string]: any })
	if not instance:IsA("GuiButton") then
		warn("[UrkUI] UrkButton must be on a TextButton or ImageButton: " .. instance:GetFullName())
		return
	end
	local button = instance :: GuiButton
	local scale = Motion.scaleOf(button)
	local hovered = false
	local pressed = false
	local lastActivated = -math.huge
	local sounds = context.config.sounds or {}
	local skin = if values.Variant then context.theme:variant(values.Variant) else nil

	local function paint()
		if skin == nil then
			return
		end
		local state = if pressed then ":pressed" elseif hovered then ":hover" else ""
		local theme = context.theme
		theme:apply(button, skin)
		if skin.Role and skin.TransparencyRole == nil then
			button.BackgroundColor3 = theme:color(skin.Role .. state)
		end
	end

	local function refresh()
		local target = if pressed then values.PressScale elseif hovered then values.HoverScale else 1
		Motion.tween(scale, { Scale = target }, "fast", Enum.EasingStyle.Quad)
		paint()
	end

	if skin then
		button.AutoButtonColor = false
		trove:Add(context.theme:watch(function()
			paint()
		end))
	end

	local function enter()
		if not hovered then
			hovered = true
			Sounds.play(values.HoverSound or sounds.hover, 0.6)
			refresh()
		end
	end

	local function leave()
		hovered = false
		pressed = false
		refresh()
	end

	trove:Connect(button.MouseEnter, enter)
	trove:Connect(button.MouseLeave, leave)
	trove:Connect(button.SelectionGained, enter)
	trove:Connect(button.SelectionLost, leave)
	trove:Connect(button.MouseButton1Down, function()
		pressed = true
		refresh()
	end)
	trove:Connect(button.MouseButton1Up, function()
		pressed = false
		refresh()
	end)
	trove:Connect(button.Activated, function()
		local now = os.clock()
		if now - lastActivated < (values.Cooldown or 0) then
			return
		end
		lastActivated = now
		Sounds.play(values.ClickSound or sounds.click)
		if values.Action then
			context.actions:run(values.Action, button, values.Target)
		end
	end)

	if values.Tooltip or values.TooltipKey then
		local function getTooltip(): string?
			if values.TooltipKey then
				return context.localize:t(values.TooltipKey)
			end
			return values.Tooltip
		end
		context.tooltip:attach(button, getTooltip, nil, trove)
	end

	trove:Add(function()
		scale.Scale = 1
	end)
end

return Button
