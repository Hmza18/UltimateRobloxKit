--!strict
local Catalog = require("../src/Visuals/VFX/CatalogData")
local EffectLogic = require("../src/Visuals/VFX/EffectLogic")
local Quality = require("../src/Visuals/Core/Quality")
local Recipe = require("../src/Visuals/VFX/RecipeLogic")
local Registry = require("../src/Visuals/Core/Registry")
local VFXLogic = require("../src/Systems/VFX/VFXLogic")
local t = require("./lib/t")

-- The ids in docs/architecture/visuals.md ("Required preset ids"), by category.
local REQUIRED: { [string]: { string } } = {
	rewards = {
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
	},
	pets = {
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
	},
	eggs = { "EggShakeDust", "EggCrack", "EggFlash", "HatchBurst", "EggEnergy" },
	combat = {
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
	},
	movement = {
		"SpeedTrail",
		"JumpBurst",
		"LandingDust",
		"DoubleJump",
		"SprintStreaks",
		"TeleportTrail",
		"MovementAura",
	},
	environment = {
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
	},
	progression = {
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
	},
	feeding = { "FoodTrail", "FoodSplat", "HeartBurst", "CrumbBurst", "TapPop" },
}

local LEVELS = { "Low", "Medium", "High", "Ultra" }

local registry = Catalog.registry()

local function data(id: string): EffectLogic.Definition
	return registry:get(id).data
end

-- Every param combination a preset can be played with: one per variant, or just the defaults.
local function variantParams(preset: Registry.Preset): { { [string]: any } }
	local def: EffectLogic.Definition = preset.data
	local out: { { [string]: any } } = {}
	if def.variants and def.variantParam then
		for name in def.variants do
			table.insert(out, Catalog.params(registry, preset.id, { [def.variantParam] = name }))
		end
	else
		table.insert(out, Catalog.params(registry, preset.id, nil))
	end
	return out
end

local function count(layers: { EffectLogic.Layer }, kind: string): number
	local n = 0
	for _, layer in layers do
		if layer.kind == kind then
			n += 1
		end
	end
	return n
end

local function sample(): EffectLogic.Definition
	return {
		duration = 1,
		layers = {
			{
				kind = "particles",
				colors = { "#FFFFFF", "#FF0000" },
				sizes = { 1, 0 },
				lifetime = { 1, 2 },
				speed = { 4, 8 },
				burst = 10,
				gravity = -10,
			},
			{
				kind = "particles",
				name = "extra",
				colors = { "#00FF00" },
				sizes = { 1 },
				lifetime = { 1, 1 },
				speed = { 1, 1 },
				burst = 2,
				optional = true,
			},
			{ kind = "light", colors = { "#FF0000" }, range = 10, brightness = 2 },
			{ kind = "flash", colors = { "#FFFFFF" }, sizes = { 1, 4 }, time = 0.1 },
			{ kind = "shake", preset = "Impact" },
			{ kind = "postfx", effect = "bloom", amount = 1 },
			{ kind = "trail", colors = { "#FFFFFF" }, time = 0.4, width = { 2 } },
			{ kind = "beam", colors = { "#FFFFFF" }, width = { 1, 1 }, length = 10 },
			{ kind = "highlight", colors = { "#FFFFFF" } },
		},
	}
end

return {
	["catalog: every required id exists in its category"] = function()
		local total = 0
		for category, ids in REQUIRED do
			for _, id in ids do
				total += 1
				local preset = registry:find(id)
				t.truthy(preset, id .. " is registered")
				t.equal((preset :: Registry.Preset).category, category, id .. " category")
			end
		end
		t.equal(total, 78, "required ids in the contract table")
		t.equal(registry:count(), 83, "78 built-in presets plus 5 legacy")
		t.equal(#registry:ids({ category = "legacy" }), 5)
	end,

	["catalog: every preset and every variant validates"] = function()
		for _, preset in registry:list() do
			t.deepEqual(Registry.validate(preset), {}, preset.id .. " metadata")
			local problems = EffectLogic.validate(preset.data)
			t.equal(#problems, 0, preset.id .. ": " .. table.concat(problems, "; "))
		end
	end,

	["catalog: registry metadata is complete"] = function()
		for _, preset in registry:list() do
			local id = preset.id
			t.truthy(#preset.description >= 40, id .. " has a real description")
			t.truthy(preset.usage and string.find(preset.usage, id, 1, true), id .. " usage names the preset")
			t.truthy(preset.tags and #preset.tags >= 2, id .. " has tags")
			t.truthy(preset.quality and preset.quality.cost, id .. " has a cost label")
			t.equal((preset.quality :: any).cost, Recipe.costLabel(preset.data), id .. " cost label is computed")
			local params = preset.params or {}
			for _, name in { "color", "scale", "intensity" } do
				t.truthy(params[name], id .. " declares " .. name)
			end
			t.equal(params.color.type, "color")
			t.equal(params.scale.type, "number")
			for name, param in params do
				t.truthy(param.description and #param.description > 0, id .. "." .. name .. " is described")
			end
			local def: EffectLogic.Definition = preset.data
			if def.variantParam then
				local declared = params[def.variantParam]
				t.truthy(declared and declared.type == "enum", id .. " declares its variant param as an enum")
				for _, option in declared.options or {} do
					t.truthy((def.variants :: any)[option], id .. " has variant " .. option)
				end
			end
			if def.area then
				t.equal(params[def.area.param].type, "number", id .. " declares its area param")
				t.equal(params[def.area.param].default, def.area.base, id .. " area base is the default size")
			end
			-- Looping presets say Attach; one-shots say Play.
			local verb = if def.looping then "Attach" else "Play"
			t.truthy(string.find(preset.usage :: string, verb, 1, true), id .. " usage uses " .. verb)
		end
	end,

	["catalog: presets are layered compositions, not single emitters"] = function()
		for _, ids in REQUIRED do
			for _, id in ids do
				local def = data(id)
				t.truthy(#def.layers >= 2 or id == "Dust", id .. " has at least two layers")
			end
		end
	end,

	["catalog: no two presets share the same definition"] = function()
		local seen: { [string]: string } = {}
		for _, preset in registry:list() do
			local parts: { string } = {}
			for _, layer in (preset.data :: EffectLogic.Definition).layers do
				local colors = layer.colors or {}
				table.insert(
					parts,
					string.format(
						"%s/%s/%s/%s/%s",
						layer.kind,
						tostring(layer.burst),
						tostring(layer.rate),
						tostring(colors[#colors]),
						tostring(layer.time)
					)
				)
			end
			local key = table.concat(parts, "|")
			t.equal(seen[key], nil, preset.id .. " duplicates " .. tostring(seen[key]))
			seen[key] = preset.id
		end
	end,

	["resolve: every preset resolves at all four levels and totals grow with the level"] = function()
		for _, preset in registry:list() do
			for _, params in variantParams(preset) do
				local previous = -1
				local previousLayers = -1
				for _, level in LEVELS do
					local resolved = EffectLogic.resolve(preset.data, Quality.profile(level), params, 1)
					t.truthy(resolved.particles >= previous, preset.id .. " particles grow at " .. level)
					t.truthy(#resolved.layers >= previousLayers, preset.id .. " layers grow at " .. level)
					previous, previousLayers = resolved.particles, #resolved.layers
					t.truthy(#resolved.layers > 0, preset.id .. " shows something at " .. level)
					t.equal(resolved.looping, (preset.data :: EffectLogic.Definition).looping == true)
					if resolved.looping then
						t.equal(resolved.duration, 0)
					else
						t.truthy(resolved.duration > 0 and resolved.duration <= 4, preset.id .. " duration")
					end
					t.truthy(resolved.linger > 0 and resolved.linger <= 8.8, preset.id .. " linger")
					for _, layer in resolved.layers do
						if layer.burst then
							t.truthy(layer.burst >= 1, preset.id .. " kept burst emits")
						end
					end
				end
			end
		end
	end,

	["resolve: Low drops optional layers, trails, lights, highlights and post-processing"] = function()
		local low = Quality.profile("Low")
		for _, preset in registry:list() do
			for _, params in variantParams(preset) do
				local resolved = EffectLogic.resolve(preset.data, low, params, 1)
				for _, layer in resolved.layers do
					t.falsy(layer.optional, preset.id .. " keeps no optional layer on Low")
					t.truthy(
						layer.kind ~= "trail"
							and layer.kind ~= "light"
							and layer.kind ~= "highlight"
							and layer.kind ~= "postfx",
						preset.id .. " has no " .. layer.kind .. " on Low"
					)
				end
			end
		end
		local high = EffectLogic.resolve(data("CoinBurst"), Quality.profile("High"), nil, 1)
		local lowCoin = EffectLogic.resolve(data("CoinBurst"), low, nil, 1)
		t.truthy(#lowCoin.layers < #high.layers)
		t.truthy(lowCoin.particles < high.particles)
	end,

	["budget: one-shots stay under 400 particles at High and inside the Low budget"] = function()
		local low = Quality.profile("Low")
		local high = Quality.profile("High")
		for _, preset in registry:list() do
			for _, params in variantParams(preset) do
				local atHigh = EffectLogic.resolve(preset.data, high, params, 1)
				local atLow = EffectLogic.resolve(preset.data, low, params, 1)
				local cap = if atHigh.looping then 160 else 400
				t.truthy(atHigh.particles <= cap, preset.id .. " High particles " .. atHigh.particles)
				t.truthy(atLow.particles <= low.maxParticles / 4, preset.id .. " Low particles " .. atLow.particles)
				t.truthy(atHigh.lights <= 2, preset.id .. " lights")
				-- The raw cost handed to Core/Effects matches what High resolves to.
				local cost = EffectLogic.cost(preset.data, params)
				t.truthy(math.abs(cost.particles - atHigh.particles) <= 3, preset.id .. " cost matches High")
			end
		end
	end,

	["budget: cost labels are honest"] = function()
		for _, id in { "TapPop", "ImpactFlash", "PetIdleSparkle", "CrumbBurst", "HitConfirm" } do
			t.equal((registry:get(id).quality :: any).cost, "low", id)
		end
		for _, id in { "HatchBurst", "RarityBurst", "Prestige", "Transformation", "Rebirth", "PetEvolve" } do
			t.equal((registry:get(id).quality :: any).cost, "high", id)
		end
		-- Effects fired on every tap are throttled.
		for _, id in { "TapPop", "ImpactFlash", "HitConfirm", "CoinBurst", "CrumbBurst" } do
			local interval = data(id).minInterval
			t.truthy(interval and interval > 0, id .. " has a minInterval")
		end
	end,

	["rarity: hierarchy is monotonic from Common to Secret"] = function()
		local high = Quality.profile("High")
		for _, id in { "RarityBurst", "HatchBurst", "RarityAura", "RarityBeam" } do
			local particles, layers, duration, lights = 0, 0, 0, 0
			for _, rarity in EffectLogic.RARITIES do
				local params = Catalog.params(registry, id, { rarity = rarity })
				local resolved = EffectLogic.resolve(data(id), high, params, 1)
				local label = id .. " " .. rarity
				t.truthy(resolved.particles >= particles, label .. " particles")
				t.truthy(#resolved.layers >= layers, label .. " layers")
				t.truthy(resolved.duration >= duration, label .. " duration")
				t.truthy(resolved.lights >= lights, label .. " lights")
				particles, layers, duration, lights =
					resolved.particles, #resolved.layers, resolved.duration, resolved.lights
			end
		end
		local common = EffectLogic.resolve(data("RarityBurst"), high, { rarity = "Common" }, 1)
		local secret = EffectLogic.resolve(data("RarityBurst"), high, { rarity = "Secret" }, 1)
		t.truthy(secret.particles >= common.particles * 4, "Secret is far richer than Common")
		t.truthy(common.particles <= 20, "Common stays small")
		t.equal(count(common.layers, "beam"), 0)
		t.equal(count(common.layers, "ring"), 0)
		t.truthy(count(secret.layers, "beam") >= 1 and count(secret.layers, "ring") >= 2)
		t.truthy(secret.duration >= 3 and common.duration <= 1)
		t.truthy(secret.priority > common.priority)
		-- The seven palettes are distinct.
		local seen: { [string]: boolean } = {}
		for _, rarity in EffectLogic.RARITIES do
			local main = EffectLogic.rarityPalette(rarity).main
			t.falsy(seen[main], rarity .. " palette is unique")
			seen[main] = true
		end
		t.equal(EffectLogic.rarityRank("Secret"), 7)
		t.equal(EffectLogic.rarityRank("Nope"), 0)
		t.equal(EffectLogic.rarityPalette("Nope").main, EffectLogic.rarityPalette("Common").main)
	end,

	["elements: eight variants with distinct palettes and motion"] = function()
		local def = data("ElementBurst")
		local variants = def.variants :: { [string]: EffectLogic.Definition }
		local mains: { [string]: boolean } = {}
		local gravity: { [string]: number } = {}
		local speed: { [string]: number } = {}
		local life: { [string]: number } = {}
		for _, element in EffectLogic.ELEMENTS do
			local variant = variants[element]
			t.truthy(variant, element .. " exists")
			local main = EffectLogic.elementPalette(element).main
			t.falsy(mains[main], element .. " palette is unique")
			mains[main] = true
			local first = variant.layers[1]
			gravity[element] = first.gravity or 0
			speed[element] = (first.speed :: { number })[2]
			life[element] = (first.lifetime :: { number })[2]
		end
		t.truthy(gravity.fire > 0, "fire rises")
		t.truthy(gravity.ice < 0 and gravity.ice > -10, "ice sinks slowly")
		t.truthy(gravity.water <= -40, "water arcs under gravity")
		t.truthy(gravity.earth < gravity.water, "earth is the heaviest")
		t.truthy(speed.lightning > speed.fire * 3 and life.lightning < 0.3, "lightning is fast and brief")
		local wind = variants.wind.layers[1]
		t.truthy((wind.drag or 0) >= 3 and (wind.spread :: { number })[2] == 180, "wind is wide with drag")
		t.equal(variants.dark.layers[1].shapeInOut, "Inward", "dark implodes")
		-- The enum param rejects anything else.
		t.throws(function()
			registry:params("ElementBurst", { element = "plasma" })
		end)
		local chosen = EffectLogic.pick(def, { element = "ice" })
		t.equal(chosen, variants.ice)
		t.equal(EffectLogic.pick(def, { element = "plasma" }), def, "unknown falls back to the base")
	end,

	["params: registry clamps numbers and validates colours and enums"] = function()
		local params = Catalog.params(registry, "CoinBurst", { scale = 99, intensity = -4, owner = "me" })
		t.equal(params.scale, 4)
		t.equal(params.intensity, 0)
		t.equal(params.owner, "me", "free-form keys pass through")
		t.equal(params.color, nil, "the default colour means no retint")
		t.equal(Catalog.params(registry, "CoinBurst", { color = "#ffc93c" }).color, nil, "default, any case")
		t.equal(Catalog.params(registry, "CoinBurst", { color = "#00FF00" }).color, "#00FF00")
		t.throws(function()
			Catalog.params(registry, "CoinBurst", { color = "green" })
		end)
		t.throws(function()
			Catalog.params(registry, "CoinBurst", { scale = "big" })
		end)
		t.throws(function()
			Catalog.params(registry, "RarityBurst", { rarity = "Ultra" })
		end)
		t.equal(Catalog.params(registry, "Rain", { size = 9999 }).size, 200)
	end,

	["resolve: scale, intensity, distance and colour params"] = function()
		local high = Quality.profile("High")
		local def = sample()
		local base = EffectLogic.resolve(def, high, nil, 1)
		local big = EffectLogic.resolve(def, high, { scale = 2 }, 1)
		t.deepEqual(big.layers[1].sizes, { 2, 0 })
		t.deepEqual(big.layers[1].speed, { 8, 16 })
		t.deepEqual(big.layers[1].acceleration, { 0, -20, 0 }, "gravity folds into acceleration and scales")
		t.equal(big.layers[1].gravity, nil)
		t.equal(big.layers[3].range, 20)
		t.equal(base.layers[1].burst, 10)
		t.equal(EffectLogic.resolve(def, high, { intensity = 2 }, 1).layers[1].burst, 20)
		t.equal(EffectLogic.resolve(def, high, nil, 0.5).layers[1].burst, 5)
		t.equal(EffectLogic.resolve(def, high, nil, 1, { intensity = 0.5 }).layers[1].burst, 5)
		-- A kept burst layer never drops below one particle.
		local tiny = EffectLogic.resolve(def, Quality.profile("Low"), { intensity = 0.01 }, 0.25)
		t.equal(tiny.layers[1].burst, 1)
		-- Low: fewer, slightly larger, shorter-lived particles.
		local low = EffectLogic.resolve(def, Quality.profile("Low"), nil, 1)
		t.equal(low.layers[1].burst, 3)
		t.near((low.layers[1].sizes :: { number })[1], 1.15, 1e-9)
		t.deepEqual(low.layers[1].lifetime, { 0.75, 1.5 })
		-- Tint recolours saturated stops and leaves white alone.
		local tinted = EffectLogic.resolve(def, high, { color = "#0000FF" }, 1)
		t.deepEqual(tinted.layers[1].colors, { "#FFFFFF", "#0000FF" })
		t.deepEqual(tinted.layers[3].colors, { "#0000FF" })
		-- The source definition is never changed.
		t.deepEqual(def.layers[1].sizes, { 1, 0 })
		t.equal(def.layers[1].gravity, -10)
		t.equal(base.duration, 1)
		t.equal(base.linger, 2)
		t.equal(base.particles, 12)
		t.equal(base.lights, 1)
	end,

	["resolve: tint = false layers keep their colours"] = function()
		local high = Quality.profile("High")
		local resolved = EffectLogic.resolve(data("LandingDust"), high, { color = "#FF0000" }, 1)
		for index, layer in resolved.layers do
			local source = data("LandingDust").layers[index]
			if source.tint == false then
				t.deepEqual(layer.colors, source.colors, "untinted layer " .. tostring(layer.name))
			end
		end
	end,

	["resolve: reduced flashing softens flashes and drops post-processing"] = function()
		local high = Quality.profile("High")
		local def = sample()
		local normal = EffectLogic.resolve(def, high, nil, 1)
		local reduced = EffectLogic.resolve(def, high, nil, 1, { reducedFlashing = true })
		t.equal(count(normal.layers, "postfx"), 1)
		t.equal(count(reduced.layers, "postfx"), 0)
		local flash: EffectLogic.Layer? = nil
		local light: EffectLogic.Layer? = nil
		for _, layer in reduced.layers do
			if layer.kind == "flash" then
				flash = layer
			elseif layer.kind == "light" then
				light = layer
			end
		end
		t.truthy(flash and light)
		t.truthy(((flash :: EffectLogic.Layer).transparency :: { number })[1] >= 0.7, "flash is mostly transparent")
		t.truthy(((flash :: EffectLogic.Layer).time :: number) >= 0.35, "flash is slower")
		t.truthy(((light :: EffectLogic.Layer).fadeIn :: number) >= 0.2, "light fades in")
		t.near((light :: EffectLogic.Layer).brightness :: number, 1.2, 1e-9)
		-- The catalog's own white-out is softened too, and loses both pulses.
		local egg = EffectLogic.resolve(data("EggFlash"), high, nil, 1, { reducedFlashing = true })
		t.equal(count(egg.layers, "postfx"), 0)
		-- Post-processing is also skipped for distant effects and on Medium.
		t.equal(count(EffectLogic.resolve(def, high, nil, 0.9).layers, "postfx"), 0)
		t.equal(count(EffectLogic.resolve(def, Quality.profile("Medium"), nil, 1).layers, "postfx"), 0)
	end,

	["resolve: reduced motion drops camera shake and light pulsing"] = function()
		local high = Quality.profile("High")
		local def = sample()
		t.equal(count(EffectLogic.resolve(def, high, nil, 1).layers, "shake"), 1)
		t.equal(count(EffectLogic.resolve(def, high, nil, 1, { reducedMotion = true }).layers, "shake"), 0)
		t.equal(count(EffectLogic.resolve(def, high, { intensity = 0 }, 1).layers, "shake"), 0)
		for _, preset in registry:list() do
			local resolved = EffectLogic.resolve(preset.data, high, nil, 1, { reducedMotion = true })
			for _, layer in resolved.layers do
				t.truthy(layer.kind ~= "shake", preset.id .. " has no shake under reduced motion")
				t.equal(layer.pulse, nil, preset.id .. " has no pulsing light under reduced motion")
			end
		end
		local aura = EffectLogic.resolve(data("ChestGlow"), high, nil, 1)
		local pulsing = false
		for _, layer in aura.layers do
			pulsing = pulsing or layer.pulse ~= nil
		end
		t.truthy(pulsing, "the light pulses normally")
	end,

	["resolve: area effects stretch their volume and keep counts bounded"] = function()
		local high = Quality.profile("High")
		local def = data("Rain")
		local base = EffectLogic.resolve(def, high, { size = 50 }, 1)
		local wide = EffectLogic.resolve(def, high, { size = 200 }, 1)
		local small = EffectLogic.resolve(def, high, { size = 25 }, 1)
		t.deepEqual(base.layers[1].shapeSize, { 50, 1, 50 })
		t.deepEqual(wide.layers[1].shapeSize, { 200, 1, 200 }, "height is unchanged")
		t.near(wide.layers[1].rate :: number, (base.layers[1].rate :: number) * 2.5, 1e-6, "rate is capped at 2.5x")
		t.near(small.layers[1].rate :: number, (base.layers[1].rate :: number) * 0.25, 1e-6)
		t.truthy(wide.particles <= 250, "a huge rain box stays affordable: " .. wide.particles)
		t.truthy(EffectLogic.cost(def, { size = 200 }).particles > EffectLogic.cost(def, { size = 50 }).particles)
	end,

	["timing: duration covers delayed layers and linger covers particle lifetimes"] = function()
		local def: EffectLogic.Definition = {
			layers = {
				{
					kind = "particles",
					delay = 0.5,
					colors = { "#FFFFFF" },
					sizes = { 1 },
					lifetime = { 1, 3 },
					speed = { 1, 1 },
					burst = 4,
				},
				{ kind = "ring", delay = 1, colors = { "#FFFFFF" }, radius = { 1, 4 }, thickness = 0.2, time = 0.5 },
				{
					kind = "light",
					colors = { "#FFFFFF" },
					range = 8,
					brightness = 1,
					fadeIn = 0.1,
					hold = 1,
					fadeOut = 1,
				},
			},
		}
		t.deepEqual(EffectLogic.validate(def), {})
		local resolved = EffectLogic.resolve(def, Quality.profile("High"), nil, 1)
		t.near(resolved.duration, 2.1, 1e-9, "the light envelope ends last")
		t.equal(resolved.linger, 3)
		-- A rate layer in a one-shot emits for the effect's duration unless emitFor says otherwise.
		local stream: EffectLogic.Definition = {
			duration = 2,
			layers = {
				{
					kind = "particles",
					colors = { "#FFFFFF" },
					sizes = { 1 },
					lifetime = { 0.5, 0.5 },
					speed = { 1, 1 },
					rate = 20,
					delay = 0.5,
				},
			},
		}
		local streamed = EffectLogic.resolve(stream, Quality.profile("High"), nil, 1)
		t.equal(streamed.layers[1].emitFor, 1.5)
		t.equal(streamed.particles, 10, "rate x lifetime")
		stream.looping = true
		stream.duration = nil
		t.equal(EffectLogic.resolve(stream, Quality.profile("High"), nil, 1).layers[1].emitFor, nil)
		t.equal(EffectLogic.cost(stream).particles, 10)
		t.near(EffectLogic.envelopeAt(0.1, 0.2, 0.4, 0.05), 0.5, 1e-9)
		t.equal(EffectLogic.envelopeAt(0.1, 0.2, 0.4, 0.2), 1)
		t.near(EffectLogic.envelopeAt(0.1, 0.2, 0.4, 0.5), 0.5, 1e-9)
		t.equal(EffectLogic.envelopeAt(0.1, 0.2, 0.4, 2), 0)
		t.equal(EffectLogic.envelopeAt(0.1, 0.2, 0.4, -1), 0)
	end,

	["cost: bursts, rates and lights; the worst variant without params"] = function()
		local cost = EffectLogic.cost(sample())
		t.equal(cost.particles, 12)
		t.equal(cost.lights, 1)
		local def = data("RarityBurst")
		local worst = EffectLogic.cost(def)
		local secret = EffectLogic.cost(def, { rarity = "Secret" })
		local common = EffectLogic.cost(def, { rarity = "Common" })
		t.equal(worst.particles, secret.particles)
		t.truthy(common.particles < secret.particles)
		t.equal(common.lights, 0)
		t.equal(secret.lights, 1)
	end,

	["validate: strict about kinds, fields, ranges, stop counts and colours"] = function()
		local function problemsWith(change: (layer: any, def: any) -> ()): string
			local def: any = sample()
			change(def.layers[1], def)
			return table.concat(EffectLogic.validate(def), "; ")
		end
		local function expect(needle: string, change: (layer: any, def: any) -> ())
			local problems = problemsWith(change)
			t.truthy(string.find(problems, needle, 1, true), "expected '" .. needle .. "' in: " .. problems)
		end
		t.deepEqual(EffectLogic.validate(sample()), {})
		expect("unknown kind", function(layer: any)
			layer.kind = "shader"
		end)
		expect("unknown field", function(layer: any)
			layer.colour = "#FFFFFF"
		end)
		expect("colors must be 1-4 hex stops", function(layer: any)
			layer.colors = { "#FFF" }
		end)
		expect("colors must be 1-4 hex stops", function(layer: any)
			layer.colors = { "#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF" }
		end)
		expect("sizes must be", function(layer: any)
			layer.sizes = {}
		end)
		expect("sizes must be", function(layer: any)
			layer.sizes = { -1 }
		end)
		expect("transparency", function(layer: any)
			layer.transparency = { 0, 1.5 }
		end)
		expect("lifetime must be", function(layer: any)
			layer.lifetime = { 2, 1 }
		end)
		expect("exactly one of burst or rate", function(layer: any)
			layer.rate = 5
		end)
		expect("exactly one of burst or rate", function(layer: any)
			layer.burst = nil
		end)
		expect("burst must be a whole number", function(layer: any)
			layer.burst = 2.5
		end)
		expect("burst must be a whole number", function(layer: any)
			layer.burst = 5000
		end)
		expect("emitFor needs rate", function(layer: any)
			layer.emitFor = 1
		end)
		expect("spread", function(layer: any)
			layer.spread = { 200, 0 }
		end)
		expect("shape must be", function(layer: any)
			layer.shape = "Cone"
		end)
		expect("orientation", function(layer: any)
			layer.orientation = "Sideways"
		end)
		expect("texture", function(layer: any)
			layer.texture = "unicorn"
		end)
		expect("lightEmission", function(layer: any)
			layer.lightEmission = 2
		end)
		expect("delay", function(layer: any)
			layer.delay = -1
		end)
		expect("easing", function(_layer: any, def: any)
			def.layers[4].easing = "wobble"
		end)
		expect("range must be", function(_layer: any, def: any)
			def.layers[3].range = 500
		end)
		expect("effect must be", function(_layer: any, def: any)
			def.layers[6].effect = "vignette"
		end)
		expect("preset must be", function(_layer: any, def: any)
			def.layers[5].preset = ""
		end)
		expect("duration must be", function(_layer: any, def: any)
			def.duration = 0
		end)
		expect("needs at least one layer", function(_layer: any, def: any)
			def.layers = {}
		end)
		expect("variants need both", function(_layer: any, def: any)
			def.variantParam = "rarity"
		end)
		expect("variant Rare: layer 1: unknown kind", function(_layer: any, def: any)
			def.variantParam = "rarity"
			def.variants = { Rare = { layers = { { kind = "nope" } } } }
		end)
		expect("area must be", function(_layer: any, def: any)
			def.area = { param = "size" }
		end)
		t.deepEqual(EffectLogic.validate(nil :: any), { "definition must be a table" })
		-- A raw asset string is accepted wherever a texture key is.
		t.equal(
			problemsWith(function(layer: any)
				layer.texture = "rbxassetid://1234"
			end),
			""
		)
	end,

	["colour helpers"] = function()
		t.truthy(EffectLogic.isHex("#A1b2C3"))
		t.falsy(EffectLogic.isHex("A1B2C3"))
		t.falsy(EffectLogic.isHex("#A1B2C"))
		t.falsy(EffectLogic.isHex(12))
		local r, g, b = EffectLogic.rgb("#FF8000")
		t.near(r, 1, 1e-9)
		t.near(g, 128 / 255, 1e-9)
		t.near(b, 0, 1e-9)
		t.equal(EffectLogic.hex(1, 0.5, 0), "#FF8000")
		t.equal(EffectLogic.hex(2, -1, 0), "#FF0000", "channels clamp")
		t.throws(function()
			EffectLogic.rgb("red")
		end)
		t.equal(EffectLogic.mix("#000000", "#FFFFFF", 0.5), "#808080")
		t.equal(EffectLogic.mix("#102030", "#FFFFFF", 0), "#102030")
		t.equal(EffectLogic.mix("#102030", "#FFFFFF", 7), "#FFFFFF")
		t.equal(EffectLogic.lighten("#FF0000", 1), "#FFFFFF")
		t.equal(EffectLogic.darken("#FF0000", 1), "#000000")
		t.equal(EffectLogic.lighten("#FF0000", 0), "#FF0000")
		-- HSV round trip.
		for _, hex in { "#FF0000", "#00FF00", "#0000FF", "#FFC93C", "#4AA8FF", "#808080", "#000000", "#FFFFFF" } do
			local h, s, v = EffectLogic.hsv(hex)
			t.equal(EffectLogic.fromHsv(h, s, v), hex, "round trip " .. hex)
		end
		local hue = EffectLogic.hsv("#00FF00")
		t.near(hue, 120, 1e-9)
		t.equal(EffectLogic.shiftHue("#FF0000", 120), "#00FF00")
		t.equal(EffectLogic.shiftHue("#FF0000", -120), "#0000FF")
		-- Tint keeps white white and black black, and moves a saturated colour to the new hue.
		t.equal(EffectLogic.tint("#FFFFFF", "#FF0000"), "#FFFFFF")
		t.equal(EffectLogic.tint("#000000", "#FF0000"), "#000000")
		t.equal(EffectLogic.tint("#00FF00", "#FF0000"), "#FF0000")
		t.equal(EffectLogic.tint("#008000", "#0000FF"), "#000080", "brightness is kept")
		t.equal(EffectLogic.tint("#FF0000", "#808080"), "#FFFFFF", "a grey tint removes the colour")
		local palette = EffectLogic.palette("#4AA8FF")
		t.equal(palette.main, "#4AA8FF")
		t.equal(palette.light, EffectLogic.lighten("#4AA8FF", 0.45))
		t.equal(palette.dark, EffectLogic.darken("#4AA8FF", 0.35))
		t.truthy(palette.accent ~= palette.main)
		t.equal(EffectLogic.palette("#4AA8FF", "#FF00FF").accent, "#FF00FF")
	end,

	["textures: keys, fallbacks and keypoints"] = function()
		t.equal(#EffectLogic.TEXTURE_KEYS, 16)
		local builtIn = {
			["rbxasset://textures/particles/sparkles_main.dds"] = true,
			["rbxasset://textures/particles/smoke_main.dds"] = true,
			["rbxasset://textures/particles/fire_main.dds"] = true,
		}
		local used: { [string]: boolean } = {}
		for _, key in EffectLogic.TEXTURE_KEYS do
			local fallback = EffectLogic.fallbackTexture(key)
			t.truthy(builtIn[fallback], key .. " falls back to a built-in texture")
			used[fallback] = true
		end
		for path in builtIn do
			t.truthy(used[path], path .. " is used")
		end
		t.equal(EffectLogic.fallbackTexture("smoke"), "rbxasset://textures/particles/smoke_main.dds")
		t.equal(EffectLogic.fallbackTexture(nil), "rbxasset://textures/particles/sparkles_main.dds")
		t.equal(EffectLogic.fallbackTexture("rbxassetid://9"), "rbxassetid://9")
		t.equal(EffectLogic.texture("coin", { coin = "rbxassetid://42" }), "rbxassetid://42")
		t.equal(EffectLogic.texture("coin", { gem = "rbxassetid://42" }), EffectLogic.fallbackTexture("coin"))
		t.equal(EffectLogic.texture("coin", { coin = "" }), EffectLogic.fallbackTexture("coin"))
		-- Every texture a preset names is a known key.
		for _, preset in registry:list() do
			local def: EffectLogic.Definition = preset.data
			local lists = { def.layers }
			for _, variant in def.variants or {} do
				table.insert(lists, variant.layers)
			end
			for _, layers in lists do
				for _, layer in layers do
					for _, key in { layer.texture, layer.image } do
						t.truthy(table.find(EffectLogic.TEXTURE_KEYS, key), preset.id .. " texture " .. key)
					end
				end
			end
		end
		-- Keypoints start at 0, end at 1 and are sorted, as NumberSequence and ColorSequence need.
		t.deepEqual(EffectLogic.keypoints({ 5 }), { { time = 0, value = 5 }, { time = 1, value = 5 } })
		t.deepEqual(EffectLogic.keypoints({}), {})
		for stops = 2, 4 do
			local values = table.create(stops, 1)
			local points = EffectLogic.keypoints(values)
			t.equal(#points, stops)
			t.equal(points[1].time, 0)
			t.equal(points[stops].time, 1)
			for index = 2, stops do
				t.truthy(points[index].time > points[index - 1].time)
			end
		end
	end,

	["recipes: merge, join, multicolor and the cost label"] = function()
		local merged: any = Recipe.merge({ a = 1, burst = 4, flag = true }, { a = 2, burst = false, flag = false })
		t.equal(merged.a, 2)
		t.equal(merged.burst, nil, "false removes a non-boolean field")
		t.equal(merged.flag, false, "false stays false on a boolean field")
		local a = Recipe.glow("#FF0000")
		local b = Recipe.dust()
		local joined = Recipe.join(a, false, nil, { b, a }, b)
		t.equal(#joined, 4)
		t.equal(joined[2], b)
		local base = Recipe.particles({ name = "paper", burst = 40 })
		local split = Recipe.multicolor(base, { "#FF0000", "#00FF00", "#0000FF", "#FFFF00" })
		t.equal(#split, 4)
		t.equal(split[1].burst, 10)
		t.falsy(split[2].optional)
		t.truthy(split[3].optional, "colours past the second are optional")
		t.equal((split[2].colors :: { string })[1], "#00FF00")
		t.equal(base.burst, 40, "the source layer is untouched")
		t.equal(Recipe.dust().tint, false)
		t.equal(Recipe.sparkles("#FFFFFF").optional, true)
		local function def(burst: number, extra: EffectLogic.Layer?): EffectLogic.Definition
			return { layers = Recipe.join(Recipe.particles({ burst = burst }), extra) }
		end
		t.equal(Recipe.costLabel(def(40)), "low")
		t.equal(Recipe.costLabel(def(41)), "medium")
		t.equal(Recipe.costLabel(def(10, Recipe.beam("#FFFFFF"))), "medium")
		t.equal(Recipe.costLabel(def(121)), "high")
		t.equal(Recipe.costLabel(def(10, Recipe.postfx("bloom"))), "high")
		local tier = Recipe.tier("Legendary")
		t.equal(tier.rank, 5)
		t.truthy(tier.count > Recipe.tier("Epic").count and tier.duration > Recipe.tier("Epic").duration)
		t.equal(Recipe.tier("Nope").rank, 1)
	end,

	["legacy bridge: the five Systems/VFX presets are converted, not copied"] = function()
		local expected = {
			hatch = "LegacyHatch",
			levelUp = "LegacyLevelUp",
			coinPickup = "LegacyCoinPickup",
			rareAura = "LegacyRareAura",
			purchase = "LegacyPurchase",
		}
		for name, id in expected do
			t.equal(Catalog.legacyId(name), id)
			local preset = registry:get(id)
			t.equal(preset.category, "legacy")
			local source = VFXLogic.PRESETS[name]
			local def: EffectLogic.Definition = preset.data
			t.equal(#def.layers, #source.layers, id .. " layer count")
			t.equal(def.duration, source.duration)
			t.equal(def.looping, source.looping)
			for index, layer in def.layers do
				local from = source.layers[index]
				t.equal(layer.kind, "particles")
				t.equal(layer.name, from.name)
				t.deepEqual(layer.colors, from.colors)
				t.deepEqual(layer.sizes, from.sizes)
				t.deepEqual(layer.lifetime, from.lifetime)
				t.deepEqual(layer.speed, from.speed)
				t.equal(layer.burst, from.burst)
				t.equal(layer.rate, from.rate)
				t.equal(layer.gravity, from.gravity)
				t.equal(layer.optional, from.optional)
				t.deepEqual(layer.spread, { from.spread or 180, from.spread or 180 })
				t.deepEqual(layer.transparency, from.transparency or { 0, 1 })
				-- The copy is independent of the legacy table.
				t.truthy(layer.colors ~= from.colors)
			end
			-- Same one-shot particle total as the legacy system reports.
			if not source.looping then
				t.equal(EffectLogic.cost(def).particles, VFXLogic.particleCount(source), id .. " particle count")
			end
		end
		t.equal(#Catalog.legacy(), #VFXLogic.names())
		-- Legacy "low" drops the same optional layers that Low drops here.
		local legacyLow = VFXLogic.resolve("hatch", Quality.toLegacy("Low") :: any)
		local low = EffectLogic.resolve(data("LegacyHatch"), Quality.profile("Low"), nil, 1)
		t.equal(#low.layers, #legacyLow.layers)
		t.equal(Quality.fromLegacy("low"), "Low")
		-- A game-registered legacy preset converts the same way.
		local custom = Catalog.legacyPreset("sparkTrail", {
			looping = true,
			layers = {
				{
					name = "trail",
					colors = { "#FFFFFF" },
					sizes = { 0.2 },
					lifetime = { 0.2, 0.4 },
					speed = { 0, 1 },
					rate = 9,
				},
			},
		})
		t.equal(custom.id, "LegacySparkTrail")
		t.deepEqual(Registry.validate(custom), {})
		t.deepEqual(EffectLogic.validate(custom.data), {})
	end,

	["registry: search, override and reset work on the catalog"] = function()
		local fresh = Catalog.registry()
		t.equal(fresh:search("coin", 1)[1], "CoinBurst")
		t.truthy(table.find(fresh:search("rarity"), "RarityAura"))
		t.deepEqual(
			fresh:categories(),
			{ "combat", "eggs", "environment", "feeding", "legacy", "movement", "pets", "progression", "rewards" }
		)
		t.throws(function()
			fresh:register(fresh:get("CoinBurst"))
		end)
		local mine = table.clone(fresh:get("CoinBurst"))
		mine.description = "My game's own coin burst with a different look."
		fresh:register(mine, { override = true })
		t.truthy(fresh:isOverridden("CoinBurst"))
		t.truthy(fresh:reset("CoinBurst"))
		t.falsy(fresh:isOverridden("CoinBurst"))
		t.equal(fresh:describe("Rain").quality.cost, "medium")
		t.equal(fresh:describe("Rain").preview.loop, true)
	end,
}
