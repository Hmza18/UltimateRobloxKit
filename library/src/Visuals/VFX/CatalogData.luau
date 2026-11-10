--!strict
-- The built-in VFX catalog (pure Luau): every preset module in one list, plus the five legacy
-- Systems/VFX presets converted to the new schema, so nothing is written twice. VFX/VFX.luau builds
-- its registry from here; specs use it to check every preset without Roblox.

local EffectLogic = require("./EffectLogic")
local Recipe = require("./RecipeLogic")
local Registry = require("../Core/Registry")
local VFXLogic = require("../../Systems/VFX/VFXLogic")

local Catalog = {}

local MODULES: { { Registry.Preset } } = {
	require("./RewardsPresets"),
	require("./PetsPresets"),
	require("./EggsPresets"),
	require("./CombatPresets"),
	require("./MovementPresets"),
	require("./EnvironmentPresets"),
	require("./ProgressionPresets"),
	require("./FeedingPresets"),
}

Catalog.CATEGORIES =
	table.freeze({ "rewards", "pets", "eggs", "combat", "movement", "environment", "progression", "feeding" })

-- "coinPickup" -> "LegacyCoinPickup".
function Catalog.legacyId(name: string): string
	return "Legacy" .. string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

-- Converts a Systems/VFX preset (VFXLogic.Preset) to an effect definition. Field for field: the
-- legacy `spread` number becomes { spread, spread } and `gravity` stays the Y acceleration.
function Catalog.fromLegacy(preset: VFXLogic.Preset): EffectLogic.Definition
	local layers: { EffectLogic.Layer } = {}
	for _, source in preset.layers do
		local spread = source.spread or 180
		local layer: EffectLogic.Layer = {
			kind = "particles",
			name = source.name,
			texture = source.texture or "spark",
			colors = table.clone(source.colors),
			sizes = table.clone(source.sizes),
			transparency = if source.transparency then table.clone(source.transparency) else { 0, 1 },
			lifetime = table.clone(source.lifetime),
			speed = table.clone(source.speed),
			spread = { spread, spread },
			rate = source.rate,
			burst = if source.rate == nil then source.burst else nil,
			gravity = source.gravity,
			lightEmission = source.lightEmission or 0,
			rotSpeed = if source.rotSpeed then table.clone(source.rotSpeed) else nil,
			optional = source.optional,
		}
		table.insert(layers, layer)
	end
	return { duration = preset.duration, looping = preset.looping, layers = layers }
end

local LEGACY_TEXT: { [string]: { string } } = {
	hatch = { "Legacy hatch", "The Systems/VFX hatch burst: a warm radial burst with cool sparkles." },
	levelUp = { "Legacy level up", "The Systems/VFX level-up: a rising green ring of particles with stars." },
	coinPickup = { "Legacy coin pickup", "The Systems/VFX coin pickup: a small golden glint." },
	rareAura = { "Legacy rare aura", "The Systems/VFX rare aura: a looping purple haze with white motes." },
	purchase = { "Legacy purchase", "The Systems/VFX purchase: a three-colour confetti cone." },
}

-- The registry entry for one legacy preset.
function Catalog.legacyPreset(name: string, preset: VFXLogic.Preset): Registry.Preset
	local text = LEGACY_TEXT[name]
		or { "Legacy " .. name, "A Systems/VFX preset registered by the game: " .. name .. "." }
	local first = preset.layers[1]
	local colors = if first then first.colors else { "#FFFFFF" }
	local built = Recipe.preset({
		id = Catalog.legacyId(name),
		name = text[1],
		category = "legacy",
		description = text[2],
		color = colors[#colors],
		tags = { "legacy", name },
		data = Catalog.fromLegacy(preset),
	})
	return built
end

-- Legacy presets as registry entries, in name order.
function Catalog.legacy(): { Registry.Preset }
	local out: { Registry.Preset } = {}
	for _, name in VFXLogic.names() do
		table.insert(out, Catalog.legacyPreset(name, VFXLogic.PRESETS[name]))
	end
	return out
end

-- Every built-in preset followed by the legacy ones.
function Catalog.presets(): { Registry.Preset }
	local out: { Registry.Preset } = {}
	for _, list in MODULES do
		for _, preset in list do
			table.insert(out, preset)
		end
	end
	for _, preset in Catalog.legacy() do
		table.insert(out, preset)
	end
	return out
end

-- A new registry (kind "vfx") holding the catalog.
function Catalog.registry(): Registry.Registry
	local registry = Registry.new("vfx")
	for _, preset in Catalog.presets() do
		registry:register(preset)
	end
	return registry
end

-- Params ready for EffectLogic.resolve: defaults merged with `overrides` and validated by the
-- registry, with `color` removed when it is still the preset's default (no retint).
function Catalog.params(registry: Registry.Registry, id: string, overrides: { [string]: any }?): { [string]: any }
	local params = registry:params(id, overrides)
	local preset = registry:get(id)
	local declared = preset.params and preset.params.color
	local color = params.color
	if declared and type(color) == "string" and string.upper(color) == string.upper(declared.default) then
		params.color = nil
	end
	return params
end

return Catalog
