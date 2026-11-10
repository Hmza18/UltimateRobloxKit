--!strict
-- The pure half of the UltimateVisuals Playground (library/examples/visuals/Playground/
-- PlaygroundLogic.luau): generated controls, the example code box, list filtering, the lazy row
-- window and the metrics text. The example code is checked against the real registries so the
-- calls it prints name presets and parameters that exist.

local Catalog = require("../src/Visuals/VFX/CatalogData")
local CameraLogic = require("../src/Visuals/Camera/CameraLogic")
local FeedbackLogic = require("../src/Visuals/Feedback/FeedbackLogic")
local ObjectsLogic = require("../src/Visuals/Objects/ObjectsLogic")
local PetsLogic = require("../src/Visuals/Pets/PetsLogic")
local PlaygroundLogic = require("../examples/visuals/Playground/PlaygroundLogic")
local RewardsLogic = require("../src/Visuals/Rewards/RewardsLogic")
local UIPresets = require("../src/Visuals/UI/UIPresets")
local t = require("./lib/t")

local vfx = Catalog.registry()

local function code(selection: PlaygroundLogic.Selection): string
	return PlaygroundLogic.exampleCode(selection)
end

return {
	["there are twelve categories and five are registry kinds"] = function()
		local categories = PlaygroundLogic.categories()
		t.equal(#categories, 12)
		local labels: { string } = {}
		local kinds: { string } = {}
		for _, category in categories do
			table.insert(labels, category.label)
			if category.kind then
				table.insert(kinds, category.kind)
			end
		end
		t.deepEqual(labels, {
			"VFX",
			"UI animations",
			"Objects",
			"Camera",
			"Pets",
			"Rewards",
			"Eggs",
			"Feedback",
			"Themes",
			"Icons",
			"Components",
			"Demos",
		})
		t.deepEqual(kinds, { "vfx", "ui", "object", "camera", "pet" })
		-- Each kind is the kind of the registry the category lists.
		t.equal(vfx.kind, "vfx")
		t.equal(UIPresets.registry.kind, "ui")
		t.equal(ObjectsLogic.registry.kind, "object")
		t.equal(CameraLogic.registry.kind, "camera")
		t.equal(PetsLogic.registry.kind, "pet")
		t.equal((PlaygroundLogic.category("eggs") :: PlaygroundLogic.Category).label, "Eggs")
		t.equal(PlaygroundLogic.category("nope"), nil)
	end,

	["controls follow the parameter type, in name order"] = function()
		local controls = PlaygroundLogic.controls(vfx:get("RarityBurst").params)
		local shape: { string } = {}
		for _, control in controls do
			table.insert(shape, control.name .. ":" .. control.kind)
		end
		t.deepEqual(shape, { "color:swatches", "intensity:slider", "rarity:dropdown", "scale:slider" })
		local toggles = PlaygroundLogic.controls(PlaygroundLogic.rewardParams())
		t.equal(toggles[1].name, "compact")
		t.equal(toggles[1].kind, "toggle")
		t.deepEqual(PlaygroundLogic.controls(nil), {})
		local text = PlaygroundLogic.controls({ label = { type = "string", default = "x" } })
		t.equal(text[1].kind, "text")
	end,

	["sliders get the declared range, or one around the default"] = function()
		local declared = PlaygroundLogic.controls({ speed = { type = "number", default = 1, min = 0.5, max = 3 } })[1]
		t.equal(declared.min, 0.5)
		t.equal(declared.max, 3)
		t.near(declared.step :: number, 0.025, 1e-9)
		local open = PlaygroundLogic.controls({ size = { type = "number", default = 40 } })[1]
		t.equal(open.min, 0)
		t.equal(open.max, 80)
		t.equal(open.step, 1, "wide ranges step in whole numbers")
		local zero = PlaygroundLogic.controls({ delay = { type = "number", default = 0 } })[1]
		t.equal(zero.min, 0)
		t.equal(zero.max, 1)
		t.equal(PlaygroundLogic.clamp({ type = "number", default = 1, min = 0, max = 2 }, 5), 2)
		t.equal(PlaygroundLogic.clamp({ type = "number", default = 1 }, 5), 5)
		-- Every numeric parameter of every VFX preset gets a usable slider.
		for _, preset in vfx:list() do
			for _, control in PlaygroundLogic.controls(preset.params) do
				if control.kind == "slider" then
					t.truthy((control.max :: number) > (control.min :: number), preset.id .. "." .. control.name)
					t.truthy((control.step :: number) > 0, preset.id .. "." .. control.name)
				end
			end
		end
	end,

	["defaults come from the metadata and changed keeps only what differs"] = function()
		local params = vfx:get("RarityBurst").params
		local values = PlaygroundLogic.defaults(params)
		t.equal(values.rarity, "Common")
		t.deepEqual(PlaygroundLogic.changed(params, values), {})
		values.rarity = "Epic"
		values.scale = values.scale + 1e-9
		values.color = string.lower(values.color)
		values.unknown = 5
		t.deepEqual(PlaygroundLogic.changed(params, values), { rarity = "Epic" })
		t.deepEqual(PlaygroundLogic.changed(nil, values), {})
		t.deepEqual(PlaygroundLogic.changed(params, nil), {})
		t.deepEqual(PlaygroundLogic.defaults(nil), {})
	end,

	["changed values are accepted by the registry they describe"] = function()
		for _, id in { "RarityBurst", "ElementBurst", "Rain", "CoinBurst" } do
			local params = vfx:get(id).params
			local values = PlaygroundLogic.defaults(params)
			for _, control in PlaygroundLogic.controls(params) do
				if control.kind == "slider" then
					values[control.name] = control.max
				elseif control.kind == "dropdown" then
					local options = control.param.options :: { string }
					values[control.name] = options[#options]
				elseif control.kind == "swatches" then
					values[control.name] = "#12AB34"
				end
			end
			local changed = PlaygroundLogic.changed(params, values)
			local ok, err = pcall(function()
				vfx:params(id, changed)
			end)
			t.truthy(ok, id .. ": " .. tostring(err))
		end
	end,

	["literals are deterministic"] = function()
		t.equal(PlaygroundLogic.literal(2), "2")
		t.equal(PlaygroundLogic.literal(-3), "-3")
		t.equal(PlaygroundLogic.literal(0.5), "0.5")
		t.equal(PlaygroundLogic.literal(1.25), "1.25")
		t.equal(PlaygroundLogic.literal(0.1 + 0.2), "0.3")
		t.equal(PlaygroundLogic.literal(1 / 3), "0.333")
		t.equal(PlaygroundLogic.literal(0 / 0), "0")
		t.equal(PlaygroundLogic.literal(true), "true")
		t.equal(PlaygroundLogic.literal("Epic"), '"Epic"')
		t.equal(PlaygroundLogic.literal('say "hi"\n'), '"say \\"hi\\"\\n"')
		t.equal(PlaygroundLogic.literal(nil), "nil")
		t.equal(PlaygroundLogic.tableLiteral({}), "{}")
		t.equal(PlaygroundLogic.tableLiteral({ b = 2, a = "x", c = true }), '{ a = "x", b = 2, c = true }')
		t.equal(PlaygroundLogic.tableLiteral({ "x", "y" }), '{ "x", "y" }')
		t.equal(PlaygroundLogic.tableLiteral({ ["two words"] = 1 }), '{ ["two words"] = 1 }')
		t.equal(
			PlaygroundLogic.tableLiteral({ tabs = { { id = "a" }, { id = "b" } }, value = "a" }),
			'{ tabs = { { id = "a" }, { id = "b" } }, value = "a" }'
		)
	end,

	["vfx code plays one-shots and attaches loops, with only changed params"] = function()
		local params = vfx:get("RarityBurst").params
		local values = PlaygroundLogic.defaults(params)
		t.equal(
			code({ category = "vfx", id = "RarityBurst", params = params, values = values }),
			'Visuals.VFX.play("RarityBurst", target.Position)'
		)
		values.rarity = "Legendary"
		values.scale = 1.5
		t.equal(
			code({ category = "vfx", id = "RarityBurst", params = params, values = values }),
			'Visuals.VFX.play("RarityBurst", target.Position, { rarity = "Legendary", scale = 1.5 })'
		)
		local rain = vfx:get("Rain")
		t.truthy(rain.data.looping, "Rain loops")
		local rainValues = PlaygroundLogic.defaults(rain.params)
		rainValues.size = 60
		t.equal(
			code({ category = "vfx", id = "Rain", params = rain.params, values = rainValues, looping = true }),
			'local handle = Visuals.VFX.attach("Rain", target, { size = 60 })\n-- later: handle.stop()'
		)
		-- The same selection always gives the same text.
		local again = code({ category = "vfx", id = "RarityBurst", params = params, values = values })
		t.equal(again, code({ category = "vfx", id = "RarityBurst", params = params, values = table.clone(values) }))
	end,

	["ui, object and pet code use the module of their kind"] = function()
		local ui = UIPresets.registry:get("PopIn").params
		t.equal(code({ category = "ui", id = "PopIn", params = ui }), 'Visuals.UI.animate(gui, "PopIn")')
		t.equal(
			code({ category = "ui", id = "PopIn", params = ui, values = { intensity = 0.5 } }),
			'Visuals.UI.animate(gui, "PopIn", { intensity = 0.5 })'
		)
		local object = ObjectsLogic.registry:get("Spin").params
		t.equal(
			code({ category = "object", id = "Spin", params = object, values = { axis = "x", speed = 2 } }),
			'local handle = Visuals.Objects.animate(model, "Spin", { axis = "x", speed = 2 })'
		)
		local pet = PetsLogic.registry:get("HappyReaction").params
		t.equal(
			code({ category = "pet", id = "HappyReaction", params = pet, values = { intensity = 1 } }),
			'Visuals.Pets.play("HappyReaction", petModel)'
		)
	end,

	["camera code depends on the preset's group"] = function()
		local shake = CameraLogic.registry:get("Impact")
		t.equal(shake.category, "shake")
		t.equal(
			code({ category = "camera", id = "Impact", group = shake.category, params = shake.params }),
			'Visuals.Camera.shake("Impact")'
		)
		t.equal(
			code({
				category = "camera",
				id = "Impact",
				group = "shake",
				params = shake.params,
				values = { intensity = 0.5 },
			}),
			'Visuals.Camera.shake("Impact", { intensity = 0.5 })'
		)
		local cinematic = CameraLogic.registry:get("PetReveal")
		t.equal(
			code({ category = "camera", id = "PetReveal", group = cinematic.category, params = cinematic.params }),
			'local handle = Visuals.Camera.cinematic("PetReveal", target)'
		)
		-- Every "move" preset has a hand-written call.
		for _, preset in CameraLogic.registry:list({ category = "move" }) do
			local text = code({ category = "camera", id = preset.id, group = "move" })
			t.truthy(
				string.find(text, "Visuals.Camera.", 1, true) == 1 or string.find(text, "local handle", 1, true) == 1
			)
			t.falsy(string.find(text, "is used through", 1, true), preset.id .. " has no example call")
		end
	end,

	["reward, egg and theme code"] = function()
		local rewards = PlaygroundLogic.rewardParams()
		t.equal(
			code({ category = "rewards", id = "Epic", params = rewards, values = PlaygroundLogic.defaults(rewards) }),
			'local handle = Visuals.Rewards.reveal("Epic", { name = "Demo reward", amount = 250 })'
		)
		t.equal(
			code({ category = "rewards", id = "Epic", params = rewards, values = { fastForward = true, speed = 2 } }),
			'local handle = Visuals.Rewards.reveal("Epic", { name = "Demo reward", amount = 250 }, '
				.. "{ fastForward = true, speed = 2 })"
		)
		local eggs = PlaygroundLogic.eggParams(table.clone(RewardsLogic.ORDER))
		t.equal(
			code({ category = "eggs", id = "Single", params = eggs, values = PlaygroundLogic.defaults(eggs) }),
			'local hatch = Visuals.Eggs.hatch({\n\teggs = { { rarity = "Rare", name = "Demo pet" } },\n})'
		)
		t.equal(
			code({ category = "eggs", id = "Multi", params = eggs, values = { rarity = "Mythic", camera = false } }),
			"local hatch = Visuals.Eggs.hatch({\n"
				.. '\teggs = eggs, -- 8 entries like { rarity = "Mythic", name = "Demo pet" }\n'
				.. "\tcamera = false,\n})"
		)
		local auto = code({ category = "eggs", id = "Auto", params = eggs, values = {} })
		t.truthy(string.find(auto, 'mode = "auto"', 1, true))
		t.truthy(string.find(auto, "next = nextBatch", 1, true))
		t.equal(PlaygroundLogic.eggCount("Single"), 1)
		t.equal(PlaygroundLogic.eggCount("Triple"), 3)
		t.equal(PlaygroundLogic.eggCount("Multi"), 8)
		t.equal(code({ category = "themes", id = "Luxury" }), 'Visuals.Themes.set("Luxury")')
		t.equal(
			code({ category = "icons", id = "coin" }),
			'local icon = Visuals.Icons.create("coin", { size = 48 })\nicon.Parent = parent'
		)
	end,

	["feedback code lists the context fields the recipe reads"] = function()
		local pack = FeedbackLogic.pack("Simulator") :: { [string]: FeedbackLogic.Recipe }
		t.deepEqual(PlaygroundLogic.contextFields(pack.Tap), { "amount", "gui", "position" })
		t.deepEqual(PlaygroundLogic.contextFields(pack.CollectCoin), { "counter", "position", "total" })
		t.deepEqual(PlaygroundLogic.contextFields(pack.HatchEgg), { "eggs", "mode", "origin", "speed" })
		t.deepEqual(PlaygroundLogic.contextFields({}), {})
		t.deepEqual(PlaygroundLogic.contextFields({ { kind = "popup", text = "$pet.name got $amount." } }), {
			"amount",
			"pet",
		})
		t.equal(
			code({ category = "feedback", id = "Tap", context = PlaygroundLogic.contextFields(pack.Tap) }),
			'Visuals.Feedback.fire("Tap", { amount = amount, gui = gui, position = position })'
		)
		t.equal(code({ category = "feedback", id = "Ping" }), 'Visuals.Feedback.fire("Ping")')
		-- A context built from these fields resolves every step of every built-in recipe.
		for _, name in FeedbackLogic.packs() do
			for event, recipe in FeedbackLogic.pack(name) :: { [string]: FeedbackLogic.Recipe } do
				local context: { [string]: any } = {}
				for _, field in PlaygroundLogic.contextFields(recipe) do
					context[field] = if field == "rarity" then "Rare" else 1
				end
				local _, dropped = FeedbackLogic.resolve(recipe, context, { count = 5 })
				for _, entry in dropped do
					t.equal(entry.reason, "when", name .. "." .. event .. " dropped a step: " .. entry.reason)
				end
			end
		end
	end,

	["component and demo code"] = function()
		t.equal(
			code({ category = "components", id = "Toggle", props = {} }),
			"local component = UrkUI.Game.Toggle.new({ parent = parent })"
		)
		t.equal(
			code({ category = "components", id = "PetCard", props = { title = "Ember", rarity = "epic" } }),
			'local component = UrkUI.Game.PetCard.new({ parent = parent, rarity = "epic", title = "Ember" })'
		)
		t.equal(
			code({
				category = "components",
				id = "PetCard",
				props = { title = "Ember" },
				values = { selected = true },
			}),
			'local component = UrkUI.Game.PetCard.new({ parent = parent, selected = true, title = "Ember" })'
		)
		t.equal(
			code({ category = "demos", id = "Egg hatching", module = "EggHatchingDemo" }),
			"local stop = require(script.Parent.EggHatchingDemo).start(playerGui)\n-- later: stop()"
		)
		t.truthy(string.find(code({ category = "mystery", id = "x" }), "nothing to show", 1, true))
	end,

	["swatches start with the default and skip repeats"] = function()
		local swatches = PlaygroundLogic.swatches("#ffd43b", { "#FFD43B", "#5CE1FF", "nope", "#5ce1ff", "#63C174" })
		t.deepEqual(swatches, { "#FFD43B", "#5CE1FF", "#63C174" })
		t.equal(#PlaygroundLogic.swatches(nil, { "#000001", "#000002", "#000003" }, 2), 2)
		t.deepEqual(PlaygroundLogic.swatches(nil, {}), {})
	end,

	["filter matches every word, case-insensitively, keeping order"] = function()
		local ids = { "CoinBurst", "GemBurst", "PetSpawn", "RarityBurst", "RarityBeam" }
		t.deepEqual(PlaygroundLogic.filter(ids, ""), ids)
		t.deepEqual(PlaygroundLogic.filter(ids, nil), ids)
		t.deepEqual(PlaygroundLogic.filter(ids, "burst"), { "CoinBurst", "GemBurst", "RarityBurst" })
		t.deepEqual(PlaygroundLogic.filter(ids, "RARITY be"), { "RarityBeam" })
		t.deepEqual(PlaygroundLogic.filter(ids, "zzz"), {})
		t.deepEqual(PlaygroundLogic.filter(ids, "   "), ids)
		t.deepEqual(
			PlaygroundLogic.ofKind({ { kind = "vfx", id = "CoinBurst" }, { kind = "ui", id = "PopIn" } }, "ui"),
			{ "PopIn" }
		)
	end,

	["only the rows near the viewport exist"] = function()
		local first, last = PlaygroundLogic.visibleRows(0, 300, 30, 83, 2)
		t.equal(first, 1)
		t.equal(last, 12)
		first, last = PlaygroundLogic.visibleRows(600, 300, 30, 83, 2)
		t.equal(first, 19)
		t.equal(last, 32)
		first, last = PlaygroundLogic.visibleRows(99999, 300, 30, 83, 2)
		t.equal(last, 83)
		t.truthy(first <= last)
		first, last = PlaygroundLogic.visibleRows(0, 300, 30, 0)
		t.equal(first, 1)
		t.equal(last, 0, "an empty list has no rows")
		first, last = PlaygroundLogic.visibleRows(-50, 300, 30, 4)
		t.equal(first, 1)
		t.equal(last, 4)
		-- 83 presets never need more than a screenful of rows.
		for scroll = 0, 83 * 30, 45 do
			local from, to = PlaygroundLogic.visibleRows(scroll, 300, 30, 83, 2)
			t.truthy(to - from + 1 <= 15, "at most 15 rows, got " .. (to - from + 1))
		end
	end,

	["metrics show fps, counts and rejection reasons"] = function()
		local sampler = PlaygroundLogic.newSampler(4)
		t.equal(PlaygroundLogic.fps(sampler), 0)
		for _ = 1, 10 do
			PlaygroundLogic.sample(sampler, 1 / 60)
		end
		PlaygroundLogic.sample(sampler, 0)
		PlaygroundLogic.sample(sampler, 0 / 0)
		t.near(PlaygroundLogic.fps(sampler), 60, 1e-6)
		t.equal(sampler.count, 4, "the window is bounded")
		local lines = PlaygroundLogic.metrics({
			level = "High",
			tracks = 3,
			jobs = 2,
			effects = 4,
			particles = 120.6,
			lights = 1,
			rejected = { throttle = 7, budget = 2 },
		}, 59.6)
		t.equal(lines[1], "60 fps   quality High")
		t.equal(lines[2], "tracks 3   jobs 2")
		t.equal(lines[3], "effects 4   particles ~120   lights 1")
		t.equal(lines[4], "rejected: budget 2, throttle 7")
		t.equal(PlaygroundLogic.metrics({}, 0)[4], "rejected: none")
	end,
}
