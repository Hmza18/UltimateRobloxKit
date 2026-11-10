--!strict
local Clock = require("../src/Visuals/Core/Clock")
local Effects = require("../src/Visuals/Core/Effects")
local Pool = require("../src/Visuals/Core/Pool")
local Quality = require("../src/Visuals/Core/Quality")
local Registry = require("../src/Visuals/Core/Registry")
local t = require("./lib/t")

local function preset(id: string, extra: { [string]: any }?): Registry.Preset
	local base: any = {
		id = id,
		name = id .. " name",
		category = "rewards",
		description = "A test preset used by the registry spec.",
		data = { layers = {} },
	}
	for key, value in extra or {} do
		base[key] = value
	end
	return base
end

local function effectsHost(level: Quality.Level?)
	local clock = Clock.new()
	local state = { level = level or "High", viewer = { 0, 0, 0 }, visible = true }
	local effects = Effects.new({
		clock = clock,
		profile = function(): Quality.Profile
			return Quality.profile(state.level)
		end,
		viewer = function(): Effects.Position?
			return state.viewer
		end,
		visible = function(): boolean
			return state.visible
		end,
	})
	return clock, effects, state
end

local function request(
	id: string,
	counter: { built: number, destroyed: number },
	extra: { [string]: any }?
): Effects.Request
	local r: any = {
		id = id,
		particles = 10,
		duration = 1,
		build = function(): (() -> ())?
			counter.built += 1
			return function()
				counter.destroyed += 1
			end
		end,
	}
	for key, value in extra or {} do
		r[key] = value
	end
	return r
end

return {
	["registry: register, get, list, categories and metadata"] = function()
		local registry = Registry.new("vfx")
		registry:register(
			preset("CoinBurst", { tags = { "currency", "burst" }, usage = 'Visuals:Play("CoinBurst", position)' })
		)
		registry:register(preset("LevelUp", { category = "progression", quality = { min = "Medium", cost = "high" } }))
		t.equal(registry:count(), 2)
		t.truthy(registry:has("CoinBurst"))
		t.equal(registry:get("LevelUp").category, "progression")
		t.deepEqual(registry:categories(), { "progression", "rewards" })
		t.deepEqual(registry:ids({ category = "rewards" }), { "CoinBurst" })
		t.deepEqual(registry:ids({ quality = "Low" }), { "CoinBurst" }, "LevelUp needs Medium")
		t.deepEqual(registry:ids({ tag = "burst" }), { "CoinBurst" })
		local described = registry:describe("CoinBurst")
		t.equal(described.kind, "vfx")
		t.equal(described.usage, 'Visuals:Play("CoinBurst", position)')
		t.equal(described.data, nil, "describe returns metadata only")
		t.throws(function()
			registry:get("Missing")
		end)
		t.equal(registry:find("Missing"), nil)
	end,
	["registry: invalid presets are rejected with reasons"] = function()
		local registry = Registry.new("vfx")
		t.throws(function()
			registry:register(preset("lowercase"))
		end)
		t.throws(function()
			registry:register(preset("NoData", { data = false }) :: any, nil)
			registry:register({ id = "X", name = "x", category = "c", description = "short" } :: any)
		end)
		local problems = Registry.validate(preset("Bad", {
			quality = { min = "Extreme" },
			params = { size = { type = "number", default = "big" }, tint = { type = "color", default = "red" } },
		}))
		t.equal(#problems, 3)
	end,
	["registry: overrides need the flag, keep the original and can be reset"] = function()
		local registry = Registry.new("ui")
		local original = registry:register(preset("Pop"))
		t.throws(function()
			registry:register(preset("Pop"))
		end)
		local mine = registry:register(preset("Pop", { name = "My pop" }), { override = true })
		t.equal(registry:get("Pop"), mine)
		t.equal(registry:original("Pop"), original)
		t.truthy(registry:isOverridden("Pop"))
		registry:register(preset("Pop", { name = "Third" }), { override = true })
		t.equal(registry:original("Pop"), original, "the built-in stays the original")
		t.truthy(registry:reset("Pop"))
		t.equal(registry:get("Pop"), original)
		t.falsy(registry:reset("Pop"))
	end,
	["registry: params merge defaults, clamp numbers and check types"] = function()
		local registry = Registry.new("vfx")
		registry:register(preset("Burst", {
			params = {
				count = { type = "number", default = 20, min = 1, max = 100 },
				color = { type = "color", default = "#FFD24A" },
				loop = { type = "boolean", default = false },
				shape = { type = "enum", default = "sphere", options = { "sphere", "ring" } },
			},
		}))
		t.deepEqual(registry:params("Burst"), { count = 20, color = "#FFD24A", loop = false, shape = "sphere" })
		local merged = registry:params("Burst", { count = 500, shape = "ring", owner = "pet" })
		t.equal(merged.count, 100)
		t.equal(merged.shape, "ring")
		t.equal(merged.owner, "pet", "unknown keys pass through")
		t.throws(function()
			registry:params("Burst", { count = "many" })
		end)
		t.throws(function()
			registry:params("Burst", { shape = "cube" })
		end)
		t.throws(function()
			registry:params("Burst", { color = "blue" })
		end)
	end,
	["registry: search ranks id matches first"] = function()
		local registry = Registry.new("vfx")
		registry:register(preset("CoinBurst", { tags = { "currency" } }))
		registry:register(preset("GemBurst", { description = "Gems fly out like a coin fountain." }))
		registry:register(preset("Rain", { category = "environment" }))
		t.deepEqual(registry:search("coin"), { "CoinBurst", "GemBurst" })
		t.deepEqual(registry:search("environment"), { "Rain" })
		t.deepEqual(registry:search("burst", 1), { "CoinBurst" })
		t.equal(#registry:search("zzz"), 0)
	end,
	["quality: profiles are ordered and budgets grow with the level"] = function()
		local previous: Quality.Profile? = nil
		for _, level in Quality.LEVELS do
			local profile = Quality.profile(level)
			t.equal(profile.level, level)
			if previous then
				t.truthy(profile.maxParticles > previous.maxParticles)
				t.truthy(profile.maxEffects > previous.maxEffects)
				t.truthy(profile.particleScale > previous.particleScale)
				t.truthy(profile.maxDistance > previous.maxDistance)
			end
			previous = profile
		end
		t.truthy(Quality.profile("Low").dropOptional)
		t.equal(Quality.profile("Low").maxLights, 0)
		t.throws(function()
			Quality.profile("Extreme")
		end)
		t.truthy(Quality.atLeast("High", "Medium"))
		t.falsy(Quality.atLeast("Low", "Medium"))
		t.equal(Quality.fromLegacy("low"), "Low")
		t.equal(Quality.toLegacy("Ultra"), "high")
	end,
	["quality: device choice"] = function()
		t.equal(Quality.choose({ graphicsLevel = 2 }), "Low")
		t.equal(Quality.choose({ graphicsLevel = 5 }), "Medium")
		t.equal(Quality.choose({ graphicsLevel = 8 }), "High")
		t.equal(Quality.choose({ graphicsLevel = 10 }), "Ultra")
		t.equal(Quality.choose({ graphicsLevel = 10, touch = true }), "High")
		t.equal(Quality.choose({ touch = true }), "Low")
		t.equal(Quality.choose({ touch = true, fps = 60 }), "Medium")
		t.equal(Quality.choose({ fps = 30 }), "Low")
		t.equal(Quality.choose({}), "High")
		t.equal(Quality.choose({ memoryMb = 1024, graphicsLevel = 10 }), "Low")
		t.equal(Quality.choose({ graphicsLevel = 0 / 0 }), "High")
	end,
	["quality: settings merge and juice"] = function()
		local settings = Quality.merge(
			Quality.defaults(),
			{ level = "Ultra", intensity = 9, reducedMotion = "yes", adaptive = false }
		)
		t.equal(settings.level, "Ultra")
		t.equal(settings.intensity, 1.5)
		t.equal(settings.reducedMotion, false, "wrong types are ignored")
		t.equal(settings.adaptive, false)
		t.equal(Quality.merge(settings, { level = "Nope" }).level, "Ultra")
		local reduced = Quality.merge(Quality.defaults(), { reducedMotion = true })
		t.equal(Quality.juice(reduced, "shake"), 0)
		t.near(Quality.juice(reduced, "scale"), 0.5)
		t.near(Quality.juice(Quality.merge(Quality.defaults(), { level = "Low" }), "shake"), 0.6)
	end,
	["quality: counts scale with level and distance"] = function()
		local low, high = Quality.profile("Low"), Quality.profile("High")
		t.equal(Quality.scaleCount(40, high), 40)
		t.equal(Quality.scaleCount(40, low), 12)
		t.equal(Quality.scaleCount(1, low), 1, "a visible effect keeps at least one particle")
		t.equal(Quality.distanceScale(high, 10), 1)
		t.equal(Quality.distanceScale(high, 1000), 0)
		t.near(Quality.distanceScale(high, high.maxDistance), 0.25)
		t.equal(Quality.scaleCount(40, high, 1000), 0)
	end,
	["quality: adaptive steps down fast, up slowly, never above the ceiling"] = function()
		local state = Quality.adaptive("High", "High")
		local changed: string? = nil
		for _ = 1, 30 * 4 do
			changed = Quality.adapt(state, 1 / 30) or changed
		end
		t.equal(changed, "Medium")
		t.equal(state.level, "Medium")
		for _ = 1, 60 * 30 do
			Quality.adapt(state, 1 / 60)
		end
		t.equal(state.level, "High", "recovers with headroom")
		for _ = 1, 60 * 60 do
			Quality.adapt(state, 1 / 60)
		end
		t.equal(state.level, "High", "ceiling holds")
		local hitch = Quality.adaptive("High")
		Quality.adapt(hitch, 0.2)
		for _ = 1, 120 do
			Quality.adapt(hitch, 1 / 60)
		end
		t.equal(hitch.level, "High", "one hitch does not change quality")
		t.equal(Quality.adapt(hitch, 0 / 0), nil)
	end,
	["pool: reuse, reset, max idle and double release"] = function()
		local made, resets, destroyed = 0, 0, 0
		local pool = Pool.new({
			create = function(): { id: number }
				made += 1
				return { id = made }
			end,
			reset = function()
				resets += 1
			end,
			destroy = function()
				destroyed += 1
			end,
			max = 2,
		})
		local a, b, c = pool:acquire(), pool:acquire(), pool:acquire()
		pool:release(a)
		pool:release(a)
		t.equal(resets, 1, "double release is ignored")
		t.equal(pool:acquire(), a, "released item is reused")
		pool:release(a)
		pool:release(b)
		pool:release(c)
		t.equal(destroyed, 1, "items past max are destroyed")
		local stats = pool:stats()
		t.equal(stats.idle, 2)
		t.equal(stats.live, 0)
		t.equal(stats.created, 3)
		t.equal(stats.reused, 1)
		pool:release({ id = 99 })
		t.equal(pool:stats().idle, 2, "foreign items are ignored")
		pool:clear()
		t.equal(destroyed, 3)
		pool:prewarm(5)
		t.equal(pool:stats().idle, 2)
	end,
	["effects: one-shots are destroyed after their duration"] = function()
		local clock, effects = effectsHost()
		local counter = { built = 0, destroyed = 0 }
		local handle = effects:spawn(request("CoinBurst", counter))
		t.truthy(handle and handle.isAlive())
		t.equal(effects:stats().live, 1)
		t.equal(effects:stats().particles, 10)
		clock:step(0.5)
		t.equal(counter.destroyed, 0)
		clock:step(0.6)
		t.equal(counter.destroyed, 1)
		t.equal(effects:stats().live, 0)
		t.equal(effects:stats().particles, 0)
		t.equal(clock:count(), 0, "no timers left")
		t.falsy((handle :: Effects.Handle).isAlive());
		(handle :: Effects.Handle).stop()
		t.equal(counter.destroyed, 1, "stop after the end is harmless")
	end,
	["effects: looping effects live until stopped; owners and ids stop groups"] = function()
		local clock, effects = effectsHost()
		local counter = { built = 0, destroyed = 0 }
		local pet = {}
		local aura = effects:spawn(request("Aura", counter, { looping = true, owner = pet }))
		effects:spawn(request("Sparkle", counter, { looping = true, owner = pet }))
		effects:spawn(request("Sparkle", counter, { looping = true }))
		clock:step(100)
		t.equal(counter.destroyed, 0)
		t.equal(effects:stopOwner(pet), 2)
		t.falsy((aura :: Effects.Handle).isAlive())
		t.equal(effects:stopId("Sparkle"), 1)
		t.equal(counter.destroyed, 3)
		effects:spawn(request("A", counter, { looping = true }))
		effects:spawn(request("B", counter))
		t.equal(effects:stopAll(), 2)
		t.equal(clock:count(), 0, "stopping cancels the one-shot timer")
		t.equal(effects:stats().live, 0)
	end,
	["effects: budgets reject, priorities evict the oldest lower-priority effect"] = function()
		local _, effects = effectsHost("Low")
		local counter = { built = 0, destroyed = 0 }
		local max = Quality.profile("Low").maxEffects
		local first: Effects.Handle? = nil
		for index = 1, max do
			local handle = effects:spawn(request("Tap" .. index, counter, { particles = 1 }))
			first = first or handle
		end
		local refused, reason = effects:spawn(request("Extra", counter))
		t.equal(refused, nil)
		t.equal(reason, "effects")
		local vip = effects:spawn(request("Legendary", counter, { priority = 10 }))
		t.truthy(vip)
		t.falsy((first :: Effects.Handle).isAlive(), "the oldest low-priority effect was evicted")
		t.equal(effects:stats().live, max)
		t.equal(effects:stats().evicted, 1)
		t.equal(effects:stats().rejected.effects, 1)
		effects:stopAll()
		local big, why = effects:spawn(request("Huge", counter, { particles = 100000 }))
		t.equal(big, nil)
		t.equal(why, "particles")
	end,
	["effects: distance, offscreen and throttle"] = function()
		local clock, effects, state = effectsHost("High")
		local counter = { built = 0, destroyed = 0 }
		local _, far = effects:spawn(request("Far", counter, { position = { 0, 0, 9999 } }))
		t.equal(far, "distance")
		local scaleSeen = 1
		effects:spawn({
			id = "Mid",
			particles = 100,
			duration = 1,
			position = { 0, 0, Quality.profile("High").maxDistance },
			build = function(scale: number): (() -> ())?
				scaleSeen = scale
				return nil
			end,
		})
		t.near(scaleSeen, 0.25)
		t.equal(effects:stats().particles, 25)
		state.visible = false
		local _, hidden = effects:spawn(request("Hidden", counter, { position = { 0, 0, 5 } }))
		t.equal(hidden, "offscreen")
		t.truthy(
			effects:spawn(request("HiddenLoop", counter, { position = { 0, 0, 5 }, looping = true })),
			"loops still attach offscreen"
		)
		state.visible = true
		t.truthy(effects:spawn(request("Tap", counter, { minInterval = 0.1 })))
		local _, throttled = effects:spawn(request("Tap", counter, { minInterval = 0.1 }))
		t.equal(throttled, "throttled")
		clock:step(0.11)
		t.truthy(effects:spawn(request("Tap", counter, { minInterval = 0.1 })))
		effects:resetStats()
		t.equal(next(effects:stats().rejected), nil)
	end,
	["effects: a failing build is reported and leaves no state behind"] = function()
		local clock, effects = effectsHost()
		local errors = 0
		clock.onError = function()
			errors += 1
		end
		local handle, reason = effects:spawn({
			id = "Broken",
			build = function(): (() -> ())?
				error("no texture")
			end,
		})
		t.equal(handle, nil)
		t.equal(reason, "error")
		t.equal(errors, 1)
		t.equal(effects:stats().live, 0)
		t.equal(clock:count(), 0)
	end,
}
