--!strict
-- Feedback: one call per gameplay event (Visuals.Feedback).
--
--   Feedback.fire("CollectCoin", { position = coin.Position, counter = coinLabel, total = 1250 })
--   Feedback.define("OpenChest", { { kind = "vfx", id = "TreasureOpen", at = "$position" } })
--   Feedback.use("Minimal")
--
-- An event maps to a recipe (see FeedbackLogic): a list of steps run through the other visuals
-- modules. Game code only fires events; nothing here holds gameplay state or authority. Fire an
-- event after the server has decided the outcome.

local FeedbackLogic = require("./FeedbackLogic")
local Host = require("../Runtime/Host")

export type Recipe = FeedbackLogic.Recipe
export type Context = FeedbackLogic.Context

export type Fired = {
	handles: { any }, -- what the steps returned (effect, animation and sound handles)
	dropped: { FeedbackLogic.Dropped }, -- steps skipped because of `when` or missing context
	stop: () -> (), -- cancels pending delayed steps and stops the handles
	cancel: () -> (),
}

local Feedback = {}

Feedback.Logic = FeedbackLogic

local recipes: { [string]: Recipe } = FeedbackLogic.pack("Simulator") or {}
local counts: { [string]: number } = {}
local warned: { [string]: boolean } = {}
local throttle = FeedbackLogic.newThrottle()
local flushing: { [string]: boolean } = {}

local modules: { [string]: any } = {}
local function optional(name: string, load: () -> any): any
	local cached = modules[name]
	if cached == nil then
		local ok, module = pcall(load)
		cached = if ok and module ~= nil then module else false
		modules[name] = cached
	end
	return if cached == false then nil else cached
end

local function vfxModule(): any
	return optional("VFX", function(): any
		return require("../VFX/VFX")
	end)
end

local function uiModule(): any
	return optional("UI", function(): any
		return require("../UI/UIAnimations")
	end)
end

local function cameraModule(): any
	return optional("Camera", function(): any
		return require("../Camera/Camera")
	end)
end

local function objectsModule(): any
	return optional("Objects", function(): any
		return require("../Objects/Objects")
	end)
end

local function petsModule(): any
	return optional("Pets", function(): any
		return require("../Pets/Pets")
	end)
end

local function audioModule(): any
	return optional("Audio", function(): any
		return require("../Audio/Audio")
	end)
end

local function rewardsModule(): any
	return optional("Rewards", function(): any
		return require("../Rewards/Rewards")
	end)
end

local function eggsModule(): any
	return optional("Eggs", function(): any
		return require("../Eggs/Eggs")
	end)
end

-- A missing module, an unknown preset or an effect skipped by a budget all give nil.
local function try(module: any, name: string, ...: any): any
	if module == nil or type(module[name]) ~= "function" then
		return nil
	end
	local ok, result = pcall(module[name], ...)
	return if ok then result else nil
end

local function endHandle(handle: any)
	if type(handle) == "function" then
		pcall(handle)
	elseif type(handle) == "table" then
		local stop = handle.stop or handle.cancel
		if type(stop) == "function" then
			pcall(stop)
		end
	end
end

local runners: { [string]: (step: FeedbackLogic.Step, context: Context) -> any } = {}

function runners.vfx(step: FeedbackLogic.Step): any
	local options: { [string]: any } = step.options or {}
	local handle = try(vfxModule(), if step.attach then "attach" else "play", step.id, step.at, step.params)
	if handle ~= nil and step.attach and type(options.duration) == "number" then
		-- Attached effects loop; a duration turns one into a timed effect (a dash trail).
		Host.clock:after(options.duration, function()
			endHandle(handle)
		end)
	end
	return handle
end

function runners.ui(step: FeedbackLogic.Step): any
	local ui = uiModule()
	local action = step.action or "animate"
	if action == "animate" then
		return try(ui, "animate", step.target, step.preset, step.options)
	elseif action == "countTo" then
		return try(ui, "countTo", step.target, step.to, step.options)
	elseif action == "flash" then
		return try(ui, "flash", step.color, step.options)
	end
	-- shine, show, hide
	if action == "show" or action == "hide" then
		return try(ui, action, step.target, step.preset, step.options)
	end
	return try(ui, action, step.target, step.options)
end

function runners.popup(step: FeedbackLogic.Step): any
	return try(uiModule(), "popup", step.text, step.at, step.options)
end

function runners.flyTo(step: FeedbackLogic.Step): any
	return try(uiModule(), "flyTo", step.from, step.to, step.options)
end

function runners.camera(step: FeedbackLogic.Step): any
	local camera = cameraModule()
	if step.shake ~= nil then
		return try(camera, "shake", step.shake, step.options)
	elseif step.cinematic ~= nil then
		return try(camera, "cinematic", step.cinematic, step.target, step.options)
	elseif step.fov ~= nil then
		return try(camera, "fov", step.fov, step.options)
	elseif step.zoom ~= nil then
		return try(camera, "zoom", step.zoom, step.options)
	elseif step.focus ~= nil then
		return try(camera, "focus", step.focus, step.options)
	end
	return nil
end

function runners.sound(step: FeedbackLogic.Step): any
	return try(audioModule(), "play", step.cue, step.options)
end

function runners.object(step: FeedbackLogic.Step): any
	return try(objectsModule(), "animate", step.target, step.preset, step.options)
end

function runners.pet(step: FeedbackLogic.Step): any
	return try(petsModule(), "play", step.reaction, step.target, step.options)
end

function runners.reward(step: FeedbackLogic.Step): any
	return try(rewardsModule(), "reveal", step.rarity, step.reward, step.options)
end

function runners.hatch(step: FeedbackLogic.Step): any
	local config: { [string]: any } = if type(step.config) == "table" then table.clone(step.config) else {}
	config.eggs = step.eggs
	return try(eggsModule(), "hatch", config)
end

function runners.call(step: FeedbackLogic.Step, context: Context): any
	if type(step.fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(step.fn, context, step)
	if not ok then
		warn("[UVK] feedback call step failed: " .. tostring(result))
		return nil
	end
	return result
end

local function run(step: FeedbackLogic.Step, context: Context, handles: { any })
	local runner = runners[step.kind]
	if runner == nil then
		return
	end
	local handle = runner(step, context)
	if handle ~= nil then
		table.insert(handles, handle)
	end
end

-- Applies a step's throttle. Returns false when the step must not run now. With `coalesce` the
-- held-back amount is shown by one merged step as soon as the limit allows.
local function admitted(event: string, step: FeedbackLogic.Step, recipe: Recipe, context: Context): boolean
	local rule = step.throttle
	if rule == nil then
		return true
	end
	local key = event .. "#" .. tostring(step.index)
	local field: string? = rule.coalesce
	local amount = if field then context[field] else nil
	local now = os.clock()
	local ok, merged = FeedbackLogic.admit(throttle, key, rule, now, if type(amount) == "number" then amount else nil)
	if ok then
		if field and merged ~= nil and merged ~= amount then
			-- This step carries what earlier, throttled events held back.
			local carried = table.clone(context)
			carried[field] = merged
			local again = FeedbackLogic.resolve({ recipe[step.index] }, carried)
			if again[1] then
				for name, value in again[1] do
					if name ~= "index" then
						step[name] = value
					end
				end
			end
		end
		return true
	end
	if field and not flushing[key] then
		flushing[key] = true
		local wait = math.max(0.02, FeedbackLogic.nextFree(throttle, key, rule, now) - now)
		Host.clock:after(wait, function()
			flushing[key] = nil
			local total = FeedbackLogic.flush(throttle, key, rule, os.clock())
			local source = recipes[event]
			if total == nil or source ~= recipe then
				return
			end
			local carried = table.clone(context)
			carried[field] = total
			local steps = FeedbackLogic.resolve({ recipe[step.index] }, carried)
			if steps[1] then
				run(steps[1], carried, {})
			end
		end)
	end
	return false
end

-- Defines or replaces the recipe for an event. Errors when the recipe is invalid.
function Feedback.define(event: string, recipe: Recipe)
	assert(type(event) == "string" and event ~= "", "event name must be a non-empty string")
	local ok, message = FeedbackLogic.validate(recipe)
	assert(ok, "invalid recipe for " .. event .. ": " .. tostring(message))
	recipes[event] = recipe
end

-- Fires an event: runs its recipe with `context` ({ position, gui, counter, amount, total, pet,
-- rarity, ... }). Steps whose context is missing are skipped and listed in the result. An
-- unknown event warns once and does nothing.
function Feedback.fire(event: string, context: Context?): Fired
	local handles: { any } = {}
	local timers: { () -> () } = {}
	local stopped = false
	local function stop()
		if stopped then
			return
		end
		stopped = true
		for _, cancel in timers do
			cancel()
		end
		for _, handle in handles do
			endHandle(handle)
		end
	end
	local fired: Fired = { handles = handles, dropped = {}, stop = stop, cancel = stop }
	local recipe = recipes[event]
	if recipe == nil then
		if not warned[event] then
			warned[event] = true
			warn("[UVK] Feedback.fire: no recipe for event " .. tostring(event))
		end
		return fired
	end
	local ctx: Context = context or {}
	local count = (counts[event] or 0) + 1
	counts[event] = count
	local steps, dropped = FeedbackLogic.resolve(recipe, ctx, { count = count })
	fired.dropped = dropped
	for _, step in steps do
		if not admitted(event, step, recipe, ctx) then
			table.insert(dropped, { index = step.index, kind = step.kind, reason = "throttle" })
			continue
		end
		if step.delay > 0 then
			table.insert(
				timers,
				Host.clock:after(step.delay, function()
					if not stopped then
						run(step, ctx, handles)
					end
				end)
			)
		else
			run(step, ctx, handles)
		end
	end
	return fired
end

-- Switches to a pack: the name of a built-in pack ("Simulator", "Minimal", "Combat") or a table
-- of event -> recipe. Only the events the pack defines are replaced.
function Feedback.use(pack: string | { [string]: Recipe })
	local map: { [string]: Recipe }?
	if type(pack) == "string" then
		map = FeedbackLogic.pack(pack)
		assert(map ~= nil, "unknown feedback pack " .. pack)
	else
		map = pack
	end
	recipes = FeedbackLogic.apply(recipes, map :: { [string]: Recipe })
end

-- Removes one event's recipe, or every recipe when no event is given.
function Feedback.clear(event: string?)
	if event == nil then
		recipes = {}
		counts = {}
	else
		recipes[event] = nil
		counts[event] = nil
	end
end

-- Restores the built-in Simulator pack and forgets counters and throttles.
function Feedback.reset()
	recipes = FeedbackLogic.pack("Simulator") or {}
	counts = {}
	warned = {}
	throttle = FeedbackLogic.newThrottle()
end

-- Event names that have a recipe, sorted.
function Feedback.events(): { string }
	local names: { string } = {}
	for name in recipes do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function Feedback.recipe(event: string): Recipe?
	return recipes[event]
end

function Feedback.packs(): { string }
	return FeedbackLogic.packs()
end

-- Fires `event` whenever `signal` fires (a Util/Signal or an RBXScriptSignal such as a
-- RemoteEvent's OnClientEvent). mapContext turns the signal's arguments into the context; by
-- default the first argument is used when it is a table. Returns a function that disconnects.
function Feedback.connect(signal: any, event: string, mapContext: ((...any) -> Context?)?): () -> ()
	local connection = signal:Connect(function(...: any)
		local context: Context? = nil
		if mapContext then
			context = mapContext(...)
		else
			local first = ...
			context = if type(first) == "table" then first else nil
		end
		Feedback.fire(event, context)
	end)
	local connected = true
	return function()
		if connected then
			connected = false
			connection:Disconnect()
		end
	end
end

return Feedback
