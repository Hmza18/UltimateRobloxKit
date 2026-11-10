--!strict
-- Parity with the Python twin (tools/ui/spec_rules.py): both validators must accept the shared valid
-- fixtures and report the expected error paths for the shared invalid fixtures in
-- tests/fixtures/ui-specs (repository root). In a game project copy the fixtures are absent, so the
-- tests return early: parity only needs checking in the kit's own CI.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local SpecSchema = require("../src/UI/Spec/SpecSchema")
local t = require("./lib/t")

local function fixtureRoot(): string?
	for _, candidate in { "../tests/fixtures/ui-specs", "tests/fixtures/ui-specs", "../../tests/fixtures/ui-specs" } do
		if fs.isDir(candidate) then
			return candidate
		end
	end
	return nil
end

local function readJson(path: string): any
	return serde.decode("json", fs.readFile(path))
end

local function paths(issues: { { path: string, message: string } }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, issue in issues do
		set[issue.path] = true
	end
	return set
end

return {
	["valid shared fixtures pass the Luau schema"] = function()
		local root = fixtureRoot()
		if root == nil then
			return
		end
		local count = 0
		for _, name in fs.readDir(root .. "/valid") do
			if string.sub(name, -5) == ".json" then
				count += 1
				local issues = SpecSchema.validate(readJson(root .. "/valid/" .. name))
				local first = if issues[1] then issues[1].path .. " " .. issues[1].message else ""
				t.equal(#issues, 0, name .. ": " .. first)
			end
		end
		t.truthy(count >= 1, "at least one valid fixture")
	end,

	["invalid shared fixtures report the same paths as Python"] = function()
		local root = fixtureRoot()
		if root == nil then
			return
		end
		local expected: { [string]: { string } } = readJson(root .. "/invalid/expected.json")
		local checked = 0
		for name, wanted in expected do
			local issues = SpecSchema.validate(readJson(root .. "/invalid/" .. name .. ".json"))
			local got = paths(issues)
			for _, path in wanted do
				t.truthy(got[path], name .. " should report " .. path)
			end
			checked += 1
		end
		t.truthy(checked >= 15, "every invalid fixture checked")
	end,

	-- `motion` ids: the Python twin keeps a copy of UIPresets.registry:ids() in MOTION_PRESETS.
	["the Python motion preset list mirrors the Luau registry"] = function()
		local path: string? = nil
		for _, candidate in { "../tools/ui/spec_rules.py", "tools/ui/spec_rules.py", "../../tools/ui/spec_rules.py" } do
			if fs.isFile(candidate) then
				path = candidate
			end
		end
		if path == nil then
			return
		end
		local source = fs.readFile(path)
		local block = string.match(source, "MOTION_PRESETS = %[(.-)%]")
		t.truthy(block ~= nil, "MOTION_PRESETS list found in spec_rules.py")
		local mirrored: { string } = {}
		for id in string.gmatch(block :: string, '"([%w_]+)"') do
			table.insert(mirrored, id)
		end
		table.sort(mirrored)
		local ids = table.clone(SpecSchema.MOTION_PRESETS)
		table.sort(ids)
		t.truthy(#ids >= 60, "the Visuals UI presets are loaded")
		t.deepEqual(mirrored, ids)
	end,

	["element types and their fields match the Python twin"] = function()
		local path: string? = nil
		for _, candidate in { "../tools/ui/spec_rules.py", "tools/ui/spec_rules.py", "../../tools/ui/spec_rules.py" } do
			if fs.isFile(candidate) then
				path = candidate
			end
		end
		if path == nil then
			return
		end
		local source = fs.readFile(path)
		local count = 0
		for name, required, optional in string.gmatch(source, '\n "(%a+)": %((%b[]), (%b[]),') do
			count += 1
			local def = SpecSchema.ELEMENT_TYPES[name]
			t.truthy(def ~= nil, name .. " exists in Luau")
			local function names(list: string): { string }
				local out: { string } = {}
				for field in string.gmatch(list, '"(%a+)"') do
					table.insert(out, field)
				end
				table.sort(out)
				return out
			end
			local wantRequired = table.clone(def.required)
			table.sort(wantRequired)
			local wantOptional = table.clone(def.optional)
			table.sort(wantOptional)
			t.deepEqual(names(required), wantRequired, name .. " required")
			t.deepEqual(names(optional), wantOptional, name .. " optional")
		end
		t.equal(count, #SpecSchema.TYPE_NAMES, "every element type is in the Python table")
	end,
}
