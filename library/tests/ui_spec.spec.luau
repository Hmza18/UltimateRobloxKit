--!strict
-- SpecSchema: screen spec validation rules (paths and messages) and defaults.

local SpecSchema = require("../src/UI/Spec/SpecSchema")
local Style = require("../src/UI/Style/Style")
local t = require("./lib/t")

local function windowSpec(body: { any }): { [string]: any }
	return { spec = 1, id = "Test", kind = "window", style = "cartoon", window = { title = "SHOP" }, body = body }
end

local function hudSpec(rails: { [string]: any }): { [string]: any }
	return { spec = 1, id = "Hud", kind = "hud", rails = rails }
end

local function product(id: string?): { [string]: any }
	return {
		type = "product",
		id = id,
		palette = "purple",
		icon = "egg-color",
		title = "TRIPLE HATCH",
		price = { kind = "robux", amount = 29, gamePassId = 0 },
	}
end

local function describe(issues: { SpecSchema.Issue }): string
	if #issues == 0 then
		return "(no issues)"
	end
	return SpecSchema.format(issues)
end

local function expectValid(spec: any, label: string?)
	local issues = SpecSchema.validate(spec)
	if #issues > 0 then
		error((label or "spec") .. " should be valid:\n" .. describe(issues), 2)
	end
end

-- Passes when some issue has exactly `path` and a message containing `fragment`.
local function expectIssue(spec: any, path: string, fragment: string)
	local issues = SpecSchema.validate(spec)
	for _, issue in ipairs(issues) do
		if issue.path == path and string.find(issue.message, fragment, 1, true) ~= nil then
			return
		end
	end
	error(string.format("expected %q at %q, got:\n%s", fragment, path, describe(issues)), 2)
end

local CONTRACT_TYPES = {
	"banner",
	"product",
	"grid",
	"row",
	"heading",
	"divider",
	"text",
	"button",
	"iconButton",
	"currency",
	"level",
	"progress",
	"timer",
	"toggle",
	"slider",
	"dropdown",
	"dayCard",
	"listRow",
}

return {
	["ELEMENT_TYPES covers every type in the contract table"] = function()
		for _, name in ipairs(CONTRACT_TYPES) do
			t.truthy(SpecSchema.ELEMENT_TYPES[name] ~= nil, name)
		end
		t.equal(#SpecSchema.TYPE_NAMES, #CONTRACT_TYPES, "no extra types")
		t.deepEqual(SpecSchema.ELEMENT_TYPES.banner.required, { "title", "palette", "price" })
		t.deepEqual(SpecSchema.ELEMENT_TYPES.toggle.required, { "id", "label" })
	end,

	["RULES exports the limits a Python twin mirrors"] = function()
		local rules = SpecSchema.RULES
		t.deepEqual(rules.kinds, { "window", "hud", "popup" })
		t.equal(rules.maxElements, 200)
		t.equal(rules.maxLength.title, 60)
		t.equal(rules.maxLength.subtitle, 90)
		t.equal(rules.minColumns, 1)
		t.equal(rules.maxColumns, 6)
		t.equal(#rules.rails, 8)
		t.deepEqual(rules.dayStates, { "claimed", "today", "locked" })
	end,

	["a minimal window spec is valid"] = function()
		expectValid(windowSpec({ { type = "divider" } }))
	end,

	["the contract example spec is valid"] = function()
		expectValid({
			spec = 1,
			id = "PetShop",
			kind = "window",
			style = "cartoon",
			window = { title = "SHOP", headerPalette = "red", sizeClass = "lg" },
			body = {
				{
					type = "banner",
					id = "starter",
					palette = "teal",
					icon = "star-color",
					title = "STARTER PACK",
					subtitle = "A great offer you can't refuse!",
					price = { kind = "robux", amount = 29, productId = 0 },
				},
				{ type = "divider" },
				{ type = "grid", columns = { phone = 2, tablet = 3, desktop = 3 }, items = { product("tripleHatch") } },
			},
		})
	end,

	["a spec that is not a table is reported at the root"] = function()
		expectIssue("nope", "", "spec must be an object")
	end,

	["spec version must be 1"] = function()
		local spec = windowSpec({ { type = "divider" } })
		spec.spec = 2
		expectIssue(spec, "spec", "spec must be 1")
	end,

	["id is required and must be an identifier"] = function()
		local spec = windowSpec({ { type = "divider" } })
		spec.id = nil
		expectIssue(spec, "id", "id is required")
		spec.id = "has space"
		expectIssue(spec, "id", "identifier")
	end,

	["unknown kinds are rejected"] = function()
		local spec = windowSpec({ { type = "divider" } })
		spec.kind = "sidebar"
		expectIssue(spec, "kind", "unknown kind sidebar")
	end,

	["style must exist and every Style name is accepted"] = function()
		local spec = windowSpec({ { type = "divider" } })
		spec.style = "neon"
		expectIssue(spec, "style", "unknown style neon")
		for _, name in ipairs(Style.names()) do
			spec.style = name
			expectValid(spec, name)
		end
	end,

	["unknown top-level fields are rejected"] = function()
		local spec = windowSpec({ { type = "divider" } })
		spec.theme = "dark"
		expectIssue(spec, "theme", "unknown field theme for spec")
	end,

	["window needs a title"] = function()
		local spec = windowSpec({ { type = "divider" } })
		spec.window = { headerPalette = "red" }
		expectIssue(spec, "window.title", "title is required for window")
	end,

	["window sizeClass and headerPalette are checked"] = function()
		local spec = windowSpec({ { type = "divider" } })
		spec.window = { title = "SHOP", sizeClass = "xl", headerPalette = "chartreuse" }
		expectIssue(spec, "window.sizeClass", "unknown sizeClass xl")
		expectIssue(spec, "window.headerPalette", "unknown palette chartreuse")
	end,

	["window screens need a non-empty body"] = function()
		local spec = windowSpec({})
		expectIssue(spec, "body", "body must not be empty")
		spec.body = nil
		expectIssue(spec, "body", "body is required for window screens")
	end,

	["missing title on a banner"] = function()
		local spec = windowSpec({
			{ type = "banner", palette = "teal", price = { kind = "robux", amount = 29, productId = 0 } },
		})
		expectIssue(spec, "body[1].title", "title is required for banner")
	end,

	["bad palette"] = function()
		local item = product("a")
		item.palette = "chartreuse"
		expectIssue(windowSpec({ item }), "body[1].palette", "unknown palette chartreuse")
	end,

	["robux prices need productId or gamePassId"] = function()
		local item = product("a")
		item.price = { kind = "robux", amount = 29 }
		expectIssue(windowSpec({ item }), "body[1].price", "robux prices need productId or gamePassId")
	end,

	["robux id 0 is a valid placeholder, negative ids are not"] = function()
		local item = product("a")
		item.price = { kind = "robux", amount = 29, productId = 0 }
		expectValid(windowSpec({ item }))
		item.price = { kind = "robux", amount = 29, productId = -5 }
		expectIssue(windowSpec({ item }), "body[1].price.productId", "whole number >= 0")
	end,

	["robux prices take one id and a positive amount"] = function()
		local item = product("a")
		item.price = { kind = "robux", amount = 29, productId = 1, gamePassId = 2 }
		expectIssue(windowSpec({ item }), "body[1].price", "not both")
		item.price = { kind = "robux", amount = 0, productId = 1 }
		expectIssue(windowSpec({ item }), "body[1].price.amount", "at least 1")
		item.price = { kind = "robux", productId = 1 }
		expectIssue(windowSpec({ item }), "body[1].price.amount", "robux prices need an amount")
	end,

	["currency prices need an amount >= 0 and a currency icon"] = function()
		local item = product("a")
		item.price = { kind = "currency", amount = 250 }
		expectIssue(windowSpec({ item }), "body[1].price.currency", "currency icon name")
		item.price = { kind = "currency", amount = -1, currency = "coin-color" }
		expectIssue(windowSpec({ item }), "body[1].price.amount", "at least 0")
		item.price = { kind = "currency", amount = 250, currency = "not-an-icon" }
		expectIssue(windowSpec({ item }), "body[1].price.currency", "unknown icon not-an-icon")
		item.price = { kind = "currency", amount = 0, currency = "coin-color" }
		expectValid(windowSpec({ item }))
	end,

	["free prices are valid and take no amount"] = function()
		local item = product("a")
		item.price = { kind = "free" }
		expectValid(windowSpec({ item }))
		item.price = { kind = "free", amount = 5 }
		expectIssue(windowSpec({ item }), "body[1].price.amount", "free prices have no amount")
	end,

	["unknown price kinds and price fields"] = function()
		local item = product("a")
		item.price = { kind = "gems", amount = 5 }
		expectIssue(windowSpec({ item }), "body[1].price.kind", "unknown price kind gems")
		item.price = { kind = "robux", amount = 5, productId = 0, discount = 10 }
		expectIssue(windowSpec({ item }), "body[1].price.discount", "unknown field discount for price")
	end,

	["duplicate ids are reported at the second use"] = function()
		local spec = windowSpec({ product("same"), { type = "grid", items = { product("same") } } })
		expectIssue(spec, "body[2].items[1].id", "duplicate id same (first used at body[1])")
	end,

	["duplicate ids are found across HUD rails"] = function()
		local spec = hudSpec({
			left = { { type = "iconButton", id = "shop", icon = "shop-color" } },
			right = { { type = "iconButton", id = "shop", icon = "shop-color" } },
		})
		expectIssue(spec, "rails.right[1].id", "duplicate id shop (first used at rails.left[1])")
	end,

	["grid columns must be whole numbers from 1 to 6"] = function()
		local function grid(columns: any): { [string]: any }
			return windowSpec({ { type = "grid", columns = columns, items = { product("a") } } })
		end
		expectIssue(grid({ phone = 7 }), "body[1].columns.phone", "from 1 to 6")
		expectIssue(grid({ desktop = 0 }), "body[1].columns.desktop", "from 1 to 6")
		expectIssue(grid({ tablet = 2.5 }), "body[1].columns.tablet", "from 1 to 6")
		expectIssue(grid(9), "body[1].columns", "from 1 to 6")
		expectIssue(grid({ watch = 1 }), "body[1].columns.watch", "unknown field watch for columns")
		expectValid(grid(4))
		expectValid(grid({ phone = 1, tablet = 6, desktop = 6, console = 6 }))
	end,

	["unknown element types"] = function()
		expectIssue(windowSpec({ { type = "carousel" } }), "body[1].type", "unknown element type carousel")
		expectIssue(windowSpec({ { text = "hi" } }), "body[1].type", "type is required")
	end,

	["unknown element fields name the element type"] = function()
		local item = product("a")
		item.colour = "red"
		expectIssue(windowSpec({ item }), "body[1].colour", "unknown field colour for product")
	end,

	["titles are limited to 60 characters"] = function()
		local item = product("a")
		item.title = string.rep("A", 60)
		expectValid(windowSpec({ item }))
		item.title = string.rep("A", 61)
		expectIssue(windowSpec({ item }), "body[1].title", "title is 61 characters; the limit is 60")
		local spec = windowSpec({ { type = "divider" } })
		spec.window.title = string.rep("W", 61)
		expectIssue(spec, "window.title", "the limit is 60")
	end,

	["subtitles are limited to 90 characters and text must not be empty"] = function()
		local item = product("a")
		item.subtitle = string.rep("s", 91)
		expectIssue(windowSpec({ item }), "body[1].subtitle", "the limit is 90")
		item.subtitle = nil
		item.title = "   "
		expectIssue(windowSpec({ item }), "body[1].title", "title must not be empty")
		expectIssue(windowSpec({ { type = "heading", text = 5 } }), "body[1].text", "text must be a string")
	end,

	["bind paths follow the Path rules"] = function()
		local function currency(bind: any): { [string]: any }
			return windowSpec({ { type = "currency", id = "cash", icon = "cash-color", bind = bind } })
		end
		expectValid(currency("Stats.Cash"))
		expectValid(currency("Inventory.3.Count"))
		expectIssue(currency("Stats..Cash"), "body[1].bind", "invalid bind path Stats..Cash")
		expectIssue(currency("Stats.Cash Total"), "body[1].bind", "invalid bind path")
		expectIssue(currency(""), "body[1].bind", "invalid bind path")
	end,

	["HUD rails must use the contract names"] = function()
		local spec = hudSpec({ middle = { { type = "timer", seconds = 30 } } })
		expectIssue(spec, "rails.middle", "unknown rail middle")
		expectValid(hudSpec({ bottomRight = { { type = "timer", seconds = 30 } } }))
	end,

	["HUD screens need rails and take no body"] = function()
		local spec = hudSpec({})
		expectIssue(spec, "rails", "at least one rail")
		spec.rails = nil
		expectIssue(spec, "rails", "rails is required for hud screens")
		local withBody = hudSpec({ top = { { type = "timer", seconds = 5 } } })
		withBody.body = { { type = "divider" } }
		expectIssue(withBody, "body", "body is not used by hud screens")
		expectIssue(hudSpec({ left = {} }), "rails.left", "rail left must not be empty")
	end,

	["dayCard state values and day range"] = function()
		local function day(state: any, number: any): { [string]: any }
			local card = { type = "dayCard", id = "d", day = number, reward = "100 Coins", state = state }
			return windowSpec({ { type = "grid", items = { card } } })
		end
		expectValid(day("today", 3))
		expectIssue(day("soon", 3), "body[1].items[1].state", "unknown dayCard state soon")
		expectIssue(day("locked", 0), "body[1].items[1].day", "at least 1")
		expectIssue(day("locked", 1.5), "body[1].items[1].day", "whole number")
	end,

	["button needs text or icon"] = function()
		expectIssue(windowSpec({ { type = "button", id = "b" } }), "body[1]", "button needs text or icon")
		expectValid(windowSpec({ { type = "button", id = "b", icon = "close-color" } }))
		local mega = { type = "button", text = "GO", kind = "mega" }
		expectIssue(windowSpec({ mega }), "body[1].kind", "unknown button kind")
	end,

	["currency needs an icon and a bind or a value"] = function()
		local unbound = { type = "currency", icon = "coin-color" }
		expectIssue(windowSpec({ unbound }), "body[1]", "currency needs bind or value")
		expectIssue(windowSpec({ { type = "currency", value = 5 } }), "body[1].icon", "icon is required for currency")
		expectIssue(
			windowSpec({ { type = "currency", icon = "coin-color", value = 5, format = "fancy" } }),
			"body[1].format",
			"unknown format fancy"
		)
		expectValid(windowSpec({ { type = "currency", icon = "coin-color", value = 5, format = "abbrev:2" } }))
	end,

	["icons: glyph and -color names pass, unknown names fail"] = function()
		t.truthy(SpecSchema.isIcon("coin"))
		t.truthy(SpecSchema.isIcon("coin-color"))
		t.falsy(SpecSchema.isIcon("coin-colour"))
		t.falsy(SpecSchema.isIcon(""))
		local item = product("a")
		item.icon = "unicorn-color"
		expectIssue(windowSpec({ item }), "body[1].icon", "unknown icon unicorn-color")
	end,

	["images must be asset ids"] = function()
		local item = product("a")
		item.image = "rbxassetid://123"
		expectValid(windowSpec({ item }))
		item.image = "https://example.com/egg.png"
		expectIssue(windowSpec({ item }), "body[1].image", "asset id")
	end,

	["badges use Style badge kinds and short text"] = function()
		local item = product("a")
		item.badge = { kind = "hot" }
		expectIssue(windowSpec({ item }), "body[1].badge.kind", "unknown badge kind hot")
		item.badge = { kind = "sale", text = "HUGE SALE TODAY" }
		expectIssue(windowSpec({ item }), "body[1].badge.text", "the limit is 12")
		item.badge = { kind = "bonus", text = "+50%" }
		expectValid(windowSpec({ item }))
	end,

	["rarity names come from the style"] = function()
		local item = product("a")
		item.rarity = "mythic"
		expectValid(windowSpec({ item }))
		item.rarity = "ultra"
		expectIssue(windowSpec({ item }), "body[1].rarity", "unknown rarity ultra")
	end,

	["actions use the UrkUI action syntax"] = function()
		t.truthy(SpecSchema.isAction("OpenPanel:Shop"))
		t.truthy(SpecSchema.isAction("Fire:Buy,starter;PlaySound:123"))
		t.truthy(SpecSchema.isAction("Back"))
		t.falsy(SpecSchema.isAction("Open Panel"))
		t.falsy(SpecSchema.isAction(";;"))
		local spec = windowSpec({ { type = "iconButton", id = "x", icon = "shop-color", action = "!!" } })
		expectIssue(spec, "body[1].action", "invalid action !!")
	end,

	["slider ranges are checked"] = function()
		local function slider(min: number, max: number, value: number): { [string]: any }
			return windowSpec({ { type = "slider", id = "s", label = "Music", min = min, max = max, value = value } })
		end
		expectValid(slider(0, 1, 0.5))
		expectIssue(slider(1, 1, 1), "body[1].max", "max must be greater than min")
		expectIssue(slider(0, 1, 2), "body[1].value", "between min and max")
		local stepped = slider(0, 1, 0.5)
		stepped.body[1].step = 0
		expectIssue(stepped, "body[1].step", "step must be greater than 0")
	end,

	["dropdown needs options and a value among them"] = function()
		local dropdown = { type = "dropdown", id = "d", label = "Size", options = { "Small", "Large" }, value = "Huge" }
		expectIssue(windowSpec({ dropdown }), "body[1].value", "one of the options")
		local missing = { type = "dropdown", id = "d", label = "Size" }
		expectIssue(windowSpec({ missing }), "body[1].options", "options is required for dropdown")
	end,

	["toggles need an id and a boolean value"] = function()
		expectIssue(windowSpec({ { type = "toggle", label = "Music" } }), "body[1].id", "id is required for toggle")
		local toggle = { type = "toggle", id = "m", label = "Music", value = "yes" }
		expectIssue(windowSpec({ toggle }), "body[1].value", "true or false")
		local extra = { type = "toggle", id = "m", label = "Music", options = { "a" } }
		expectIssue(windowSpec({ extra }), "body[1].options", "options is not used by toggle")
	end,

	["text color must be a hex colour"] = function()
		expectIssue(windowSpec({ { type = "text", text = "Hi", color = "red" } }), "body[1].color", "#RRGGBB")
		expectValid(windowSpec({ { type = "text", text = "Hi", color = "#FFAA00", size = "caption" } }))
	end,

	["listRow buttons are validated as buttons"] = function()
		local row = { type = "listRow", id = "r", title = "Speed", button = { text = "BUY", kind = "mega" } }
		expectIssue(windowSpec({ row }), "body[1].button.kind", "unknown button kind mega")
		local typed = { type = "listRow", id = "r", title = "Speed", button = { type = "toggle", text = "x" } }
		expectIssue(windowSpec({ typed }), "body[1].button.type", "must have type button")
		local priced = {
			type = "listRow",
			id = "r",
			title = "Speed",
			rank = 1,
			value = "Lv 3",
			progress = { value = 3, max = 10 },
			button = { id = "rBuy", text = "UPGRADE", price = { kind = "currency", amount = 100, currency = "coin" } },
		}
		expectValid(windowSpec({ priced }))
	end,

	["listRow progress and rank are checked"] = function()
		local row = { type = "listRow", title = "Speed", progress = { value = 1, total = 3 } }
		expectIssue(windowSpec({ row }), "body[1].progress.total", "unknown field total for progress")
		local ranked = { type = "listRow", title = "Speed", rank = 0 }
		expectIssue(windowSpec({ ranked }), "body[1].rank", "at least 1")
	end,

	["level and progress values must not exceed max"] = function()
		expectIssue(windowSpec({ { type = "progress", value = 12, max = 10 } }), "body[1].value", "must not exceed max")
		expectIssue(windowSpec({ { type = "level", max = 0 } }), "body[1].max", "greater than 0")
		expectValid(windowSpec({ { type = "level", bind = "Stats.Level", level = 3, value = 40, max = 100 } }))
	end,

	["a screen holds at most 200 elements"] = function()
		local body: { any } = {}
		for _ = 1, 200 do
			table.insert(body, { type = "divider" })
		end
		expectValid(windowSpec(body))
		table.insert(body, { type = "divider" })
		expectIssue(windowSpec(body), "", "screen has 201 elements; the limit is 200")
	end,

	["elements cannot nest deeper than the limit"] = function()
		local inner: { [string]: any } = { type = "divider" }
		for _ = 1, 6 do
			inner = { type = "row", items = { inner } }
		end
		local issues = SpecSchema.validate(windowSpec({ inner }))
		local found = false
		for _, issue in ipairs(issues) do
			if string.find(issue.message, "nested too deeply", 1, true) then
				found = true
			end
		end
		t.truthy(found, describe(issues))
	end,

	["popup screens: reward and confirm variants"] = function()
		local reward: { [string]: any } = {
			spec = 1,
			id = "Reward",
			kind = "popup",
			popup = { variant = "reward", title = "YOU GOT", icon = "chest-color", amount = "x1", rays = true },
		}
		expectValid(reward)
		local confirm: { [string]: any } = {
			spec = 1,
			id = "Confirm",
			kind = "popup",
			popup = {
				variant = "confirm",
				title = "BUY?",
				message = "Are you sure?",
				price = { kind = "robux", amount = 49, gamePassId = 0 },
			},
			body = { { type = "listRow", title = "Perk" } },
		}
		expectValid(confirm)
		reward.popup.confirmText = "OK"
		expectIssue(reward, "popup.confirmText", "only used by confirm popups")
		confirm.popup.variant = nil
		expectIssue(confirm, "popup.variant", "variant is required for popup")
	end,

	["popup kind requires a popup table"] = function()
		expectIssue({ spec = 1, id = "P", kind = "popup" }, "popup", "popup is required for popup screens")
		local wrong = windowSpec({ { type = "divider" } })
		wrong.popup = { variant = "reward", title = "X" }
		expectIssue(wrong, "popup", "popup is not used by window screens")
	end,

	["issues are path and message strings and format joins them"] = function()
		local issues = SpecSchema.validate({ spec = 1, kind = "window" })
		t.truthy(#issues >= 3)
		for _, issue in ipairs(issues) do
			t.equal(type(issue.path), "string")
			t.equal(type(issue.message), "string")
		end
		local text = SpecSchema.format({ { path = "", message = "a" }, { path = "body[1]", message = "b" } })
		t.equal(text, "(spec): a\nbody[1]: b")
	end,

	["withDefaults never modifies its input"] = function()
		local spec = windowSpec({ product(nil) })
		local before = SpecSchema.format(SpecSchema.validate(spec))
		local filled = SpecSchema.withDefaults(spec)
		t.truthy(filled ~= spec)
		t.equal(spec.window.sizeClass, nil)
		t.equal(spec.body[1].id, nil)
		t.equal(SpecSchema.format(SpecSchema.validate(spec)), before)
	end,

	["withDefaults fills window, element and price-dependent defaults"] = function()
		local spec = windowSpec({
			product("card"),
			{ type = "button", text = "BUY", price = { kind = "robux", amount = 5, productId = 0 } },
			{ type = "button", text = "BUY", price = { kind = "currency", amount = 5, currency = "coin" } },
			{ type = "button", text = "OK" },
			{ type = "heading", text = "PACKS" },
		})
		local filled = SpecSchema.withDefaults(spec)
		t.equal(filled.style, "cartoon")
		t.equal(filled.window.headerPalette, "red")
		t.equal(filled.window.sizeClass, "md")
		t.equal(filled.window.closable, true)
		t.equal(filled.window.scroll, true)
		t.equal(filled.body[1].layout, "tall")
		t.equal(filled.body[1].gift, false)
		t.equal(filled.body[1].owned, false)
		t.equal(filled.body[2].kind, "robux")
		t.equal(filled.body[3].kind, "buy")
		t.equal(filled.body[4].kind, "primary")
		t.equal(filled.body[5].size, "heading")
		t.equal(filled.body[5].id, nil, "headings are not interactive, so they get no id")
		t.equal(filled.body[5].visible, true)
	end,

	["withDefaults gives interactive elements unique ids"] = function()
		local spec = windowSpec({
			{ type = "button", id = "auto_body_2", text = "A" },
			{ type = "button", text = "B" },
			{ type = "grid", items = { product(nil), product(nil) } },
		})
		local filled = SpecSchema.withDefaults(spec)
		t.equal(filled.body[1].id, "auto_body_2")
		t.equal(filled.body[2].id, "auto_body_2_2", "a taken id gets a suffix")
		t.equal(filled.body[3].items[1].id, "auto_body_3_1")
		t.equal(filled.body[3].items[2].id, "auto_body_3_2")
		expectValid(filled, "filled spec")
	end,

	["withDefaults resolves grid columns for every breakpoint"] = function()
		local spec = windowSpec({
			{ type = "grid", items = { product("a") } },
			{ type = "grid", columns = { desktop = 5 }, items = { product("b") } },
			{ type = "grid", columns = 4, items = { product("c") } },
		})
		local filled = SpecSchema.withDefaults(spec)
		t.deepEqual(filled.body[1].columns, { phone = 2, tablet = 3, desktop = 3, console = 3 })
		t.deepEqual(filled.body[2].columns, { phone = 2, tablet = 5, desktop = 5, console = 5 })
		t.deepEqual(filled.body[3].columns, { phone = 4, tablet = 4, desktop = 4, console = 4 })
		t.equal(filled.body[1].cellAspect, 1.25)
		t.equal(filled.body[1].gap, "md")
	end,

	["withDefaults fills controls, bars, timers and day cards"] = function()
		local spec = windowSpec({
			{ type = "slider", id = "s", label = "Music", min = 2, max = 8 },
			{ type = "dropdown", id = "d", label = "Size", options = { "Small", "Large" } },
			{ type = "toggle", id = "t", label = "Mute" },
			{ type = "progress" },
			{ type = "timer", seconds = 30 },
			{ type = "dayCard", day = 1, reward = "Coins" },
			{ type = "listRow", title = "Row", progress = { value = 2 }, button = { text = "GO" } },
		})
		local filled = SpecSchema.withDefaults(spec)
		t.equal(filled.body[1].value, 2)
		t.equal(filled.body[1].step, 0.1)
		t.equal(filled.body[2].value, "Small")
		t.equal(filled.body[3].value, false)
		t.equal(filled.body[4].max, 100)
		t.equal(filled.body[4].palette, "green")
		t.equal(filled.body[5].format, "clock")
		t.equal(filled.body[6].state, "locked")
		t.equal(filled.body[6].premium, false)
		t.truthy(filled.body[6].id ~= nil, "day cards are interactive")
		t.equal(filled.body[7].button.type, "button")
		t.equal(filled.body[7].button.kind, "primary")
		t.equal(filled.body[7].progress.max, 100)
		expectValid(filled, "filled spec")
	end,

	["withDefaults fills popup defaults per variant"] = function()
		local confirm = SpecSchema.withDefaults({
			spec = 1,
			id = "C",
			kind = "popup",
			popup = { variant = "confirm", title = "BUY?", price = { kind = "robux", amount = 5, productId = 0 } },
		})
		t.equal(confirm.popup.confirmText, "BUY")
		t.equal(confirm.popup.cancelText, "CANCEL")
		t.deepEqual(confirm.body, {})
		local reward = SpecSchema.withDefaults({
			spec = 1,
			id = "R",
			kind = "popup",
			popup = { variant = "reward", title = "YOU GOT" },
		})
		t.equal(reward.popup.palette, "gold")
		t.equal(reward.popup.rays, true)
	end,

	["withDefaults tolerates invalid input"] = function()
		t.equal(SpecSchema.withDefaults(5), 5)
		local filled = SpecSchema.withDefaults({ kind = "window", body = { { type = "nope" }, 7 } })
		t.equal(filled.body[2], 7)
	end,

	["resolveColumns fills missing breakpoints"] = function()
		t.deepEqual(SpecSchema.resolveColumns(nil), { phone = 2, tablet = 3, desktop = 3, console = 3 })
		t.deepEqual(SpecSchema.resolveColumns({ phone = 1 }), { phone = 1, tablet = 3, desktop = 3, console = 3 })
		t.deepEqual(
			SpecSchema.resolveColumns({ tablet = 4, console = 6 }),
			{ phone = 2, tablet = 4, desktop = 4, console = 6 }
		)
	end,

	["walk visits body, items, rails and listRow buttons"] = function()
		local spec = windowSpec({
			{ type = "grid", items = { product("a"), product("b") } },
			{ type = "listRow", title = "R", button = { text = "GO" } },
		})
		local paths: { string } = {}
		SpecSchema.walk(spec, function(_element: any, path: string)
			table.insert(paths, path)
		end)
		t.deepEqual(paths, { "body[1]", "body[1].items[1]", "body[1].items[2]", "body[2]", "body[2].button" })
	end,
}
