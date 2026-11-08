--!strict
local ColorContrast = require("../src/shared/Logic/ColorContrast")
local t = require("./lib/t")

local BLACK = { r = 0, g = 0, b = 0 }
local WHITE = { r = 1, g = 1, b = 1 }
local MID_GREY = { r = 0.47, g = 0.47, b = 0.47 }

return {
	["luminance of black and white"] = function()
		t.equal(ColorContrast.luminance(BLACK), 0)
		t.near(ColorContrast.luminance(WHITE), 1)
	end,

	["ratio runs from 1 to 21 and ignores order"] = function()
		t.near(ColorContrast.ratio(BLACK, WHITE), 21)
		t.near(ColorContrast.ratio(WHITE, BLACK), 21)
		t.near(ColorContrast.ratio(MID_GREY, MID_GREY), 1)
	end,

	["meets uses the right thresholds"] = function()
		t.truthy(ColorContrast.meets(BLACK, WHITE))
		t.truthy(ColorContrast.meets(BLACK, WHITE, false, true))
		-- Mid grey on white is about 4.4:1, which passes for large text only.
		t.falsy(ColorContrast.meets(MID_GREY, WHITE))
		t.truthy(ColorContrast.meets(MID_GREY, WHITE, true))
	end,

	["best picks the most readable candidate"] = function()
		local dark = { r = 0.05, g = 0.05, b = 0.08 }
		local picked = ColorContrast.best({ r = 1, g = 0.77, b = 0 }, { WHITE, dark })
		t.equal(picked, dark)
		t.throws(function()
			ColorContrast.best(WHITE, {})
		end)
	end,
}
