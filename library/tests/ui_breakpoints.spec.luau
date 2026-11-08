--!strict
-- Breakpoints (classification, UIScale, per-breakpoint attributes) and Layout (rails, popups).

local t = require("./lib/t")
local Breakpoints = require("../src/UI/Core/Breakpoints")
local Layout = require("../src/UI/Core/Layout")

local SCREEN = { x = 0, y = 0, w = 1000, h = 800 }

return {
	["classify phones and tablets by short side"] = function()
		t.equal(Breakpoints.classify({ x = 844, y = 390 }, { touch = true }), "phone")
		t.equal(Breakpoints.classify({ x = 390, y = 844 }, { touch = true }), "phone", "portrait")
		t.equal(Breakpoints.classify({ x = 1180, y = 820 }, { touch = true }), "tablet")
		t.equal(Breakpoints.classify({ x = 1366, y = 1024 }, { touch = true }), "desktop", "very large touch screen")
	end,

	["classify desktop, console and small windows"] = function()
		t.equal(Breakpoints.classify({ x = 1920, y = 1080 }, { keyboard = true }), "desktop")
		t.equal(Breakpoints.classify({ x = 1920, y = 1080 }, { tenFoot = true }), "console")
		t.equal(Breakpoints.classify({ x = 1920, y = 1080 }, { gamepad = true }), "console", "gamepad only")
		t.equal(Breakpoints.classify({ x = 1920, y = 1080 }, { gamepad = true, keyboard = true }), "desktop")
		t.equal(Breakpoints.classify({ x = 800, y = 600 }, { keyboard = true }), "tablet", "narrow window")
		t.equal(Breakpoints.classify({ x = 0, y = 0 }), "desktop", "viewport not ready yet")
	end,

	["classify honours custom thresholds"] = function()
		local thresholds = { phoneShortSide = 700, tabletShortSide = 1000, desktopMinWidth = 1200 }
		t.equal(Breakpoints.classify({ x = 1180, y = 600 }, { touch = true }, thresholds), "phone")
	end,

	["scale fits the reference resolution and clamps"] = function()
		t.near(Breakpoints.scale({ x = 1920, y = 1080 }, "desktop"), 1)
		t.near(Breakpoints.scale({ x = 960, y = 540 }, "desktop"), 0.6, 1e-9, "clamped to min")
		t.near(Breakpoints.scale({ x = 3840, y = 2160 }, "desktop"), 1.5, 1e-9, "clamped to max")
		t.near(Breakpoints.scale({ x = 1920, y = 1080 }, "desktop", { userScale = 1.2 }), 1.2)
		t.near(Breakpoints.scale({ x = 844, y = 390 }, "phone"), 1)
		t.near(Breakpoints.scale({ x = 0, y = 0 }, "desktop"), 1, 1e-9, "empty viewport")
	end,

	["pick uses breakpoint overrides with console falling back to desktop"] = function()
		local attributes = { Phone_Size = "phone", Desktop_Size = "desktop" }
		local value, name = Breakpoints.pick(attributes, "Size", "phone", "base")
		t.equal(value, "phone")
		t.equal(name, "Phone_Size")
		t.equal(Breakpoints.pick(attributes, "Size", "console", "base"), "desktop")
		local tabletValue, tabletName = Breakpoints.pick(attributes, "Size", "tablet", "base")
		t.equal(tabletValue, "base")
		t.equal(tabletName, nil)
		t.equal(Breakpoints.attributeName("Size", "phone"), "Phone_Size")
	end,

	["properties lists responsive properties once"] = function()
		local attributes = { Phone_Size = 1, Desktop_Size = 2, Tablet_Visible = true, Other_Thing = 1 }
		t.deepEqual(Breakpoints.properties(attributes), { "Size", "Visible" })
	end,

	["safeRect removes insets and padding"] = function()
		local rect = Layout.safeRect({ x = 1000, y = 800 }, { top = 36, left = 0, right = 0, bottom = 20 }, 8)
		t.deepEqual(rect, { x = 8, y = 44, w = 984, h = 728 })
	end,

	["rail positions anchor children inside the area"] = function()
		local bottom = Layout.railPosition("bottomCenter", SCREEN, { x = 200, y = 50 })
		t.deepEqual(bottom, { x = 400, y = 750 })
		local topRight = Layout.railPosition("topRight", SCREEN, { x = 100, y = 40 })
		t.deepEqual(topRight, { x = 900, y = 0 })
		t.equal(Layout.rail("nowhere"), nil)
		t.equal(#Layout.RAIL_NAMES, 9)
		for _, name in Layout.RAIL_NAMES do
			t.truthy(Layout.rail(name) ~= nil, name)
		end
	end,

	["place prefers below, flips above near the bottom edge"] = function()
		local size = { x = 80, y = 30 }
		local position, side = Layout.place({ x = 100, y = 100, w = 50, h = 20 }, size, SCREEN)
		t.equal(side, "below")
		t.deepEqual(position, { x = 85, y = 128 })
		local flipped, flippedSide = Layout.place({ x = 100, y = 780, w = 50, h = 20 }, size, SCREEN)
		t.equal(flippedSide, "above")
		t.equal(flipped.y, 742)
	end,

	["place moves sideways near the right edge and clamps when nothing fits"] = function()
		local position, side = Layout.place({ x = 990, y = 100, w = 10, h = 10 }, { x = 80, y = 30 }, SCREEN)
		t.equal(side, "left")
		t.equal(position.x, 902)
		local huge, hugeSide = Layout.place({ x = 10, y = 10, w = 10, h = 10 }, { x = 2000, y = 30 }, SCREEN)
		t.equal(hugeSide, "below")
		t.equal(huge.x, 4, "clamped to the margin")
	end,

	["clamp and gridCell"] = function()
		t.deepEqual(Layout.clamp({ x = -10, y = 900 }, { x = 50, y = 50 }, SCREEN, 4), { x = 4, y = 746 })
		t.deepEqual(Layout.gridCell(420, 4, 4), { x = 102, y = 102 })
		t.deepEqual(Layout.gridCell(100, 0, 0, 1.5), { x = 100, y = 150 }, "at least one column")
	end,
}
