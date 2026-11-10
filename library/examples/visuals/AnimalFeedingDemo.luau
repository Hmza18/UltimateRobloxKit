--!strict
-- Demo 5: feeding animals.
--
-- Two original blocky demo animals idle on a stage. Pick a food from the tray and it is thrown:
-- a short wind-up (anticipation), a ballistic arc computed by DemoLogic.arc, a FoodTrail on the
-- projectile, FoodSplat and CrumbBurst at impact, then the animal reacts: a squash-and-stretch
-- "Interact", a HappyReaction and a HeartBurst. Its hunger and happiness bars animate, a popup
-- shows the reward and coins fly to the counter. Every fourth throw (or the "aim wide" toggle)
-- misses: the food lands on the ground with a splat and a dust puff.
--
-- Public APIs used: Visuals.Feedback.fire("FeedAnimal"), Visuals.Play / Attach,
-- Visuals.Objects.animate, Visuals.Pets.play, Visuals.UI.popup / flyTo / countTo,
-- UrkUI.Game (Panel, ProgressBar, GameText, CartoonButton, Toggle, RewardPopup).
--
-- NOT run in Studio.

local RunService = game:GetService("RunService")

local DemoKit = require("./DemoKit")
local DemoLogic = require("./DemoLogic")

local Visuals = DemoKit.Visuals
local Game = DemoKit.Game

local AnimalFeedingDemo = {}

AnimalFeedingDemo.title = "Animal feeding"
AnimalFeedingDemo.description = "Throw food in an arc; animals react, bars fill, coins fly."

local WIND_UP = 0.22
local APEX = 4.5

type Pen = {
	data: DemoLogic.Animal,
	model: Model,
	mouth: Vector3,
	needs: DemoLogic.Needs,
	hungerBar: any,
	happyBar: any,
	shownHunger: number,
	shownHappy: number,
	idle: any,
	reacting: boolean,
	celebrated: boolean,
}

type Throw = {
	part: BasePart,
	food: DemoLogic.Food,
	pen: Pen,
	start: DemoLogic.Vec3,
	landing: DemoLogic.Vec3,
	miss: boolean,
	arc: DemoLogic.Arc?,
	time: number,
	trail: any,
}

function AnimalFeedingDemo.start(parent: Instance): () -> ()
	DemoKit.bootstrap()
	local scope = DemoKit.scope()
	local gui = DemoKit.screen(scope, parent, "AnimalFeedingDemo")
	local stage = DemoKit.stage(scope, "FeedingStage", DemoKit.origin(22), DemoKit.color("#FF8A3D"), 8)
	local list = DemoKit.panel(scope, gui, { title = "FEEDING", height = 470, width = 260 })
	local log = DemoKit.log(scope, list, 5, 30)
	local groundY = stage.top.Position.Y

	local state = { coins = 0, throws = 0, target = 1, wide = false }
	local _, coinLabel = DemoKit.counter(scope, gui, "Coins", DemoKit.color("#FFD43B"), UDim2.new(0.5, 0, 0, 12))

	-- The food tray at the front of the stage, with one of each food on it.
	local trayCFrame = stage.top * CFrame.new(0, 0.5, -stage.radius + 1.2)
	DemoKit.part(stage.folder, "Tray", Vector3.new(5, 0.3, 1.8), trayCFrame, DemoKit.color("#B9825A"))
	for index, food in DemoLogic.foods() do
		local display = DemoKit.food(
			stage.folder,
			trayCFrame * CFrame.new((index - 2) * 1.5, 0.6, 0),
			food.shape,
			DemoKit.color(food.color),
			food.name
		)
		scope.add(Visuals.Objects.animate(display, "Hover", { phase = index / 3 }))
	end
	local hand = (trayCFrame * CFrame.new(0, 2, 0)).Position

	-- Animals ------------------------------------------------------------------------------------

	local pens: { Pen } = {}

	local function startIdle(pen: Pen)
		pen.idle = Visuals.Objects.animate(pen.model, "Bounce", { amplitude = 0.12, speed = 0.6 })
	end

	for index, animal in DemoLogic.animals() do
		local side = if index == 1 then -1 else 1
		local at = stage.top * CFrame.new(side * 3.4, 0, 2)
		local model = DemoKit.animal(
			stage.folder,
			at,
			animal.kind,
			DemoKit.color(animal.color),
			DemoKit.color(animal.accent),
			animal.name
		)
		local card = Game.Panel.new({
			name = animal.name .. "Card",
			surface = "window",
			size = UDim2.fromOffset(230, 112),
			anchor = Vector2.new(if side < 0 then 0 else 1, 0),
			position = UDim2.new(if side < 0 then 0 else 1, side * -12, 0, 12),
			parent = gui,
		})
		scope.add(card)
		scope.add(Game.GameText.new({
			text = string.upper(animal.name),
			size = UDim2.new(1, -16, 0, 26),
			role = "heading",
			position = UDim2.fromOffset(8, 4),
			parent = card.Content,
		}))
		local needs = DemoLogic.startingNeeds()
		local function bar(label: string, y: number, palette: string, value: number): any
			scope.add(Game.GameText.new({
				text = label,
				size = UDim2.fromOffset(70, 24),
				role = "caption",
				align = "left",
				position = UDim2.fromOffset(10, y),
				parent = card.Content,
			}))
			local progress = Game.ProgressBar.new({
				value = value,
				max = 100,
				palette = palette,
				size = UDim2.fromOffset(134, 24),
				position = UDim2.fromOffset(84, y),
				parent = card.Content,
			})
			scope.add(progress)
			return progress
		end
		local pen: Pen = {
			data = animal,
			model = model,
			mouth = (at * CFrame.new(0, 2.9, -2.4)).Position,
			needs = needs,
			hungerBar = bar("Food", 36, "orange", needs.hunger),
			happyBar = bar("Happy", 68, "pink", needs.happiness),
			shownHunger = math.floor(needs.hunger),
			shownHappy = math.floor(needs.happiness),
			idle = nil,
			reacting = false,
			celebrated = false,
		}
		startIdle(pen)
		table.insert(pens, pen)
	end

	local function showNeeds(pen: Pen)
		-- The bars tween on update; only whole-number changes are sent so decay costs nothing.
		local hunger, happy = math.floor(pen.needs.hunger), math.floor(pen.needs.happiness)
		if hunger ~= pen.shownHunger then
			pen.shownHunger = hunger
			pen.hungerBar:update({ value = hunger })
		end
		if happy ~= pen.shownHappy then
			pen.shownHappy = happy
			pen.happyBar:update({ value = happy })
		end
	end

	-- STAND-IN FOR THE SERVER. A real game tells the server which animal was fed with what; the
	-- server updates the animal and the player's coins and replies. Here it is a local function.
	local function fakeServerFeed(pen: Pen, food: DemoLogic.Food): number
		pen.needs = DemoLogic.feed(pen.needs, food)
		state.coins += food.coins
		return food.coins
	end

	local function react(pen: Pen)
		if pen.reacting or not scope.isAlive() then
			return
		end
		pen.reacting = true
		-- Squash and stretch first, then the happy hop; the idle loop resumes afterwards. The
		-- steps run one after another because each of them moves the same model.
		Visuals.Objects.animate(pen.model, "Interact", {
			onDone = function()
				if not scope.isAlive() then
					return
				end
				Visuals.Pets.play("HappyReaction", pen.model, {
					onDone = function()
						pen.reacting = false
						if scope.isAlive() then
							startIdle(pen)
						end
					end,
				})
			end,
		})
	end

	local function onHit(thrown: Throw)
		local pen, food = thrown.pen, thrown.food
		local at = DemoKit.toVector(thrown.landing)
		local earned = fakeServerFeed(pen, food)
		Visuals.Play("CrumbBurst", at, { color = food.color })
		react(pen)
		showNeeds(pen)
		Visuals.UI.popup("+" .. earned, at + Vector3.new(0, 1.5, 0), { style = "currency" })
		Visuals.UI.flyTo(at, coinLabel, {
			count = 4,
			onDone = function()
				if scope.isAlive() then
					Visuals.UI.countTo(coinLabel, state.coins)
				end
			end,
		})
		log(string.format("%s ate the %s (+%d coins)", pen.data.name, string.lower(food.name), earned))
		if not pen.celebrated and pen.needs.hunger >= 100 and pen.needs.happiness >= 100 then
			pen.celebrated = true
			scope.add(Game.RewardPopup.new({
				title = string.upper(pen.data.name) .. " IS FULL AND HAPPY!",
				amount = "BEST FRIENDS",
				palette = "gold",
				duration = 2.2,
				parent = gui,
			}))
		end
	end

	local function onMiss(thrown: Throw)
		local at = DemoKit.toVector(thrown.landing)
		Visuals.Play("FoodSplat", at, { color = thrown.food.color })
		Visuals.Play("LandingDust", at)
		log("missed: the " .. string.lower(thrown.food.name) .. " hit the ground")
	end

	-- Throwing -----------------------------------------------------------------------------------

	local throws: { Throw } = {}

	local function throw(food: DemoLogic.Food)
		state.throws += 1
		local pen = pens[state.target]
		local miss = state.wide or DemoLogic.throwMisses(state.throws)
		local start = DemoKit.toPoint(hand)
		local landing = DemoLogic.landing(DemoKit.toPoint(pen.mouth), groundY, miss, state.throws)
		local part =
			DemoKit.food(stage.folder, CFrame.new(hand), food.shape, DemoKit.color(food.color), "Thrown" .. food.name)
		local thrown: Throw = {
			part = part,
			food = food,
			pen = pen,
			start = start,
			landing = landing,
			miss = miss,
			arc = nil,
			time = 0,
			trail = nil,
		}
		table.insert(throws, thrown)
	end

	local function release(thrown: Throw)
		local arc = DemoLogic.arc(thrown.start, thrown.landing, APEX)
		thrown.arc = arc
		thrown.time = 0
		if thrown.miss then
			thrown.trail = Visuals.Attach("FoodTrail", thrown.part, { color = thrown.food.color })
		else
			-- One event for the trail, the throw and hit sounds, the splat, the hearts and the
			-- "+amount" popup, each delayed by the flight time. The animal's own reaction is
			-- started in onHit, so `animal` and `pet` are left out of the context on purpose.
			Visuals.Feedback.fire("FeedAnimal", {
				projectile = thrown.part,
				position = DemoKit.toVector(thrown.landing),
				travel = arc.flightTime,
				amount = thrown.food.hunger,
			})
		end
	end

	local function step(thrown: Throw, dt: number): boolean
		thrown.time += dt
		local arc = thrown.arc
		if arc == nil then
			-- Anticipation: pull back and dip before the release.
			local alpha = math.min(1, thrown.time / WIND_UP)
			thrown.part.CFrame = CFrame.new(DemoKit.toVector(DemoLogic.windUp(thrown.start, thrown.landing, alpha)))
			if alpha >= 1 then
				release(thrown)
			end
			return true
		end
		if thrown.time < arc.flightTime then
			local point = DemoKit.toVector(DemoLogic.arcPoint(arc, thrown.time))
			local velocity = DemoKit.toVector(DemoLogic.arcVelocity(arc, thrown.time))
			thrown.part.CFrame = CFrame.lookAt(point, point + velocity) * CFrame.Angles(0, 0, thrown.time * 9)
			return true
		end
		-- Landed. Destroying the part ends the trail attached to it.
		if thrown.trail then
			thrown.trail.stop()
		end
		thrown.part:Destroy()
		if thrown.miss then
			onMiss(thrown)
		else
			onHit(thrown)
		end
		return false
	end

	local sinceDecay = 0
	scope.add(RunService.Heartbeat:Connect(function(dt: number)
		for index = #throws, 1, -1 do
			if not step(throws[index], dt) then
				table.remove(throws, index)
			end
		end
		sinceDecay += dt
		if sinceDecay >= 0.5 then
			for _, pen in pens do
				pen.needs = DemoLogic.decay(pen.needs, sinceDecay)
				showNeeds(pen)
			end
			sinceDecay = 0
		end
	end))

	-- Controls -----------------------------------------------------------------------------------

	for index, food in DemoLogic.foods() do
		DemoKit.button(scope, list, "THROW " .. string.upper(food.name), "primary", index, function()
			throw(food)
		end)
	end
	local targetButton: any = nil
	local function targetText(): string
		return "TARGET: " .. string.upper(pens[state.target].data.name)
	end
	targetButton = DemoKit.button(scope, list, targetText(), "neutral", 10, function()
		state.target = state.target % #pens + 1
		targetButton:update({ text = targetText() })
		Visuals.Play("PetSelect", pens[state.target].model)
	end)
	DemoKit.toggle(scope, list, "Aim wide (miss)", false, 11, function(value: boolean)
		state.wide = value
	end)
	DemoKit.text(scope, list, "Every fourth throw misses by itself.", "caption", 12)

	scope.add(function()
		for _, thrown in throws do
			if thrown.trail then
				thrown.trail.stop(true)
			end
		end
		table.clear(throws)
		for _, pen in pens do
			Visuals.Objects.stop(pen.model)
		end
		Visuals.StopAll(stage.folder)
	end)
	return scope.clean
end

return AnimalFeedingDemo
