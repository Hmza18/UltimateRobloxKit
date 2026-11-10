--!strict
-- Demo 1: the flagship pet selection screen.
--
-- Shows Visuals.Pets.selection with four original demo pets (name, description, rarity, stats).
-- Selecting and confirming are logged. On confirm the chosen pet spawns next to the stage with
-- Visuals.Pets.play("Spawn"), a follower (Visuals.Pets.follow) walks it after the player, and a
-- toast confirms the choice.
--
-- Public APIs used: Visuals.Pets.selection / demoPet / play / follow, Visuals.Play,
-- UrkUI.toast, UrkUI.Game (Panel, CartoonButton, GameText).
--
-- NOT run in Studio.

local Players = game:GetService("Players")

local DemoKit = require("./DemoKit")
local DemoLogic = require("./DemoLogic")

local Visuals = DemoKit.Visuals

local PetSelectionDemo = {}

PetSelectionDemo.title = "Pet selection"
PetSelectionDemo.description = "Pick one of four demo pets; it spawns and follows you."

-- STAND-IN FOR THE SERVER. A real game sends the choice to the server, which checks that the
-- player may have this pet and replies; the client then plays the visuals. Here the "server" is
-- a local function that always agrees and grants nothing.
local function fakeServerAdopt(petId: string): (boolean, DemoLogic.DemoPet?)
	local pet = DemoLogic.pet(petId)
	return pet ~= nil, pet
end

function PetSelectionDemo.start(parent: Instance): () -> ()
	DemoKit.bootstrap()
	local scope = DemoKit.scope()
	local gui = DemoKit.screen(scope, parent, "PetSelectionDemo")
	local stage = DemoKit.stage(scope, "PetSelectionStage", DemoKit.origin(20), DemoKit.color("#8E7BFF"))
	local list = DemoKit.panel(scope, gui, { title = "PET SELECTION", height = 360 })
	local log = DemoKit.log(scope, list, 7, 20)

	local selection: any = nil
	local follower: any = nil
	local companion: Model? = nil
	local previews: { Model } = {}

	local function ownerCFrame(): CFrame?
		local character = Players.LocalPlayer.Character
		return if character then character:GetPivot() else nil
	end

	local function release()
		if follower then
			follower:destroy()
			follower = nil
		end
		local old = companion
		companion = nil
		if old then
			-- Despawn leaves the model scaled to nothing; remove it when the timeline ends.
			Visuals.Pets.play("Despawn", old, {
				onDone = function()
					old:Destroy()
				end,
			})
		end
	end

	local function spawnCompanion(pet: DemoLogic.DemoPet)
		release()
		local at = stage.top * CFrame.new(stage.radius + 2.5, -0.6, 0)
		local model = DemoKit.pet(stage.folder, at, DemoKit.color(pet.color), pet.variant, pet.name)
		companion = model
		Visuals.Pets.play("Spawn", model, {
			rarity = pet.rarity,
			onDone = function(completed: boolean)
				if not completed or companion ~= model or not scope.isAlive() then
					return
				end
				-- The follower takes over once the spawn timeline has finished with the model.
				follower = Visuals.Pets.follow(ownerCFrame, { model }, { mode = "rows", distance = 5 })
				log("follower started for " .. pet.name)
			end,
		})
		DemoKit.toast(pet.name .. " joined your team!", "success", gui)
	end

	local function closeSelection()
		if selection and not selection:isDestroyed() then
			selection:destroy()
		end
		selection = nil
		for _, model in previews do
			model:Destroy()
		end
		table.clear(previews)
	end

	local function openSelection()
		closeSelection()
		local entries = {}
		for _, pet in DemoLogic.pets() do
			-- The card previews clone this model, so it never needs a parent.
			local model =
				Visuals.Pets.demoPet({ color = DemoKit.color(pet.color), variant = pet.variant, name = pet.name })
			table.insert(previews, model)
			table.insert(entries, {
				id = pet.id,
				name = pet.name,
				description = pet.description,
				rarity = pet.rarity,
				color = pet.color,
				model = model,
				stats = pet.stats,
			})
		end
		selection = Visuals.Pets.selection({
			parent = parent,
			title = "CHOOSE YOUR COMPANION",
			subtitle = "Four original demo pets. Nothing is saved.",
			pets = entries,
			confirmText = "ADOPT",
			worldPosition = stage.top.Position + Vector3.new(0, 3, 0),
			onSelect = function(id: string)
				log("select  " .. id)
			end,
			onConfirm = function(id: string)
				log("confirm " .. id)
				local accepted, pet = fakeServerAdopt(id)
				if accepted and pet then
					spawnCompanion(pet)
				end
				-- The screen closes itself after a confirm (closeOnConfirm defaults to true).
				selection = nil
			end,
		})
		log("selection opened")
	end

	DemoKit.button(scope, list, "CHOOSE A PET", "buy", 1, openSelection)
	DemoKit.button(scope, list, "HAPPY REACTION", "primary", 2, function()
		if companion then
			Visuals.Pets.play("HappyReaction", companion)
			Visuals.Play("PetHappy", companion)
		else
			log("no pet yet: choose one first")
		end
	end)
	DemoKit.button(scope, list, "RELEASE PET", "neutral", 3, function()
		if companion then
			log("released")
			release()
		end
	end)
	DemoKit.text(scope, list, "Arrow keys / gamepad move the selection; Enter confirms.", "caption", 4)

	scope.add(function()
		closeSelection()
		if follower then
			follower:destroy()
			follower = nil
		end
		if companion then
			Visuals.StopAll(companion)
		end
	end)

	openSelection()
	return scope.clean
end

return PetSelectionDemo
