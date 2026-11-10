--!strict
local FeedbackLogic = require("../src/Visuals/Feedback/FeedbackLogic")
local t = require("./lib/t")

-- The preset ids docs/architecture/visuals.md requires of the VFX module.
local VFX_IDS = {
	"CoinBurst",
	"GemBurst",
	"StarBurst",
	"CashExplosion",
	"SparkleBurst",
	"RewardGlow",
	"TreasureOpen",
	"ChestGlow",
	"RarityBurst",
	"RarityBeam",
	"Confetti",
	"Fireworks",
	"GoldenShine",
	"PetSpawn",
	"PetDespawn",
	"PetEquip",
	"PetUnequip",
	"PetHappy",
	"PetSelect",
	"PetUpgrade",
	"PetEvolve",
	"PetFusion",
	"PetTeleport",
	"RarityAura",
	"PetCollect",
	"PetSummon",
	"PetIdleSparkle",
	"EggShakeDust",
	"EggCrack",
	"EggFlash",
	"HatchBurst",
	"EggEnergy",
	"ImpactFlash",
	"EnergyBurst",
	"Shockwave",
	"HitConfirm",
	"AbilityActivate",
	"AbilityCharge",
	"ElementBurst",
	"Aura",
	"DashTrail",
	"Transformation",
	"CooldownReady",
	"SpeedTrail",
	"JumpBurst",
	"LandingDust",
	"DoubleJump",
	"SprintStreaks",
	"TeleportTrail",
	"MovementAura",
	"Fireflies",
	"Dust",
	"Snow",
	"Rain",
	"Wind",
	"FallingLeaves",
	"Bubbles",
	"WaterSplash",
	"MagicParticles",
	"Portal",
	"Checkpoint",
	"AreaUnlock",
	"AmbientGlow",
	"LevelUp",
	"QuestComplete",
	"Achievement",
	"RankUp",
	"Prestige",
	"Rebirth",
	"SkillUnlock",
	"DailyReward",
	"StreakReward",
	"NewArea",
	"FoodTrail",
	"FoodSplat",
	"HeartBurst",
	"CrumbBurst",
	"TapPop",
}
local SHAKES = { "SoftImpact", "Impact", "HeavyImpact", "Rumble", "Tap", "Hatch", "Landing", "Explosion" }
local CINEMATICS = { "PetReveal", "RewardReveal", "AreaUnlock", "Teleport" }
local OBJECTS = {
	"Float",
	"Hover",
	"Bounce",
	"Spin",
	"Pulse",
	"Sway",
	"Orbit",
	"ScaleIn",
	"ScaleOut",
	"Reveal",
	"Dissolve",
	"Appear",
	"Disappear",
	"Collect",
	"Teleport",
	"Shake",
	"SquashStretch",
	"Interact",
}
local REACTIONS = {
	"HappyReaction",
	"CuriousReaction",
	"SelectBounce",
	"HoverReaction",
	"Spawn",
	"Despawn",
	"Equip",
	"Unequip",
	"Evolve",
	"Upgrade",
}
local SIMULATOR_EVENTS = {
	"Tap",
	"CollectCoin",
	"CollectGem",
	"EquipPet",
	"UnequipPet",
	"HatchEgg",
	"QuestComplete",
	"LevelUp",
	"UnlockArea",
	"UpgradeItem",
	"FeedAnimal",
	"Purchase",
	"Error",
	"RebirthDone",
	"DailyReward",
	"Achievement",
	"RankUp",
	"AbilityUsed",
	"Hit",
	"Dash",
}

local function has(recipe: FeedbackLogic.Recipe, kind: string, field: string, value: any): boolean
	for _, step in recipe do
		if step.kind == kind and step[field] == value then
			return true
		end
	end
	return false
end

return {
	["numbers are formatted for popups"] = function()
		t.equal(FeedbackLogic.format(0), "0")
		t.equal(FeedbackLogic.format(950), "950")
		t.equal(FeedbackLogic.format(1250), "1,250")
		t.equal(FeedbackLogic.format(9999), "9,999")
		t.equal(FeedbackLogic.format(12500), "12.5K")
		t.equal(FeedbackLogic.format(999999), "999.9K")
		t.equal(FeedbackLogic.format(1e6), "1M")
		t.equal(FeedbackLogic.format(3.25e6), "3.2M")
		t.equal(FeedbackLogic.format(1.2e9), "1.2B")
		t.equal(FeedbackLogic.format(1e12), "1T")
		t.equal(FeedbackLogic.format(1e15), "1Qa")
		t.equal(FeedbackLogic.format(-1250), "-1,250")
		t.equal(FeedbackLogic.format(2.5), "2.5")
		t.equal(FeedbackLogic.format(2.04), "2")
		t.equal(FeedbackLogic.format("x"), "x")
	end,
	["resolve substitutes references"] = function()
		local position = { 1, 2, 3 }
		local steps, dropped = FeedbackLogic.resolve({
			{ kind = "vfx", id = "CoinBurst", at = "$position", params = { color = "$color", scale = 2 } },
			{ kind = "popup", text = "+$amount coins.", at = "$position", delay = 0.2 },
			{ kind = "popup", text = "$pet.name is level $pet.level!", at = "$position" },
			{ kind = "sound", cue = "coin" },
		}, { position = position, amount = 12500, pet = { name = "Dragon", level = 7 } })
		t.equal(#dropped, 0)
		t.equal(#steps, 4)
		t.equal(steps[1].at, position, "whole references keep the value's type")
		t.equal(steps[1].params.color, nil, "missing references inside option tables are nil")
		t.equal(steps[1].params.scale, 2)
		t.equal(steps[1].delay, 0)
		t.equal(steps[1].index, 1)
		t.equal(steps[2].text, "+12.5K coins.")
		t.equal(steps[2].delay, 0.2)
		t.equal(steps[3].text, "Dragon is level 7!")
		t.equal(steps[4].cue, "coin")
	end,
	["resolve does not change the recipe"] = function()
		local recipe = { { kind = "popup", text = "+$amount", at = "$position", options = { style = "$style" } } }
		local steps = FeedbackLogic.resolve(recipe, { amount = 5, position = "here", style = "tap" })
		t.equal(steps[1].text, "+5")
		t.equal(steps[1].options.style, "tap")
		t.equal(recipe[1].text, "+$amount")
		t.equal(recipe[1].options.style, "$style")
	end,
	["steps with missing context are dropped and reported"] = function()
		local steps, dropped = FeedbackLogic.resolve({
			{ kind = "vfx", id = "CoinBurst", at = "$position" },
			{ kind = "popup", text = "+$amount", at = "$position" },
			{ kind = "sound", cue = "coin" },
			{ kind = "vfx", id = "FoodSplat", at = "$position", delay = "$travel", optional = { "delay" } },
		}, { position = "p" })
		t.equal(#steps, 3)
		t.equal(steps[1].id, "CoinBurst")
		t.equal(steps[2].cue, "coin")
		t.equal(steps[3].delay, 0, "an optional missing field is cleared")
		t.deepEqual(dropped, { { index = 2, kind = "popup", reason = "missing amount" } })
		local none, all = FeedbackLogic.resolve({ { kind = "vfx", id = "X", at = "$position" } }, nil)
		t.equal(#none, 0)
		t.equal(all[1].reason, "missing position")
		local delayed = FeedbackLogic.resolve(
			{ { kind = "vfx", id = "X", at = "$p", delay = "$travel", optional = { "delay" } } },
			{ p = 1, travel = 0.4 }
		)
		t.equal(delayed[1].delay, 0.4)
	end,
	["conditions"] = function()
		local check = FeedbackLogic.check
		t.truthy(check(nil, {}))
		t.truthy(check({ field = "amount", min = 100 }, { amount = 100 }))
		t.falsy(check({ field = "amount", min = 100 }, { amount = 99 }))
		t.falsy(check({ field = "amount", min = 100 }, {}))
		t.truthy(check({ field = "amount", max = 5 }, { amount = 5 }))
		t.falsy(check({ field = "amount", max = 5 }, { amount = 6 }))
		t.truthy(check({ field = "rarity", atLeast = "Epic" }, { rarity = "Legendary" }))
		t.truthy(check({ field = "rarity", atLeast = "Epic" }, { rarity = "Epic" }))
		t.falsy(check({ field = "rarity", atLeast = "Epic" }, { rarity = "Rare" }))
		t.falsy(check({ field = "rarity", atLeast = "Epic" }, { rarity = "Nope" }))
		t.falsy(check({ field = "rarity", atLeast = "Epic" }, {}))
		t.truthy(check({ field = "pet", exists = true }, { pet = {} }))
		t.falsy(check({ field = "pet", exists = true }, {}))
		t.truthy(check({ field = "pet", exists = false }, {}))
		t.truthy(check({ field = "mode", equals = "boss" }, { mode = "boss" }))
		t.falsy(check({ field = "mode", equals = "boss" }, { mode = "x" }))
		t.truthy(check({ field = "stats.level", min = 3 }, { stats = { level = 4 } }))
		t.truthy(check({ every = 5 }, {}, { count = 10 }))
		t.falsy(check({ every = 5 }, {}, { count = 11 }))
		t.falsy(check({ every = 5 }, {}, nil), "the first fire is not a fifth")
		t.truthy(
			check(
				{ { field = "amount", min = 1 }, { field = "rarity", atLeast = "Rare" } },
				{ amount = 2, rarity = "Rare" }
			)
		)
		t.falsy(
			check(
				{ { field = "amount", min = 1 }, { field = "rarity", atLeast = "Rare" } },
				{ amount = 0, rarity = "Rare" }
			)
		)

		local recipe = { { kind = "camera", shake = "Tap", when = { every = 5 } }, { kind = "sound", cue = "tap" } }
		local shakes = 0
		for count = 1, 20 do
			local steps, dropped = FeedbackLogic.resolve(recipe, {}, { count = count })
			if #steps == 2 then
				shakes += 1
			else
				t.deepEqual(dropped, { { index = 1, kind = "camera", reason = "when" } })
			end
		end
		t.equal(shakes, 4)
	end,
	["throttle admits max per window"] = function()
		local state = FeedbackLogic.newThrottle()
		local rule = { max = 3, window = 1 }
		local admitted = 0
		for i = 0, 9 do
			if FeedbackLogic.admit(state, "Tap#3", rule, i * 0.05) then
				admitted += 1
			end
		end
		t.equal(admitted, 3)
		t.near(FeedbackLogic.nextFree(state, "Tap#3", rule, 0.5), 1)
		t.falsy(FeedbackLogic.admit(state, "Tap#3", rule, 0.99))
		t.truthy(FeedbackLogic.admit(state, "Tap#3", rule, 1), "the first slot frees after the window")
		t.falsy(FeedbackLogic.admit(state, "Tap#3", rule, 1.01))
		t.truthy(FeedbackLogic.admit(state, "Tap#3", rule, 1.05))
		t.truthy(FeedbackLogic.admit(state, "Other", rule, 1.05), "keys are independent")
		t.equal(FeedbackLogic.nextFree(state, "Fresh", rule, 7), 7)
		local pending, count = FeedbackLogic.pending(state, "Tap#3")
		t.equal(pending, 0)
		t.equal(count, 0, "nothing is held back without coalesce")
		t.equal(FeedbackLogic.flush(state, "Tap#3", rule, 5), nil)
	end,
	["throttle coalesces amounts over the limit"] = function()
		local state = FeedbackLogic.newThrottle()
		local rule = { max = 2, window = 1, coalesce = "amount" }
		local ok, amount = FeedbackLogic.admit(state, "k", rule, 0, 5)
		t.truthy(ok)
		t.equal(amount, 5)
		t.truthy(FeedbackLogic.admit(state, "k", rule, 0.1, 5))
		t.falsy(FeedbackLogic.admit(state, "k", rule, 0.2, 7))
		t.falsy(FeedbackLogic.admit(state, "k", rule, 0.3, 8))
		local pending, count = FeedbackLogic.pending(state, "k")
		t.equal(pending, 15)
		t.equal(count, 2)
		t.equal(FeedbackLogic.flush(state, "k", rule, 0.5), nil, "no room yet")
		t.near(FeedbackLogic.nextFree(state, "k", rule, 0.5), 1)
		-- The next admitted event carries what was held back.
		local later, merged = FeedbackLogic.admit(state, "k", rule, 1, 1)
		t.truthy(later)
		t.equal(merged, 16)
		t.equal((FeedbackLogic.pending(state, "k")), 0)
		-- Or a flush emits it when a slot frees.
		t.falsy(FeedbackLogic.admit(state, "k", rule, 1.05, 3))
		t.falsy(FeedbackLogic.admit(state, "k", rule, 1.06, 4))
		t.equal(FeedbackLogic.flush(state, "k", rule, 1.1), 7)
		t.equal(FeedbackLogic.flush(state, "k", rule, 1.1), nil, "flushed once")
		t.falsy(FeedbackLogic.admit(state, "k", rule, 1.2, 1), "the flush used a slot")
		-- Total shown always equals total earned.
		local fresh = FeedbackLogic.newThrottle()
		local shown, earned = 0, 0
		for i = 0, 199 do
			earned += 3
			local admitted, value =
				FeedbackLogic.admit(fresh, "t", { max = 8, window = 1, coalesce = "amount" }, i * 0.02, 3)
			if admitted then
				shown += value :: number
			end
		end
		shown += FeedbackLogic.flush(fresh, "t", { max = 8, window = 1, coalesce = "amount" }, 10) or 0
		t.equal(shown, earned)
	end,
	["validate accepts good recipes and names the problem in bad ones"] = function()
		t.truthy((FeedbackLogic.validate({})))
		t.truthy((FeedbackLogic.validate({ { kind = "call", fn = function() end } })))
		t.truthy((FeedbackLogic.validate({ { kind = "call", fn = "$callback" } })))
		t.truthy((FeedbackLogic.validate({ { kind = "ui", action = "flash" } })))
		local bad: { any } = {
			"nope",
			{ steps = {} },
			{ "x" },
			{ { kind = "explode" } },
			{ { id = "CoinBurst" } },
			{ { kind = "vfx", id = "CoinBurst" } },
			{ { kind = "popup", at = "$position" } },
			{ { kind = "ui", target = "$gui" } },
			{ { kind = "ui", action = "wiggle", target = "$gui" } },
			{ { kind = "ui", action = "countTo", target = "$gui" } },
			{ { kind = "camera" } },
			{ { kind = "camera", shake = "Tap", fov = 60 } },
			{ { kind = "camera", cinematic = "AreaUnlock" } },
			{ { kind = "call", fn = 5 } },
			{ { kind = "sound", cue = "x", delay = -1 } },
			{ { kind = "sound", cue = "x", when = "always" } },
			{ { kind = "sound", cue = "x", throttle = { max = 0 } } },
			{ { kind = "sound", cue = "x", throttle = { max = 2, window = 0 } } },
			{ { kind = "sound", cue = "x", throttle = { max = 2, coalesce = true } } },
			{ { kind = "sound", cue = "x", optional = "delay" } },
		}
		for index, recipe in bad do
			local ok, message = FeedbackLogic.validate(recipe)
			t.falsy(ok, "bad recipe " .. index)
			t.equal(type(message), "string")
		end
		local _, message = FeedbackLogic.validate({ { kind = "sound", cue = "a" }, { kind = "vfx", id = "X" } })
		t.truthy(string.find(message :: string, "step 2", 1, true))
	end,
	["the Simulator pack defines every documented event with valid steps"] = function()
		local pack = FeedbackLogic.pack("Simulator")
		assert(pack, "Simulator pack")
		local count = 0
		for _ in pack do
			count += 1
		end
		t.equal(count, #SIMULATOR_EVENTS)
		for _, event in SIMULATOR_EVENTS do
			local recipe = pack[event]
			t.truthy(recipe, event .. " is defined")
			t.truthy(#recipe >= 1, event .. " has steps")
			local ok, message = FeedbackLogic.validate(recipe)
			t.truthy(ok, event .. ": " .. tostring(message))
		end
	end,
	["every pack only references contract ids and known kinds"] = function()
		for _, name in FeedbackLogic.packs() do
			local pack = FeedbackLogic.pack(name)
			assert(pack, name)
			for event, recipe in pack do
				local where = name .. "." .. event
				local ok, message = FeedbackLogic.validate(recipe)
				t.truthy(ok, where .. ": " .. tostring(message))
				for _, step in recipe do
					t.truthy(table.find(FeedbackLogic.KINDS, step.kind), where .. " kind " .. tostring(step.kind))
					if step.kind == "vfx" then
						t.truthy(table.find(VFX_IDS, step.id), where .. " vfx " .. tostring(step.id))
					elseif step.kind == "camera" then
						if step.shake then
							t.truthy(table.find(SHAKES, step.shake), where .. " shake " .. tostring(step.shake))
						end
						if step.cinematic then
							t.truthy(table.find(CINEMATICS, step.cinematic), where .. " cinematic")
						end
					elseif step.kind == "object" then
						t.truthy(table.find(OBJECTS, step.preset), where .. " object " .. tostring(step.preset))
					elseif step.kind == "pet" then
						t.truthy(table.find(REACTIONS, step.reaction), where .. " reaction " .. tostring(step.reaction))
					elseif step.kind == "ui" and (step.action == nil or step.action == "animate") then
						t.truthy(
							table.find(FeedbackLogic.UI_PRESETS, step.preset),
							where .. " ui " .. tostring(step.preset)
						)
					end
				end
			end
		end
		t.equal(FeedbackLogic.pack("Nope"), nil)
	end,
	["the Simulator events contain what the design calls for"] = function()
		local pack = FeedbackLogic.pack("Simulator") :: { [string]: FeedbackLogic.Recipe }
		t.truthy(has(pack.Tap, "ui", "preset", "BouncyPress"))
		t.truthy(has(pack.Tap, "vfx", "id", "TapPop"))
		t.truthy(has(pack.Tap, "popup", "text", "+$amount"))
		t.truthy(has(pack.Tap, "sound", "cue", "tap"))
		for _, step in pack.Tap do
			if step.kind == "camera" then
				t.equal(step.shake, "Tap")
				t.equal(step.when.every, 5, "the tap shake is occasional")
			elseif step.kind == "popup" then
				t.equal(step.throttle.coalesce, "amount")
			elseif step.kind == "sound" then
				t.truthy(step.options.pitchVariance > 0)
			end
		end
		t.truthy(has(pack.CollectCoin, "vfx", "id", "CoinBurst"))
		t.truthy(has(pack.CollectCoin, "flyTo", "to", "$counter"))
		t.truthy(has(pack.CollectCoin, "ui", "action", "countTo"))
		t.truthy(has(pack.CollectGem, "vfx", "id", "GemBurst"))
		t.truthy(has(pack.EquipPet, "pet", "reaction", "Equip"))
		t.truthy(has(pack.EquipPet, "vfx", "id", "PetEquip"))
		t.truthy(has(pack.UnequipPet, "pet", "reaction", "Unequip"))
		t.truthy(has(pack.HatchEgg, "hatch", "eggs", "$eggs"))
		t.truthy(has(pack.QuestComplete, "vfx", "id", "QuestComplete"))
		t.truthy(has(pack.LevelUp, "vfx", "id", "LevelUp"))
		t.truthy(has(pack.LevelUp, "camera", "shake", "SoftImpact"))
		t.truthy(has(pack.UnlockArea, "camera", "cinematic", "AreaUnlock"))
		t.truthy(has(pack.UnlockArea, "vfx", "id", "NewArea"))
		t.truthy(has(pack.UpgradeItem, "ui", "preset", "UpgradePulse"))
		t.truthy(has(pack.UpgradeItem, "ui", "action", "shine"))
		t.truthy(has(pack.UpgradeItem, "vfx", "id", "SparkleBurst"))
		t.truthy(has(pack.FeedAnimal, "vfx", "id", "FoodTrail"))
		t.truthy(has(pack.FeedAnimal, "vfx", "id", "FoodSplat"))
		t.truthy(has(pack.FeedAnimal, "vfx", "id", "HeartBurst"))
		t.truthy(has(pack.FeedAnimal, "object", "preset", "Interact"))
		t.truthy(has(pack.FeedAnimal, "pet", "reaction", "HappyReaction"))
		t.truthy(has(pack.Purchase, "vfx", "id", "Confetti"))
		t.truthy(has(pack.Error, "sound", "cue", "error"))
		t.truthy(has(pack.RebirthDone, "vfx", "id", "Rebirth"))
		t.truthy(has(pack.RebirthDone, "camera", "shake", "Impact"))
		t.truthy(has(pack.RebirthDone, "ui", "action", "flash"))
		t.truthy(has(pack.AbilityUsed, "vfx", "id", "AbilityActivate"))
		t.truthy(has(pack.Hit, "vfx", "id", "HitConfirm"))
		t.truthy(has(pack.Hit, "vfx", "id", "ImpactFlash"))
		t.truthy(has(pack.Dash, "vfx", "id", "DashTrail"))
	end,
	["Minimal has fewer steps and never moves the camera"] = function()
		local base = FeedbackLogic.pack("Simulator") :: { [string]: FeedbackLogic.Recipe }
		local minimal = FeedbackLogic.pack("Minimal") :: { [string]: FeedbackLogic.Recipe }
		for event, recipe in minimal do
			t.truthy(base[event], event .. " overrides a Simulator event")
			t.truthy(#recipe < #base[event], event .. " is smaller")
			for _, step in recipe do
				t.truthy(step.kind ~= "camera", event .. " has no camera step")
			end
		end
	end,
	["applying a pack replaces only the events it defines"] = function()
		local base = FeedbackLogic.pack("Simulator") :: { [string]: FeedbackLogic.Recipe }
		local merged = FeedbackLogic.apply(base, FeedbackLogic.pack("Combat") :: any)
		t.truthy(has(merged.Hit, "vfx", "id", "Shockwave"), "Hit is the Combat one")
		t.truthy(merged.Critical, "Combat adds events")
		t.equal(merged.Tap, base.Tap, "Tap is untouched")
		t.equal(merged.CollectCoin, base.CollectCoin)
		t.falsy(base.Critical, "the original map is not changed")
		local custom = FeedbackLogic.apply(merged, { Tap = { { kind = "sound", cue = "tap" } } })
		t.equal(#custom.Tap, 1)
		t.equal(custom.Hit, merged.Hit)
		t.throws(function()
			FeedbackLogic.apply(base, { Tap = { { kind = "nope" } } })
		end)
		t.throws(function()
			FeedbackLogic.apply(base, { [1] = {} } :: any)
		end)
		-- Packs are fresh copies: editing one does not leak into the next.
		table.clear(base.Tap)
		t.truthy(#(FeedbackLogic.pack("Simulator") :: any).Tap > 0)
	end,
	["a Combat hit picks its shake from the damage"] = function()
		local combat = FeedbackLogic.pack("Combat") :: { [string]: FeedbackLogic.Recipe }
		local function shakes(amount: number): { string }
			local found: { string } = {}
			for _, step in FeedbackLogic.resolve(combat.Hit, { position = "p", amount = amount }) do
				if step.kind == "camera" then
					table.insert(found, step.shake)
				end
			end
			return found
		end
		t.deepEqual(shakes(20), { "Tap" })
		t.deepEqual(shakes(250), { "SoftImpact" })
	end,
}
