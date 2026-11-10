--!strict
-- Demo 4: simulator feedback loop.
--
-- A big tap target (a world crystal and a UI button) fires Visuals.Feedback.fire("Tap"). Each tap
-- drops a coin that is collected a moment later with the CollectCoin feedback: burst, fly to the
-- counter, counter roll. An upgrade button fires UpgradeItem, the XP bar fills and fires LevelUp,
-- a rebirth button fires RebirthDone, and a quest card fires QuestComplete with a toast.
--
-- The Debug overlay toggle and the "20 taps per second" stress toggle make the throttles and
-- effect budgets visible: the stats block shows how many steps were held back and why.
--
-- Public APIs used: Visuals.Feedback.fire, Visuals.Objects.animate, Visuals.UI.countTo,
-- Visuals.Debug.overlay, Visuals.Stats, UrkUI.Game (XPBar, QuestCard, CartoonButton, Toggle).
--
-- NOT run in Studio.

local RunService = game:GetService("RunService")

local DemoKit = require("./DemoKit")
local DemoLogic = require("./DemoLogic")

local Visuals = DemoKit.Visuals
local Game = DemoKit.Game

local SimulatorFeedbackDemo = {}

SimulatorFeedbackDemo.title = "Simulator feedback"
SimulatorFeedbackDemo.description = "Tap, collect, upgrade, level up, rebirth, quest; with a stress test."

local MAX_COINS = 24
local COIN_DELAY = 0.55
local QUEST_TAPS = 25
local QUEST_REWARD = 100
local REBIRTH_LEVEL = 3
local STRESS_RATE = 20

type Coin = { part: BasePart, age: number, value: number }

function SimulatorFeedbackDemo.start(parent: Instance): () -> ()
	DemoKit.bootstrap()
	local scope = DemoKit.scope()
	local gui = DemoKit.screen(scope, parent, "SimulatorFeedbackDemo")
	local stage = DemoKit.stage(scope, "SimulatorStage", DemoKit.origin(22), DemoKit.color("#63C174"))
	local list = DemoKit.panel(scope, gui, { title = "SIMULATOR", height = 620, width = 300 })

	-- The demo's whole "save file". A real game keeps this on the server; every function below
	-- that changes it is a STAND-IN FOR THE SERVER and grants nothing real.
	local state = { coins = 0, upgrade = 0, rebirths = 0, level = 1, taps = 0, questDone = false, questClaimed = false }
	local counts = { fired = 0, held = 0 }

	-- World: the tap crystal on the stage.
	local crystal = DemoKit.part(
		stage.folder,
		"TapCrystal",
		Vector3.new(4, 4, 4),
		stage.top * CFrame.new(0, 3, 0),
		DemoKit.color("#5CE1FF"),
		Enum.PartType.Ball
	)
	crystal.Material = Enum.Material.Neon
	crystal.CanQuery = true
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 64
	click.Parent = crystal
	scope.add(Visuals.Objects.animate(crystal, "Float", { amplitude = 0.35 }))
	local tapPoint = crystal.Position + Vector3.new(0, 2.5, 0)

	-- HUD: coin counter, XP bar and the big tap button.
	local _, coinLabel = DemoKit.counter(scope, gui, "Coins", DemoKit.color("#FFD43B"), UDim2.new(0.5, 0, 0, 12))
	local xp = Game.XPBar.new({
		level = 1,
		value = 0,
		max = DemoLogic.xpForLevel(1),
		maxForLevel = DemoLogic.xpForLevel,
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 64),
		parent = gui,
	})
	scope.add(xp)
	local levelText = Game.GameText.new({
		text = "LEVEL 1",
		size = UDim2.fromOffset(320, 40),
		role = "title",
		color = "#FFD43B",
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 112),
		parent = gui,
	})
	scope.add(levelText)

	local tapButton = Instance.new("TextButton")
	tapButton.Name = "TapButton"
	tapButton.AnchorPoint = Vector2.new(0.5, 1)
	tapButton.Position = UDim2.new(0.5, 0, 1, -28)
	tapButton.Size = UDim2.fromOffset(150, 150)
	tapButton.BackgroundColor3 = DemoKit.color("#FF8A3D")
	tapButton.AutoButtonColor = false
	tapButton.Font = Enum.Font.GothamBlack
	tapButton.Text = "TAP!"
	tapButton.TextSize = 36
	tapButton.TextColor3 = Color3.new(1, 1, 1)
	tapButton.Parent = gui
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = tapButton
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.Color = DemoKit.color("#7A3A12")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = tapButton

	-- Coins --------------------------------------------------------------------------------------

	local coins: { Coin } = {}
	local coinSeed = 0

	local function collect(coin: Coin)
		local position = coin.part.Position
		-- Stand-in server: the coin's value is added to the balance.
		state.coins += coin.value
		Visuals.Feedback.fire("CollectCoin", { position = position, counter = coinLabel, total = state.coins })
		local part = coin.part
		Visuals.Objects.animate(part, "Collect", {
			onDone = function()
				part:Destroy()
			end,
		})
	end

	local function dropCoin(value: number)
		if #coins >= MAX_COINS then
			-- Too many on the ground: bank the oldest one now instead of letting them pile up.
			collect(table.remove(coins, 1) :: Coin)
		end
		coinSeed += 1
		local spots = DemoLogic.scatter(8, stage.radius - 1.5, math.floor(coinSeed / 8) + 1)
		local spot = spots[coinSeed % 8 + 1]
		local at = stage.top * CFrame.new(spot.x, 0.7, spot.z)
		local part = DemoKit.part(
			stage.folder,
			"Coin",
			Vector3.new(0.25, 1.3, 1.3),
			at * CFrame.Angles(0, 0, math.rad(90)),
			DemoKit.color("#FFD43B"),
			Enum.PartType.Cylinder
		)
		Visuals.Objects.animate(part, "ScaleIn")
		local coin: Coin = { part = part, age = 0, value = value }
		table.insert(coins, coin)
	end

	-- Feedback -----------------------------------------------------------------------------------

	local function record(fired: any)
		counts.fired += 1
		for _, dropped in fired.dropped do
			if dropped.reason == "throttle" then
				counts.held += 1
			end
		end
	end

	local quest: any = nil

	local function tap()
		state.taps += 1
		local value = DemoLogic.tapValue(state.upgrade, state.rebirths)
		-- The first visual change happens in this same call: the button press, the popup, the pop.
		record(Visuals.Feedback.fire("Tap", { gui = tapButton, position = tapPoint, amount = value }))
		dropCoin(value)
		xp:gain(2)
		if quest and not state.questDone then
			quest:update({ value = math.min(state.taps, QUEST_TAPS) })
			if state.taps >= QUEST_TAPS then
				state.questDone = true
				Visuals.Feedback.fire("QuestComplete", { gui = quest.Instance, position = tapPoint })
				DemoKit.toast("Quest complete: Tap Training", "success", gui)
			end
		end
	end

	scope.add(tapButton.Activated:Connect(tap))
	scope.add(click.MouseClick:Connect(tap))

	scope.add(xp.LevelUp:Connect(function(level: number)
		state.level = level
		levelText:update({ text = "LEVEL " .. level })
		Visuals.Feedback.fire("LevelUp", { position = tapPoint, text = levelText.Instance, bar = xp.Instance })
	end))

	-- Controls -----------------------------------------------------------------------------------

	local function holder(order: number, height: number): Frame
		-- Feedback animates this frame, not the button inside it, so the button's own hover and
		-- press motion never fights the recipe's pulse.
		local frame = Instance.new("Frame")
		frame.Name = "Holder"
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.new(1, -4, 0, height)
		frame.LayoutOrder = order
		frame.Parent = list
		return frame
	end

	local upgradeHolder = holder(1, 46)
	local upgradeButton: any = nil
	local function upgradeText(): string
		return string.format("UPGRADE  (%d coins)", DemoLogic.upgradeCost(state.upgrade))
	end
	upgradeButton = DemoKit.button(scope, upgradeHolder, upgradeText(), "buy", 1, function()
		local cost = DemoLogic.upgradeCost(state.upgrade)
		if state.coins < cost then
			Visuals.Feedback.fire("Error", { gui = upgradeHolder })
			return
		end
		-- Stand-in server: spend and raise the level.
		state.coins -= cost
		state.upgrade += 1
		upgradeButton:update({ text = upgradeText() })
		Visuals.Feedback.fire(
			"UpgradeItem",
			{ gui = upgradeHolder, counter = coinLabel, total = state.coins, position = tapPoint }
		)
	end)

	local rebirthHolder = holder(2, 46)
	DemoKit.button(scope, rebirthHolder, "REBIRTH  (level " .. REBIRTH_LEVEL .. "+)", "@purple", 1, function()
		if state.level < REBIRTH_LEVEL then
			Visuals.Feedback.fire("Error", { gui = rebirthHolder })
			return
		end
		-- Stand-in server: reset progress, keep a permanent multiplier.
		state.rebirths += 1
		state.coins, state.upgrade, state.level = 0, 0, 1
		xp:update({ level = 1, value = 0, max = DemoLogic.xpForLevel(1) })
		levelText:update({ text = "LEVEL 1" })
		upgradeButton:update({ text = upgradeText() })
		Visuals.UI.countTo(coinLabel, 0)
		Visuals.Feedback.fire("RebirthDone", { position = tapPoint })
		DemoKit.toast("Rebirth " .. state.rebirths .. ": taps are worth more", "info", gui)
	end)

	quest = Game.QuestCard.new({
		name = "tapTraining",
		title = "TAP TRAINING",
		description = "Tap " .. QUEST_TAPS .. " times",
		value = 0,
		max = QUEST_TAPS,
		rewards = { { text = "+" .. QUEST_REWARD } },
		size = UDim2.fromOffset(272, 104),
		layoutOrder = 3,
		parent = list,
	})
	scope.add(quest)
	scope.add(quest.Claimed:Connect(function()
		if state.questClaimed then
			return
		end
		-- Stand-in server: pay the quest reward once.
		state.questClaimed = true
		state.coins += QUEST_REWARD
		quest:update({ state = "claimed" })
		Visuals.Feedback.fire("CollectCoin", { position = tapPoint, counter = coinLabel, total = state.coins })
	end))

	local closeOverlay: (() -> ())? = nil
	DemoKit.toggle(scope, list, "Debug overlay", false, 4, function(value: boolean)
		if closeOverlay then
			closeOverlay()
			closeOverlay = nil
		end
		if value then
			closeOverlay = Visuals.Debug.overlay()
		end
	end)

	local tapper = DemoLogic.newTapper(STRESS_RATE)
	local stress = false
	DemoKit.toggle(scope, list, "Spam " .. STRESS_RATE .. " taps/sec", false, 5, function(value: boolean)
		stress = value
		tapper.carry = 0
	end)

	local stats = DemoKit.log(scope, list, 6, 6)

	-- One loop: ages coins, runs the stress taps and refreshes the stats text four times a second.
	local sinceStats = 1
	scope.add(RunService.Heartbeat:Connect(function(dt: number)
		for index = #coins, 1, -1 do
			local coin = coins[index]
			coin.age += dt
			if coin.age >= COIN_DELAY then
				table.remove(coins, index)
				collect(coin)
			end
		end
		if stress then
			for _ = 1, DemoLogic.tapsDue(tapper, dt) do
				tap()
			end
		end
		sinceStats += dt
		if sinceStats >= 0.25 then
			sinceStats = 0
			local live = Visuals.Stats()
			local reasons: { string } = {}
			for reason, count in live.rejected do
				table.insert(reasons, tostring(reason) .. " " .. tostring(count))
			end
			table.sort(reasons)
			stats(string.format("taps %d   coins on stage %d", state.taps, #coins))
			stats(string.format("tap events %d   steps throttled %d", counts.fired, counts.held))
			stats(string.format("effects %d   particles ~%d", live.effects, live.particles))
			stats(string.format("tracks %d   quality %s", live.tracks, tostring(live.level)))
			stats("skipped: " .. (if #reasons > 0 then table.concat(reasons, ", ") else "none"))
			stats(
				string.format(
					"x%d per tap   rebirths %d",
					DemoLogic.tapValue(state.upgrade, state.rebirths),
					state.rebirths
				)
			)
		end
	end))

	scope.add(function()
		if closeOverlay then
			closeOverlay()
			closeOverlay = nil
		end
		Visuals.Objects.stop(crystal)
		table.clear(coins)
	end)
	return scope.clean
end

return SimulatorFeedbackDemo
