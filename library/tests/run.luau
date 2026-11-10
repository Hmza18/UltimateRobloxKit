--!strict
-- Lune test runner. From library/: `lune run tests/run`
-- Loads every tests/*.spec.luau file. A spec returns a table of test name -> function,
-- and a test fails by raising an error. Exits with code 1 if anything fails.

local fs = require("@lune/fs")
local process = require("@lune/process")

-- Optional first argument: the folder holding the specs (e.g. `lune run tests/urk/run tests/urk`).
local TESTS_DIR = process.args[1] or (if fs.isDir("tests") then "tests" else ".")
-- Optional second argument: only run spec files whose name starts with this prefix
-- (e.g. `lune run tests/run tests visuals_`).
local FILTER = process.args[2]

local specFiles: { string } = {}
for _, fileName in fs.readDir(TESTS_DIR) do
	local wanted = FILTER == nil or string.sub(fileName, 1, #FILTER) == FILTER
	if wanted and string.sub(fileName, -10) == ".spec.luau" then
		table.insert(specFiles, fileName)
	end
end
table.sort(specFiles)

local passed, failed = 0, 0

for _, fileName in specFiles do
	-- Relative requires resolve from this file, so "./name.spec" is tests/name.spec.luau.
	local modulePath = "./" .. string.sub(fileName, 1, -6)
	local loaded, cases = pcall(function(): any
		return require(modulePath)
	end)
	if not loaded or type(cases) ~= "table" then
		failed += 1
		print(string.format("FAIL %s (could not load: %s)", fileName, tostring(cases)))
		continue
	end
	local names: { string } = {}
	for name in cases do
		table.insert(names, tostring(name))
	end
	table.sort(names)
	for _, name in names do
		local ok, err = pcall(cases[name])
		if ok then
			passed += 1
			print(string.format("PASS %s > %s", fileName, name))
		else
			failed += 1
			print(string.format("FAIL %s > %s\n     %s", fileName, name, tostring(err)))
		end
	end
end

print(string.format("\n%d passed, %d failed, %d spec files", passed, failed, #specFiles))
if failed > 0 or passed == 0 then
	process.exit(1)
end
