--!strict
-- Scales a whole ScreenGui with the screen. Lay UI out at 1280 x 720 and attach a UIScale:
--     local scale, stop = Responsive.attach(screenGui)
-- The scale is clamped so text stays readable on phones and does not balloon on 4K screens.

local Responsive = {}

Responsive.REFERENCE_SIZE = Vector2.new(1280, 720)
Responsive.MIN_SCALE = 0.8
Responsive.MAX_SCALE = 1.4
Responsive.COMPACT_WIDTH = 700 -- viewports narrower than this count as phone-sized

-- The UIScale for a viewport size: the smaller of the width and height ratios, clamped.
function Responsive.scaleFor(viewport: Vector2): number
	if viewport.X <= 0 or viewport.Y <= 0 then
		return 1
	end
	local reference = Responsive.REFERENCE_SIZE
	local scale = math.min(viewport.X / reference.X, viewport.Y / reference.Y)
	return math.clamp(scale, Responsive.MIN_SCALE, Responsive.MAX_SCALE)
end

function Responsive.viewportSize(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Responsive.REFERENCE_SIZE
end

-- True on phone-sized screens, for switching to a simpler layout.
function Responsive.isCompact(): boolean
	return Responsive.viewportSize().X < Responsive.COMPACT_WIDTH
end

-- Adds a UIScale to `gui` and keeps it in step with the viewport, including camera changes.
-- Returns the UIScale and a function that stops the updates.
function Responsive.attach(gui: Instance): (UIScale, () -> ())
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local cameraConnection: RBXScriptConnection? = nil

	local function update()
		scale.Scale = Responsive.scaleFor(Responsive.viewportSize())
	end

	local function watchCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
		update()
	end

	local workspaceConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()

	return scale, function()
		workspaceConnection:Disconnect()
		if cameraConnection then
			cameraConnection:Disconnect()
		end
	end
end

return Responsive
