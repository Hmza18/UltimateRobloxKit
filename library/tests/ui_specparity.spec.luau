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
}
