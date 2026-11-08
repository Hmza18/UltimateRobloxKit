--!strict
-- TextFit: size bounds, the minimum floor, long text, wrapping, truncation and ellipsis.

local t = require("./lib/t")
local TextFit = require("../src/UI/Core/TextFit")

return {
	["bounds apply the floor and keep max above min"] = function()
		local low, high = TextFit.bounds(8, 30, 12)
		t.equal(low, 12, "min raised to the floor")
		t.equal(high, 30)
		low, high = TextFit.bounds()
		t.equal(low, TextFit.DEFAULT_FLOOR)
		t.equal(high, TextFit.DEFAULT_MAX)
		low, high = TextFit.bounds(20, 10, 12)
		t.equal(low, 20)
		t.equal(high, 20, "max below min becomes min")
	end,

	["short text gets the maximum size"] = function()
		local result = TextFit.fit({ width = 200, height = 50, text = "SHOP", max = 40 })
		t.equal(result.size, 40)
		t.equal(result.lines, 1)
		t.falsy(result.truncate)
	end,

	["box height limits a single line"] = function()
		local result = TextFit.fit({ width = 1000, height = 20, text = "hi", max = 40 })
		t.equal(result.size, 20)
	end,

	["long text shrinks to fit the width"] = function()
		local result = TextFit.fit({ width = 300, height = 40, text = string.rep("a", 30), max = 32, floor = 12 })
		t.equal(result.size, 17)
		t.falsy(result.truncate)
	end,

	["size never goes below the floor"] = function()
		local result = TextFit.fit({ width = 100, height = 20, text = string.rep("a", 200), min = 6, floor = 12 })
		t.equal(result.size, 12, "min 6 is raised to the floor 12")
		t.truthy(result.truncate, "does not fit even at the floor")
		t.equal(result.maxChars, 14, "characters that fit at 12")
	end,

	["max below the floor is raised to the floor"] = function()
		local result = TextFit.fit({ width = 500, height = 100, text = "a", max = 8, floor = 12 })
		t.equal(result.size, 12)
		t.falsy(result.truncate)
	end,

	["wrapping uses several lines"] = function()
		local text = string.rep("word ", 8)
		local wrapped = TextFit.fit({ width = 200, height = 100, text = text, max = 32, wrap = true })
		t.equal(wrapped.size, 22)
		t.equal(wrapped.lines, 4)
		t.falsy(wrapped.truncate)
		local single = TextFit.fit({ width = 200, height = 100, text = text, max = 32 })
		t.equal(single.size, 12)
		t.truthy(single.truncate, "one line cannot hold it")
	end,

	["empty text fits at the maximum"] = function()
		local result = TextFit.fit({ width = 10, height = 10, text = "", max = 40 })
		t.equal(result.size, 40)
		t.falsy(result.truncate)
	end,

	["a zero-sized box truncates at the floor"] = function()
		local result = TextFit.fit({ width = 0, height = 0, text = "abc" })
		t.equal(result.size, 12)
		t.truthy(result.truncate)
		t.equal(result.maxChars, 0)
	end,

	["padding reduces the room"] = function()
		local plain = TextFit.fit({ width = 100, height = 40, text = "ABCDE", max = 40 })
		local padded = TextFit.fit({ width = 100, height = 40, text = "ABCDE", max = 40, padding = 10 })
		t.equal(plain.size, 29)
		t.equal(padded.size, 20)
	end,

	["capitals use the wider metric"] = function()
		local caps = TextFit.fit({ width = 100, height = 50, text = string.rep("A", 10), max = 40 })
		local lower = TextFit.fit({ width = 100, height = 50, text = string.rep("a", 10), max = 40 })
		t.equal(caps.size, 14)
		t.equal(lower.size, 17)
		t.truthy(TextFit.isCaps("SHOP"))
		t.truthy(TextFit.isCaps("R$ 599"))
		t.falsy(TextFit.isCaps("Shop"))
		t.falsy(TextFit.isCaps("123"), "no letters")
	end,

	["length works without the text"] = function()
		local result = TextFit.fit({ width = 100, height = 30, length = 10, max = 30 })
		t.equal(result.size, 17)
	end,

	["custom metrics change the result"] = function()
		local narrow = TextFit.fit({ width = 100, height = 50, text = string.rep("a", 10), max = 40, charWidth = 0.4 })
		t.equal(narrow.size, 25)
	end,

	["sizes are whole numbers within the bounds"] = function()
		for length = 0, 60, 5 do
			local result = TextFit.fit({ width = 180, height = 36, length = length, min = 14, max = 30 })
			t.truthy(result.size >= 14 and result.size <= 30, "length " .. length)
			t.equal(result.size % 1, 0, "whole size")
		end
	end,

	["length counts UTF-8 characters"] = function()
		t.equal(TextFit.length("h\u{E9}llo"), 5)
		t.equal(TextFit.length(""), 0)
	end,

	["ellipsize cuts long text"] = function()
		t.equal(TextFit.ellipsize("Hello world", 8), "Hello...")
		t.equal(TextFit.ellipsize("Hi", 8), "Hi", "short text is unchanged")
		t.equal(TextFit.ellipsize("Hello", 3), "...")
		t.equal(TextFit.ellipsize("Hello", 0), "")
		t.equal(TextFit.ellipsize(string.rep("\u{E9}", 5), 4), "\u{E9}...", "never splits a character")
	end,
}
