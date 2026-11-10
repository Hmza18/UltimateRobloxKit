--!strict
-- Demo 3: reward reveals.
--
-- One button per built-in rarity (Common to Secret), one for a rarity the demo registers itself
-- ("Stardust", through Visuals.Rewards.registerRarity), a batch of six mixed rewards and a
-- fast-forward toggle. Each reveal plays its rarity's world VFX on the stage.
--
-- Public APIs used: Visuals.Rewards.reveal / batch / registerRarity / rarity, Visuals.Pets.demoPet,
-- UrkUI.Game.
--
-- NOT run in Studio.

local DemoKit = require("./DemoKit")
local DemoLogic = require("./DemoLogic")

local Visuals = DemoKit.Visuals

local RewardRevealDemo = {}

RewardRevealDemo.title = "Reward reveal"
RewardRevealDemo.description = "Seven rarities, a custom rarity, a mixed batch and fast-forward."

local PALETTES: { [string]: string } = {
	Common = "neutral",
	Uncommon = "@green",
	Rare = "@blue",
	Epic = "@purple",
	Legendary = "@gold",
	Mythic = "@red",
	Secret = "@teal",
}

function RewardRevealDemo.start(parent: Instance): () -> ()
	DemoKit.bootstrap()
	local scope = DemoKit.scope()
	local gui = DemoKit.screen(scope, parent, "RewardRevealDemo")
	local stage = DemoKit.stage(scope, "RewardStage", DemoKit.origin(20), DemoKit.color("#4EA3FF"), 6)
	local list = DemoKit.panel(scope, gui, { title = "REWARD REVEAL", height = 600, width = 260 })
	local log = DemoKit.log(scope, list, 5, 40)

	-- A game-defined rarity: starts from Legendary and changes the colours, label and rank.
	local custom = DemoLogic.CUSTOM_RARITY
	local registered = pcall(function()
		Visuals.Rewards.registerRarity(custom.id, table.clone(custom.profile))
	end)
	if not registered then
		log("could not register " .. custom.id)
	end

	local current: any = nil
	local fastForward = false
	local revealPoint = stage.top.Position + Vector3.new(0, 3, 0)

	-- A reward shown as a small demo pet in the rarity's colour, so the reveal has something to
	-- show without any image assets.
	local function rewardFor(rarity: string, name: string, amount: number): { [string]: any }
		local color = if rarity == custom.id then custom.profile.color else DemoLogic.rarityColor(rarity)
		return {
			name = name,
			amount = amount,
			subtitle = "Demo reward: nothing is granted",
			model = function(): Model
				return Visuals.Pets.demoPet({ color = DemoKit.color(color), variant = (amount % 3) + 1 })
			end,
		}
	end

	local function begin(label: string): boolean
		if current ~= nil and current.isRunning() then
			log("a reveal is running (click to skip it)")
			return false
		end
		log(label .. (if fastForward then "  [fast-forward]" else ""))
		return true
	end

	local function track(handle: any)
		current = handle
		handle.Completed:Connect(function(dismissed: boolean)
			log(if dismissed then "dismissed" else "cancelled")
			if current == handle then
				current = nil
			end
		end)
	end

	-- STAND-IN FOR THE SERVER: a real game reveals what the server already granted. These
	-- functions only choose what to show.
	local function reveal(rarity: string)
		if not begin("reveal " .. rarity) then
			return
		end
		local amount = 50 * (#rarity + 1)
		track(
			Visuals.Rewards.reveal(
				rarity,
				rewardFor(rarity, DemoLogic.petName(rarity, amount), amount),
				{ position = revealPoint, fastForward = fastForward }
			)
		)
	end

	local function revealBatch()
		if not begin("batch of 6") then
			return
		end
		local rewards: { any } = {}
		for _, entry in DemoLogic.mixedRewards() do
			table.insert(rewards, { rarity = entry.rarity, reward = rewardFor(entry.rarity, entry.name, entry.amount) })
		end
		track(Visuals.Rewards.batch(rewards, { position = revealPoint, fastForward = fastForward }))
	end

	for index, rarity in DemoLogic.RARITIES do
		DemoKit.button(scope, list, rarity:upper(), PALETTES[rarity], index, function()
			reveal(rarity)
		end)
	end
	DemoKit.button(scope, list, custom.profile.label .. " (CUSTOM)", "@blue", 10, function()
		reveal(custom.id)
	end)
	DemoKit.button(scope, list, "BATCH OF 6", "buy", 11, revealBatch)
	DemoKit.toggle(scope, list, "Fast-forward", false, 12, function(value: boolean)
		fastForward = value
	end)
	DemoKit.text(scope, list, "Click or tap skips; again dismisses.", "caption", 13)

	scope.add(function()
		if current then
			current.cancel()
			current = nil
		end
	end)
	return scope.clean
end

return RewardRevealDemo
