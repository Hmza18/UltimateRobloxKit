--!strict
-- Small TweenService helpers. Set TweenUtil.reducedMotion = true (for example from a settings
-- toggle) to make every tween finish instantly for players who prefer less motion.

local TweenService = game:GetService("TweenService")

local TweenUtil = { reducedMotion = false }

function TweenUtil.info(duration: number?, style: Enum.EasingStyle?): TweenInfo
	local seconds = if TweenUtil.reducedMotion then 0 else duration or 0.2
	return TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

-- Tweens `goals` (property name -> target value) on `instance` and starts it.
function TweenUtil.play(instance: Instance, goals: { [string]: any }, duration: number?, style: Enum.EasingStyle?)
	local tween = TweenService:Create(instance, TweenUtil.info(duration, style), goals)
	tween:Play()
	return tween
end

-- Fades a GuiObject's background (and text, for text objects) fully in or out, then hides it when out.
function TweenUtil.fade(object: GuiObject, visible: boolean, duration: number?)
	local target = if visible then 0 else 1
	local goals: { [string]: any } = { BackgroundTransparency = target }
	if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		goals.TextTransparency = target
	end
	if visible then
		object.Visible = true
	end
	local tween = TweenUtil.play(object, goals, duration)
	if not visible then
		tween.Completed:Once(function()
			object.Visible = false
		end)
	end
	return tween
end

-- A quick press effect on a UIScale: shrink slightly, then spring back to 1.
function TweenUtil.pop(scale: UIScale)
	if TweenUtil.reducedMotion then
		return
	end
	local shrink = TweenUtil.play(scale, { Scale = 0.92 }, 0.06)
	shrink.Completed:Once(function()
		TweenUtil.play(scale, { Scale = 1 }, 0.18, Enum.EasingStyle.Back)
	end)
end

return TweenUtil
