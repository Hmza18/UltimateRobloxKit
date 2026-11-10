--!strict
-- The shared runtime for the visuals kit: one Clock stepped from the frame signal (connected only
-- while something is running), one motion Engine bound to Roblox properties, the effect manager,
-- and the settings every module reads (quality level, reduced motion, intensity).
--
-- Modules never connect to RenderStepped themselves; they add jobs to Host.clock.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Clock = require("../Core/Clock")
local Effects = require("../Core/Effects")
local Engine = require("../Core/Engine")
local Props = require("./Props")
local Quality = require("../Core/Quality")
local Signal = require("../../Util/Signal")

local Host = {}

local clock = Clock.new()
clock.onError = function(message: string)
	warn(message)
end

local connection: RBXScriptConnection? = nil
local lastFrame = 1 / 60

local function frame(dt: number)
	lastFrame = dt
	clock:step(dt)
end

clock.onActive = function(active: boolean)
	if active and connection == nil then
		if RunService:IsClient() then
			connection = RunService.RenderStepped:Connect(frame)
		else
			connection = RunService.Heartbeat:Connect(frame)
		end
	elseif not active and connection then
		connection:Disconnect()
		connection = nil
	end
end

local settings: Quality.Settings = Quality.defaults()
local explicitLevel = false
local adaptive: Quality.Adaptive? = nil
local adaptiveConnection: RBXScriptConnection? = nil

Host.clock = clock
Host.engine = Engine.new(Props.adapter, clock)
-- Fires with the new settings whenever quality, reduced motion or intensity change.
Host.Changed = Signal.new()

local function cameraPosition(): Effects.Position?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local p = camera.CFrame.Position
	return { p.X, p.Y, p.Z }
end

local function onScreen(position: Effects.Position): boolean
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return true
	end
	local point, visible = camera:WorldToViewportPoint(Vector3.new(position[1], position[2], position[3]))
	if visible then
		return true
	end
	-- Keep effects just outside the frame: their particles usually drift into view.
	local size = camera.ViewportSize
	local margin = 0.35
	return point.Z > 0
		and point.X > -size.X * margin
		and point.X < size.X * (1 + margin)
		and point.Y > -size.Y * margin
		and point.Y < size.Y * (1 + margin)
end

Host.effects = Effects.new({
	clock = clock,
	profile = function(): Quality.Profile
		return Quality.profile(settings.level)
	end,
	viewer = cameraPosition,
	visible = onScreen,
})

function Host.settings(): Quality.Settings
	return table.clone(settings)
end

function Host.profile(): Quality.Profile
	return Quality.profile(settings.level)
end

-- Multiplier for shake / punch / particle amounts under the current settings.
function Host.juice(kind: ("shake" | "scale" | "particles")?): number
	return Quality.juice(settings, kind)
end

function Host.frameTime(): number
	return lastFrame
end

local function device(): Quality.Device
	local level: number? = nil
	local ok, saved = pcall(function(): number
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	if ok and type(saved) == "number" and saved > 0 then
		level = saved
	end
	return {
		touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
		gamepad = UserInputService.GamepadEnabled,
		graphicsLevel = level,
	}
end

local function stopAdaptive()
	if adaptiveConnection then
		adaptiveConnection:Disconnect()
		adaptiveConnection = nil
	end
	adaptive = nil
end

local function startAdaptive()
	if adaptiveConnection or not RunService:IsClient() then
		return
	end
	adaptive = Quality.adaptive(settings.level, settings.level)
	-- Adaptive quality needs frame times even while no effect runs; this is the one always-on
	-- connection in the kit and it does a few arithmetic operations per frame.
	adaptiveConnection = RunService.RenderStepped:Connect(function(dt: number)
		local state = adaptive
		if state == nil then
			return
		end
		local changed = Quality.adapt(state, dt)
		if changed then
			settings.level = changed :: any
			Host.Changed:Fire(Host.settings())
		end
	end)
end

-- Applies settings: { level, adaptive, reducedMotion, reducedFlashing, intensity }. An explicit
-- level is kept as the adaptive ceiling: quality may step down under load and back up to it.
function Host.configure(partial: { [string]: any }?)
	if partial and Quality.isLevel(partial.level) then
		explicitLevel = true
	end
	settings = Quality.merge(settings, partial)
	Host.engine.reducedMotion = settings.reducedMotion
	stopAdaptive()
	if settings.adaptive then
		startAdaptive()
	end
	Host.Changed:Fire(Host.settings())
end

-- Chooses a starting level from the device unless one was set explicitly. Called once by Visuals.
function Host.detect()
	if not explicitLevel then
		settings.level = Quality.choose(device())
	end
	Host.engine.reducedMotion = settings.reducedMotion
	if settings.adaptive then
		stopAdaptive()
		startAdaptive()
	end
end

-- True when the frame loop is connected (something is animating).
function Host.isRunning(): boolean
	return connection ~= nil
end

return Host
