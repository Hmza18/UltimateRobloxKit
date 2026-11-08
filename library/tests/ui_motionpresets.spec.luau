--!strict
-- Motion presets: the contract's 20 presets, key ordering, sampling, looping and helpers.

local t = require("./lib/t")
local Easing = require("../src/UI/Core/Easing")
local MotionPresets = require("../src/UI/Core/MotionPresets")

local CONTRACT = {
	"hover",
	"unhover",
	"press",
	"release",
	"open",
	"close",
	"popIn",
	"bounce",
	"count",
	"reveal",
	"acquire",
	"purchase",
	"select",
	"tabSwitch",
	"toastIn",
	"toastOut",
	"progress",
	"attention",
	"wiggle",
	"shine",
}

local function read(key: any, property: string): number?
	return key[property]
end

-- The value a property ends on: the last key that sets it, else its rest value.
local function lastValue(preset: any, property: string): number
	local value = if property == "scale" then 1 else 0
	for _, key in preset.keys do
		local v = read(key, property)
		if v ~= nil then
			value = v
		end
	end
	return value
end

return {
	["all 20 contract presets exist"] = function()
		for _, name in CONTRACT do
			t.truthy(MotionPresets.has(name), name)
			t.truthy(MotionPresets.get(name), name)
		end
		t.equal(#MotionPresets.names(), #CONTRACT, "no extra presets")
	end,

	["names are sorted and unique"] = function()
		local names = MotionPresets.names()
		for index = 2, #names do
			t.truthy(names[index - 1] < names[index], names[index])
		end
	end,

	["every preset passes validation"] = function()
		for _, name in MotionPresets.names() do
			local problems = MotionPresets.validate(MotionPresets.get(name))
			t.equal(#problems, 0, name .. ": " .. table.concat(problems, "; "))
		end
	end,

	["keys are sorted from 0 to 1"] = function()
		for _, name in MotionPresets.names() do
			local keys = MotionPresets.get(name).keys
			t.equal(keys[1].t, 0, name .. " first key")
			t.equal(keys[#keys].t, 1, name .. " last key")
			for index = 2, #keys do
				t.truthy(keys[index].t > keys[index - 1].t, name .. " key " .. index)
			end
		end
	end,

	["every preset uses a known easing and a positive duration"] = function()
		for _, name in MotionPresets.names() do
			local preset = MotionPresets.get(name)
			t.truthy(Easing.has(preset.easing), name .. " easing " .. preset.easing)
			t.truthy(preset.duration > 0, name .. " duration")
		end
	end,

	["sample at 0 equals the first key"] = function()
		for _, name in MotionPresets.names() do
			local preset = MotionPresets.get(name)
			local first = preset.keys[1]
			local sample = MotionPresets.sample(preset, 0) :: any
			for _, property in MotionPresets.PROPERTIES do
				local expected = read(first, property)
				if expected ~= nil then
					t.near(sample[property], expected, 1e-9, name .. "." .. property)
				end
			end
		end
	end,

	["sample at 1 equals the last value of each property"] = function()
		for _, name in MotionPresets.names() do
			local preset = MotionPresets.get(name)
			local sample = MotionPresets.sample(preset, 1) :: any
			for _, property in MotionPresets.PROPERTIES do
				t.near(sample[property], lastValue(preset, property), 1e-9, name .. "." .. property)
			end
			t.deepEqual(MotionPresets.final(name), sample, name .. " final")
		end
	end,

	["one-shot presets clamp t outside 0..1"] = function()
		t.near(MotionPresets.sample("hover", 2).scale, 1.06, 1e-9)
		t.near(MotionPresets.sample("hover", -1).scale, 1, 1e-9)
		t.near(MotionPresets.sample("bounce", 5).offsetY, 0, 1e-9)
	end,

	["looping presets wrap time past 1"] = function()
		for _, name in { "attention", "wiggle", "shine" } do
			local preset = MotionPresets.get(name)
			t.truthy(preset.loop, name .. " loops")
			local a = MotionPresets.sample(preset, 0.3) :: any
			local b = MotionPresets.sample(preset, 2.3) :: any
			for _, property in MotionPresets.PROPERTIES do
				t.near(b[property], a[property], 1e-6, name .. "." .. property)
			end
		end
	end,

	["only attention, wiggle and shine loop"] = function()
		for _, name in MotionPresets.names() do
			local loops = MotionPresets.get(name).loop == true
			local expected = name == "attention" or name == "wiggle" or name == "shine"
			t.equal(loops, expected, name)
		end
	end,

	["in-between values follow the easing curve"] = function()
		local expected = 1 + 0.06 * Easing.ease("quadOut", 0.5)
		t.near(MotionPresets.sample("hover", 0.5).scale, expected, 1e-9)
		t.near(MotionPresets.sample("attention", 0.5).scale, 1.15, 1e-9, "attention peak")
	end,

	["properties interpolate between the keys that set them"] = function()
		-- open: scale is set at t = 0 and t = 1 only, transparency at 0, 0.5 and 1.
		local sample = MotionPresets.sample("open", 0.25)
		t.near(sample.scale, 0.6 + 0.4 * Easing.ease("backOut", 0.25), 1e-9, "scale skips the middle key")
		local transparency = math.clamp(1 - Easing.ease("backOut", 0.5), 0, 1)
		t.near(sample.transparency, transparency, 1e-9, "transparency uses the middle key")
	end,

	["properties no key sets stay at rest"] = function()
		local sample = MotionPresets.sample("hover", 0.5)
		t.equal(sample.rotation, 0)
		t.equal(sample.offsetY, 0)
		t.equal(sample.transparency, 0)
		t.equal(MotionPresets.sample("wiggle", 0.15).scale, 1)
	end,

	["samples stay in range"] = function()
		for _, name in MotionPresets.names() do
			for step = 0, 40 do
				local sample = MotionPresets.sample(name, step / 40)
				t.truthy(sample.scale >= 0, name .. " scale")
				t.truthy(sample.transparency >= 0 and sample.transparency <= 1, name .. " transparency")
			end
		end
	end,

	["unknown presets raise an error"] = function()
		t.falsy(MotionPresets.has("nope"))
		t.throws(function()
			MotionPresets.get("nope")
		end)
		t.throws(function()
			MotionPresets.sample("nope", 0.5)
		end)
	end,

	["presets are frozen"] = function()
		local preset = MotionPresets.get("hover")
		t.truthy(table.isfrozen(preset))
		t.truthy(table.isfrozen(preset.keys))
		t.truthy(table.isfrozen(preset.keys[1]))
		local mutable: any = preset
		t.throws(function()
			mutable.duration = 5
		end)
	end,

	["from starts at the current values and leaves the preset alone"] = function()
		local current = { scale = 0.92, rotation = 0, offsetY = 0, transparency = 0 }
		local blended = MotionPresets.from(MotionPresets.get("hover"), current)
		t.near(MotionPresets.sample(blended, 0).scale, 0.92, 1e-9)
		t.near(MotionPresets.sample(blended, 1).scale, 1.06, 1e-9)
		t.equal(MotionPresets.get("hover").keys[1].scale, 1, "original unchanged")
		t.equal(blended.keys[1].rotation, nil, "unused properties are not added")
	end,

	["from inserts a start key when the first key is late"] = function()
		local custom = { duration = 1, easing = "linear", keys = { { t = 0.5, scale = 2 }, { t = 1, scale = 3 } } }
		local current = { scale = 1.5, rotation = 0, offsetY = 0, transparency = 0 }
		local blended = MotionPresets.from(custom, current)
		t.equal(#blended.keys, 3)
		t.equal(blended.keys[1].t, 0)
		t.near(MotionPresets.sample(blended, 0.25).scale, 1.75, 1e-9)
	end,

	["validate reports broken presets"] = function()
		local broken = {
			duration = -1,
			easing = "wobble",
			keys = { { t = 0.2, scale = 1 }, { t = 0.1, scale = 2 }, { t = 0.9, scale = 1 } },
		}
		local problems = MotionPresets.validate(broken)
		t.truthy(#problems >= 5, "found " .. #problems .. " problems")
		t.equal(#MotionPresets.validate({ duration = 1, easing = "linear", keys = { { t = 0 } } }), 1, "one key")
	end,

	["durations and reduced motion"] = function()
		t.near(MotionPresets.duration("open"), MotionPresets.get("open").duration, 1e-9)
		t.equal(MotionPresets.duration("open", true), 0)
		t.truthy(MotionPresets.uses(MotionPresets.get("wiggle"), "rotation"))
		t.falsy(MotionPresets.uses(MotionPresets.get("wiggle"), "scale"))
		t.truthy(MotionPresets.uses(MotionPresets.get("shine"), "offsetY"))
	end,
}
