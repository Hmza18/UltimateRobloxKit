--!strict
-- Theme tokens, resolution, inheritance, state variants and WCAG contrast.

local t = require("./lib/t")
local Contrast = require("../src/UI/Core/Contrast")
local Theme = require("../src/UI/Core/Theme")
local Tokens = require("../src/UI/Core/Tokens")

local WHITE = { r = 1, g = 1, b = 1 }
local BLACK = { r = 0, g = 0, b = 0 }

return {
	["contrast ratio matches WCAG reference values"] = function()
		t.near(Contrast.ratio(BLACK, WHITE), 21, 1e-9)
		t.near(Contrast.ratio(WHITE, WHITE), 1, 1e-9)
		-- #777777 on white is the classic 4.48:1 example that just fails AA.
		local grey = Theme.hexToRgb("#777777") :: Contrast.RGB
		t.near(Contrast.ratio(grey, WHITE), 4.48, 0.01)
		t.falsy(Contrast.meets(grey, WHITE))
		t.truthy(Contrast.meets(grey, WHITE, "AA", true), "passes for large text")
	end,

	["contrast best and adjust"] = function()
		local navy = Theme.hexToRgb("#1A1F33") :: Contrast.RGB
		t.truthy(Contrast.best(navy, { BLACK, WHITE }) == WHITE)
		local muted = Theme.hexToRgb("#3A3F55") :: Contrast.RGB
		local adjusted, ok = Contrast.adjust(muted, navy, 4.5)
		t.truthy(ok)
		t.truthy(Contrast.ratio(adjusted, navy) >= 4.5)
	end,

	["hexToRgb parses long and short forms and rejects junk"] = function()
		local color = Theme.hexToRgb("#FF8000") :: Contrast.RGB
		t.near(color.r, 1)
		t.near(color.g, 128 / 255)
		t.near(color.b, 0)
		local short = Theme.hexToRgb("0F0") :: Contrast.RGB
		t.near(short.g, 1)
		t.equal(Theme.hexToRgb("#GG0000"), nil)
		t.equal(Theme.hexToRgb("#12345"), nil)
		t.equal(Theme.rgbToHex({ r = 1, g = 0.5, b = 0 }), "#FF8000")
	end,

	["every built-in theme defines every role"] = function()
		for name in Tokens.themes do
			local resolved = Theme.resolve(Tokens.themes, name)
			for _, role in Tokens.ROLES do
				t.truthy(resolved.colors[role] ~= nil, name .. " is missing " .. role)
			end
		end
	end,

	["built-in themes pass their promised contrast level"] = function()
		for name, level in Tokens.levels do
			local problems = Theme.validate(Theme.resolve(Tokens.themes, name), level)
			local details: { string } = {}
			for _, problem in problems do
				table.insert(details, problem.detail)
			end
			t.equal(#problems, 0, name .. ": " .. table.concat(details, "; "))
		end
	end,

	["validate reports low contrast"] = function()
		local themes = Theme.merge(Tokens.themes, {
			bad = { name = "bad", extends = "dark", colors = { text = "#20263D" } },
		})
		local problems = Theme.validate(Theme.resolve(themes, "bad"), "AA")
		t.truthy(#problems > 0)
		t.equal(problems[1].kind, "contrast")
	end,

	["themes inherit through extends"] = function()
		local themes = Theme.merge(Tokens.themes, {
			brand = { name = "brand", extends = "dark", colors = { primary = "#8E24AA" } },
		})
		local brand = Theme.resolve(themes, "brand")
		local dark = Theme.resolve(themes, "dark")
		t.equal(Theme.rgbToHex(brand.colors.primary), "#8E24AA")
		t.equal(Theme.rgbToHex(brand.colors.surface), Theme.rgbToHex(dark.colors.surface))
		t.equal(Theme.transparency(brand, "overlay"), Theme.transparency(dark, "overlay"))
	end,

	["resolve rejects cycles, unknown parents and bad colours"] = function()
		local cyclic = {
			a = { name = "a", extends = "b", colors = {} },
			b = { name = "b", extends = "a", colors = {} },
		}
		t.throws(function()
			Theme.resolve(cyclic, "a")
		end)
		t.throws(function()
			Theme.resolve({ a = { name = "a", extends = "missing", colors = {} } }, "a")
		end)
		t.throws(function()
			Theme.resolve({ a = { name = "a", colors = { text = "pink" } } }, "a")
		end)
	end,

	["color lookups support states and fallbacks"] = function()
		local dark = Theme.resolve(Tokens.themes, "dark")
		local primary = Theme.color(dark, "primary") :: Contrast.RGB
		local hover = Theme.color(dark, "primary:hover") :: Contrast.RGB
		t.truthy(Contrast.luminance(hover) > Contrast.luminance(primary), "dark colours lighten on hover")
		local light = Theme.resolve(Tokens.themes, "light")
		local surface = Theme.color(light, "surface") :: Contrast.RGB
		local pressed = Theme.color(light, "surface:pressed") :: Contrast.RGB
		t.truthy(Contrast.luminance(pressed) < Contrast.luminance(surface), "light colours darken when pressed")
		local unknown = Theme.color(dark, "nope", "danger") :: Contrast.RGB
		t.equal(Theme.rgbToHex(unknown), Theme.rgbToHex(dark.colors.danger))
	end,

	["nextName cycles theme order"] = function()
		local order = { "dark", "light", "highContrast" }
		t.equal(Theme.nextName(order, "dark"), "light")
		t.equal(Theme.nextName(order, "highContrast"), "dark")
		t.equal(Theme.nextName(order, "unknown"), "dark")
	end,
}
