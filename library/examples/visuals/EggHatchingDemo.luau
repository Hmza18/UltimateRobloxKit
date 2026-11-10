--!strict
-- Demo 2: egg hatching.
--
-- An egg stand with buttons for a single Common, Rare, Legendary and Mythic hatch, a triple
-- hatch, an eight-egg multi hatch and an auto-hatch toggle. Every hatch goes through
-- Visuals.Eggs.hatch with the rarity the button names; results are logged when the hatch ends.
-- Click, tap, Enter or gamepad A skips to the result; pressing again dismisses it.
--
-- Public APIs used: Visuals.Eggs.hatch / idle / demoEgg, Visuals.Attach, UrkUI.Game.
--
-- NOT run in Studio.

local DemoKit = require("./DemoKit")
local DemoLogic = require("./DemoLogic")

local Visuals = DemoKit.Visuals

local EggHatchingDemo = {}

EggHatchingDemo.title = "Egg hatching"
EggHatchingDemo.description = "Single, triple, multi and auto hatches at chosen rarities."

local SINGLES = { "Common", "Rare", "Legendary", "Mythic" }
local PALETTES: { [string]: string } = { Common = "neutral", Rare = "@blue", Legendary = "@gold", Mythic = "@purple" }

function EggHatchingDemo.start(parent: Instance): () -> ()
	DemoKit.bootstrap()
	local scope = DemoKit.scope()
	local gui = DemoKit.screen(scope, parent, "EggHatchingDemo")
	local stage = DemoKit.stage(scope, "EggStandStage", DemoKit.origin(20), DemoKit.color("#FFC53D"), 6)
	local list = DemoKit.panel(scope, gui, { title = "EGG HATCHING", height = 560, width = 260 })
	local log = DemoKit.log(scope, list, 8, 30)

	-- The stand: a short pedestal with a display egg that sways.
	DemoKit.part(
		stage.folder,
		"Pedestal",
		Vector3.new(1.4, 3, 3),
		stage.top * CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)),
		DemoKit.color("#FFE9A8"),
		Enum.PartType.Cylinder
	)
	local displayEgg: Model = Visuals.Eggs.demoEgg("#FFF4D6")
	displayEgg:PivotTo(stage.top * CFrame.new(0, 1.4, 0))
	displayEgg.Parent = stage.folder
	scope.add(Visuals.Eggs.idle(displayEgg))
	scope.add(Visuals.Attach("ChestGlow", displayEgg, { owner = stage.folder }))

	local current: any = nil
	local auto = false
	local hatchCount = 0

	-- STAND-IN FOR THE SERVER. A real game asks the server to open the eggs; the server rolls,
	-- saves the pets and replies with the results, and only then does the client call
	-- Visuals.Eggs.hatch. Here the "results" come from DemoLogic and nothing is granted.
	local function fakeServerOpen(count: number, rarity: string?): { DemoLogic.EggEntry }
		hatchCount += 1
		return DemoLogic.eggBatch(count, rarity, hatchCount * 13)
	end

	local function describe(results: { any }): string
		local parts: { string } = {}
		for _, result in results do
			table.insert(
				parts,
				string.format("%s (%s)%s", result.name or "?", result.rarity, if result.isNew then " NEW" else "")
			)
		end
		return table.concat(parts, ", ")
	end

	local function busy(): boolean
		if current ~= nil and current:isRunning() then
			log("a hatch is already running (click to skip it)")
			return true
		end
		return false
	end

	local function hatch(count: number, rarity: string?)
		if busy() then
			return
		end
		local eggs = fakeServerOpen(count, rarity)
		log(string.format("hatch x%d %s", count, rarity or "(rolled)"))
		local running = Visuals.Eggs.hatch({ eggs = eggs })
		current = running
		running.Revealed:Connect(function(index: number, entry: any)
			log(string.format("  revealed #%d %s", index, tostring(entry.rarity)))
		end)
		running.Completed:Connect(function(results: { any }, skipped: boolean)
			log((if skipped then "skipped: " else "done: ") .. describe(results))
			if current == running then
				current = nil
			end
		end)
	end

	local function startAuto()
		if busy() then
			return false
		end
		local running = Visuals.Eggs.hatch({
			eggs = fakeServerOpen(3, nil),
			mode = "auto",
			next = function(): { DemoLogic.EggEntry }?
				-- Asked after every batch; nil ends auto-hatch.
				return if auto then fakeServerOpen(3, nil) else nil
			end,
		})
		current = running
		running.BatchCompleted:Connect(function(results: { any })
			log("auto: " .. describe(results))
		end)
		running.Completed:Connect(function(results: { any })
			log(string.format("auto-hatch ended after %d pets", #results))
			if current == running then
				current = nil
			end
		end)
		return true
	end

	for index, rarity in SINGLES do
		DemoKit.button(scope, list, rarity:upper() .. " EGG", PALETTES[rarity], index, function()
			hatch(1, rarity)
		end)
	end
	DemoKit.button(scope, list, "TRIPLE HATCH", "buy", 10, function()
		hatch(3, nil)
	end)
	DemoKit.button(scope, list, "MULTI HATCH x8", "buy", 11, function()
		hatch(8, nil)
	end)
	local autoToggle: any = nil
	autoToggle = DemoKit.toggle(scope, list, "Auto-hatch", false, 12, function(value: boolean)
		auto = value
		if value then
			if not startAuto() then
				auto = false
				autoToggle:set(false, true)
			end
		elseif current then
			-- stop() ends auto mode after removing the batch on screen.
			current.stop()
		end
	end)
	DemoKit.text(scope, list, "Click, tap, Enter or gamepad A skips to the result.", "caption", 13)

	scope.add(function()
		auto = false
		if current then
			current.cancel()
			current = nil
		end
	end)
	return scope.clean
end

return EggHatchingDemo
