--!strict
-- Format: numbers, abbreviations, percentages, clock times, durations and the formatter registry.

local t = require("./lib/t")
local Format = require("../src/UI/Core/Format")

return {
	["number groups thousands"] = function()
		t.equal(Format.number(1234567), "1,234,567")
		t.equal(Format.number(1234567.891, 2), "1,234,567.89")
		t.equal(Format.number(999), "999")
		t.equal(Format.number(-1500), "-1,500")
		t.equal(Format.number(-0.001), "0", "no negative zero")
		t.equal(Format.number(1000, 0, " "), "1 000", "custom separator")
	end,

	["number rejects NaN and infinity"] = function()
		t.equal(Format.number(0 / 0), "--")
		t.equal(Format.number(math.huge), "--")
		t.equal(Format.abbrev(-math.huge), "--")
	end,

	["abbrev uses suffixes and rounds down by default"] = function()
		t.equal(Format.abbrev(999), "999")
		t.equal(Format.abbrev(1500), "1.5K")
		t.equal(Format.abbrev(1999), "1.9K", "never shows more than the player has")
		t.equal(Format.abbrev(1000000), "1M")
		t.equal(Format.abbrev(1234567, 2), "1.23M")
		t.equal(Format.abbrev(1e15), "1Qa")
		t.equal(Format.abbrev(12.5), "12.5")
		t.equal(Format.abbrev(0), "0")
		t.equal(Format.abbrev(-2500), "-2.5K")
	end,

	["abbrev rounding carries into the next suffix"] = function()
		t.equal(Format.abbrev(1999, 1, true), "2K")
		t.equal(Format.abbrev(999999, 1, true), "1M")
		t.equal(Format.abbrev(999999), "999.9K")
	end,

	["percent from ratios and raw percentages"] = function()
		t.equal(Format.percent(0.256), "26%")
		t.equal(Format.percent(0.125, 1), "12.5%")
		t.equal(Format.percent(50, 0, false), "50%")
		t.equal(Format.percent(1), "100%")
	end,

	["time formats clocks"] = function()
		t.equal(Format.time(65), "1:05")
		t.equal(Format.time(3723), "1:02:03")
		t.equal(Format.time(-5), "0:00")
		t.equal(Format.time(59.9), "0:59", "rounds down")
	end,

	["duration shows the two largest units"] = function()
		t.equal(Format.duration(93784), "1d 2h")
		t.equal(Format.duration(125), "2m 5s")
		t.equal(Format.duration(45), "45s")
		t.equal(Format.duration(3600), "1h")
		t.equal(Format.duration(0), "0s")
	end,

	["apply parses specs and falls back safely"] = function()
		t.equal(Format.apply("abbrev:2", 1234567), "1.23M")
		t.equal(Format.apply("number", 2500), "2,500")
		t.equal(Format.apply(nil, 5), "5")
		t.equal(Format.apply("", nil), "")
		t.equal(Format.apply("unknown", 5), "5")
		t.equal(Format.apply("abbrev", "hi"), "hi", "non-numbers pass through")
		t.equal(Format.apply("upper", "gold"), "GOLD")
	end,

	["parseSpec splits name and argument"] = function()
		local name, argument = Format.parseSpec("abbrev:2")
		t.equal(name, "abbrev")
		t.equal(argument, "2")
		local plain, none = Format.parseSpec("time")
		t.equal(plain, "time")
		t.equal(none, nil)
	end,

	["custom formatters register, fail safely and unregister"] = function()
		local unregister = Format.register("coins", function(value: any): string
			return tostring(value) .. " coins"
		end)
		t.truthy(Format.has("coins"))
		t.equal(Format.apply("coins", 3), "3 coins")
		unregister()
		t.equal(Format.apply("coins", 3), "3")
		local removeBad = Format.register("broken", function(): string
			error("formatter bug")
		end)
		t.equal(Format.apply("broken", 7), "7", "an erroring formatter falls back to tostring")
		removeBad()
		t.throws(function()
			Format.register("not valid!", function(): string
				return ""
			end)
		end)
	end,
}
