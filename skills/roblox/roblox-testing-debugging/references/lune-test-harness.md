# Lune test harness and bug report template

A dependency-free harness. Put `harness.luau` and `run.luau` in `tests/`; every `*.spec.luau` returns the harness after registering tests.

## tests/harness.luau

```lua
--!strict
type Case = { name: string, fn: () -> () }

local T = {}
local cases: { Case } = {}

function T.test(name: string, fn: () -> ())
	table.insert(cases, { name = name, fn = fn })
end

function T.equal(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(("%sexpected %s, got %s"):format(if message then message .. ": " else "", tostring(expected), tostring(actual)), 2)
	end
end

function T.near(actual: number, expected: number, tolerance: number)
	if math.abs(actual - expected) > tolerance then
		error(("expected %s +/- %s, got %s"):format(tostring(expected), tostring(tolerance), tostring(actual)), 2)
	end
end

function T.throws(fn: () -> ())
	local ok = pcall(fn)
	if ok then
		error("expected an error", 2)
	end
end

function T.run(): (number, number)
	local passed, failed = 0, 0
	for _, case in cases do
		local ok, err = pcall(case.fn)
		if ok then
			passed += 1
		else
			failed += 1
			print(("FAIL %s\n  %s"):format(case.name, tostring(err)))
		end
	end
	table.clear(cases)
	return passed, failed
end

return T
```

## tests/run.luau

```lua
--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")

local totalPassed, totalFailed = 0, 0
local specs = {}
for _, name in fs.readDir("tests") do
	if string.match(name, "%.spec%.luau$") then
		table.insert(specs, name)
	end
end
table.sort(specs)

for _, name in specs do
	local moduleName = string.gsub(name, "%.luau$", "")
	local T = (require :: any)("./" .. moduleName)
	local passed, failed = T.run()
	print(("%s: %d passed, %d failed"):format(name, passed, failed))
	totalPassed += passed
	totalFailed += failed
end

print(("TOTAL: %d passed, %d failed"):format(totalPassed, totalFailed))
process.exit(if totalFailed > 0 then 1 else 0)
```

Run with `lune run tests/run`. Dynamic `require` with a computed string works in Lune but not in Roblox's static require analysis; this runner is Lune-only. Check the Lune docs for your installed version if require resolution differs (paths are relative to the requiring file in current Lune).

## Bug report template

```
Title: <one line, observable symptom>
Place / version: <place id, published version number or git commit>
Server JobId (if live): <id>    Seed (if procedural): <seed>
Device / client: <PC, phone model, Studio version>

Steps (from a fresh join):
1.
2.
3.

Expected:
Actual:

Output (client):
<paste exact lines, with timestamps>
Output (server):
<paste exact lines>

Frequency: <always / 1 in N / once>
Minimal repro: <attached .rbxl or "not yet">
```
