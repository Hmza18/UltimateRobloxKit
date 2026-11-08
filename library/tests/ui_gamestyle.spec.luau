--!strict
-- Game styles (Style/Style.luau over the generated StyleTokens): lookup, fallbacks, colour maths,
-- outline weights, rarity and the keys every style must define.

local t = require("./lib/t")
local Style = require("../src/UI/Style/Style")

local HEX = "^#%x%x%x%x%x%x$"
local PALETTES = { "red", "orange", "yellow", "green", "teal", "blue", "purple", "pink", "gold", "gray" }
local BUTTONS = { "buy", "robux", "gift", "close", "primary", "danger", "neutral", "price" }
local BADGES = { "sale", "bonus", "attention", "new", "best" }
local RARITIES = { "common", "uncommon", "rare", "epic", "legendary", "mythic", "secret" }
local TEXT_ROLES = { "display", "title", "heading", "label", "caption", "price" }

local function isHex(value: any): boolean
	return type(value) == "string" and string.find(value, HEX) ~= nil
end

local function checkSwatch(swatch: any, label: string)
	t.truthy(isHex(swatch.top), label .. ".top")
	t.truthy(isHex(swatch.bottom), label .. ".bottom")
	t.truthy(isHex(swatch.text), label .. ".text")
end

return {
	["names are sorted and include cartoon"] = function()
		local names = Style.names()
		t.truthy(table.find(names, "cartoon") ~= nil)
		for index = 2, #names do
			t.truthy(names[index - 1] < names[index], names[index])
		end
	end,

	["get returns the default style"] = function()
		t.equal(Style.default(), "cartoon")
		t.equal(Style.get().name, "cartoon")
		t.equal(Style.get("cartoon"), Style.get())
	end,

	["unknown styles raise errors"] = function()
		t.throws(function()
			Style.get("doesNotExist")
		end)
		t.throws(function()
			Style.setDefault("doesNotExist")
		end)
		t.equal(Style.default(), "cartoon", "a failed setDefault changes nothing")
	end,

	["setDefault switches the default style"] = function()
		local names = Style.names()
		local other = if names[1] == "cartoon" then names[2] else names[1]
		Style.setDefault(other)
		local ok, err = pcall(function()
			t.equal(Style.default(), other)
			t.equal(Style.get().name, other)
		end)
		Style.setDefault("cartoon")
		assert(ok, err)
	end,

	["unknown palettes fall back to blue"] = function()
		local style = Style.get("cartoon")
		local blue = Style.palette(style, "blue")
		t.equal(Style.palette(style, "doesNotExist"), blue)
		t.equal(Style.palette(style, nil), blue)
		t.falsy(Style.hasPalette(style, "doesNotExist"))
		t.truthy(Style.hasPalette(style, "purple"))
	end,

	["palettes resolve their colours"] = function()
		local style = Style.get("cartoon")
		local purple = Style.palette(style, "purple")
		t.equal(purple.top, "#B98CFF")
		t.equal(purple.bottom, "#7A4DE8")
		t.equal(purple.text, "#FFFFFF")
	end,

	["surfaces fall back to window"] = function()
		local style = Style.get("cartoon")
		t.equal(Style.surface(style, "doesNotExist"), Style.surface(style, "window"))
		t.equal(Style.surface(style), Style.surface(style, "window"))
		t.equal(Style.surface(style, "dark").top, "#2A2F4A")
	end,

	["button kinds resolve and unknown kinds use primary"] = function()
		local style = Style.get("cartoon")
		for _, kind in BUTTONS do
			local def = Style.button(style, kind)
			t.truthy(def.palette ~= nil or def.surface ~= nil, kind)
		end
		t.equal(Style.button(style, "price").surface, "dark")
		t.equal(Style.button(style, "robux").palette, "green")
		t.equal(Style.button(style, "doesNotExist"), Style.button(style, "primary"))
	end,

	["badge kinds resolve and unknown kinds use new"] = function()
		local style = Style.get("cartoon")
		for _, kind in BADGES do
			local def = Style.badge(style, kind)
			t.truthy(Style.hasPalette(style, def.palette), kind .. " palette")
			t.truthy(type(def.shape) == "string", kind .. " shape")
		end
		local attention = Style.badge(style, "attention")
		t.equal(attention.shape, "circle")
		t.equal(attention.text, "!")
		t.equal(Style.badge(style, "doesNotExist"), Style.badge(style, "new"))
	end,

	["rarity colours and the secret rainbow"] = function()
		local style = Style.get("cartoon")
		for _, name in RARITIES do
			t.truthy(isHex(Style.rarity(style, name).color), name)
		end
		t.equal(Style.rarity(style, "secret").rainbow, true)
		t.falsy(Style.rarity(style, "legendary").rainbow)
		t.equal(Style.rarity(style, "doesNotExist"), Style.rarity(style, "common"))
		t.equal(Style.rarity(style, nil), Style.rarity(style, "common"))
	end,

	["outline weights grow and default to regular"] = function()
		for _, name in Style.names() do
			local style = Style.get(name)
			local thin = Style.outline(style, "thin")
			local regular = Style.outline(style, "regular")
			local thick = Style.outline(style, "thick")
			local heavy = Style.outline(style, "heavy")
			t.truthy(thin > 0, name .. " thin")
			t.truthy(thin <= regular and regular <= thick and thick <= heavy, name .. " order")
			t.equal(Style.outline(style), regular, name .. " default")
			t.equal(Style.outline(style, "doesNotExist"), regular, name .. " unknown")
			t.equal(Style.outline(style, "color"), regular, name .. " colour is not a weight")
		end
		t.equal(Style.outline(Style.get("cartoon"), "heavy"), 6)
	end,

	["darken moves toward black"] = function()
		t.equal(Style.darken("#FFFFFF", 0.5), "#808080")
		t.equal(Style.darken("#FF8040", 0.25), "#BF6030")
		t.equal(Style.darken("#FF8040", 0), "#FF8040")
		t.equal(Style.darken("#FF8040", 1), "#000000")
		t.equal(Style.darken("#FF8040", 3), "#000000", "amount is clamped")
		t.equal(Style.darken("#FF8040", -1), "#FF8040", "negative amount is clamped")
	end,

	["lighten moves toward white"] = function()
		t.equal(Style.lighten("#000000", 0.5), "#808080")
		t.equal(Style.lighten("#204060", 0.5), "#90A0B0")
		t.equal(Style.lighten("#123456", 0), "#123456")
		t.equal(Style.lighten("#123456", 1), "#FFFFFF")
		t.equal(Style.lighten("#abcdef", 0), "#ABCDEF", "output is upper case")
	end,

	["colour helpers reject bad hex"] = function()
		t.throws(function()
			Style.darken("red", 0.1)
		end)
		t.throws(function()
			Style.lighten("#FFF", 0.1)
		end)
		t.deepEqual(Style.rgb("#1B1530"), { r = 27, g = 21, b = 48 })
	end,

	["fonts and text sizes fall back sensibly"] = function()
		for _, name in Style.names() do
			local style = Style.get(name)
			t.equal(Style.font(style), style.fonts.body, name .. " body by default")
			t.equal(Style.font(style, "doesNotExist"), style.fonts.fallback, name .. " fallback")
			t.equal(Style.textSize(style, "doesNotExist"), Style.textSize(style, "label"), name)
			local minimum = Style.textSize(style, "minimum")
			for _, role in TEXT_ROLES do
				t.truthy(Style.textSize(style, role) >= minimum, name .. " " .. role .. " >= minimum")
			end
		end
	end,

	["every style defines the keys components need"] = function()
		for _, name in Style.names() do
			local style = Style.get(name)
			t.equal(style.name, name)
			for _, role in { "title", "body", "number", "fallback" } do
				t.truthy(type(style.fonts[role]) == "string", name .. " font " .. role)
			end
			t.truthy(isHex(style.outline.color), name .. " outline colour")
			t.truthy(isHex(style.textStroke.color), name .. " text stroke colour")
			t.truthy(type(style.textStroke.thickness) == "number", name .. " text stroke")
			for _, token in { "sm", "md", "lg", "xl", "pill" } do
				t.truthy(type(style.radius[token]) == "number", name .. " radius " .. token)
			end
			for _, token in { "xs", "sm", "md", "lg", "xl", "xxl" } do
				t.truthy(type(style.spacing[token]) == "number", name .. " spacing " .. token)
			end
			t.truthy(isHex(style.shadow.color) and type(style.shadow.transparency) == "number", name .. " shadow")
			t.truthy(type(style.gloss.heightFraction) == "number", name .. " gloss")
			t.truthy(type(style.pattern.cell) == "number", name .. " pattern")
			for _, surface in { "window", "inset", "dark" } do
				checkSwatch(Style.surface(style, surface), name .. " surface " .. surface)
			end
			for _, palette in PALETTES do
				t.truthy(Style.hasPalette(style, palette), name .. " palette " .. palette)
				checkSwatch(Style.palette(style, palette), name .. " palette " .. palette)
			end
			for _, kind in BUTTONS do
				t.truthy(style.buttons[kind] ~= nil, name .. " button " .. kind)
			end
			for _, kind in BADGES do
				t.truthy(style.badges[kind] ~= nil, name .. " badge " .. kind)
			end
			for _, rarity in RARITIES do
				t.truthy(style.rarity[rarity] ~= nil, name .. " rarity " .. rarity)
			end
			t.truthy(type(style.sizes.card.width) == "number", name .. " card size")
			t.truthy(type(style.sizes.banner.height) == "number", name .. " banner size")
			t.truthy(type(style.sizes.hudButton.size) == "number", name .. " HUD button size")
		end
	end,

	["darkened and lightened palette colours stay valid"] = function()
		local style = Style.get("cartoon")
		for _, palette in PALETTES do
			local top = Style.palette(style, palette).top
			local darker = Style.rgb(Style.darken(top, 0.2))
			local lighter = Style.rgb(Style.lighten(top, 0.2))
			local base = Style.rgb(top)
			t.truthy(darker.r <= base.r and darker.g <= base.g and darker.b <= base.b, palette .. " darker")
			t.truthy(lighter.r >= base.r and lighter.g >= base.g and lighter.b >= base.b, palette .. " lighter")
		end
	end,
}
