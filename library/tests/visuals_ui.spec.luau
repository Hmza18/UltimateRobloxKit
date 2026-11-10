--!strict
local Clock = require("../src/Visuals/Core/Clock")
local Engine = require("../src/Visuals/Core/Engine")
local Registry = require("../src/Visuals/Core/Registry")
local Springs = require("../src/Visuals/Core/Springs")
local UILogic = require("../src/Visuals/UI/UILogic")
local UIPresets = require("../src/Visuals/UI/UIPresets")
local t = require("./lib/t")

local registry = UIPresets.registry

local function recipe(id: string): UILogic.Recipe
	return registry:get(id).data
end

local function rest(): UILogic.Rest
	return {
		scale = 1,
		rotation = 0,
		fade = 0,
		position = { 0.5, 10, 0.5, 20 },
		size = { 0, 200, 0, 100 },
		pixels = { 200, 100 },
	}
end

-- Plays a recipe on a plain table through the real engine, the way UIAnimations chains steps:
-- every step starts from a clock timer at its scheduled time.
local adapter: Engine.Adapter = {
	read = function(target: any, property: string): { number }?
		local value = target[property]
		if type(value) == "number" then
			return { value }
		elseif type(value) == "table" then
			return table.clone(value)
		end
		return nil
	end,
	write = function(target: any, property: string, value: { number })
		target[property] = if type(target[property]) == "table" then table.clone(value) else value[1]
	end,
	alive = function(target: any): boolean
		return target.dead ~= true
	end,
}

local function play(clock: Clock.Clock, engine: Engine.Engine, target: any, data: UILogic.Recipe): () -> ()
	local state = rest()
	local cancels: { () -> () } = {}
	for _, entry in UILogic.schedule(data).entries do
		local function start()
			engine:animate(target, {
				props = UILogic.resolve(entry.step.props, state),
				from = if entry.step.from then UILogic.resolve(entry.step.from, state) else nil,
				duration = entry.step.duration,
				easing = entry.step.easing,
				spring = entry.step.spring,
			})
		end
		if entry.at <= 0 then
			start()
		else
			table.insert(cancels, clock:after(entry.at, start))
		end
	end
	return function()
		for _, cancel in cancels do
			cancel()
		end
		engine:stop(target)
	end
end

local function run(clock: Clock.Clock, seconds: number)
	for _ = 1, math.floor(seconds * 120 + 0.5) do
		clock:step(1 / 120)
	end
end

local function target(): any
	return { Scale = 1, Rotation = 0, GroupFade = 0, Position = { 0.5, 10, 0.5, 20 }, Size = { 0, 200, 0, 100 } }
end

return {
	["presets: every recipe validates and carries full registry metadata"] = function()
		t.equal(registry.kind, "ui")
		t.truthy(registry:count() >= 67, "67 or more presets")
		t.equal(registry:count(), 70)
		for _, preset in registry:list() do
			t.deepEqual(Registry.validate(preset), {}, preset.id .. " metadata")
			t.deepEqual(UILogic.validate(preset.data), {}, preset.id .. " recipe")
			t.truthy(#preset.description >= 20, preset.id .. " description")
			t.truthy(preset.usage and string.find(preset.usage, preset.id, 1, true), preset.id .. " usage")
			t.truthy(preset.params and preset.params.intensity and preset.params.speed, preset.id .. " params")
			t.truthy(preset.quality and preset.quality.cost, preset.id .. " quality")
			t.truthy(preset.tags and #preset.tags >= 1, preset.id .. " tags")
			t.equal(registry:describe(preset.id).id, preset.id)
		end
	end,

	["presets: every required id exists in its category"] = function()
		local total = 0
		for category, ids in UIPresets.REQUIRED :: { [string]: { string } } do
			for _, id in ids do
				total += 1
				t.truthy(registry:has(id), id .. " is registered")
				t.equal(registry:get(id).category, category, id .. " category")
			end
		end
		t.equal(total, 67)
		t.deepEqual(registry:categories(), { "buttons", "cards", "navigation", "notifications", "panels", "text" })
	end,

	["presets: durations follow the timing hierarchy"] = function()
		t.truthy(UILogic.duration(recipe("PressDown")) <= 0.12, "press is 120 ms or less")
		t.truthy(UILogic.duration(recipe("PressDown")) >= 0.05, "press is visible")
		local hover = UILogic.duration(recipe("HoverScale"))
		t.truthy(hover >= 0.08 and hover <= 0.16, "hover about 110 ms")
		local release = UILogic.duration(recipe("ReleaseSpring"))
		t.truthy(release >= 0.18 and release <= 0.3, "release spring 180-300 ms")
		for _, preset in registry:list({ category = "panels" }) do
			local seconds = UILogic.duration(preset.data)
			t.truthy(seconds > 0 and seconds <= 0.5, preset.id .. " lasts 0.5 s or less")
			if preset.data.out then
				t.truthy(seconds <= 0.2, preset.id .. " exits in 200 ms or less")
			end
		end
		for _, id in { "ToastIn", "BadgePop", "TabSwitch", "DropdownOpen", "PageNext" } do
			t.truthy(UILogic.duration(recipe(id)) <= 0.35, id .. " is quick")
		end
		t.truthy(UILogic.duration(recipe("ToastOut")) <= 0.2)
		-- Exits are faster than their entrances.
		t.truthy(UILogic.duration(recipe("PopOut")) <= UILogic.duration(recipe("PopIn")) + 0.02)
		t.truthy(UILogic.duration(recipe("DrawerOut")) < UILogic.duration(recipe("DrawerIn")))
		for _, preset in registry:list() do
			local seconds = UILogic.duration(preset.data)
			t.truthy(seconds <= 2.5, preset.id .. " cycle is 2.5 s or less")
		end
	end,

	["presets: entrances end at rest, exits and states do not"] = function()
		for _, id in { "PopIn", "SlideInLeft", "ModalIn", "ToastIn", "BouncyPress", "Error", "Wiggle", "CardFlip" } do
			t.truthy(UILogic.endsAtRest(recipe(id)), id .. " ends at rest")
		end
		for _, id in { "PopOut", "FadeOut", "DrawerOut", "PressDown", "HoverScale", "Selected", "Disabled" } do
			t.falsy(UILogic.endsAtRest(recipe(id)), id .. " ends away from rest")
		end
		t.deepEqual(UILogic.startPose(recipe("PopIn")), { Scale = 0.6, GroupFade = 1 })
		t.deepEqual(UILogic.endPose(recipe("PopIn")), { Scale = 1, GroupFade = 0 })
		t.deepEqual(UILogic.startPose(recipe("BouncyPress")), {})
	end,

	["presets: loops are flagged and reduced motion skips or replaces them"] = function()
		local loops: { string } = {}
		for _, preset in registry:list() do
			if preset.data.loop then
				table.insert(loops, preset.id)
				t.equal(UILogic.reduced(preset.data), false, preset.id .. " is skipped under reduced motion")
				t.truthy(table.find(preset.tags or {}, "loop") ~= nil, preset.id .. " is tagged loop")
			end
			local substitute = UILogic.reduced(preset.data)
			if type(substitute) == "string" then
				t.truthy(registry:has(substitute), preset.id .. " substitute exists")
				local replacement = recipe(substitute)
				t.equal(UILogic.reduced(replacement), nil, substitute .. " is itself allowed")
				for _, step in replacement.steps do
					t.truthy(step.essential, substitute .. " only uses essential (fade) steps")
					for name in step.props do
						t.equal(name, "GroupFade")
					end
				end
				t.equal(replacement.out == true, preset.data.out == true, preset.id .. " substitute direction")
			end
		end
		table.sort(loops)
		t.deepEqual(
			loops,
			{ "AttentionPing", "Glow", "Loading", "Pulse", "RarityBorder", "Spinner", "TextGlow", "TextPulse" }
		)
		t.equal(UILogic.reduced(recipe("PopIn")), "FadeIn")
		t.equal(UILogic.reduced(recipe("SlideOutUp")), "FadeOut")
		t.equal(UILogic.reduced(recipe("Shine")), false)
		t.equal(UILogic.reduced(recipe("BouncyPress")), nil)
	end,

	["validate: reports bad recipes"] = function()
		t.truthy(#UILogic.validate(nil) > 0)
		t.truthy(#UILogic.validate({ steps = {} }) > 0, "empty")
		t.truthy(#UILogic.validate({ steps = { { props = { Bogus = 1 }, duration = 0.1 } } }) > 0, "unknown property")
		t.truthy(#UILogic.validate({ steps = { { props = { Scale = 1 } } } }) > 0, "no timing")
		t.truthy(#UILogic.validate({ steps = { { props = { Scale = 1 }, spring = "Nope" } } }) > 0, "unknown spring")
		t.truthy(
			#UILogic.validate({ steps = { { props = { Scale = 1 }, duration = 0.1, easing = "nope" } } }) > 0,
			"unknown easing"
		)
		t.truthy(#UILogic.validate({ steps = { { props = { GroupFade = 2 }, duration = 0.1 } } }) > 0, "fade range")
		t.truthy(#UILogic.validate({ steps = { { props = { Scale = -1 }, duration = 0.1 } } }) > 0, "negative scale")
		t.truthy(#UILogic.validate({ steps = { { props = { Scale = 1 }, duration = 0.1, join = true } } }) > 0, "join")
		t.truthy(#UILogic.validate({ steps = {}, layers = { { kind = "sparkles", duration = 1 } } }) > 0, "layer kind")
		t.truthy(#UILogic.validate({ steps = {}, layers = { { kind = "shine" } } }) > 0, "layer duration")
		t.truthy(
			#UILogic.validate({ steps = {}, layers = { { kind = "glow", mode = "pulse", period = 1 } } }) > 0,
			"looping layer needs loop"
		)
		t.truthy(
			#UILogic.validate({ steps = { { props = { Scale = 1 }, duration = 0 } }, loop = true }) > 0,
			"zero loop"
		)
		t.deepEqual(
			UILogic.validate({ steps = { { props = { Scale = 1.1 }, spring = { frequency = 3, damping = 0.5 } } } }),
			{}
		)
	end,

	["schedule: steps chain, joined steps start together, delays shift"] = function()
		local data: UILogic.Recipe = {
			steps = {
				{ props = { Scale = 0.9 }, duration = 0.1 },
				{ props = { GroupFade = 0 }, duration = 0.05, join = true, delay = 0.02 },
				{ props = { Scale = 1 }, duration = 0.2 },
				{ props = { Rotation = 0 }, duration = 0.5, join = true },
				{ props = { Scale = 1 }, duration = 0.1 },
			},
		}
		local plan = UILogic.schedule(data)
		t.near(plan.entries[1].at, 0)
		t.near(plan.entries[2].at, 0.02)
		t.near(plan.entries[3].at, 0.1)
		t.near(plan.entries[4].at, 0.1)
		t.near(plan.entries[5].at, 0.6, 1e-9, "waits for the longest step of the group")
		t.near(plan.total, 0.7)
		local bouncy = UILogic.schedule(recipe("BouncyPress"))
		t.near(bouncy.entries[2].at, 0.07)
		t.near(bouncy.total, 0.07 + Springs.settleTime("Bouncy", UILogic.SETTLE))
		t.near(UILogic.duration(recipe("Shine")), 0.6, 1e-9, "layer-only recipes last as long as the layer")
		t.near(UILogic.duration(recipe("CardReveal")), 0.8, 1e-9, "a delayed layer extends the recipe")
		t.near(UILogic.duration(recipe("Glow")), 0, 1e-9, "endless layers have no length")
	end,

	["scale: duration, speed, intensity, overrides, delay and mirror"] = function()
		local base = recipe("BouncyPress")
		local total = UILogic.duration(base)
		local slow = UILogic.scale(base, { duration = total * 2 })
		t.near(UILogic.duration(slow), total * 2, 1e-6, "duration sets the total")
		t.near(slow.steps[1].duration :: number, 0.14)
		local slowSpring = slow.steps[2].spring :: Springs.Spring
		t.near(slowSpring.frequency, Springs.get("Bouncy").frequency / 2, 1e-9, "springs slow down by frequency")
		t.near(slowSpring.damping, Springs.get("Bouncy").damping)
		t.near(UILogic.duration(UILogic.scale(base, { speed = 2 })), total / 2, 1e-6)
		t.near(UILogic.duration(UILogic.scale(base, { duration = 0.3 })), 0.3, 1e-6)

		local half = UILogic.scale(base, { intensity = 0.5 })
		t.near(half.steps[1].props.Scale, 0.96)
		t.near(half.steps[2].props.Scale, 1)
		t.near(UILogic.scale(base, { intensity = 0 }).steps[1].props.Scale, 1, 1e-9, "intensity 0 removes the motion")
		t.near(base.steps[1].props.Scale, 0.92, 1e-9, "the registered recipe is untouched")

		local slide = UILogic.scale(recipe("SlideInLeft"), { intensity = 2, mirror = true })
		t.near((slide.steps[1].from :: UILogic.Props).OffsetX, 96, 1e-9, "offsets scale and mirror")
		t.near((slide.steps[2].from :: UILogic.Props).GroupFade, 1, 1e-9, "fades do not scale")
		local drawer = UILogic.scale(recipe("DrawerIn"), { intensity = 0.25 })
		t.near((drawer.steps[1].from :: UILogic.Props).OffsetYSize, 1, 1e-9, "size offsets ignore intensity")
		local flip = UILogic.scale(recipe("CardFlip"), { intensity = 0.25 })
		t.near(flip.steps[1].props.Width, 0, 1e-9, "width ignores intensity")
		t.equal(flip.steps[2].marker, "flip")
		t.near(UILogic.scale(recipe("Wiggle"), { mirror = true }).steps[1].props.Rotation, 8)

		local eased = UILogic.scale(base, { easing = "linear", spring = "Soft" })
		t.equal(eased.steps[1].easing, "linear")
		t.equal(eased.steps[2].spring, "Soft")
		t.equal(eased.steps[2].easing, nil)

		local delayed = UILogic.scale(base, { delay = 0.5 })
		local plan = UILogic.schedule(delayed)
		t.near(plan.entries[1].at, 0.5)
		t.near(plan.total, total + 0.5)
		t.near(UILogic.duration(UILogic.scale(delayed, { duration = 1 })), 1.5, 1e-6, "delay is not time-scaled")

		local shine = UILogic.scale(recipe("CardReveal"), { speed = 2 })
		local layer = (shine.layers :: { UILogic.Layer })[1]
		t.near(layer.duration, 0.275)
		t.near(layer.delay, 0.125)
		local ping = UILogic.scale(recipe("AttentionPing"), { speed = 2 })
		t.near(ping.gap :: number, 0.55)
		t.truthy(ping.loop)
	end,

	["resolve: goals are relative to the rest state"] = function()
		local state = rest()
		state.scale = 0.5
		state.rotation = 10
		state.fade = 0.4
		local goals = UILogic.resolve({ Scale = 1.2, Rotation = -5, GroupFade = 0.5 }, state)
		t.near(goals.Scale[1], 0.6)
		t.near(goals.Rotation[1], 5)
		t.near(goals.GroupFade[1], 0.7, 1e-9, "fade moves from rest toward invisible")
		t.equal(goals.Position, nil)
		t.equal(goals.Size, nil)
		t.near(UILogic.resolve({ GroupFade = 0 }, state).GroupFade[1], 0.4)
		t.near(UILogic.resolve({ GroupFade = 1 }, state).GroupFade[1], 1)

		t.deepEqual(UILogic.resolve({ OffsetX = -48 }, state).Position, { 0.5, -38, 0.5, 20 })
		t.deepEqual(UILogic.resolve({ OffsetY = 6, OffsetX = 0 }, state).Position, { 0.5, 10, 0.5, 26 })
		t.deepEqual(UILogic.resolve({ OffsetXSize = -1 }, state).Position, { 0.5, -190, 0.5, 20 })
		t.deepEqual(UILogic.resolve({ OffsetYSize = 0.5, OffsetY = 4 }, state).Position, { 0.5, 10, 0.5, 74 })
		t.deepEqual(UILogic.resolve({ Width = 0 }, state).Size, { 0, 0, 0, 100 })
		t.deepEqual(UILogic.resolve({ Height = 0.5 }, state).Size, { 0, 200, 0, 50 })
		local scaled = rest()
		scaled.size = { 0.5, 20, 1, -10 }
		t.deepEqual(UILogic.resolve({ Width = 0.5, Height = 2 }, scaled).Size, { 0.25, 10, 2, -20 })
	end,

	["channels: recipes that share a property replace each other"] = function()
		local press = UILogic.channels(recipe("PressDown"))
		local hover = UILogic.channels(recipe("HoverScale"))
		local shine = UILogic.channels(recipe("Shine"))
		local slide = UILogic.channels(recipe("SlideInLeft"))
		t.deepEqual(press, { Scale = true })
		t.deepEqual(shine, { ["layer:shine"] = true })
		t.deepEqual(slide, { Position = true, GroupFade = true })
		t.truthy(UILogic.sharesChannel(press, hover))
		t.falsy(UILogic.sharesChannel(press, shine), "a shine can run over a press")
		t.falsy(UILogic.sharesChannel(press, slide))
		t.truthy(UILogic.channels(recipe("IndicatorSlide")).Position)
		t.truthy(UILogic.channels(recipe("Selected"))["layer:glow"])
	end,

	["engine: BouncyPress squashes, bounces past rest and settles"] = function()
		local clock = Clock.new()
		local engine = Engine.new(adapter, clock)
		local button = target()
		play(clock, engine, button, recipe("BouncyPress"))
		local lowest, highest = 1, 0
		for _ = 1, 120 do
			clock:step(1 / 120)
			lowest = math.min(lowest, button.Scale)
			highest = math.max(highest, button.Scale)
		end
		t.near(lowest, 0.92, 0.005, "reaches the press scale")
		t.truthy(highest > 1.01, "overshoots rest on release")
		t.near(button.Scale, 1, 0.002, "settles at rest")
		t.equal(clock:count(), 0, "nothing keeps running")
	end,

	["engine: an entrance starts from its pose and ends exactly at rest"] = function()
		local clock = Clock.new()
		local engine = Engine.new(adapter, clock)
		for _, id in { "PopIn", "SlideInUp", "ModalIn", "ToastIn", "ScrollReveal", "LevelUpText", "DropdownOpen" } do
			local panel = target()
			play(clock, engine, panel, recipe(id))
			clock:step(0)
			local pose = UILogic.resolve(UILogic.startPose(recipe(id)), rest())
			for property, value in pose do
				if property ~= "GroupFade" or id ~= "LevelUpText" then
					local actual: { number } = if type(panel[property]) == "table"
						then panel[property]
						else { panel[property] }
					for index, expected in value do
						t.near(actual[index], expected, 1e-9, id .. " starts at its pose: " .. property)
					end
				end
			end
			run(clock, 2)
			t.near(panel.Scale, 1, 0.002, id .. " scale")
			t.near(panel.GroupFade, 0, 1e-6, id .. " fade")
			t.near(panel.Position[2], 10, 0.05, id .. " x")
			t.near(panel.Position[4], 20, 0.05, id .. " y")
			t.near(panel.Size[4], 100, 1e-6, id .. " height")
			t.equal(clock:count(), 0, id .. " leaves no job")
		end
	end,

	["engine: cancelling a chain stops later steps"] = function()
		local clock = Clock.new()
		local engine = Engine.new(adapter, clock)
		local button = target()
		local cancel = play(clock, engine, button, recipe("Wiggle"))
		run(clock, 0.05)
		cancel()
		local angle = button.Rotation
		t.truthy(angle < 0, "was rotating")
		run(clock, 1)
		t.equal(button.Rotation, angle, "no later step ran")
		t.equal(clock:count(), 0)
		-- A destroyed target ends its tracks.
		local dead = target()
		play(clock, engine, dead, recipe("PopIn"))
		dead.dead = true
		run(clock, 1)
		t.equal(clock:count(), 0)
	end,

	["counter: rolls whole numbers, scales time with the change, formats"] = function()
		t.equal(UILogic.count(0, 100, 0), 0)
		t.equal(UILogic.count(0, 100, 1), 100)
		local previous = 0
		for step = 0, 20 do
			local value = UILogic.count(0, 1000, step / 20)
			t.equal(value % 1, 0, "whole numbers stay whole")
			t.truthy(value >= previous, "never runs backwards")
			previous = value
		end
		t.truthy(UILogic.count(0, 1000, 0.5) > 500, "eases out: most of the change comes early")
		t.equal(UILogic.count(50, 10, 1), 10)
		t.truthy(UILogic.count(50, 10, 0.5) < 50)
		t.near(UILogic.count(0, 1.5, 1), 1.5)
		t.equal(UILogic.countDuration(0), 0)
		t.truthy(UILogic.countDuration(5) >= 0.4, "small gains still take 0.4 s")
		t.truthy(UILogic.countDuration(5) < UILogic.countDuration(5000))
		t.near(UILogic.countDuration(1e12), 1.2, 1e-9, "capped at 1.2 s")
		t.near(UILogic.countDuration(-5000), UILogic.countDuration(5000))
		t.near(UILogic.countDuration(1e12, 0.2, 2), 2)
		t.equal(UILogic.countText(1234), "1,234")
		t.equal(UILogic.countText(1500, { format = "abbrev" }), "1.5K")
		t.equal(UILogic.countText(250, { prefix = "+", suffix = " XP" }), "+250 XP")
		t.equal(UILogic.countText(0.42, { format = "percent" }), "42%")
	end,

	["typewriter: UTF-8 safe index and prefix"] = function()
		local text = "Héllo ★ wörld"
		local count = UILogic.typeCount(text)
		t.equal(count, 13)
		t.truthy(#text > count, "the text has multi-byte characters")
		t.equal(UILogic.typeIndex(0, 40, count), 0)
		t.equal(UILogic.typeIndex(0.1, 40, count), 4)
		t.equal(UILogic.typeIndex(10, 40, count), count, "clamped to the length")
		t.equal(UILogic.typeIndex(-1, 40, count), 0)
		t.near(UILogic.typeDuration(count, 26), 0.5)
		t.near(UILogic.typeDuration(40), 1, 1e-9, "40 characters per second by default")
		t.equal(UILogic.typePrefix(text, 0), "")
		t.equal(UILogic.typePrefix(text, 2), "Hé")
		t.equal(UILogic.typePrefix(text, 7), "Héllo ★")
		t.equal(UILogic.typePrefix(text, count), text)
		t.equal(UILogic.typePrefix(text, 99), text)
		for index = 0, count do
			t.truthy(utf8.len(UILogic.typePrefix(text, index)) == index, "prefix " .. index .. " is valid UTF-8")
		end
		t.equal(UILogic.typePrefix("ab\255cd", 3), "ab\255", "invalid UTF-8 falls back to bytes")
	end,

	["stagger: forward, reverse, center, edges and seeded random"] = function()
		t.deepEqual(UILogic.staggerDelays(4, 0.05), { 0, 0.05, 0.1, 0.15000000000000002 })
		t.deepEqual(UILogic.staggerDelays(3, 0.1, "reverse"), { 0.2, 0.1, 0 })
		t.deepEqual(UILogic.staggerDelays(5, 1, "center"), { 2, 1, 0, 1, 2 })
		t.deepEqual(UILogic.staggerDelays(4, 1, "center"), { 1, 0, 0, 1 })
		t.deepEqual(UILogic.staggerDelays(5, 1, "edges"), { 0, 1, 2, 1, 0 })
		t.deepEqual(UILogic.staggerDelays(0, 1), {})
		t.deepEqual(UILogic.staggerDelays(1, 1, "center"), { 0 })
		local a = UILogic.staggerDelays(8, 1, "random", 42)
		local b = UILogic.staggerDelays(8, 1, "random", 42)
		local c = UILogic.staggerDelays(8, 1, "random", 43)
		t.deepEqual(a, b, "the same seed gives the same order")
		local same = true
		for index = 1, 8 do
			if a[index] ~= c[index] then
				same = false
			end
		end
		t.falsy(same, "another seed gives another order")
		local sorted = table.clone(a)
		table.sort(sorted)
		t.deepEqual(sorted, { 0, 1, 2, 3, 4, 5, 6, 7 }, "a permutation: every slot used once")
		t.deepEqual(UILogic.staggerDelays(3, -1), { 0, 0, 0 }, "negative intervals clamp to zero")
	end,

	["popup: pops, rises, drifts and fades; crits are bigger and wobble"] = function()
		for _, name in UILogic.POPUP_STYLES do
			local style = UILogic.popupStyle(name)
			t.truthy(style.duration >= 0.6 and style.duration <= 1.2, name .. " duration")
			local start = UILogic.popupSample(style, 0, 3)
			t.near(start.y, 0)
			t.near(start.x, 0)
			t.near(start.scale, 0.4)
			t.equal(start.transparency, 0)
			local peak = UILogic.popupSample(style, style.popTime / style.duration, 3)
			t.near(peak.scale, style.pop, 0.01, name .. " reaches its peak scale")
			local middle = UILogic.popupSample(style, 0.5, 3)
			t.near(middle.scale, 1, 1e-6, name .. " has settled by half way")
			t.equal(middle.transparency, 0, name .. " is readable at half way")
			t.truthy(middle.y < -style.rise * 0.8, name .. " rises fast, then slows")
			local finish = UILogic.popupSample(style, 1, 3)
			t.near(finish.y, -style.rise)
			t.near(finish.transparency, 1)
			t.truthy(math.abs(finish.x) <= style.drift + 1e-9)
			local previous = 0
			for step = 0, 20 do
				local sample = UILogic.popupSample(style, step / 20, 3)
				t.truthy(sample.y <= previous + 1e-9, name .. " never falls")
				previous = sample.y
			end
		end
		local crit, damage = UILogic.popupStyle("crit"), UILogic.popupStyle("damage")
		t.truthy(crit.pop > damage.pop and crit.size > damage.size and crit.duration > damage.duration)
		local wobble = 0
		for step = 1, 19 do
			wobble = math.max(wobble, math.abs(UILogic.popupSample(crit, step / 20, 1).rotation))
			t.equal(UILogic.popupSample(damage, step / 20, 1).rotation, 0)
		end
		t.truthy(wobble > 2, "crits wobble")
		t.near(UILogic.popupSample(crit, 1, 1).rotation, 0)
		t.equal(UILogic.popupStyle("nope"), damage, "unknown styles fall back to damage")
		local left, right = false, false
		for seed = 1, 20 do
			local x = UILogic.popupSample(damage, 1, seed).x
			left = left or x < 0
			right = right or x > 0
			t.equal(x, UILogic.popupSample(damage, 1, seed).x, "drift is deterministic per seed")
		end
		t.truthy(left and right, "popups drift to both sides")
	end,

	["fly: bursts outward in every direction, then homes onto the target"] = function()
		local items = UILogic.flyPlan(8, 7, { spread = 70, stagger = 0.05, duration = 0.6 })
		t.equal(#items, 8)
		t.deepEqual(UILogic.flyPlan(8, 7, { spread = 70, stagger = 0.05, duration = 0.6 }), items, "deterministic")
		local quadrants: { [string]: boolean } = {}
		for index, item in items do
			t.near(item.delay, (index - 1) * 0.05)
			t.truthy(item.duration >= 0.54 - 1e-9 and item.duration <= 0.66 + 1e-9, "duration varies by 10 %")
			local radius = math.sqrt(item.bx * item.bx + item.by * item.by)
			t.truthy(radius >= 70 * 0.55 - 1e-6 and radius <= 70 + 1e-6, "burst radius within the spread")
			quadrants[(if item.bx >= 0 then "R" else "L") .. (if item.by >= 0 then "D" else "U")] = true

			local start = UILogic.flySample(item, 100, 100, 500, 40, 0)
			t.near(start.x, 100)
			t.near(start.y, 100)
			local burst = UILogic.flySample(item, 100, 100, 500, 40, UILogic.FLY_BURST)
			t.near(burst.x, 100 + item.bx, 1e-6, "the burst ends at its offset")
			t.near(burst.y, 100 + item.by, 1e-6)
			local before = UILogic.flySample(item, 100, 100, 500, 40, UILogic.FLY_BURST - 1e-6)
			t.near(before.x, burst.x, 0.01, "no jump between burst and homing")
			t.near(before.y, burst.y, 0.01)
			local finish = UILogic.flySample(item, 100, 100, 500, 40, 1)
			t.near(finish.x, 500, 1e-6, "arrives exactly on the target")
			t.near(finish.y, 40, 1e-6)
			t.truthy(finish.scale < 1, "shrinks into the counter")
			-- Homing accelerates: less than half the remaining distance is covered at half time.
			local half = UILogic.flySample(item, 100, 100, 500, 40, UILogic.FLY_BURST + (1 - UILogic.FLY_BURST) / 2)
			local whole = math.abs(500 - burst.x)
			t.truthy(math.abs(half.x - burst.x) < whole * 0.6, "eases in toward the target")
		end
		t.truthy(quadrants.RD and quadrants.RU and quadrants.LD and quadrants.LU, "covers every direction")
		t.near(UILogic.flyDuration(items), items[8].delay + items[8].duration, 0.07)
		t.truthy(UILogic.flyDuration(items) >= 0.35 + 0.54)
		t.deepEqual(UILogic.flyPlan(0), {})
		t.equal(UILogic.flyDuration({}), 0)
		t.equal(#UILogic.flyPlan(3), 3)
	end,

	["ripple: covers the far corner and fades as it grows"] = function()
		t.near(UILogic.rippleRadius(200, 100, 100, 50), math.sqrt(100 * 100 + 50 * 50))
		t.near(UILogic.rippleRadius(200, 100, 0, 0), math.sqrt(200 * 200 + 100 * 100))
		t.near(UILogic.rippleRadius(200, 100, 200, 100), math.sqrt(200 * 200 + 100 * 100))
		t.near(UILogic.rippleRadius(200, 100, 150, 20), math.sqrt(150 * 150 + 80 * 80))
		local start, finish = UILogic.rippleSample(0), UILogic.rippleSample(1)
		t.truthy(start.size > 0 and start.size < 0.2, "visible on the first frame")
		t.near(start.transparency, 0.72)
		t.near(finish.size, 1)
		t.near(finish.transparency, 1)
		local previous = UILogic.rippleSample(0)
		for step = 1, 10 do
			local sample = UILogic.rippleSample(step / 10)
			t.truthy(sample.size >= previous.size and sample.transparency >= previous.transparency)
			previous = sample
		end
		t.truthy(UILogic.rippleSample(0.5).size > 0.8, "decelerates: most growth is early")
		t.near(UILogic.rippleSample(0, 0.5).transparency, 0.5)
	end,

	["button: hover, press, release, leave"] = function()
		local state = UILogic.buttonState()
		local action: string?
		t.equal(UILogic.buttonStatus(state), "idle")
		state, action = UILogic.buttonEvent(state, "enter")
		t.equal(action, "hover")
		t.equal(UILogic.buttonStatus(state), "hover")
		state, action = UILogic.buttonEvent(state, "enter")
		t.equal(action, nil, "entering twice does nothing")
		state, action = UILogic.buttonEvent(state, "press")
		t.equal(action, "press")
		t.equal(UILogic.buttonStatus(state), "pressed")
		state, action = UILogic.buttonEvent(state, "press")
		t.equal(action, nil, "mouse and touch may both report the press")
		state, action = UILogic.buttonEvent(state, "release")
		t.equal(action, "releaseHover", "released under the pointer: back to hover")
		t.equal(UILogic.buttonStatus(state), "hover")
		state, action = UILogic.buttonEvent(state, "release")
		t.equal(action, nil)
		state, action = UILogic.buttonEvent(state, "leave")
		t.equal(action, "unhover")
		t.equal(UILogic.buttonStatus(state), "idle")
		state, action = UILogic.buttonEvent(state, "leave")
		t.equal(action, nil)
		-- Touch: press and release without hover.
		state, action = UILogic.buttonEvent(state, "press")
		t.equal(action, "press")
		state, action = UILogic.buttonEvent(state, "release")
		t.equal(action, "release")
		-- Dragging off while pressed cancels the press.
		state = UILogic.buttonEvent(state, "enter")
		state = UILogic.buttonEvent(state, "press")
		state, action = UILogic.buttonEvent(state, "leave")
		t.equal(action, "unhover")
		t.falsy(state.pressed)
		state, action = UILogic.buttonEvent(state, "bogus")
		t.equal(action, nil)
	end,

	["button: gamepad focus, selected and disabled"] = function()
		local state = UILogic.buttonState()
		local action: string?
		state, action = UILogic.buttonEvent(state, "focus")
		t.equal(action, "hover")
		t.equal(UILogic.buttonStatus(state), "focused")
		state, action = UILogic.buttonEvent(state, "enter")
		t.equal(action, nil, "already highlighted by focus")
		state, action = UILogic.buttonEvent(state, "blur")
		t.equal(action, nil, "the pointer still hovers")
		state, action = UILogic.buttonEvent(state, "leave")
		t.equal(action, "unhover")

		state, action = UILogic.buttonEvent(state, "select")
		t.equal(action, "select")
		t.equal(UILogic.buttonStatus(state), "selected")
		state, action = UILogic.buttonEvent(state, "select")
		t.equal(action, nil)
		state, action = UILogic.buttonEvent(state, "enter")
		t.equal(action, "hover")
		state, action = UILogic.buttonEvent(state, "leave")
		t.equal(action, "selectedRest", "a selected button rests in its selected pose")
		state = UILogic.buttonEvent(state, "press")
		state, action = UILogic.buttonEvent(state, "release")
		t.equal(action, "selectedRest")
		state, action = UILogic.buttonEvent(state, "deselect")
		t.equal(action, "deselect")

		state, action = UILogic.buttonEvent(state, "disable")
		t.equal(action, "disable")
		t.equal(UILogic.buttonStatus(state), "disabled")
		for _, event in { "enter", "press", "release", "leave", "focus", "blur", "disable" } do
			state, action = UILogic.buttonEvent(state, event)
			t.equal(action, nil, event .. " is ignored while disabled")
		end
		state, action = UILogic.buttonEvent(state, "select")
		t.equal(action, nil, "selection is remembered but not shown while disabled")
		t.truthy(state.selected)
		state, action = UILogic.buttonEvent(state, "enable")
		t.equal(action, "enable")
		state, action = UILogic.buttonEvent(state, "enable")
		t.equal(action, nil)
		-- Disabling while pressed drops the press.
		state = UILogic.buttonEvent(state, "press")
		state = UILogic.buttonEvent(state, "disable")
		t.falsy(state.pressed)
	end,

	["button: every style maps actions to registered presets"] = function()
		t.deepEqual(UILogic.BUTTON_STYLES, { "BouncyPress", "Soft", "Snappy", "Premium", "Arcade", "Minimal" })
		local actions = {
			"hover",
			"unhover",
			"press",
			"release",
			"releaseHover",
			"select",
			"selectedRest",
			"deselect",
			"disable",
			"enable",
		}
		for _, style in UILogic.BUTTON_STYLES do
			t.truthy(UILogic.hasButtonStyle(style))
			for _, action in actions do
				local spec = UILogic.buttonAction(style, action)
				if spec then
					t.truthy(registry:has(spec.preset), style .. "." .. action .. " preset exists")
					t.truthy(spec.spring == nil or Springs.has(spec.spring), style .. "." .. action .. " spring")
					t.truthy(spec.effect == nil or spec.effect == "shine" or spec.effect == "ripple")
				end
			end
			t.truthy(UILogic.buttonAction(style, "press"), style .. " responds to a press")
			t.truthy(UILogic.buttonAction(style, "release"), style .. " releases")
			t.equal((UILogic.buttonAction(style, "select") :: UILogic.ButtonAction).preset, "Selected")
			t.equal((UILogic.buttonAction(style, "disable") :: UILogic.ButtonAction).preset, "Disabled")
		end
		t.equal((UILogic.buttonAction(nil, "press") :: UILogic.ButtonAction).preset, "PressDown")
		t.equal((UILogic.buttonAction("Unknown", "hover") :: UILogic.ButtonAction).preset, "HoverScale")
		t.equal(UILogic.buttonAction("Minimal", "hover"), nil, "Minimal does not move on hover")
		t.equal((UILogic.buttonAction("Premium", "hover") :: UILogic.ButtonAction).effect, "shine")
		t.equal((UILogic.buttonAction("Arcade", "press") :: UILogic.ButtonAction).effect, "ripple")
		t.falsy(UILogic.hasButtonStyle("Unknown"))
		t.equal(UILogic.buttonAction("BouncyPress", "bogus"), nil)
	end,

	["xp: gains overflow across levels"] = function()
		local plan = UILogic.xpPlan(3, 40, 100, 30)
		t.deepEqual(plan.segments, { { level = 3, from = 40, to = 70, max = 100, levelUp = false } })
		t.equal(plan.level, 3)
		t.equal(plan.value, 70)
		t.equal(plan.levelUps, 0)

		local exact = UILogic.xpPlan(3, 40, 100, 60)
		t.deepEqual(exact.segments, { { level = 3, from = 40, to = 100, max = 100, levelUp = true } })
		t.equal(exact.level, 4)
		t.equal(exact.value, 0)

		local big = UILogic.xpPlan(1, 50, 100, 400, function(level: number): number
			return level * 100
		end)
		t.deepEqual(big.segments, {
			{ level = 1, from = 50, to = 100, max = 100, levelUp = true },
			{ level = 2, from = 0, to = 200, max = 200, levelUp = true },
			{ level = 3, from = 0, to = 150, max = 300, levelUp = false },
		})
		t.equal(big.level, 3)
		t.equal(big.value, 150)
		t.equal(big.max, 300)
		t.equal(big.levelUps, 2)

		t.deepEqual(UILogic.xpPlan(1, 10, 100, 0).segments, {})
		t.deepEqual(UILogic.xpPlan(1, 10, 100, -5).segments, {})
		local capped = UILogic.xpPlan(1, 0, 1, 1e6)
		t.equal(capped.levelUps, 50, "at most 50 level-ups per call")
		t.equal(capped.value, 1)
		local guarded = UILogic.xpPlan(1, 0, 0, 3, function(): number
			return 0
		end)
		t.equal(guarded.levelUps, 3, "a zero-sized bar counts as 1")
	end,

	["cooldown: ratio and text"] = function()
		t.equal(UILogic.cooldownRatio(5, 10), 0.5)
		t.equal(UILogic.cooldownRatio(0, 10), 0)
		t.equal(UILogic.cooldownRatio(20, 10), 1)
		t.equal(UILogic.cooldownRatio(-1, 10), 0)
		t.equal(UILogic.cooldownRatio(5, 0), 0)
		t.equal(UILogic.cooldownText(12.2), "13")
		t.equal(UILogic.cooldownText(3), "3")
		t.equal(UILogic.cooldownText(2.44), "2.4")
		t.equal(UILogic.cooldownText(0), "")
	end,

	["random: deterministic and inside 0..1"] = function()
		local seed = 12345
		local seen: { [number]: boolean } = {}
		for _ = 1, 200 do
			local value: number
			seed, value = UILogic.random(seed)
			t.truthy(value > 0 and value < 1)
			t.falsy(seen[seed], "no short cycle")
			seen[seed] = true
		end
		local a = UILogic.random(99)
		local b = UILogic.random(99)
		t.equal(a, b)
		local zero = UILogic.random(0)
		t.truthy(zero > 0, "seed 0 is usable")
	end,
}
