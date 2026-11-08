--!strict
local t = require("./lib/t")
local IconCatalog = require("../src/Icons/IconCatalog")
local IconData = require("../src/Icons/IconData")

return {
	["every icon resolves and names are unique"] = function()
		local seen: { [string]: boolean } = {}
		for _, entry in IconData.icons do
			t.falsy(seen[entry.name], "duplicate " .. entry.name)
			seen[entry.name] = true
			t.truthy(IconCatalog.has(entry.name), entry.name)
		end
		t.truthy(#IconData.icons >= 80, "catalog has at least 80 icons")
	end,
	["names are normalised"] = function()
		t.truthy(IconCatalog.has("arrow_left"))
		t.truthy(IconCatalog.has("Arrow Left"))
		t.truthy(IconCatalog.has("arrowLeft"))
		t.falsy(IconCatalog.has("not-an-icon"))
	end,
	["rect is inside its cell and padded"] = function()
		local rect = IconCatalog.rect("coin")
		t.truthy(rect)
		if rect then
			t.equal(rect.w, IconData.cell - 2 * IconData.padding)
			t.truthy(rect.x >= 0 and rect.y >= 0 and rect.x + rect.w <= 1024 and rect.y + rect.h <= 1024)
		end
	end,
	["sheet ids are validated and applied"] = function()
		t.throws(function()
			IconCatalog.configure({ sheets = { "not an id" } })
		end)
		IconCatalog.configure({ sheets = { "rbxassetid://101", "rbxassetid://202" } })
		local rect = IconCatalog.rect("coin")
		t.truthy(rect and rect.image ~= nil)
	end,
	["aliases point at real icons only"] = function()
		IconCatalog.configure({ aliases = { money = "coins" } })
		t.truthy(IconCatalog.has("money"))
		t.throws(function()
			IconCatalog.configure({ aliases = { foo = "missing-icon" } })
		end)
	end,
	["search ranks exact, prefix, then tags"] = function()
		local results = IconCatalog.search("arrow")
		t.truthy(#results >= 4)
		t.equal(string.sub(results[1], 1, 5), "arrow")
		local tagged = IconCatalog.search("money")
		t.truthy(table.find(tagged, "coin") ~= nil, "tag search finds coin")
		t.equal(IconCatalog.search("coin")[1], "coin")
		t.equal(#IconCatalog.search("arrow", 2), 2)
		t.equal(#IconCatalog.search(""), 0)
	end,
	["imported packs register, search and resolve to their own sheets"] = function()
		IconCatalog.register({
			pack = "testpack",
			cell = 128,
			padding = 4,
			icons = {
				{
					name = "test-flame",
					category = "imported",
					tags = { "fire" },
					sheet = 1,
					x = 128,
					y = 0,
					w = 128,
					h = 128,
				},
			},
		})
		IconCatalog.configure({ pack = "testpack", sheets = { "rbxassetid://303" } })
		local rect = IconCatalog.rect("test-flame")
		t.truthy(rect)
		if rect then
			t.equal(rect.pack, "testpack")
			t.equal(rect.image, "rbxassetid://303")
			t.equal(rect.x, 132)
		end
		t.truthy(table.find(IconCatalog.search("fire"), "test-flame") ~= nil)
		t.throws(function()
			IconCatalog.register({
				pack = "other",
				cell = 128,
				padding = 0,
				icons = {
					{ name = "coin", category = "x", tags = {}, sheet = 1, x = 0, y = 0, w = 1, h = 1 },
				},
			})
		end)
	end,
	["list filters by category"] = function()
		local currency = IconCatalog.list("currency")
		t.truthy(table.find(currency, "gem") ~= nil)
		t.falsy(table.find(currency, "sword") ~= nil)
		t.truthy(#IconCatalog.list() >= #IconData.icons)
		t.equal(#IconCatalog.categories(), #IconData.categories)
	end,
}
