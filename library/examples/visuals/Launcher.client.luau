--!strict
-- UltimateVisualsKit demo launcher (LocalScript). A small menu on the left starts one demo at a
-- time; every demo is a ModuleScript with `start(parent) -> stop`, so the launcher (and the
-- playground's Demos tab) can start and stop them.
--
-- Serve it with `rojo serve library/examples/visuals/visuals.project.json`; see README.md.
-- Client-side preview code only: the demos fake their "server" locally and grant nothing.
--
-- NOT run in Studio.

local DemoKit = require("./DemoKit")

type Demo = { title: string, description: string, start: (parent: Instance) -> () -> () }

local DEMOS: { Demo } = {
	require("./PetSelectionDemo"),
	require("./EggHatchingDemo"),
	require("./RewardRevealDemo"),
	require("./SimulatorFeedbackDemo"),
	require("./AnimalFeedingDemo"),
	require("./Playground/Playground"),
}

local Visuals = DemoKit.Visuals

DemoKit.bootstrap()

local playerGui = DemoKit.playerGui()
local scope = DemoKit.scope()
local gui = DemoKit.screen(scope, playerGui, "UvkLauncher", 30)
local list = DemoKit.panel(scope, gui, { title = "VISUALS DEMOS", side = "left", width = 240, height = 560 })
local status = DemoKit.text(scope, list, "Pick a demo.", "caption", 90)

local stopCurrent: (() -> ())? = nil

local function stop()
	local running = stopCurrent
	stopCurrent = nil
	if running then
		local ok, err = pcall(running)
		if not ok then
			warn("[UVK demo] stop failed: " .. tostring(err))
		end
	end
end

local function start(demo: Demo)
	stop()
	-- A demo that fails to start reports here instead of taking the launcher down with it.
	local ok, result = pcall(demo.start, playerGui)
	if ok and type(result) == "function" then
		stopCurrent = result
		status:update({ text = demo.title .. ": " .. demo.description })
	else
		status:update({ text = demo.title .. " failed: " .. tostring(result) })
		warn("[UVK demo] " .. demo.title .. " failed to start: " .. tostring(result))
	end
end

for index, demo in DEMOS do
	DemoKit.button(
		scope,
		list,
		string.upper(demo.title),
		if index == #DEMOS then "buy" else "primary",
		index,
		function()
			start(demo)
		end
	)
end
DemoKit.button(scope, list, "STOP DEMO", "danger", 50, function()
	stop()
	status:update({ text = "Stopped. Pick a demo." })
end)

-- Accessibility switches apply to every demo. Reduced motion is set on both UrkUI and Visuals.
DemoKit.toggle(scope, list, "Reduced motion", Visuals.Settings().reducedMotion, 60, function(value: boolean)
	DemoKit.setReducedMotion(value)
end)
DemoKit.toggle(scope, list, "Reduced flashing", Visuals.Settings().reducedFlashing, 61, function(value: boolean)
	Visuals.Configure({ reducedFlashing = value })
end)
