--!strict
-- Visuals.VFX: plays data-driven effect presets in the world.
--
--   VFX.play("CoinBurst", position)
--   VFX.play("RarityBurst", petModel, { rarity = "Legendary" })
--   local aura = VFX.attach("RarityAura", petModel, { rarity = "Epic", owner = petModel })
--   aura.stop()                      -- looping effects fade out; aura.stop(true) removes at once
--   VFX.configure({ textures = { coin = "rbxassetid://123" } })
--
-- Every effect goes through Host.effects, which applies the quality budget, distance, offscreen
-- and throttle rules; a nil handle means the effect was skipped, which is normal. Presets live in
-- VFX.registry (Core/Registry, kind "vfx"); see README.md for the schema and the preset table.
--
-- NOT run in Studio. The pure half (EffectLogic, the preset modules, CatalogData) is Lune-tested.

local ContentProvider = game:GetService("ContentProvider")

local Builders = require("./Builders")
local Catalog = require("./CatalogData")
local EffectLogic = require("./EffectLogic")
local Host = require("../Runtime/Host")
local Quality = require("../Core/Quality")

export type Handle = {
	id: string,
	stop: (immediate: boolean?) -> (),
	cancel: (immediate: boolean?) -> (),
	isAlive: () -> boolean,
}

export type Config = { textures: { [string]: string }? }

local VFX = {}

VFX.registry = Catalog.registry()
VFX.EffectLogic = EffectLogic

type Live = { handle: Handle, owner: any? }

local live: { Live } = {}
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn("[UVK] " .. message)
	end
end

-- Camera and Audio are optional: VFX still works when those modules are not installed.
local function lazy(load: () -> any): () -> any
	local tried = false
	local module: any = nil
	return function(): any
		if not tried then
			tried = true
			local ok, result = pcall(load)
			if ok then
				module = result
			end
		end
		return module
	end
end

local camera = lazy(function(): any
	return (require :: any)("../Camera/Camera")
end)

local audio = lazy(function(): any
	return (require :: any)("../Audio/Audio")
end)

local function shake(preset: string, amount: number, position: Vector3)
	local module = camera()
	if module == nil or amount <= 0 then
		return
	end
	local ok, err = pcall(module.shake, preset, {
		intensity = amount,
		position = position,
		radius = Host.profile().maxDistance,
	})
	if not ok then
		warnOnce("shake:" .. preset, "camera shake " .. preset .. " failed: " .. tostring(err))
	end
end

local function sound(cue: string, volume: number?, at: Instance)
	local module = audio()
	if module == nil then
		return
	end
	local ok, err = pcall(module.play, cue, { volume = volume, at = at })
	if not ok then
		warnOnce("sound:" .. cue, "audio cue " .. cue .. " failed: " .. tostring(err))
	end
end

local function prune()
	local kept: { Live } = {}
	for _, entry in live do
		if entry.handle.isAlive() then
			table.insert(kept, entry)
		end
	end
	live = kept
end

local function start(id: string, at: any, params: { [string]: any }?): Handle?
	local registry = VFX.registry
	local preset = registry:find(id)
	if preset == nil then
		warnOnce("unknown:" .. tostring(id), "unknown vfx preset: " .. tostring(id))
		return nil
	end
	local profile = Host.profile()
	if preset.quality and not Quality.atLeast(profile.level, preset.quality.min) then
		return nil
	end
	local position = Builders.position(at)
	if position == nil then
		return nil
	end

	local given: { [string]: any } = if params then table.clone(params) else {}
	if typeof(given.color) == "Color3" then
		given.color = "#" .. string.upper(given.color:ToHex())
	end
	local ok, resolvedParams = pcall(Catalog.params, registry, id, given)
	if not ok then
		warnOnce("params:" .. id, tostring(resolvedParams))
		resolvedParams = Catalog.params(registry, id, nil)
	end
	local values: { [string]: any } = resolvedParams

	local hostSettings = Host.settings()
	local settings: EffectLogic.Settings = {
		reducedMotion = hostSettings.reducedMotion,
		reducedFlashing = hostSettings.reducedFlashing,
		intensity = Host.juice("particles"),
	}
	local def: EffectLogic.Definition = preset.data
	local preview = EffectLogic.resolve(def, profile, values, 1, settings)
	if #preview.layers == 0 then
		return nil
	end
	local cost = EffectLogic.cost(def, values)
	local amount = math.clamp((if type(values.intensity) == "number" then values.intensity else 1), 0, 2)
	local parent: Instance? = if typeof(values.parent) == "Instance" then values.parent else nil

	local control: Builders.Control? = nil
	local inner: any = nil
	local targetGone = false
	inner = Host.effects:spawn({
		id = id,
		particles = cost.particles * amount * (settings.intensity or 1),
		lights = preview.lights,
		duration = preview.duration + preview.linger,
		looping = preview.looping,
		position = { position.X, position.Y, position.Z },
		priority = if type(values.priority) == "number" then values.priority else preview.priority,
		owner = values.owner,
		minInterval = preview.minInterval,
		build = function(scale: number, buildProfile: Quality.Profile): (() -> ())?
			local resolved = if scale >= 0.999
				then preview
				else EffectLogic.resolve(def, buildProfile, values, scale, settings)
			local origin = Builders.origin(at, parent)
			if origin == nil then
				return nil
			end
			local stats = Host.effects:stats()
			local built = Builders.build(resolved, origin, {
				lights = math.max(0, buildProfile.maxLights - stats.lights),
				maxDistance = buildProfile.maxDistance,
				shake = shake,
				sound = sound,
			})
			control = built
			-- A looping effect on a part that leaves the world must not stay in the budget.
			local target = origin.moving
			if target then
				built.own(target.AncestryChanged:Connect(function()
					if not target:IsDescendantOf(game) then
						targetGone = true
						if inner then
							inner.stop()
						end
					end
				end))
			end
			return built.destroy
		end,
	})
	if inner == nil then
		return nil
	end
	if targetGone then
		inner.stop()
		return nil
	end

	local softening = false
	local function stop(immediate: boolean?)
		if not inner.isAlive() then
			return
		end
		local built = control
		if immediate or not preview.looping or built == nil then
			inner.stop()
			return
		end
		if softening then
			return
		end
		softening = true
		-- Soft stop: stop emitting, let live particles and envelopes fade, then destroy.
		local fade = built.soften()
		built.after(math.max(fade, preview.linger), function()
			inner.stop()
		end)
	end
	local handle: Handle = {
		id = id,
		stop = stop,
		cancel = stop,
		isAlive = function(): boolean
			return inner.isAlive()
		end,
	}
	if #live >= 64 then
		prune()
	end
	table.insert(live, { handle = handle, owner = values.owner })
	return handle
end

-- Plays a preset at a Vector3, CFrame, BasePart, Attachment or Model. Returns nil when skipped.
function VFX.play(id: string, at: any, params: { [string]: any }?): Handle?
	return start(id, at, params)
end

-- Attaches a preset (usually a looping one) to a BasePart, Attachment or Model.
function VFX.attach(id: string, target: any, params: { [string]: any }?): Handle?
	if typeof(target) ~= "Instance" then
		warnOnce("attach:" .. tostring(id), "VFX.attach needs a BasePart, Attachment or Model")
		return nil
	end
	return start(id, target, params)
end

-- Stops an effect. Looping effects fade out unless `immediate` is true. Safe on nil and twice.
function VFX.stop(handle: Handle?, immediate: boolean?)
	if handle then
		handle.stop(immediate)
	end
end

-- Immediately stops every VFX effect, or only those started with params.owner == owner.
function VFX.stopAll(owner: any?): number
	local count = 0
	for _, entry in table.clone(live) do
		if (owner == nil or entry.owner == owner) and entry.handle.isAlive() then
			entry.handle.stop(true)
			count += 1
		end
	end
	prune()
	return count
end

-- Texture ids by key ("spark", "glow", "coin", ...). Keys without an id use built-in textures.
function VFX.configure(config: Config)
	if config.textures then
		Builders.setTextures(config.textures)
	end
end

function VFX.textures(): { [string]: string }
	return Builders.textures()
end

function VFX.stats(): { [string]: any }
	prune()
	local effects = Host.effects:stats()
	return {
		live = #live,
		effects = effects.live,
		particles = effects.particles,
		lights = effects.lights,
		rejected = effects.rejected,
		highlights = Builders.highlightCount(),
		holders = Builders.poolStats(),
		presets = VFX.registry:count(),
	}
end

-- Asks Roblox to load the configured texture ids ahead of first use. Returns at once.
function VFX.preload()
	local ids: { any } = {}
	for _, id in Builders.textures() do
		table.insert(ids, id)
	end
	if #ids == 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(ids)
		end)
	end)
end

return VFX
