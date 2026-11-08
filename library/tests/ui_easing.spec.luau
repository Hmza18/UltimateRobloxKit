--!strict
-- Easing curves, springs, count-up maths and decorative effect values.

local t = require("./lib/t")
local Decor = require("../src/UI/Core/Decor")
local Easing = require("../src/UI/Core/Easing")

return {
	["every curve starts at 0 and ends at 1"] = function()
		for _, name in Easing.NAMES do
			t.near(Easing.ease(name, 0), 0, 1e-9, name .. " at 0")
			t.near(Easing.ease(name, 1), 1, 1e-9, name .. " at 1")
		end
	end,

	["curves have the expected shape"] = function()
		t.near(Easing.ease("linear", 0.25), 0.25)
		t.near(Easing.ease("quadIn", 0.5), 0.25)
		t.near(Easing.ease("quadOut", 0.5), 0.75)
		t.near(Easing.ease("sineInOut", 0.5), 0.5, 1e-9)
		t.truthy(Easing.ease("backOut", 0.6) > 1, "backOut overshoots")
		t.near(Easing.ease("bounceOut", 0.5), 0.765625, 1e-9)
	end,

	["unknown curves fall back to linear and t is clamped"] = function()
		t.near(Easing.ease("doesNotExist", 0.3), 0.3)
		t.near(Easing.ease("quadIn", 2), 1)
		t.near(Easing.ease("quadIn", -1), 0)
		t.falsy(Easing.has("doesNotExist"))
	end,

	["progress and reduced-motion durations"] = function()
		t.near(Easing.progress(10, 2, 11), 0.5)
		t.near(Easing.progress(10, 2, 20), 1)
		t.near(Easing.progress(10, 0, 10), 1, 1e-9, "zero duration completes")
		t.equal(Easing.duration(0.3, true), 0)
		t.equal(Easing.duration(0.3, false), 0.3)
	end,

	["countUp stays on whole numbers and lands exactly"] = function()
		for step = 0, 10 do
			local value = Easing.countUp(0, 1000, step / 10)
			t.equal(value % 1, 0, "whole number at step " .. step)
			t.truthy(value >= 0 and value <= 1000)
		end
		t.equal(Easing.countUp(0, 1000, 1), 1000)
		t.equal(Easing.countUp(500, 100, 1), 100, "counts down too")
		t.near(Easing.countUp(0, 1.5, 1, "linear"), 1.5)
		t.equal(Easing.countUpDuration(0), 0)
		t.truthy(Easing.countUpDuration(1e9) <= 1.2)
		t.truthy(Easing.countUpDuration(10) < Easing.countUpDuration(10000))
	end,

	["critically damped spring settles without overshoot"] = function()
		local state = { position = 0, velocity = 0 }
		local peak = 0
		for _ = 1, 120 do
			state = Easing.springStep(state, 1, 1 / 60, { frequency = 3, damping = 1 })
			peak = math.max(peak, state.position)
		end
		t.truthy(Easing.springSettled(state, 1, 1e-2), "settles within two seconds")
		t.truthy(peak <= 1 + 1e-6, "no overshoot")
	end,

	["underdamped spring overshoots and is frame-rate independent"] = function()
		local options = { frequency = 3, damping = 0.3 }
		local peak = 0
		local state = { position = 0, velocity = 0 }
		for _ = 1, 60 do
			state = Easing.springStep(state, 1, 1 / 60, options)
			peak = math.max(peak, state.position)
		end
		t.truthy(peak > 1.1, "overshoots")
		local coarse = Easing.springStep({ position = 0, velocity = 0 }, 1, 0.5, options)
		local fine = { position = 0, velocity = 0 }
		for _ = 1, 30 do
			fine = Easing.springStep(fine, 1, 0.5 / 30, options)
		end
		t.near(coarse.position, fine.position, 1e-3, "one big step equals many small ones")
		local still = Easing.springStep({ position = 0.4, velocity = 0 }, 1, 0)
		t.equal(still.position, 0.4, "dt = 0 changes nothing")
	end,

	["decorative effects and reduced motion"] = function()
		t.near(Decor.spin(1, { speed = 90 }), 90)
		t.near(Decor.spin(5, { speed = 90 }), 90, 1e-9, "wraps at 360")
		t.near(Decor.bob(0, nil), 0)
		t.near(Decor.bob(0.3125, { speed = 0.8, amplitude = 4 }), 4, 1e-9, "peak at a quarter cycle")
		t.near(Decor.pulse(0, { amplitude = 0.1 }), 1.05)
		t.equal(Decor.spin(3, nil, true), 0)
		t.equal(Decor.bob(3, nil, true), 0)
		t.equal(Decor.pulse(3, nil, true), 1)
		t.equal(Decor.shine(0.2, nil, true), -1)
		t.truthy(Decor.isEffect("Spin"))
		t.falsy(Decor.isEffect("Explode"))
	end,

	["shine sweeps then rests"] = function()
		local params = { speed = 1, pause = 1 }
		t.near(Decor.shine(0, params), -1)
		t.near(Decor.shine(0.5, params), 0)
		t.near(Decor.shine(1.5, params), -1, 1e-9, "resting")
		t.near(Decor.shine(2.5, params), 0, 1e-9, "next sweep")
	end,

	["hsvToRgb primary colours"] = function()
		t.deepEqual(Decor.hsvToRgb(0, 1, 1), { r = 1, g = 0, b = 0 })
		local green = Decor.hsvToRgb(1 / 3, 1, 1)
		t.near(green.g, 1)
		t.near(green.r, 0, 1e-9)
		local blue = Decor.hsvToRgb(2 / 3, 1, 1)
		t.near(blue.b, 1)
		t.near(blue.g, 0, 1e-9)
		t.deepEqual(Decor.hsvToRgb(0.5, 0, 0.5), { r = 0.5, g = 0.5, b = 0.5 })
	end,
}
