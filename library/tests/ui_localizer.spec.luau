--!strict
-- Localizer: lookup, fallback chain, interpolation, format specs and plural rules.

local t = require("./lib/t")
local Localizer = require("../src/UI/Core/Localizer")

local function make(locale: string): Localizer.Localizer
	return Localizer.new({
		locale = locale,
		fallback = "en",
		tables = {
			en = {
				greet = "Hello, {name}!",
				coins = { one = "{count} coin", other = "{count} coins" },
				cash = "Cash: {cash:abbrev}",
			},
			fr = { greet = "Bonjour, {name} !", coins = { one = "{count} piece", other = "{count} pieces" } },
			pt = { bye = "Tchau" },
		},
	})
end

return {
	["translates and interpolates"] = function()
		local loc = make("en")
		t.equal(loc:t("greet", { name = "Ana" }), "Hello, Ana!")
		t.truthy(loc:has("greet"))
		t.falsy(loc:has("nothing"))
	end,

	["falls back from region to language to fallback"] = function()
		local loc = make("pt-BR")
		t.deepEqual(loc:chain(), { "pt-br", "pt", "en" })
		t.equal(loc:t("bye"), "Tchau")
		t.equal(loc:t("greet", { name = "Rui" }), "Hello, Rui!")
	end,

	["missing keys return the key and report it"] = function()
		local missing: { string } = {}
		local loc = Localizer.new({
			tables = { en = {} },
			onMissing = function(key: string)
				table.insert(missing, key)
			end,
		})
		t.equal(loc:t("menu.play"), "menu.play")
		t.deepEqual(missing, { "menu.play" })
	end,

	["english plurals"] = function()
		local loc = make("en")
		t.equal(loc:t("coins", { count = 1 }), "1 coin")
		t.equal(loc:t("coins", { count = 5 }), "5 coins")
		t.equal(loc:t("coins", { count = 0 }), "0 coins")
		t.equal(loc:t("coins"), "{count} coins", "no count uses other")
	end,

	["french treats zero and one as singular"] = function()
		local loc = make("fr")
		t.equal(loc:t("coins", { count = 0 }), "0 piece")
		t.equal(loc:t("coins", { count = 1 }), "1 piece")
		t.equal(loc:t("coins", { count = 2 }), "2 pieces")
	end,

	["slavic plural categories"] = function()
		t.equal(Localizer.pluralCategory("ru", 1), "one")
		t.equal(Localizer.pluralCategory("ru", 3), "few")
		t.equal(Localizer.pluralCategory("ru", 5), "many")
		t.equal(Localizer.pluralCategory("ru", 11), "many")
		t.equal(Localizer.pluralCategory("ru", 21), "one")
		t.equal(Localizer.pluralCategory("ru", 22), "few")
		t.equal(Localizer.pluralCategory("ru", 1.5), "other")
		t.equal(Localizer.pluralCategory("pl", 22), "few")
		t.equal(Localizer.pluralCategory("pl", 21), "many")
		t.equal(Localizer.pluralCategory("ja", 1), "other")
	end,

	["plural rule hook overrides the built-ins"] = function()
		local rules = {
			en = function(count: number): string
				return if count == 2 then "two" else "other"
			end,
		}
		t.equal(Localizer.pluralCategory("en-GB", 2, rules), "two", "language rule applies to regions")
		local loc = Localizer.new({
			tables = { en = { pair = { two = "a pair", other = "{count} items" } } },
			pluralRules = rules,
		})
		t.equal(loc:t("pair", { count = 2 }), "a pair")
		t.equal(loc:t("pair", { count = 3 }), "3 items")
	end,

	["interpolation formats, escapes and keeps unknown placeholders"] = function()
		t.equal(make("en"):t("cash", { cash = 1500 }), "Cash: 1.5K")
		t.equal(Localizer.interpolate("{a} and {b}", { a = 1 }), "1 and {b}")
		t.equal(Localizer.interpolate("{{literal}} {x}", { x = "y" }), "{literal} y")
		t.equal(Localizer.interpolate("no placeholders"), "no placeholders")
	end,

	["setLocale and addTable"] = function()
		local loc = make("en")
		loc:setLocale("fr")
		t.equal(loc:getLocale(), "fr")
		t.equal(loc:t("greet", { name = "Zoe" }), "Bonjour, Zoe !")
		loc:addTable("FR", { extra = "Plus" })
		t.equal(loc:t("extra"), "Plus")
		t.equal(loc:t("greet", { name = "Zoe" }), "Bonjour, Zoe !", "addTable merges instead of replacing")
	end,
}
