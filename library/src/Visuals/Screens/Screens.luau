--!strict
-- Visuals.Screens: reusable, configurable, animated screen templates built from the UrkUI Game
-- components, the active style and Visuals.UI.
--
--   local Screens = Visuals.Screens
--   local hud = Screens.create("TappingHud", { parent = playerGui, currencies = { { id = "coins", value = 0 } } })
--   hud.Tapped:Connect(function(position) TapRemote:FireServer() end)   -- intents only
--   hud:open()
--   hud:update({ multiplier = 2 })
--   hud:destroy()
--
-- A Screen has `.Instance`, `:open()`, `:close()`, `:update(partial)`, `:destroy()`, `:isOpen()`,
-- one Signal per intent of its definition (`Selected`, `Confirmed`, `Claimed`, `Closed` ...) and
-- `Intent`, which fires (name, ...) for all of them. Screens raise intents and show what they are
-- told: they never decide a gameplay result, charge a price or grant a reward.
--
-- Each screen is `Screens/<Name>.luau`, loaded on first use. ScreensData lists them (props,
-- intents, usage); ScreensLogic holds the layout and view-model maths.
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")
local ScreensData = require("./ScreensData")
local ScreensLogic = require("./ScreensLogic")
local Signal = require("../../Util/Signal")

-- What a screen file returns: build(shell, props) -> Built.
export type Built = {
	update: ((partial: { [string]: any }, props: { [string]: any }) -> ())?,
	methods: { [string]: (...any) -> ...any }?,
	open: (() -> ())?, -- replaces the shell's open (screens that wrap another module)
	close: (() -> ())?,
	isOpen: (() -> boolean)?,
	instance: Instance?,
}

export type Builder = (shell: ScreenKit.Shell, props: { [string]: any }) -> Built

export type Screen = {
	name: string,
	Instance: Instance,
	Intent: Signal.Signal,
	open: (self: Screen) -> (),
	close: (self: Screen) -> (),
	isOpen: (self: Screen) -> boolean,
	update: (self: Screen, partial: { [string]: any }) -> (),
	destroy: (self: Screen) -> (),
	[string]: any,
}

local Screens = {}

Screens.Logic = ScreensLogic
Screens.Data = ScreensData
Screens.Kit = ScreenKit
Screens.registry = ScreensData.registry

-- One loader per built-in screen file (string requires must be literal).
local loaders: { [string]: () -> any } = {
	PetSelection = function(): any
		return require("./PetSelection")
	end,
	EggHatching = function(): any
		return require("./EggHatching")
	end,
	RewardReveal = function(): any
		return require("./RewardReveal")
	end,
	TappingHud = function(): any
		return require("./TappingHud")
	end,
	AnimalInteraction = function(): any
		return require("./AnimalInteraction")
	end,
	Shop = function(): any
		return require("./Shop")
	end,
	PremiumShop = function(): any
		return require("./PremiumShop")
	end,
	DailyRewards = function(): any
		return require("./DailyRewards")
	end,
	PetInventory = function(): any
		return require("./PetInventory")
	end,
	SpinWheel = function(): any
		return require("./SpinWheel")
	end,
	QuestLog = function(): any
		return require("./QuestLog")
	end,
	Achievements = function(): any
		return require("./Achievements")
	end,
	Settings = function(): any
		return require("./Settings")
	end,
	Leaderboard = function(): any
		return require("./Leaderboard")
	end,
	Rebirth = function(): any
		return require("./Rebirth")
	end,
	LevelUp = function(): any
		return require("./LevelUp")
	end,
	Loading = function(): any
		return require("./Loading")
	end,
	Welcome = function(): any
		return require("./Welcome")
	end,
	Tutorial = function(): any
		return require("./Tutorial")
	end,
	AreaUnlock = function(): any
		return require("./AreaUnlock")
	end,
	Collection = function(): any
		return require("./Collection")
	end,
	UpgradeShop = function(): any
		return require("./UpgradeShop")
	end,
	Trading = function(): any
		return require("./Trading")
	end,
	AbilityHotbar = function(): any
		return require("./AbilityHotbar")
	end,
	CombatProgression = function(): any
		return require("./CombatProgression")
	end,
}

local builders: { [string]: Builder } = {}

local function builderFor(name: string): Builder
	local builder = builders[name]
	if builder == nil then
		local loader = loaders[name]
		assert(loader ~= nil, "Screens: no screen named " .. tostring(name))
		builder = loader() :: Builder
		builders[name] = builder
	end
	return builder
end

-- Names of the screens that can be created: the built-in ones in build order, then registered ones.
function Screens.names(): { string }
	return ScreensData.names()
end

function Screens.has(name: string): boolean
	local def = ScreensData.get(name)
	return def ~= nil and def.implemented
end

-- Props, intents and usage of a screen (the registry entry as a plain table).
function Screens.describe(name: string): { [string]: any }
	local described = Screens.registry:describe(name)
	described.data = Screens.registry:get(name).data
	return described
end

-- Adds a game's own screen, or replaces a built-in one:
--   Screens.register("Codes", function(shell, props) ... return { update = ... } end, {
--       name = "Codes", kind = "dialog", category = "system", description = "Redeem a code.",
--       props = { "title: string = CODES | Window title" },
--       intents = { "Confirmed(code) | A code was entered", "Closed() | The screen closed" },
--   })
function Screens.register(name: string, builder: Builder, metadata: { [string]: any }?)
	assert(type(name) == "string" and string.match(name, "^%u%w*$") ~= nil, "screen names are PascalCase")
	assert(type(builder) == "function", "Screens.register needs a builder function")
	local meta: { [string]: any } = metadata or {}
	local kind = meta.kind or "window"
	assert(table.find(ScreensLogic.SCREEN_KINDS, kind) ~= nil, "unknown screen kind " .. tostring(kind))
	local def = ScreensData.define({
		id = name,
		name = meta.name or name,
		kind = kind,
		category = meta.category or "game",
		implemented = true,
		description = meta.description or ("Game screen " .. name .. "."),
		props = meta.props,
		intents = meta.intents or { "Closed() | The screen finished closing" },
		methods = meta.methods,
		usage = meta.usage or string.format('Screens.create("%s", props)', name),
	})
	local preset = ScreensData.preset(def)
	preset.data.builtin = false
	Screens.registry:register(preset, { override = true })
	builders[name] = builder
end

-- Builds a screen. Errors with every problem when the props do not match the screen's definition.
function Screens.create(name: string, props: { [string]: any }?): Screen
	local def = ScreensData.get(name)
	if def == nil or not def.implemented then
		error("Screens.create: no screen named " .. tostring(name), 2)
	end
	local checked, issues = ScreensLogic.check(name, props)
	if #issues > 0 then
		error(string.format("Screens.create(%q): %s", name, table.concat(issues, "; ")), 2)
	end
	local build = builderFor(name)
	local shell = ScreenKit.new(def, checked)
	local ok, built = pcall(build, shell, checked)
	if not ok then
		shell:destroy()
		error(built, 2)
	end
	local result: Built = built or {}
	local destroyed = false

	local screen: Screen = {
		name = name,
		Instance = result.instance or shell.gui or shell.root,
		Intent = shell.Intent,
		open = function(_self: Screen)
			if destroyed then
				return
			end
			if result.open then
				result.open()
			else
				shell:open()
			end
		end,
		close = function(_self: Screen)
			if destroyed then
				return
			end
			if result.close then
				result.close()
			else
				shell:close()
			end
		end,
		isOpen = function(_self: Screen): boolean
			if result.isOpen then
				return result.isOpen()
			end
			return shell:isOpen()
		end,
		update = function(_self: Screen, partial: { [string]: any })
			if destroyed or type(partial) ~= "table" then
				return
			end
			local merged = table.clone(shell.props)
			for key, value in pairs(partial) do
				merged[key] = value
			end
			local nextProps, problems = ScreensLogic.check(name, merged)
			if #problems > 0 then
				error(string.format("%s:update: %s", name, table.concat(problems, "; ")), 2)
			end
			table.clear(shell.props)
			for key, value in pairs(nextProps) do
				shell.props[key] = value
			end
			if result.update then
				result.update(partial, shell.props)
			end
		end,
		destroy = function(_self: Screen)
			if destroyed then
				return
			end
			destroyed = true
			shell:destroy()
		end,
	}
	for intentName, signal in pairs(shell.signals) do
		screen[intentName] = signal
	end
	for methodName, method in pairs(result.methods or {}) do
		screen[methodName] = function(_self: Screen, ...: any): ...any
			if destroyed then
				return nil
			end
			return method(...)
		end
	end
	if checked.startOpen == true then
		screen:open()
	end
	return screen
end

return Screens
