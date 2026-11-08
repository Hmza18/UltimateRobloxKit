--!strict
-- The bundled CC0 Kenney packs register cleanly next to the kit's own icons.
local IconCatalog = require("../src/Icons/IconCatalog")
local KenneyColor = require("../src/Icons/Packs/KenneyColor")
local KenneyGame = require("../src/Icons/Packs/KenneyGame")
local t = require("./lib/t")

return {
	["kenney packs register without name clashes"] = function()
		IconCatalog.register(KenneyGame :: any)
		IconCatalog.register(KenneyColor :: any)
		t.truthy(IconCatalog.has("kenney-arrow-down"))
		local rect = IconCatalog.rect("kenney-arrow-down")
		t.truthy(rect ~= nil)
		t.equal((rect :: any).pack, "kenneygame")
		t.equal((rect :: any).w, 112)
		t.truthy(#KenneyGame.icons >= 180)
		t.truthy(#KenneyColor.icons >= 15)
		t.throws(function()
			IconCatalog.register(KenneyGame :: any)
		end)
	end,
}
