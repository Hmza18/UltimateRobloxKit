--!strict
-- TagSpec: tag/attribute reference, attribute reading, Action and menu parsing, README coverage.

local fs = require("@lune/fs")
local t = require("./lib/t")
local TagSpec = require("../src/UI/Core/TagSpec")

local function getter(values: { [string]: any }): (name: string) -> any
	return function(name: string): any
		return values[name]
	end
end

return {
	["every tag is prefixed Urk and documents its attributes"] = function()
		local names = TagSpec.names()
		t.truthy(#names >= 17, "all required tags are declared")
		for _, name in names do
			t.equal(string.sub(name, 1, 3), "Urk", name)
			local def = TagSpec.tags[name]
			t.truthy(#def.description > 0, name .. " description")
			for attribute, spec in def.attributes do
				t.truthy(#spec.description > 0, name .. "." .. attribute .. " description")
			end
		end
	end,

	["read applies defaults and reports wrong kinds and missing required attributes"] = function()
		local attributes = { PanelId = "Shop", Modal = true, AdoptPriority = "high" }
		local values, warnings = TagSpec.read("UrkPanel", getter(attributes))
		t.equal(values.PanelId, "Shop")
		t.equal(values.Modal, true)
		t.equal(values.Exclusive, true, "default")
		t.equal(values.AdoptPriority, 0, "wrong kind falls back to the default")
		t.equal(#warnings, 1)
		local _, missing = TagSpec.read("UrkBind", getter({}))
		t.equal(#missing, 1)
		t.truthy(string.find(missing[1], "Path") ~= nil)
		t.throws(function()
			TagSpec.read("NotATag", getter({}))
		end)
	end,

	["read accepts Roblox types through an injected typeof"] = function()
		local fakeColor = { isColor = true }
		local function fakeTypeof(value: any): string
			if type(value) == "table" and value.isColor then
				return "Color3"
			end
			return type(value)
		end
		local values, warnings = TagSpec.read("UrkIcon", getter({ Icon = "coin", IconColor = fakeColor }), fakeTypeof)
		t.truthy(values.IconColor == fakeColor)
		t.equal(#warnings, 0)
	end,

	["parseAction splits calls and arguments"] = function()
		local calls = TagSpec.parseAction("OpenPanel:Shop; ShowToast: Saved , success ;Back")
		t.equal(#calls, 3)
		t.equal(calls[1].name, "OpenPanel")
		t.deepEqual(calls[1].args, { "Shop" })
		t.deepEqual(calls[2].args, { "Saved", "success" })
		t.equal(calls[2].raw, "Saved , success")
		t.equal(calls[3].name, "Back")
		t.deepEqual(calls[3].args, {})
		t.deepEqual(TagSpec.parseAction(nil), {})
		t.deepEqual(TagSpec.parseAction("  ;; "), {})
		t.deepEqual(TagSpec.parseAction("not valid!"), {}, "junk is ignored")
	end,

	["parseMenuItems reads labels, actions and separators"] = function()
		local items = TagSpec.parseMenuItems("Equip=EquipItem; - ;Drop all = DropItem:all;Info")
		t.equal(#items, 4)
		t.deepEqual(items[1], { label = "Equip", action = "EquipItem", separator = false })
		t.truthy(items[2].separator)
		t.equal(items[3].label, "Drop all")
		t.equal(items[3].action, "DropItem:all")
		t.equal(items[4].action, nil, "a label without an action")
	end,

	["prefixed collects attribute families"] = function()
		local attributes = { Arg_count = 3, Arg_name = "Ana", ArgPath_cash = "Stats.Cash", Key = "x" }
		t.deepEqual(TagSpec.prefixed(attributes, "Arg_"), { count = 3, name = "Ana" })
	end,

	["README documents every tag and attribute"] = function()
		local path = if fs.isFile("src/UI/README.md") then "src/UI/README.md" else "../src/UI/README.md"
		local readme = fs.readFile(path)
		for name, def in TagSpec.tags do
			t.truthy(string.find(readme, "`" .. name .. "`", 1, true) ~= nil, "README is missing tag " .. name)
			for attribute in def.attributes do
				local documented = string.find(readme, "`" .. attribute .. "`", 1, true) ~= nil
				t.truthy(documented, "README is missing " .. attribute)
			end
		end
	end,
}
