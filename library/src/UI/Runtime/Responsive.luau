--!strict
-- Watches the viewport and input devices, classifies the current breakpoint with
-- Core/Breakpoints, and keeps UIScale objects in sync. Event-driven: it recomputes only when the
-- camera viewport, the camera itself, or the last input type changes.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Breakpoints = require("../Core/Breakpoints")
local Signal = require("../../Util/Signal")

export type Config = { thresholds: Breakpoints.Thresholds?, scale: Breakpoints.ScaleOptions? }

local Responsive = {}

local GAMEPADS: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
}

function Responsive.new(config: Config?)
	local cfg: Config = config or {}
	local responsive = {}
	responsive.Changed = Signal.new()
	responsive.breakpoint = "desktop"
	responsive.scale = 1
	responsive.viewport = Vector2.new(0, 0)
	local userScale = 1
	local scales: { [UIScale]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local connections: { RBXScriptConnection } = {}
	local cameraConnection: RBXScriptConnection? = nil

	local function inputState(): Breakpoints.InputState
		local lastInput = UserInputService:GetLastInputType()
		return {
			touch = UserInputService.TouchEnabled,
			keyboard = UserInputService.KeyboardEnabled,
			gamepad = GAMEPADS[lastInput] == true,
			tenFoot = GuiService:IsTenFootInterface(),
		}
	end

	local function recompute()
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(0, 0)
		local size = { x = viewport.X, y = viewport.Y }
		local breakpoint = Breakpoints.classify(size, inputState(), cfg.thresholds)
		local scaleOptions: Breakpoints.ScaleOptions = table.clone(cfg.scale or {})
		scaleOptions.userScale = userScale
		local scale = Breakpoints.scale(size, breakpoint, scaleOptions)
		local changed = breakpoint ~= responsive.breakpoint or math.abs(scale - responsive.scale) > 1e-3
		responsive.viewport = viewport
		responsive.breakpoint = breakpoint
		responsive.scale = scale
		for uiScale in scales do
			uiScale.Scale = scale
		end
		if changed then
			responsive.Changed:Fire(breakpoint, scale)
		end
	end

	local function watchCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(recompute)
		end
		recompute()
	end

	table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera))
	table.insert(connections, UserInputService.LastInputTypeChanged:Connect(recompute))
	watchCamera()

	-- Keeps `uiScale.Scale` equal to the breakpoint scale until the UIScale is destroyed.
	function responsive.manage(_self: any, uiScale: UIScale)
		scales[uiScale] = true
		uiScale.Scale = responsive.scale
	end

	function responsive.unmanage(_self: any, uiScale: UIScale)
		scales[uiScale] = nil
	end

	-- Accessibility multiplier from settings (1 = default).
	function responsive.setUserScale(_self: any, value: number)
		userScale = math.clamp(value, 0.5, 2)
		recompute()
	end

	-- The safe area insets in pixels from GuiService:GetGuiInset (top bar and device cut-outs).
	function responsive.insets(_self: any): { top: number, left: number, right: number, bottom: number }
		local topLeft, bottomRight = GuiService:GetGuiInset()
		return { top = topLeft.Y, left = topLeft.X, right = bottomRight.X, bottom = bottomRight.Y }
	end

	function responsive.destroy(_self: any)
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		responsive.Changed:DisconnectAll()
	end

	return responsive
end

return Responsive
