--!strict
-- Visuals.Presets: every preset in the kit, across VFX, UI animations, object animations, camera
-- moves and pet reactions. Registries are collected the first time this module is used; a module
-- that is not installed is simply left out.
--
--   Visuals.Presets.search("coin")                 -- { { kind = "vfx", id = "CoinBurst" }, ... }
--   Visuals.Presets.describe("vfx", "CoinBurst")   -- name, params, quality, usage line
--   Visuals.Presets.register("vfx", myPreset)      -- add a game preset
--   Visuals.Presets.register("vfx", myCoinBurst, { override = true })

local PresetsLogic = require("./PresetsLogic")
local Registry = require("../Core/Registry")

local Presets = {}

local catalog = PresetsLogic.new()
local collected = false

-- Each loader is a separate thunk because string requires must be literal.
local sources: { () -> any } = {
	function(): any
		return require("../VFX/VFX")
	end,
	function(): any
		return require("../UI/UIAnimations")
	end,
	function(): any
		return require("../Objects/Objects")
	end,
	function(): any
		return require("../Camera/Camera")
	end,
	function(): any
		return require("../Pets/Pets")
	end,
	function(): any
		return require("../Screens/Screens")
	end,
}

local function collect()
	if collected then
		return
	end
	collected = true
	for _, load in sources do
		local ok, module = pcall(load)
		if ok and type(module) == "table" and type(module.registry) == "table" then
			catalog:add(module.registry)
		end
	end
end

-- Adds a registry from a game module (anything built with Core/Registry).
function Presets.add(registry: Registry.Registry)
	collect()
	catalog:add(registry)
end

function Presets.kinds(): { string }
	collect()
	return catalog:kinds()
end

function Presets.count(): number
	collect()
	return catalog:count()
end

function Presets.search(query: string, limit: number?): { PresetsLogic.Entry }
	collect()
	return catalog:search(query, limit)
end

function Presets.list(kind: string?, filter: Registry.Filter?): { PresetsLogic.Entry }
	collect()
	return catalog:list(kind, filter)
end

function Presets.describe(kind: string, id: string): { [string]: any }
	collect()
	return catalog:describe(kind, id)
end

function Presets.usage(kind: string, id: string): string
	collect()
	return catalog:usage(kind, id)
end

-- Registers a preset into the registry of its kind. Pass { override = true } to replace a built-in.
function Presets.register(kind: string, preset: Registry.Preset, options: Registry.RegisterOptions?): Registry.Preset
	collect()
	local registry = catalog:registry(kind)
	if registry == nil then
		error("unknown preset kind: " .. tostring(kind), 2)
	end
	return registry:register(preset, options)
end

-- Puts a built-in preset back after an override.
function Presets.reset(kind: string, id: string): boolean
	collect()
	local registry = catalog:registry(kind)
	return registry ~= nil and registry:reset(id)
end

-- Plain metadata for every preset (JSON-safe), for tools and the playground.
function Presets.export(): { [string]: any }
	collect()
	return catalog:export()
end

return Presets
