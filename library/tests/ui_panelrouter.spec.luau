--!strict
-- PanelRouter: open/close/toggle/back, exclusive groups, modals, children and AdoptPriority.

local t = require("./lib/t")
local PanelRouter = require("../src/UI/Core/PanelRouter")

local function kinds(events: { PanelRouter.Event }): { string }
	local out: { string } = {}
	for _, event in events do
		table.insert(out, event.kind .. ":" .. event.id)
	end
	return out
end

local function setup(): PanelRouter.Router
	local router = PanelRouter.new()
	router:register("Shop", { group = "main" }, "shopGui")
	router:register("Inventory", { group = "main" }, "inventoryGui")
	router:register("Settings", {}, "settingsGui")
	router:register("Confirm", { modal = true, dismissible = false }, "confirmGui")
	return router
end

return {
	["open, close and toggle"] = function()
		local router = setup()
		t.deepEqual(kinds(router:open("Shop")), { "open:Shop" })
		t.truthy(router:isOpen("Shop"))
		t.deepEqual(kinds(router:open("Shop")), {}, "opening twice is a no-op")
		t.deepEqual(kinds(router:toggle("Shop")), { "close:Shop" })
		t.deepEqual(kinds(router:toggle("Shop")), { "open:Shop" })
		t.deepEqual(kinds(router:close("Settings")), {}, "closing a closed panel is a no-op")
	end,

	["exclusive groups replace each other"] = function()
		local router = setup()
		router:open("Settings")
		router:open("Shop")
		t.deepEqual(kinds(router:open("Inventory")), { "close:Shop", "open:Inventory" })
		t.deepEqual(router:stack(), { "Settings", "Inventory" }, "panels outside the group stay open")
	end,

	["non-exclusive groups can stack"] = function()
		local router = PanelRouter.new()
		router:register("A", { group = "side", exclusive = false }, 1)
		router:register("B", { group = "side", exclusive = false }, 2)
		router:open("A")
		router:open("B")
		t.deepEqual(router:stack(), { "A", "B" })
	end,

	["back closes the top panel in order"] = function()
		local router = setup()
		router:open("Settings")
		router:open("Shop")
		t.deepEqual(kinds(router:back()), { "close:Shop" })
		t.deepEqual(kinds(router:back()), { "close:Settings" })
		t.deepEqual(kinds(router:back()), {})
		t.falsy(router:canGoBack())
	end,

	["non-dismissible modals block back"] = function()
		local router = setup()
		router:open("Shop")
		router:open("Confirm")
		t.falsy(router:canGoBack())
		t.deepEqual(kinds(router:back()), {})
		t.truthy(router:isOpen("Confirm"))
		router:close("Confirm")
		t.deepEqual(kinds(router:back()), { "close:Shop" })
	end,

	["layers put modals above panels and follow stack order"] = function()
		local router = setup()
		router:open("Settings")
		router:open("Shop")
		router:open("Confirm")
		t.equal(router:layer("Settings"), 11)
		t.equal(router:layer("Shop"), 12)
		t.equal(router:layer("Confirm"), 53)
		t.equal(router:layer("Inventory"), nil, "closed panels have no layer")
		router:open("Settings")
		t.equal(router:top(), "Settings", "re-opening brings a panel to the top")
	end,

	["closing a parent closes its children"] = function()
		local router = setup()
		router:register("Details", {}, "detailsGui")
		router:register("Zoom", {}, "zoomGui")
		router:open("Shop")
		router:open("Details", { from = "Shop" })
		router:open("Zoom", { from = "Details" })
		router:open("Settings")
		t.deepEqual(kinds(router:close("Shop")), { "close:Zoom", "close:Details", "close:Shop" })
		t.deepEqual(router:stack(), { "Settings" })
	end,

	["closeAll closes everything or one group"] = function()
		local router = setup()
		router:open("Settings")
		router:open("Shop")
		t.deepEqual(kinds(router:closeAll("main")), { "close:Shop" })
		router:open("Inventory")
		t.equal(#router:closeAll(), 2)
		t.equal(router:top(), nil)
	end,

	["unknown panels are ignored"] = function()
		local router = setup()
		t.deepEqual(router:open("Nope"), {})
		t.falsy(router:isRegistered("Nope"))
		t.throws(function()
			router:register("", {}, "x")
		end)
	end,

	["AdoptPriority keeps the highest priority duplicate"] = function()
		local router = PanelRouter.new()
		router:register("Menu", { priority = 1 }, "copyA")
		local events = router:register("Menu", { priority = 5 }, "copyB")
		t.deepEqual(kinds(events), { "reject:Menu", "adopt:Menu" })
		t.equal(events[1].owner, "copyA", "the previous owner is rejected")
		t.equal(router:owner("Menu"), "copyB")
		local lower = router:register("Menu", { priority = 0 }, "copyC")
		t.deepEqual(kinds(lower), { "reject:Menu" })
		t.equal(lower[1].owner, "copyC")
	end,

	["equal priority keeps the first registration"] = function()
		local router = PanelRouter.new()
		router:register("Menu", {}, "first")
		router:register("Menu", {}, "second")
		t.equal(router:owner("Menu"), "first")
	end,

	["unregistering the active owner adopts the next candidate"] = function()
		local router = PanelRouter.new()
		router:register("Menu", { priority = 2 }, "high")
		router:register("Menu", { priority = 1 }, "low")
		router:open("Menu")
		local events = router:unregister("Menu", "high")
		t.deepEqual(kinds(events), { "adopt:Menu", "open:Menu" }, "the open panel stays open on its new owner")
		t.equal(router:owner("Menu"), "low")
		router:unregister("Menu", "low")
		t.falsy(router:isRegistered("Menu"))
		t.falsy(router:isOpen("Menu"))
	end,
}
