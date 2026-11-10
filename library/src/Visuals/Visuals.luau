--!strict
-- UltimateVisualsKit (UVK): one entry point for motion, VFX, UI animation, pets, eggs, rewards,
-- camera, object animation and gameplay feedback.
--
--   local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)
--
--   Visuals:Play("CoinBurst", position)
--   Visuals.UI:Animate(button, "BouncyPress")
--   Visuals.Pets:Play("HappyReaction", petModel)
--   Visuals.Rewards:Reveal("Legendary", rewardData)
--   Visuals.Camera:Shake("SoftImpact")
--   Visuals.Sequence():Play("SparkleBurst", position):Wait(0.2):Play("RewardGlow", position):Start()
--
-- Sub-modules load on first use, so a game that only animates UI never loads the pet or egg code.
-- Each sub-module is a table of functions (Visuals.UI.animate); the facade also accepts the method
-- style shown above (Visuals.UI:Animate), so both spellings work everywhere.
--
-- Visuals are cosmetic and client-side. Nothing here decides gameplay results.

local Host = require("./Runtime/Host")

export type Config = {
	quality: string?, -- "Low" | "Medium" | "High" | "Ultra" (default: chosen from the device)
	adaptive: boolean?, -- step quality down under load and back up (default true)
	reducedMotion: boolean?,
	reducedFlashing: boolean?,
	intensity: number?, -- 0..1.5 global "juice" multiplier (default 1)
	theme: string?, -- a Visuals theme id, for example "VibrantSimulator"
	textures: { [string]: string }?, -- texture key -> rbxassetid, see VFX/README.md
	sounds: { [string]: string | number }?, -- sound cue -> asset id, see Audio/README.md
}

local loaders: { [string]: () -> any } = {
	Motion = function(): any
		return require("./Runtime/Motion")
	end,
	VFX = function(): any
		return require("./VFX/VFX")
	end,
	UI = function(): any
		return require("./UI/UIAnimations")
	end,
	Camera = function(): any
		return require("./Camera/Camera")
	end,
	Objects = function(): any
		return require("./Objects/Objects")
	end,
	Pets = function(): any
		return require("./Pets/Pets")
	end,
	Eggs = function(): any
		return require("./Eggs/Eggs")
	end,
	Rewards = function(): any
		return require("./Rewards/Rewards")
	end,
	Feedback = function(): any
		return require("./Feedback/Feedback")
	end,
	Audio = function(): any
		return require("./Audio/Audio")
	end,
	Themes = function(): any
		return require("./Themes/Themes")
	end,
	Icons = function(): any
		return require("./Icons/IconVault")
	end,
	Screens = function(): any
		return require("./Screens/Screens")
	end,
	Presets = function(): any
		return require("./Presets/Presets")
	end,
	Debug = function(): any
		return require("./Debug/Debug")
	end,
	Quality = function(): any
		return require("./Core/Quality")
	end,
	Springs = function(): any
		return require("./Core/Springs")
	end,
	Curves = function(): any
		return require("./Core/Curves")
	end,
}

local Visuals: any = {}

local started = false

local function lowerFirst(name: string): string
	return string.lower(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

-- Wraps a module so Module:Method(...) and Module.method(...) both reach the same function.
local function facade(module: any): any
	if type(module) ~= "table" then
		return module
	end
	local proxy = {}
	return setmetatable(proxy, {
		__index = function(_, key: any): any
			local direct = module[key]
			if direct ~= nil or type(key) ~= "string" then
				return direct
			end
			local target = module[lowerFirst(key)]
			if type(target) ~= "function" then
				return target
			end
			local function method(first: any, ...: any): ...any
				if first == proxy then
					return target(...)
				end
				return target(first, ...)
			end
			rawset(proxy, key, method)
			return method
		end,
		__newindex = function(_, key: any, value: any)
			module[key] = value
		end,
	})
end

local function ensureStarted()
	if not started then
		started = true
		Host.detect()
	end
end

-- Plays a one-shot VFX preset at a position, part, attachment or model. Returns a handle with
-- stop(), or nil when the effect was skipped (budget, distance, throttle). Extra arguments after
-- `self` are optional so `Visuals.Play("CoinBurst", position)` works too.
function Visuals.Play(first: any, ...: any): any
	ensureStarted()
	local module = Visuals.VFX
	if first == Visuals then
		return module.play(...)
	end
	return module.play(first, ...)
end

-- Attaches a looping VFX preset (aura, trail, ambient) to a part, attachment or model.
function Visuals.Attach(first: any, ...: any): any
	ensureStarted()
	local module = Visuals.VFX
	if first == Visuals then
		return module.attach(...)
	end
	return module.attach(first, ...)
end

-- Stops every effect tagged with `owner` (a model, a player, any value passed as params.owner),
-- or every effect when owner is nil.
function Visuals.StopAll(first: any, owner: any?)
	if first ~= Visuals then
		owner = first
	end
	if owner ~= nil then
		Host.effects:stopOwner(owner)
	else
		Host.effects:stopAll()
	end
end

-- A new sequence whose Play steps run VFX presets and Sound steps run audio cues.
function Visuals.Sequence(_first: any?): any
	ensureStarted()
	local Motion = Visuals.Motion
	return Motion.sequence({
		play = function(name: string, ...: any): any
			return Visuals.VFX.play(name, ...)
		end,
		sound = function(cue: string, options: any?): any
			return Visuals.Audio.play(cue, options)
		end,
	})
end

-- Applies settings. Safe to call more than once; later calls change only the fields given.
function Visuals.Configure(first: any, config: Config?)
	local options: Config? = if first == Visuals then config else first
	ensureStarted()
	if options == nil then
		return
	end
	Host.configure({
		level = options.quality,
		adaptive = options.adaptive,
		reducedMotion = options.reducedMotion,
		reducedFlashing = options.reducedFlashing,
		intensity = options.intensity,
	})
	if options.theme then
		Visuals.Themes.set(options.theme)
	end
	if options.textures then
		Visuals.VFX.configure({ textures = options.textures })
	end
	if options.sounds then
		for cue, id in options.sounds do
			Visuals.Audio.register(cue, id)
		end
	end
end

-- Current settings: { level, adaptive, reducedMotion, reducedFlashing, intensity }.
function Visuals.Settings(_first: any?): any
	return Host.settings()
end

-- Live numbers for debugging and the playground: running tracks, live effects, particle estimate,
-- rejected effects by reason, and the last frame time.
function Visuals.Stats(_first: any?): { [string]: any }
	local effects = Host.effects:stats()
	return {
		level = Host.settings().level,
		tracks = Host.engine:count(),
		jobs = Host.clock:count(),
		effects = effects.live,
		particles = effects.particles,
		lights = effects.lights,
		spawned = effects.spawned,
		evicted = effects.evicted,
		rejected = effects.rejected,
		frameTime = Host.frameTime(),
		running = Host.isRunning(),
	}
end

-- Fires when settings change (quality stepped down, reduced motion toggled).
Visuals.Changed = Host.Changed

-- camelCase aliases, matching the rest of the library.
Visuals.play = Visuals.Play
Visuals.attach = Visuals.Attach
Visuals.stopAll = Visuals.StopAll
Visuals.sequence = Visuals.Sequence
Visuals.configure = Visuals.Configure
Visuals.settings = Visuals.Settings
Visuals.stats = Visuals.Stats

setmetatable(Visuals, {
	__index = function(self: any, key: string): any
		local loader = loaders[key]
		if loader == nil then
			return nil
		end
		local module = facade(loader())
		rawset(self, key, module)
		return module
	end,
})

return Visuals :: any
