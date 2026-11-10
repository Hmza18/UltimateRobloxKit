--!strict
-- Pets (Visuals.Pets): pet animation that works on any Model.
--
--   local animator = Pets.animator(petModel)              -- idle float, breathing, sway
--   animator:react("HappyReaction")
--   animator:setRarity("Legendary")                       -- RarityAura through the VFX module
--   Pets.play("Spawn", petModel)                          -- model animation + matching VFX
--   local follower = Pets.follow(character, { petA, petB }, { mode = "arc" })
--   local preview = Pets.preview(viewportFrame, petModel)
--   local screen = Pets.selection({ parent = playerGui, title = "Choose your starter", pets = ... })
--
-- Everything here is cosmetic and client-side: which pets a player owns, where they are on the
-- server and how other players see them is the game's job.
--
-- NOT run in Studio: see README.md.

local Host = require("../Runtime/Host")
local PetAnimator = require("./PetAnimator")
local PetFollow = require("./PetFollow")
local PetPreview = require("./PetPreview")
local PetsLogic = require("./PetsLogic")

export type PetAnimator = PetAnimator.PetAnimator
export type Follower = PetFollow.Follower
export type Preview = PetPreview.Preview

export type Handle = {
	stop: () -> (),
	cancel: () -> (),
	finish: () -> (),
	isActive: () -> boolean,
}

export type PlayOptions = {
	rarity: string?, -- passed to the VFX presets
	color: any?,
	intensity: number?,
	direction: Vector3?, -- CuriousReaction: world point to look toward
	vfx: boolean?, -- false plays the model animation only
	onDone: ((completed: boolean) -> ())?,
}

local Pets = {}

Pets.registry = PetsLogic.registry
Pets.Logic = PetsLogic

-- Attaches an animator to a pet model: idle loop, :react(id), :setHover, :setSelected,
-- :setRarity, :destroy. See PetAnimator.Options.
function Pets.animator(model: Model, options: PetAnimator.Options?): PetAnimator
	return PetAnimator.new(model, options)
end

-- The animator already attached to a model, if any.
function Pets.find(model: Model): PetAnimator?
	return PetAnimator.find(model)
end

-- Plays a reaction (HappyReaction, CuriousReaction, SelectBounce, HoverReaction) or a timeline
-- (Spawn, Despawn, Equip, Unequip, Evolve, Upgrade) on a pet model. Uses the model's animator when
-- it has one, else a temporary one. Timelines also play the matching VFX preset (PetSpawn, ...)
-- when the VFX module is present. After Despawn the model is left scaled to nothing: destroy it,
-- or play Spawn on it again.
function Pets.play(id: string, model: Model, options: PlayOptions?): Handle
	local opts: PlayOptions = options or {}
	local plan = PetsLogic.plan(id)
	if plan == nil and not PetsLogic.isReaction(id) then
		error("unknown pet animation: " .. tostring(id), 2)
	end
	local animator = PetAnimator.find(model)
	local temporary = animator == nil
	local pet: PetAnimator = animator or PetAnimator.new(model, { idle = false })
	local cancels: { () -> () } = {}
	local effects: { any } = {}
	local active = true
	local endsHidden = id == "Despawn"

	local function finish(completed: boolean)
		if not active then
			return
		end
		active = false
		for _, cancel in cancels do
			cancel()
		end
		table.clear(cancels)
		if temporary and not pet:isDestroyed() then
			pet:destroy(not (completed and endsHidden))
		elseif not completed and not pet:isDestroyed() then
			pet:clearLayers()
		end
		if opts.onDone then
			local ok, err = pcall(opts.onDone, completed)
			if not ok then
				warn("[UVK] Pets.play onDone failed: " .. tostring(err))
			end
		end
	end

	local function runStep(step: PetsLogic.Step)
		if not active or pet:isDestroyed() then
			return
		end
		if step.kind == "vfx" then
			local vfx = PetAnimator.vfx()
			if opts.vfx ~= false and vfx and type(vfx.play) == "function" and step.id then
				local ok, handle = pcall(vfx.play, step.id, model, {
					owner = model,
					rarity = opts.rarity,
					color = opts.color,
					intensity = opts.intensity,
				})
				if ok and handle then
					table.insert(effects, handle)
				elseif not ok then
					warn("[UVK] pet effect " .. step.id .. " failed: " .. tostring(handle))
				end
			end
		elseif step.kind == "object" and step.id then
			pet:playObject(step.id, { intensity = opts.intensity })
		elseif step.kind == "reaction" and step.id then
			pet:react(step.id, { intensity = opts.intensity })
		elseif step.kind == "hide" then
			pet:setHidden(true)
		elseif step.kind == "show" then
			pet:setHidden(false)
		end
	end

	if plan then
		local reduced = Host.settings().reducedMotion
		for _, step in plan.steps do
			if step.at <= 0 or reduced then
				runStep(step)
			else
				table.insert(
					cancels,
					Host.clock:after(step.at, function()
						runStep(step)
					end)
				)
			end
		end
		table.insert(
			cancels,
			Host.clock:after(if reduced then 0.05 else plan.duration, function()
				finish(true)
			end)
		)
	else
		pet:react(id, {
			direction = opts.direction,
			intensity = opts.intensity,
			onDone = function(completed: boolean)
				finish(completed)
			end,
		})
	end

	local function stop()
		finish(false)
	end
	return {
		stop = stop,
		cancel = stop,
		-- Ends now, leaving the pet in the animation's end state.
		finish = function()
			if active and plan and not pet:isDestroyed() then
				pet:clearLayers()
				if endsHidden then
					pet:setHidden(true)
				end
			end
			finish(true)
		end,
		isActive = function(): boolean
			return active
		end,
	}
end

-- Makes anchored pet Models follow an owner in a formation. See PetFollow.Options.
function Pets.follow(owner: PetFollow.Owner, pets: { Model }, options: PetFollow.Options?): Follower
	return PetFollow.new(owner, pets, options)
end

-- Shows a pet in a ViewportFrame with its own camera and an idle turntable.
function Pets.preview(viewportFrame: ViewportFrame, model: Model, options: PetPreview.Options?): Preview
	return PetPreview.new(viewportFrame, model, options)
end

-- The pet selection screen ("choose your starter"). Loaded on first use so games that only
-- animate pets never load the UI code. See PetSelection.Props.
function Pets.selection(props: any): any
	local PetSelection = require("./PetSelection")
	return PetSelection.new(props)
end

-- Builds the kit's original demo pet (Parts only), for prototypes and the selection screen.
function Pets.demoPet(options: any): Model
	local DemoPet = require("./DemoPet")
	return DemoPet.build(options)
end

-- Live numbers for the debug overlay.
function Pets.stats(): { animators: number, followers: number }
	return { animators = PetAnimator.count(), followers = PetFollow.count() }
end

return Pets
