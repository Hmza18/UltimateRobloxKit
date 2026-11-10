--!strict
-- Visuals/Icons/IconVaultLogic: registration, validation, name resolution across packs, search
-- ranking, filters, asset ids, sheets and the picker's grid maths. The data mirrors what
-- tools/icons/vault.py writes (see tests/test_visuals_icons.py for the generated module itself).
local Logic = require("../src/Visuals/Icons/IconVaultLogic")
local t = require("./lib/t")

local function icon(name: string, category: string, tags: { string }, assetId: number?): any
	return { name = name, category = category, tags = tags, width = 64, height = 64, assetId = assetId or 0 }
end

local function gamePack(): any
	return {
		pack = "game",
		schema = 1,
		sheets = {},
		icons = {
			icon("sword", "weapons", { "sword", "weapons", "blade" }, 1001),
			icon("sword-fire", "weapons", { "sword", "fire", "weapons" }),
			icon("broadsword", "weapons", { "broadsword", "weapons" }, 1003),
			icon("coin", "currency", { "coin", "currency", "money" }, 1004),
			icon("coin-stack", "currency", { "coin", "stack", "currency" }),
			icon("shield", "armor", { "shield", "armor", "swordsman" }),
			icon("gem", "currency", { "gem", "currency" }, 1007),
		},
	}
end

local function uiPack(): any
	return {
		pack = "ui",
		sheets = { { width = 1024, height = 1024, assetId = 0 } },
		icons = {
			{
				name = "close",
				category = "buttons",
				tags = { "close", "x" },
				width = 128,
				height = 128,
				assetId = 0,
				sheet = 1,
				x = 2,
				y = 2,
				w = 64,
				h = 64,
			},
			{
				name = "coin",
				category = "hud",
				tags = { "coin" },
				width = 128,
				height = 128,
				assetId = 2002,
				sheet = 1,
				x = 70,
				y = 2,
				w = 64,
				h = 64,
			},
			{
				name = "arrow-left",
				category = "buttons",
				tags = { "arrow", "left", "back" },
				width = 128,
				height = 128,
				assetId = 0,
				sheet = 0,
				x = 0,
				y = 0,
				w = 0,
				h = 0,
			},
		},
	}
end

local function fresh()
	Logic.reset()
	t.equal(Logic.register("game", gamePack()), 7)
	t.equal(Logic.register("ui", uiPack()), 3)
end

return {
	["register returns the icon count and lists packs in order"] = function()
		fresh()
		t.deepEqual(Logic.packs(), { "game", "ui" })
		t.equal(Logic.count(), 10)
		t.equal(Logic.count("ui"), 3)
		t.equal(Logic.count("nope"), 0)
		t.equal(Logic.defaultPack(), "game")
	end,

	["registering a pack twice raises unless override is set"] = function()
		fresh()
		t.throws(function()
			Logic.register("game", gamePack())
		end)
		local smaller = gamePack()
		table.remove(smaller.icons)
		t.equal(Logic.register("game", smaller, { override = true }), 6)
		t.deepEqual(Logic.packs(), { "game", "ui" }, "override keeps the registration order")
		t.falsy(Logic.has("game:gem"))
	end,

	["invalid data is rejected and nothing is registered"] = function()
		Logic.reset()
		local cases: { any } = {
			"not a table",
			{},
			{ icons = "x" },
			{ pack = "other", icons = {} },
			{ icons = { { name = "Bad Name", category = "a" } } },
			{ icons = { { name = "ok", category = "" } } },
			{ icons = { { name = "ok" } } },
			{ icons = { icon("a", "c", {}), icon("a", "c", {}) } },
			{ icons = { { name = "a", category = "c", tags = { 1 } } } },
			{ icons = { { name = "a", category = "c", tags = "x" } } },
			{ icons = { { name = "a", category = "c", width = "64" } } },
			{ icons = { { name = "a", category = "c", assetId = -5 } } },
			{ icons = { { name = "a", category = "c", assetId = "rbxassetid://abc" } } },
			{ icons = { { name = "a", category = "c", assetId = 1.5 } } },
			{ icons = { { name = "a", category = "c", sheet = 1, x = 0, y = 0, w = 8, h = 8 } } },
			{ sheets = { { width = 64, height = 64 } }, icons = { { name = "a", category = "c", sheet = 1 } } },
			{ sheets = { { width = 64 } }, icons = {} },
			{ sheets = { { width = 64, height = 64, assetId = "nope" } }, icons = {} },
		}
		for index, data in cases do
			t.throws(function()
				Logic.register("bad", data)
			end, "case " .. index)
			t.deepEqual(Logic.packs(), {}, "case " .. index .. " left nothing behind")
		end
		for _, name in { "Bad", "", "1pack", "has space", "a:b" } do
			t.throws(function()
				Logic.register(name, { icons = {} })
			end, "pack name " .. name)
		end
		t.throws(function()
			Logic.register(nil :: any, { icons = {} })
		end)
	end,

	["optional fields default and an empty pack is allowed"] = function()
		Logic.reset()
		t.equal(Logic.register("empty", { icons = {} }), 0)
		t.equal(Logic.register("lean", { icons = { { name = "dot", category = "misc" } } }), 1)
		local entry = Logic.get("lean:dot") :: Logic.Entry
		t.deepEqual(entry.tags, {})
		t.equal(entry.width, 0)
		t.equal(entry.assetId, nil)
		t.equal(entry.id, "lean:dot")
	end,

	["names resolve qualified, unqualified and in any spelling"] = function()
		fresh()
		t.equal((Logic.get("game:sword") :: Logic.Entry).category, "weapons")
		t.equal((Logic.get("sword") :: Logic.Entry).id, "game:sword")
		t.equal((Logic.get("Sword Fire") :: Logic.Entry).id, "game:sword-fire")
		t.equal((Logic.get("swordFire") :: Logic.Entry).id, "game:sword-fire")
		t.equal((Logic.get("ui:arrow_left") :: Logic.Entry).id, "ui:arrow-left")
		t.equal((Logic.get("UI:close") :: Logic.Entry).id, "ui:close")
		t.equal((Logic.get("close") :: Logic.Entry).id, "ui:close", "falls through to the next pack")
		t.equal(Logic.get("ui:sword"), nil, "a qualified name never falls through")
		t.equal(Logic.get("nope:sword"), nil)
		t.equal(Logic.get("missing"), nil)
		t.equal(Logic.get(""), nil)
		t.equal(Logic.get(nil :: any), nil)
		t.truthy(Logic.has("coin"))
		t.falsy(Logic.has("ui:gem"))
	end,

	["the default pack wins unqualified names and can be changed"] = function()
		fresh()
		t.equal((Logic.get("coin") :: Logic.Entry).id, "game:coin")
		Logic.setDefaultPack("ui")
		t.equal(Logic.defaultPack(), "ui")
		t.equal((Logic.get("coin") :: Logic.Entry).id, "ui:coin")
		t.deepEqual(Logic.packs(), { "ui", "game" })
		t.equal((Logic.get("sword") :: Logic.Entry).id, "game:sword")
		Logic.setDefaultPack(nil)
		t.equal((Logic.get("coin") :: Logic.Entry).id, "game:coin")
		t.throws(function()
			Logic.setDefaultPack("nope")
		end)
		Logic.reset()
		Logic.register("game", gamePack())
		Logic.register("ui", uiPack(), { default = true })
		t.equal(Logic.defaultPack(), "ui")
	end,

	["unregister removes a pack and its default"] = function()
		fresh()
		Logic.setDefaultPack("ui")
		t.truthy(Logic.unregister("ui"))
		t.falsy(Logic.unregister("ui"))
		t.deepEqual(Logic.packs(), { "game" })
		t.equal(Logic.defaultPack(), "game")
		t.equal(Logic.get("close"), nil)
	end,

	["search ranks exact, prefix, word, substring, tag, tag prefix, category"] = function()
		fresh()
		t.deepEqual(Logic.search("sword"), {
			"game:sword", -- exact
			"game:sword-fire", -- prefix
			"game:broadsword", -- substring
			"game:shield", -- tag prefix ("swordsman")
		})
		t.deepEqual(Logic.search("fire"), { "game:sword-fire" }, "whole word inside the name")
		t.deepEqual(Logic.search("money"), { "game:coin" }, "tag")
		t.deepEqual(Logic.search("weap"), { "game:broadsword", "game:sword", "game:sword-fire" }, "tag prefix, by id")
		t.deepEqual(Logic.search("urren"), { "game:coin", "game:coin-stack", "game:gem" }, "category substring")
		t.deepEqual(Logic.search("stack"), { "game:coin-stack" })
		t.deepEqual(Logic.search("zzz"), {})
		t.deepEqual(Logic.search(""), {})
		t.deepEqual(Logic.search("   "), {})
		t.deepEqual(Logic.search(nil :: any), {})
	end,

	["search covers every pack, prefers the default pack on ties and honours limit and pack"] = function()
		fresh()
		t.deepEqual(Logic.search("coin"), { "game:coin", "ui:coin", "game:coin-stack" })
		t.deepEqual(Logic.search("coin", 1), { "game:coin" })
		t.deepEqual(Logic.search("ui:coin"), { "ui:coin" })
		t.deepEqual(Logic.search("Coin Stack"), { "game:coin-stack" })
		Logic.setDefaultPack("ui")
		t.deepEqual(Logic.search("coin", 2), { "ui:coin", "game:coin" })
		t.deepEqual(Logic.search("nope:coin"), {})
	end,

	["categories are sorted and can be per pack"] = function()
		fresh()
		t.deepEqual(Logic.categories(), { "armor", "buttons", "currency", "hud", "weapons" })
		t.deepEqual(Logic.categories("ui"), { "buttons", "hud" })
		t.deepEqual(Logic.categories("nope"), {})
	end,

	["list filters by pack, category, tag and mapped state"] = function()
		fresh()
		t.equal(#Logic.list(), 10)
		t.deepEqual(Logic.list({ pack = "ui" }), { "ui:arrow-left", "ui:close", "ui:coin" })
		t.deepEqual(Logic.list({ category = "currency" }), { "game:coin", "game:coin-stack", "game:gem" })
		t.deepEqual(Logic.list({ tag = "Fire" }), { "game:sword-fire" })
		t.deepEqual(Logic.list({ pack = "game", mapped = true }), {
			"game:broadsword",
			"game:coin",
			"game:gem",
			"game:sword",
		})
		t.deepEqual(
			Logic.list({ pack = "game", mapped = false }),
			{ "game:coin-stack", "game:shield", "game:sword-fire" }
		)
		t.deepEqual(Logic.list({ category = "buttons", tag = "back" }), { "ui:arrow-left" })
		t.deepEqual(Logic.list({ pack = "nope" }), {})
	end,

	["autocomplete matches name prefixes with a limit"] = function()
		fresh()
		t.deepEqual(Logic.autocomplete("sw"), { "game:sword", "game:sword-fire" })
		t.deepEqual(Logic.autocomplete("co"), { "game:coin", "game:coin-stack", "ui:coin" })
		t.deepEqual(Logic.autocomplete("co", 2), { "game:coin", "game:coin-stack" })
		t.deepEqual(Logic.autocomplete("ui:c"), { "ui:close", "ui:coin" })
		t.deepEqual(Logic.autocomplete("ui:"), { "ui:arrow-left", "ui:close", "ui:coin" })
		t.deepEqual(Logic.autocomplete("Arrow L"), { "ui:arrow-left" })
		t.equal(#Logic.autocomplete(""), 10)
		t.equal(#Logic.autocomplete("", 4), 4)
		t.deepEqual(Logic.autocomplete("zz"), {})
		t.equal(#Logic.autocomplete(nil :: any, 3), 3)
	end,

	["assetId and image give Roblox content strings only for uploaded icons"] = function()
		fresh()
		t.equal(Logic.assetId("sword"), "rbxassetid://1001")
		t.equal(Logic.assetId("sword-fire"), nil)
		t.equal(Logic.assetId("missing"), nil)
		t.deepEqual(Logic.image("game:coin"), { image = "rbxassetid://1004", width = 64, height = 64 })
		t.equal(Logic.image("sword-fire"), nil)
		t.equal(Logic.image("missing"), nil)
		t.deepEqual(
			Logic.image("ui:coin"),
			{ image = "rbxassetid://2002", width = 128, height = 128 },
			"an icon's own asset wins over its sheet"
		)
	end,

	["sheet icons resolve to the sheet image and rect once the sheet has an id"] = function()
		fresh()
		t.equal(Logic.image("ui:close"), nil, "sheet not uploaded yet")
		t.deepEqual(Logic.missingAssetIds("ui"), { "arrow-left", "close" })
		Logic.setSheetIds("ui", { "rbxassetid://9001" })
		t.deepEqual(Logic.image("ui:close"), {
			image = "rbxassetid://9001",
			rect = { x = 2, y = 2, w = 64, h = 64 },
			width = 64,
			height = 64,
		})
		t.equal(Logic.image("ui:arrow-left"), nil, "not on a sheet and no id")
		t.deepEqual(Logic.missingAssetIds("ui"), { "arrow-left" })
		t.deepEqual(Logic.list({ pack = "ui", mapped = true }), { "ui:close", "ui:coin" })
		t.throws(function()
			Logic.setSheetIds("ui", { 1, 2 })
		end)
		t.throws(function()
			Logic.setSheetIds("nope", { 1 })
		end)
		t.throws(function()
			Logic.setSheetIds("ui", { "bad" })
		end)
	end,

	["missingAssetIds lists what still needs uploading"] = function()
		fresh()
		t.deepEqual(Logic.missingAssetIds("game"), { "coin-stack", "shield", "sword-fire" })
		t.deepEqual(Logic.missingAssetIds("nope"), {})
		t.deepEqual(Logic.missingAssetIds(), {
			"game:coin-stack",
			"game:shield",
			"game:sword-fire",
			"ui:arrow-left",
			"ui:close",
		})
		local info = Logic.info("game") :: Logic.PackInfo
		t.equal(info.count, 7)
		t.equal(info.mapped, 4)
		t.equal(info.sheets, 0)
		t.deepEqual(info.categories, { "armor", "currency", "weapons" })
		t.equal(Logic.info("nope"), nil)
	end,

	["setAssetIds merges ids, reports unknown names and is atomic"] = function()
		fresh()
		local applied, unknown = Logic.setAssetIds("game", {
			["sword-fire"] = 5001,
			["Coin Stack"] = "rbxassetid://5002",
			["game:shield"] = "5003",
			ghost = 1,
			gem = 0,
		})
		t.equal(applied, 3)
		t.deepEqual(unknown, { "ghost" })
		t.equal(Logic.assetId("sword-fire"), "rbxassetid://5001")
		t.equal(Logic.assetId("coin-stack"), "rbxassetid://5002")
		t.equal(Logic.assetId("shield"), "rbxassetid://5003")
		t.equal(Logic.assetId("gem"), "rbxassetid://1007", "0 means no change")
		t.deepEqual(Logic.missingAssetIds("game"), {})
		t.throws(function()
			Logic.setAssetIds("game", { sword = 7, coin = "oops" })
		end)
		t.equal(Logic.assetId("sword"), "rbxassetid://1001", "a bad id changes nothing")
		t.throws(function()
			Logic.setAssetIds("nope", {})
		end)
	end,

	["parseAssetId accepts ids in the usual spellings"] = function()
		t.equal(Logic.parseAssetId(123), 123)
		t.equal(Logic.parseAssetId("123"), 123)
		t.equal(Logic.parseAssetId("rbxassetid://123"), 123)
		t.equal(Logic.parseAssetId(0), nil)
		t.equal(Logic.parseAssetId(""), nil)
		t.equal(Logic.parseAssetId(nil), nil)
		for _, bad in { -1, 1.5, "abc", "rbxassetid://", "http://x/123", true, {} } :: { any } do
			t.throws(function()
				Logic.parseAssetId(bad)
			end, tostring(bad))
		end
	end,

	["split and normalize"] = function()
		local pack, name = Logic.split("My:Arrow Left")
		t.equal(pack, "my")
		t.equal(name, "arrow-left")
		local none, plain = Logic.split("arrow_left")
		t.equal(none, nil)
		t.equal(plain, "arrow-left")
		t.equal(Logic.normalize("gemBlue"), "gem-blue")
	end,

	["gridLayout fits columns and computes the canvas height"] = function()
		local layout = Logic.gridLayout(10, 300, 64, 8)
		t.equal(layout.columns, 4) -- 4 * 64 + 3 * 8 = 280 <= 300
		t.equal(layout.rows, 3)
		t.equal(layout.height, 3 * 64 + 2 * 8)
		t.equal(Logic.gridLayout(800, 640, 72, 8).rows, 100)
		local narrow = Logic.gridLayout(5, 10, 64, 8)
		t.equal(narrow.columns, 1, "never fewer than one column")
		t.equal(narrow.rows, 5)
		local empty = Logic.gridLayout(0, 300, 64, 8)
		t.equal(empty.rows, 0)
		t.equal(empty.height, 0)
		t.equal(Logic.gridLayout(4, 256, 64).columns, 4, "gap defaults to 0")
	end,

	["visibleRange keeps only the rows near the viewport"] = function()
		local layout = Logic.gridLayout(800, 640, 72, 8) -- 8 columns, 100 rows, pitch 80
		t.equal(layout.columns, 8)
		local first, last = Logic.visibleRange(layout, 0, 400, 1)
		t.equal(first, 1)
		t.equal(last, 56) -- rows 0..5 visible plus one overscan row = 7 rows
		first, last = Logic.visibleRange(layout, 800, 400, 1)
		t.equal(first, 9 * 8 + 1) -- row 10 is the first visible; one overscan row above
		t.equal(last, 17 * 8)
		first, last = Logic.visibleRange(layout, 100 * 80, 400, 1)
		t.equal(last, 800, "clamped to the item count")
		t.truthy(first <= last)
		first, last = Logic.visibleRange(layout, 0, 400, 0)
		t.equal(last, 48)
		first, last = Logic.visibleRange(layout, -50, 400, 0)
		t.equal(first, 1)
		first, last = Logic.visibleRange(Logic.gridLayout(0, 640, 72, 8), 0, 400)
		t.equal(first, 1)
		t.equal(last, 0)
		first, last = Logic.visibleRange(layout, 0, 0)
		t.equal(last, 0)
		local short = Logic.gridLayout(5, 640, 72, 8)
		first, last = Logic.visibleRange(short, 0, 400, 2)
		t.equal(first, 1)
		t.equal(last, 5)
	end,

	["cellPosition places items row by row"] = function()
		local layout = Logic.gridLayout(10, 300, 64, 8)
		local x, y = Logic.cellPosition(layout, 1)
		t.equal(x, 0)
		t.equal(y, 0)
		x, y = Logic.cellPosition(layout, 4)
		t.equal(x, 3 * 72)
		t.equal(y, 0)
		x, y = Logic.cellPosition(layout, 5)
		t.equal(x, 0)
		t.equal(y, 72)
		x, y = Logic.cellPosition(layout, 10)
		t.equal(x, 72)
		t.equal(y, 144)
	end,

	["an 800-icon pack registers and searches"] = function()
		Logic.reset()
		local icons: { any } = {}
		for index = 1, 800 do
			local category = "cat-" .. tostring(index % 16)
			table.insert(icons, icon(string.format("icon-%03d", index), category, { "icon", category }, index % 2))
		end
		t.equal(Logic.register("big", { pack = "big", icons = icons }), 800)
		t.equal(#Logic.categories("big"), 16)
		t.equal(#Logic.search("icon-0", 50), 50)
		t.deepEqual(Logic.search("icon-777"), { "big:icon-777" })
		t.equal(#Logic.missingAssetIds("big"), 400)
		t.equal(#Logic.list({ pack = "big", category = "cat-3" }), 50)
		Logic.reset()
	end,
}
