--!strict
-- Cross-module referential integrity for UltimateVisualsKit.
--
-- The visuals modules call each other through lazy, pcall-guarded requires and pass preset ids,
-- cue names and option tables as plain data, so a wrong id or option fails silently at runtime.
-- This spec loads the pure data / logic modules and checks that every reference resolves:
--
--   * Feedback packs   -> VFX, UI, Camera, Objects, Pets, Audio, Rewards
--   * Rewards profiles -> VFX (with valid params), Camera, Audio, Core/Springs
--   * Hatch plans      -> VFX (with valid params), Camera, Pets, Audio, Core/Springs
--   * Pet timelines    -> VFX, Objects, pet reactions
--   * VFX presets      -> Camera shake presets, Audio cues, texture keys
--   * Themes           -> Core/Springs, Core/Curves, VFX texture keys, rarity names
--
-- The last group scans the runtime sources for string literals (easing and spring names, preset
-- ids passed to another module) because those call sites cannot be loaded outside Roblox.

local fs = require("@lune/fs")

local AudioLogic = require("../src/Visuals/Audio/AudioLogic")
local CameraLogic = require("../src/Visuals/Camera/CameraLogic")
local Catalog = require("../src/Visuals/VFX/CatalogData")
local Curves = require("../src/Visuals/Core/Curves")
local EffectLogic = require("../src/Visuals/VFX/EffectLogic")
local FeedbackLogic = require("../src/Visuals/Feedback/FeedbackLogic")
local HatchLogic = require("../src/Visuals/Eggs/HatchLogic")
local ObjectsLogic = require("../src/Visuals/Objects/ObjectsLogic")
local PetsLogic = require("../src/Visuals/Pets/PetsLogic")
local RewardsLogic = require("../src/Visuals/Rewards/RewardsLogic")
local Springs = require("../src/Visuals/Core/Springs")
local ThemeData = require("../src/Visuals/Themes/ThemeData")
local ThemeLogic = require("../src/Visuals/Themes/ThemeLogic")
local UILogic = require("../src/Visuals/UI/UILogic")
local UIPresets = require("../src/Visuals/UI/UIPresets")
local t = require("./lib/t")

local vfx = Catalog.registry()

-- Option names each runtime function documents. A caller that passes another key is a typo or a
-- drifted name: the callee would ignore it without a word.
local OPTIONS: { [string]: { string } } = {
	sound = { "volume", "pitch", "pitchVariance", "force", "at" },
	shake = {
		"intensity",
		"seed",
		"duration",
		"amplitude",
		"rotation",
		"frequency",
		"fadeIn",
		"fadeOut",
		"position",
		"radius",
	},
	move = {
		"priority",
		"blendIn",
		"blendOut",
		"duration",
		"easing",
		"fov",
		"onDone",
		"distance",
		"angle",
		"elevation",
		"height",
	},
	popup = { "style", "color", "size", "duration", "format", "font", "offset", "onDone" },
	flyTo = {
		"count",
		"image",
		"color",
		"size",
		"spread",
		"duration",
		"stagger",
		"seed",
		"punch",
		"onArrive",
		"onDone",
	},
	flash = { "duration", "alpha", "onDone" },
	shine = { "duration", "delay", "angle", "width", "alpha", "color", "loop", "interval", "onDone" },
	countTo = { "from", "duration", "easing", "format", "prefix", "suffix", "pop", "onStep", "onDone" },
	object = {
		"amplitude",
		"speed",
		"duration",
		"axis",
		"phase",
		"intensity",
		"target",
		"onDone",
		"restore",
		"allowUnanchored",
		"fresh",
	},
	pet = { "rarity", "color", "intensity", "direction", "vfx", "onDone" },
	hatch = {
		"mode",
		"origin",
		"distance",
		"speed",
		"camera",
		"ui",
		"skippable",
		"autoContinue",
		"hold",
		"parent",
		"guiParent",
		"sounds",
		"onReveal",
		"next",
	},
	-- VFX attach steps: Feedback reads options.duration itself.
	vfx = { "duration" },
}

local function isReference(value: any): boolean
	return type(value) == "string" and string.find(value, "$", 1, true) ~= nil
end

local function isHex(value: any): boolean
	return type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") ~= nil
end

local function isCue(cue: any): boolean
	return type(cue) == "string" and table.find(AudioLogic.CUES, cue) ~= nil
end

local function checkOptions(options: any, kind: string, where: string)
	if options == nil then
		return
	end
	t.equal(type(options), "table", where .. ": options must be a table")
	local allowed = OPTIONS[kind]
	for key in options do
		t.truthy(table.find(allowed, key) ~= nil, where .. ": unknown " .. kind .. " option '" .. tostring(key) .. "'")
	end
end

-- The preset exists and accepts these params (types, enum options, hex colours). Context
-- references ("$element") are left out: their values only exist at runtime.
local function checkVfx(id: any, params: any, where: string)
	t.truthy(type(id) == "string" and vfx:has(id), where .. ": unknown VFX preset " .. tostring(id))
	local literal: { [string]: any } = {}
	if type(params) == "table" then
		for key, value in params do
			if not isReference(value) then
				literal[key] = value
			end
		end
	end
	local ok, err = pcall(function()
		vfx:params(id, literal)
	end)
	t.truthy(ok, where .. ": " .. id .. " rejects its params: " .. tostring(err))
end

local function checkShake(name: any, where: string)
	t.truthy(
		type(name) == "string" and CameraLogic.shakeDef(name) ~= nil,
		where .. ": unknown camera shake " .. tostring(name)
	)
end

local function checkCinematic(name: any, where: string)
	t.truthy(
		type(name) == "string" and CameraLogic.cinematic(name) ~= nil,
		where .. ": unknown cinematic " .. tostring(name)
	)
end

local function checkPet(id: any, where: string)
	t.truthy(type(id) == "string" and PetsLogic.registry:has(id), where .. ": unknown pet reaction " .. tostring(id))
end

local function checkStep(step: FeedbackLogic.Step, where: string)
	local kind = step.kind
	local options = step.options
	if kind == "vfx" then
		checkVfx(step.id, step.params, where)
		checkOptions(options, "vfx", where)
	elseif kind == "ui" then
		local action = step.action or "animate"
		t.truthy(table.find(FeedbackLogic.UI_ACTIONS, action) ~= nil, where .. ": unknown ui action " .. action)
		if action == "animate" or action == "show" or action == "hide" then
			if step.preset ~= nil and not isReference(step.preset) then
				t.truthy(UIPresets.registry:has(step.preset), where .. ": unknown UI preset " .. tostring(step.preset))
			end
		elseif action == "flash" then
			t.truthy(step.color == nil or isReference(step.color) or isHex(step.color), where .. ": flash colour")
			checkOptions(options, "flash", where)
		elseif action == "shine" then
			checkOptions(options, "shine", where)
		elseif action == "countTo" then
			checkOptions(options, "countTo", where)
		end
	elseif kind == "popup" then
		checkOptions(options, "popup", where)
		if options and options.style ~= nil then
			t.truthy(
				table.find(UILogic.POPUP_STYLES, options.style) ~= nil,
				where .. ": unknown popup style " .. tostring(options.style)
			)
		end
		if options and options.color ~= nil then
			t.truthy(isHex(options.color), where .. ": popup colour must be #RRGGBB")
		end
	elseif kind == "flyTo" then
		checkOptions(options, "flyTo", where)
		if options and options.color ~= nil then
			t.truthy(isHex(options.color), where .. ": flyTo colour must be #RRGGBB")
		end
	elseif kind == "camera" then
		if step.shake ~= nil then
			checkShake(step.shake, where)
			checkOptions(options, "shake", where)
		elseif step.cinematic ~= nil then
			checkCinematic(step.cinematic, where)
			checkOptions(options, "move", where)
		else
			checkOptions(options, "move", where)
		end
	elseif kind == "sound" then
		t.truthy(isCue(step.cue), where .. ": cue '" .. tostring(step.cue) .. "' is not in AudioLogic.CUES")
		checkOptions(options, "sound", where)
	elseif kind == "object" then
		t.truthy(ObjectsLogic.has(step.preset), where .. ": unknown object preset " .. tostring(step.preset))
		checkOptions(options, "object", where)
	elseif kind == "pet" then
		checkPet(step.reaction, where)
		checkOptions(options, "pet", where)
	elseif kind == "reward" then
		if not isReference(step.rarity) then
			t.truthy(RewardsLogic.has(step.rarity), where .. ": unknown rarity " .. tostring(step.rarity))
		end
	elseif kind == "hatch" then
		checkOptions(step.config, "hatch", where)
	end
end

-- Every definition a preset can resolve to: the base and each variant.
local function definitions(preset: any): { EffectLogic.Definition }
	local base: EffectLogic.Definition = preset.data
	local out = { base }
	for _, variant in base.variants or {} do
		table.insert(out, variant)
	end
	return out
end

local RARE_CUSTOM = "IntegrationCelestial"

-- Sources ------------------------------------------------------------------------------------

local function sourceRoot(): string?
	for _, candidate in { "src", "../src", "library/src" } do
		if fs.isDir(candidate .. "/Visuals") then
			return candidate
		end
	end
	return nil
end

local function collect(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			collect(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

type Line = { path: string, number: number, text: string }

-- Code lines (comments dropped) of the visuals runtime and the game components.
local function sourceLines(): { Line }
	local root = sourceRoot()
	local lines: { Line } = {}
	if root == nil then
		return lines
	end
	local files: { string } = {}
	collect(root .. "/Visuals", files)
	collect(root .. "/UI/Game", files)
	table.sort(files)
	for _, path in files do
		local number = 0
		for text in string.gmatch(fs.readFile(path) .. "\n", "(.-)\n") do
			number += 1
			if string.match(text, "^%s*%-%-") == nil then
				table.insert(lines, { path = path, number = number, text = text })
			end
		end
	end
	return lines
end

-- Runs `check(name)` for every capture of `pattern` in the sources; returns how many it saw.
local function scan(lines: { Line }, pattern: string, check: (name: string) -> boolean, what: string): number
	local seen = 0
	for _, line in lines do
		for name in string.gmatch(line.text, pattern) do
			seen += 1
			t.truthy(check(name), string.format("%s:%d: unknown %s '%s'", line.path, line.number, what, name))
		end
	end
	return seen
end

return {
	["rarity names agree across Rewards, VFX and Themes"] = function()
		t.deepEqual(table.clone(EffectLogic.RARITIES), table.clone(RewardsLogic.ORDER), "VFX and Rewards rarities")
		t.deepEqual(table.clone(ThemeData.RARITIES), table.clone(RewardsLogic.ORDER), "Theme and Rewards rarities")
		for _, rarity in RewardsLogic.ORDER do
			t.truthy(isCue("rarity." .. string.lower(rarity)), "no audio cue for rarity " .. rarity)
			for _, id in ThemeData.IDS do
				t.truthy(isHex(ThemeData.themes[id].rarity[rarity]), id .. " has no colour for " .. rarity)
			end
		end
		-- Presets with a rarity param accept exactly the built-in names, in the same casing.
		for _, id in { "RarityBurst", "RarityBeam", "RarityAura", "HatchBurst" } do
			local param = vfx:get(id).params.rarity
			t.equal(param.type, "enum", id .. ".rarity")
			t.deepEqual(table.clone(param.options), table.clone(RewardsLogic.ORDER), id .. ".rarity options")
		end
	end,

	["feedback packs only reference things that exist"] = function()
		local steps = 0
		for _, name in FeedbackLogic.packs() do
			local pack = FeedbackLogic.pack(name)
			t.truthy(pack ~= nil, "pack " .. name)
			for event, recipe in pack :: { [string]: FeedbackLogic.Recipe } do
				local ok, message = FeedbackLogic.validate(recipe)
				t.truthy(ok, name .. "." .. event .. ": " .. tostring(message))
				for index, step in recipe do
					steps += 1
					checkStep(step, string.format("%s.%s step %d (%s)", name, event, index, tostring(step.kind)))
				end
			end
		end
		t.truthy(steps > 60, "the packs were walked")
		for _, id in FeedbackLogic.UI_PRESETS do
			t.truthy(UIPresets.registry:has(id), "FeedbackLogic.UI_PRESETS names unknown preset " .. id)
		end
	end,

	["feedback steps resolve to the argument shapes the runners pass on"] = function()
		-- The Tap recipe with a full context keeps every step and substitutes the references.
		local pack = FeedbackLogic.pack("Simulator") :: { [string]: FeedbackLogic.Recipe }
		local context = { gui = "GUI", position = "POS", amount = 5, counter = "COUNTER", total = 105 }
		local steps, dropped = FeedbackLogic.resolve(pack.Tap, context, { count = 5 })
		t.equal(#dropped, 0, "nothing dropped with a full context")
		t.equal(#steps, #pack.Tap)
		t.equal(steps[1].target, "GUI")
		t.equal(steps[2].text, "+5")
		t.equal(steps[2].at, "POS")
		local collected = FeedbackLogic.resolve(pack.CollectCoin, context)
		t.equal(collected[2].from, "POS")
		t.equal(collected[2].to, "COUNTER")
		t.equal(collected[3].to, 105)
	end,

	["reward profiles reference valid VFX, shakes, cues and springs"] = function()
		RewardsLogic.reset()
		RewardsLogic.register(RARE_CUSTOM, { extends = "Legendary", rank = 5.5, color = "#7AF0FF" })
		local ok, err = pcall(function()
			for _, id in RewardsLogic.list() do
				local profile = RewardsLogic.get(id)
				local where = "rarity " .. id
				t.truthy(Springs.has(profile.spring), where .. ": unknown spring " .. profile.spring)
				for index, entry in profile.vfx do
					checkVfx(entry.id, entry.params, where .. " vfx[" .. index .. "]")
				end
				if profile.camera.shake then
					checkShake(profile.camera.shake, where)
				end
				if profile.camera.cinematic then
					checkCinematic(profile.camera.cinematic, where)
				end
				for _, cue in profile.sounds do
					t.truthy(isCue(cue), where .. ": cue '" .. cue .. "' is not in AudioLogic.CUES")
				end
				for _, hex in { profile.color, profile.secondary, profile.glow } do
					t.truthy(isHex(hex), where .. ": colours must be #RRGGBB")
				end
			end
		end)
		RewardsLogic.reset()
		t.truthy(ok, tostring(err))
		for _, name in RewardsLogic.SOFT_SHAKES do
			checkShake(name, "RewardsLogic.SOFT_SHAKES")
		end
		for _, name in RewardsLogic.CINEMATICS do
			checkCinematic(name, "RewardsLogic.CINEMATICS")
		end
	end,

	["reward plans carry valid ids and params in every step"] = function()
		RewardsLogic.reset()
		RewardsLogic.register(RARE_CUSTOM, { extends = "Mythic", rank = 6.5 })
		local variants: { RewardsLogic.Options } = {
			{},
			{ compact = true },
			{ quality = "Low" },
			{ reducedMotion = true, reducedFlashing = true },
			{ fastForward = true },
		}
		local ok, err = pcall(function()
			local vfxSteps = 0
			for _, id in RewardsLogic.list() do
				for index, options in variants do
					local plan = RewardsLogic.plan(id, { name = "Prize", amount = 250 }, options)
					local where = string.format("plan %s #%d", id, index)
					for _, step in plan.steps do
						local payload = step.payload
						if step.kind == "vfx" then
							vfxSteps += 1
							checkVfx(payload.id, payload.params, where)
						elseif step.kind == "shake" then
							checkShake(payload.preset, where)
						elseif step.kind == "sound" then
							t.truthy(isCue(payload.cue), where .. ": cue '" .. tostring(payload.cue) .. "'")
						elseif step.kind == "camera" and payload.cinematic then
							checkCinematic(payload.cinematic, where)
						elseif step.kind == "reveal" and payload.spring then
							t.truthy(Springs.has(payload.spring), where .. ": spring " .. tostring(payload.spring))
						end
					end
				end
			end
			t.truthy(vfxSteps > 20, "plans contain VFX steps")
		end)
		RewardsLogic.reset()
		t.truthy(ok, tostring(err))
	end,

	["hatch plans carry valid ids and params, custom rarities included"] = function()
		RewardsLogic.reset()
		RewardsLogic.register(RARE_CUSTOM, { extends = "Legendary", rank = 5.6, color = "#7AF0FF" })
		local rarities = RewardsLogic.list()
		local batches: { { mode: string?, count: number, options: HatchLogic.Options } } = {
			{ count = 1, options = {} },
			{ count = 1, options = { quality = "Low" } },
			{ count = 1, options = { reducedMotion = true, reducedFlashing = true } },
			{ count = 3, options = {} },
			{ count = 8, options = {} },
			{ count = 8, options = { quality = "Low" } },
			{ count = 4, options = { mode = "auto" } },
		}
		local ok, err = pcall(function()
			local checked = 0
			for _, top in rarities do
				for index, batch in batches do
					local eggs: { any } = {}
					for i = 1, batch.count do
						-- The named rarity plus a spread of others, so every tier appears in a batch.
						table.insert(eggs, { rarity = if i == 1 then top else rarities[(i - 1) % #rarities + 1] })
					end
					local plan = HatchLogic.plan(eggs, batch.options)
					local where = string.format("hatch %s #%d", top, index)
					for _, step in plan.steps do
						local payload: { [string]: any } = step.payload or {}
						checked += 1
						if payload.vfx ~= nil then
							checkVfx(payload.vfx, payload.params, where .. " " .. step.kind)
						end
						if payload.flash ~= nil then
							checkVfx(payload.flash, nil, where .. " " .. step.kind)
						end
						if payload.aura ~= nil then
							checkVfx(
								payload.aura,
								{ rarity = payload.vfxRarity, color = payload.color },
								where .. " aura"
							)
						end
						if step.kind == "rarity" then
							t.truthy(
								table.find(EffectLogic.RARITIES, payload.vfxRarity) ~= nil,
								where .. ": vfxRarity must be a built-in tier, got " .. tostring(payload.vfxRarity)
							)
							checkVfx("RarityBurst", { rarity = payload.vfxRarity, color = payload.color }, where)
							checkVfx("RarityBeam", { rarity = payload.vfxRarity, color = payload.color }, where)
							for _, id in payload.celebrate do
								checkVfx(id, { color = payload.color }, where .. " celebrate")
							end
						end
						if payload.cue ~= nil then
							t.truthy(isCue(payload.cue), where .. ": cue '" .. tostring(payload.cue) .. "'")
						end
						if
							payload.rarityCue ~= nil
							and table.find(RewardsLogic.ORDER, plan.eggs[step.egg :: number].rarity)
						then
							t.truthy(isCue(payload.rarityCue), where .. ": cue '" .. tostring(payload.rarityCue) .. "'")
						end
						if type(payload.shake) == "string" then
							checkShake(payload.shake, where .. " " .. step.kind)
						end
						if payload.cinematic ~= nil then
							checkCinematic(payload.cinematic, where)
						end
						if payload.reaction ~= nil then
							checkPet(payload.reaction, where)
						end
						if payload.spring ~= nil then
							t.truthy(Springs.has(payload.spring), where .. ": spring " .. tostring(payload.spring))
						end
					end
				end
			end
			t.truthy(checked > 500, "plans were walked")
		end)
		RewardsLogic.reset()
		t.truthy(ok, tostring(err))
	end,

	["a custom rarity maps to the nearest built-in VFX tier"] = function()
		RewardsLogic.reset()
		RewardsLogic.register(RARE_CUSTOM, { extends = "Legendary", rank = 5.6 })
		local ok, err = pcall(function()
			local plan = HatchLogic.plan({ { rarity = RARE_CUSTOM } })
			local seen = 0
			for _, step in plan.steps do
				if step.kind == "appear" then
					seen += 1
					t.equal(step.payload.params.rarity, "Mythic", "rank 5.6 rounds to Mythic")
				elseif step.kind == "rarity" then
					seen += 1
					t.equal(step.payload.rarity, RARE_CUSTOM, "the label keeps the custom rarity")
					t.equal(step.payload.vfxRarity, "Mythic")
				end
			end
			t.equal(seen, 2)
			local builtin = HatchLogic.plan({ { rarity = "Epic" } })
			for _, step in builtin.steps do
				if step.kind == "appear" then
					t.equal(step.payload.params.rarity, "Epic", "built-in rarities pass through")
				end
			end
		end)
		RewardsLogic.reset()
		t.truthy(ok, tostring(err))
	end,

	["pet timelines reference valid VFX, object presets and reactions"] = function()
		for _, id in PetsLogic.PLANS do
			local plan = PetsLogic.plan(id)
			t.truthy(plan ~= nil, "plan " .. id)
			local timeline = plan :: PetsLogic.Plan
			t.deepEqual(PetsLogic.validatePlan(timeline), {}, id)
			for index, step in timeline.steps do
				local where = string.format("pet plan %s step %d", id, index)
				if step.kind == "vfx" then
					-- Pets.play passes these params with every timeline effect.
					checkVfx(step.id, { rarity = nil, color = "#FFFFFF", intensity = 1 }, where)
				elseif step.kind == "object" then
					t.truthy(ObjectsLogic.has(step.id :: string), where .. ": object preset " .. tostring(step.id))
					t.falsy(ObjectsLogic.isLoop(step.id :: string), where .. ": needs a one-shot")
				elseif step.kind == "reaction" then
					t.truthy(PetsLogic.isReaction(step.id :: string), where .. ": reaction " .. tostring(step.id))
				end
			end
			t.truthy(PetsLogic.registry:has(id), id .. " is registered")
		end
		for _, id in PetsLogic.REACTIONS do
			t.truthy(PetsLogic.registry:has(id), id .. " is registered")
		end
		-- The aura the animator attaches for a rarity, and the presets other modules ask Pets for.
		checkVfx("RarityAura", { rarity = "Epic" }, "PetAnimator aura")
		for _, id in { "HappyReaction", "Equip", "Unequip", "Spawn" } do
			checkPet(id, "contract")
		end
	end,

	["VFX presets reference valid shakes, cues, textures and dependencies"] = function()
		local shakes, layers = 0, 0
		for _, preset in vfx:list() do
			for _, def in definitions(preset) do
				for index, layer in def.layers do
					layers += 1
					local where = string.format("%s layer %d (%s)", preset.id, index, layer.kind)
					if layer.kind == "shake" then
						shakes += 1
						checkShake(layer.preset, where)
					elseif layer.kind == "sound" then
						t.truthy(isCue(layer.cue), where .. ": cue '" .. tostring(layer.cue) .. "'")
					end
					for _, key in { layer.texture, layer.image } do
						t.truthy(
							table.find(EffectLogic.TEXTURE_KEYS, key) ~= nil,
							where .. ": unknown texture key " .. tostring(key)
						)
					end
					if layer.easing ~= nil then
						t.truthy(Curves.has(layer.easing), where .. ": unknown curve " .. tostring(layer.easing))
					end
				end
			end
			for _, dependency in preset.dependencies or {} do
				local known = vfx:has(dependency)
					or table.find(EffectLogic.TEXTURE_KEYS, dependency) ~= nil
					or isCue(dependency)
					or CameraLogic.shakeDef(dependency) ~= nil
				t.truthy(known, preset.id .. ": dependency '" .. dependency .. "' resolves nowhere")
			end
		end
		t.truthy(layers > 200, "layers were walked")
		t.truthy(shakes >= 8, "some presets shake the camera")
	end,

	["camera, object and pet registries match their logic tables"] = function()
		for _, preset in CameraLogic.registry:list({ category = "shake" }) do
			checkShake(preset.id, "camera registry")
		end
		for _, preset in CameraLogic.registry:list({ category = "cinematic" }) do
			checkCinematic(preset.id, "camera registry")
		end
		for _, name in { "SoftImpact", "Impact", "HeavyImpact", "Rumble", "Tap", "Hatch", "Landing", "Explosion" } do
			checkShake(name, "contract")
			t.truthy(CameraLogic.registry:has(name), name .. " is registered")
		end
		for _, name in { "PetReveal", "RewardReveal", "AreaUnlock", "Teleport" } do
			checkCinematic(name, "contract")
			t.truthy(CameraLogic.registry:has(name), name .. " is registered")
		end
		for _, id in ObjectsLogic.LOOPS do
			t.truthy(ObjectsLogic.registry:has(id), id)
		end
		for _, id in ObjectsLogic.ONE_SHOTS do
			t.truthy(ObjectsLogic.registry:has(id), id)
		end
		t.equal(ObjectsLogic.registry:count(), #ObjectsLogic.LOOPS + #ObjectsLogic.ONE_SHOTS)
		-- Pet dependencies listed in the registry are VFX presets.
		for _, preset in PetsLogic.registry:list() do
			for _, dependency in preset.dependencies or {} do
				t.truthy(vfx:has(dependency), preset.id .. ": dependency " .. dependency)
			end
		end
	end,

	["theme tokens resolve in Springs, Curves and the VFX texture keys"] = function()
		t.equal(#ThemeData.IDS, 10)
		for _, id in ThemeData.IDS do
			local theme = ThemeData.themes[id]
			t.truthy(theme ~= nil, id)
			t.deepEqual(ThemeLogic.validate(theme), {}, id .. " validates")
			for _, role in ThemeData.SPRING_ROLES do
				local name = theme.motion.spring[role]
				t.truthy(
					Springs.has(name),
					string.format("%s motion.spring.%s: unknown spring %s", id, role, tostring(name))
				)
			end
			t.truthy(Curves.has(theme.motion.easing), id .. " motion.easing: " .. theme.motion.easing)
			t.truthy(Springs.has(theme.motion.reduced.spring), id .. " motion.reduced.spring")
			t.truthy(Curves.has(theme.motion.reduced.easing), id .. " motion.reduced.easing")
			for _, role in ThemeData.TRANSITION_ROLES do
				local transition = theme.motion.transition[role]
				t.truthy(
					table.find(ThemeData.TRANSITIONS, transition) ~= nil,
					string.format("%s motion.transition.%s: %s", id, role, tostring(transition))
				)
			end
			t.truthy(
				table.find(EffectLogic.TEXTURE_KEYS, theme.effects.sparkle) ~= nil,
				id .. " effects.sparkle: '" .. theme.effects.sparkle .. "' is not a VFX texture key"
			)
			for index, hex in theme.effects.particles do
				t.truthy(isHex(hex), string.format("%s effects.particles.%d", id, index))
				-- A particle colour is a valid `color` param for any preset.
				checkVfx("SparkleBurst", { color = hex }, id .. " particle colour")
			end
		end
		for _, name in Springs.NAMES do
			t.truthy(Springs.has(name), name)
		end
	end,

	["audio cue list has no duplicates and covers what the modules play"] = function()
		local seen: { [string]: boolean } = {}
		for _, cue in AudioLogic.CUES do
			t.falsy(seen[cue], "duplicate cue " .. cue)
			seen[cue] = true
		end
		for _, cue in
			{ "tap", "coin", "gem", "whoosh", "impact", "success", "error", "level.up", "quest.complete", "pet.happy" }
		do
			t.truthy(seen[cue], cue)
		end
		for _, cue in { "egg.land", "egg.wobble", "egg.energy", "egg.crack", "egg.reveal", "reward.reveal" } do
			t.truthy(seen[cue], cue)
		end
		for _, cue in { "food.throw", "food.hit", "ui.hover", "ui.press", "ui.pop", "ui.close" } do
			t.truthy(seen[cue], cue)
		end
	end,

	["string literals in the runtime sources name things that exist"] = function()
		local lines = sourceLines()
		if #lines == 0 then
			return -- a game project copy without the sources next to the specs
		end
		local function curve(name: string): boolean
			return Curves.has(name)
		end
		local function spring(name: string): boolean
			return Springs.has(name)
		end
		local function uiPreset(name: string): boolean
			return UIPresets.registry:has(name)
		end
		local function vfxPreset(name: string): boolean
			return vfx:has(name)
		end
		local function shake(name: string): boolean
			return CameraLogic.shakeDef(name) ~= nil
		end
		local function cinematic(name: string): boolean
			return CameraLogic.cinematic(name) ~= nil
		end
		local function cue(name: string): boolean
			return isCue(name)
		end
		local function pet(name: string): boolean
			return PetsLogic.registry:has(name)
		end

		local curves = scan(lines, 'easing = "([%w_]+)"', curve, "curve")
		curves += scan(lines, 'easing or "([%w_]+)"', curve, "curve")
		local springs = scan(lines, 'spring = "([%w_]+)"', spring, "spring")
		springs += scan(lines, 'Motion%.spring%(.-}, "([%w_]+)"', spring, "spring")
		springs += scan(lines, 'Motion%.punch%(.-, "(%u[%w_]+)"%)', spring, "spring")
		local ui = scan(lines, '[Uu][Ii]%.animate%([^,]+, "([%w_]+)"', uiPreset, "UI preset")
		ui += scan(lines, '[Uu][Ii]%.show%([^,]+, "([%w_]+)"', uiPreset, "UI preset")
		ui += scan(lines, '[Uu][Ii]%.hide%([^,]+, "([%w_]+)"', uiPreset, "UI preset")
		ui += scan(lines, '[Uu][Ii]%.stagger%([^,]+, "([%w_]+)"', uiPreset, "UI preset")
		ui += scan(lines, 'hasUiPreset%("([%w_]+)"%)', uiPreset, "UI preset")
		local effects = scan(lines, '"play", "(%u[%w_]+)"', vfxPreset, "VFX preset")
		effects += scan(lines, '"attach", "(%u[%w_]+)"', vfxPreset, "VFX preset")
		effects += scan(lines, 'vfx%.play, "(%u[%w_]+)"', vfxPreset, "VFX preset")
		effects += scan(lines, 'vfx%.attach, "(%u[%w_]+)"', vfxPreset, "VFX preset")
		effects += scan(lines, 'vfx = "(%u[%w_]+)"', vfxPreset, "VFX preset")
		effects += scan(lines, 'kind = "vfx", id = "(%u[%w_]+)"', vfxPreset, "VFX preset")
		local shakes = scan(lines, 'shake = "(%u[%w_]+)"', shake, "camera shake")
		shakes += scan(lines, 'R%.shake%("(%u[%w_]+)"', shake, "camera shake")
		shakes += scan(lines, '"shake", "(%u[%w_]+)"', shake, "camera shake")
		local cinematics = scan(lines, 'cinematic = "(%u[%w_]+)"', cinematic, "cinematic")
		local cues = scan(lines, 'cue = "([%w_%.]+)"', cue, "audio cue")
		cues += scan(lines, 'audioModule%(%), "play", "([%w_%.]+)"', cue, "audio cue")
		cues += scan(lines, 'R%.sound%("([%w_%.]+)"', cue, "audio cue")
		local pets = scan(lines, 'reaction = "(%u[%w_]+)"', pet, "pet reaction")

		-- The patterns must keep matching the code they were written for; if a refactor makes one
		-- stop matching, this spec would pass while guarding nothing.
		t.truthy(curves >= 40, "easing literals found: " .. curves)
		t.truthy(springs >= 20, "spring literals found: " .. springs)
		t.truthy(ui >= 25, "UI preset literals found: " .. ui)
		t.truthy(effects >= 25, "VFX preset literals found: " .. effects)
		t.truthy(shakes >= 15, "shake literals found: " .. shakes)
		t.truthy(cinematics >= 2, "cinematic literals found: " .. cinematics)
		t.truthy(cues >= 30, "cue literals found: " .. cues)
		t.truthy(pets >= 4, "pet reaction literals found: " .. pets)
	end,

	["option names passed across modules are ones the callee documents"] = function()
		local lines = sourceLines()
		if #lines == 0 then
			return
		end
		-- Pets.preview(viewport, model, options): PetPreview.Options has no `spin`.
		local previews = 0
		for _, line in lines do
			if string.find(line.text, "module.preview, viewport", 1, true) then
				previews += 1
				t.falsy(
					string.find(line.text, "spin =", 1, true),
					line.path .. ": Pets.preview has no `spin` option (use turntable)"
				)
			end
			-- UI and Objects handles take stop(restore?), VFX handles stop(immediate?): passing the
			-- handle itself as that argument silently turns the flag on.
			t.falsy(
				string.find(line.text, "pcall(stop, handle)", 1, true) ~= nil
					and string.find(line.path, "IconVault", 1, true) ~= nil,
				line.path .. ":" .. line.number .. ": handle.stop is not a method"
			)
		end
		t.truthy(previews >= 1, "the Pets.preview call site was found")
	end,
}
