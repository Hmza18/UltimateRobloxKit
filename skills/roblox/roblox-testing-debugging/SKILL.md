---
name: roblox-testing-debugging
description: Testing and debugging Roblox code - unit tests for pure Luau with Lune, in-engine tests with Roblox's maintained Jest (roblox/jest), CI runs through rocale-cli or the Open Cloud Luau Execution API, the Studio debugger and breakpoints, Output, Developer Console (F9), MicroProfiler, ScriptProfiler, assert-based invariants and reproducible bug reports. Use when writing tests, setting up CI, chasing an error or crash, or profiling a slow script.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [unit test, lune, jest, rocale, luau execution, breakpoint, debugger, microprofiler, scriptprofiler, developer console, bug report]
  depends: [luau-language, roblox-toolchain-doctor]
---

# Roblox testing and debugging

## When to use

- Adding tests to game logic, setting up CI for a Rojo project.
- An error in Output, a script that silently does nothing, a crash or a lag spike.
- Writing a bug report someone else can reproduce.

When not to use: frame-rate and memory budgets are `roblox-performance`; installing Lune, Rojo and friends is `roblox-toolchain-doctor`; driving a live Studio session through MCP is `roblox-studio-mcp`.

## Inputs

- Project layout (Rojo `default.project.json`), where shared pure modules live.
- Tool versions pinned in `rokit.toml` (or `aftman.toml` / `foreman.toml` in older projects).
- For CI in-engine tests: an Open Cloud API key with Luau execution permission stored as a CI secret, plus universe and place ids of a **test** place.

## Test pyramid

| Layer | Tool | Runs where | What to test |
|---|---|---|---|
| Pure logic | Lune (`lune run`) | Any machine, CI, no Studio | Formulas, grids, parsers, state machines |
| In-engine | Jest for Roblox (`roblox/jest` 3.20.1 + `roblox/jest-globals`, MIT, maintained by Roblox) | Studio, rocale-cli, Open Cloud | Code using Instances and services |
| End-to-end | Manual or MCP-driven playtest | Studio / published test place | Remotes, UI, teleports, purchases |

## Workflow

1. **Split pure from engine code.** Keep logic in modules that only take plain values in and return values out. These run under Lune untouched (Roblox datatypes such as `Vector3` are available through `@lune/roblox`; others such as `Random` may not be, so pass a number generator in or verify in the Lune docs).
2. **Write Lune tests** with a tiny harness (see [references/lune-test-harness.md](references/lune-test-harness.md)) and run `lune run tests/run` locally and in CI.
3. **In-engine tests**: add Roblox's Jest as Wally dev-dependencies (`[dev-dependencies]` `Jest = "roblox/jest@3.20.1"`, `JestGlobals = "roblox/jest-globals@3.20.1"`; checked against the Wally registry on 2026-11-08), put `*.spec.luau` files next to modules, and run them from a Studio test runner script or CI. TestEZ is archived and jsdotlua/jest-lua has been inactive since 2024-12, so neither is recommended for new work.
4. **CI options for in-engine tests:**
   - **rocale-cli** (`Roblox/rocale-cli` 0.1.3, MIT, official): builds the place, uploads it and runs Luau through Open Cloud Luau Execution from the command line. Its README installs it through Foreman; check that the Rokit pin `Roblox/rocale-cli@0.1.3` works before relying on it. Use a dedicated test place and a key scoped to that place only. (`run-in-roblox` has been stale since 2024.)
   - **Open Cloud Luau Execution API**: upload a place version, create a Luau execution session task with your test script, poll for the result and logs. Runs on Roblox servers, no Studio needed. Endpoint paths and the required API key scope change occasionally; verify in creator docs (Open Cloud > Luau execution).
5. **Invariants.** Use `assert(cond, message)` at module boundaries for programmer errors (impossible states), and return `(false, reason)` for expected failures such as invalid player input. Never `assert` on client-sent data in a way that lets a client spam errors; validate and drop instead.
6. **Debugging in Studio:**
   - **Output** window: click an error to jump to the line. Turn on Script Analysis for type and lint errors before running.
   - **Breakpoints**: click the gutter; F5 to play; step over F10, step into F11 (verify shortcuts in Studio). Use **Watch** and **Call Stack**. Conditional breakpoints and logpoints avoid editing code.
   - Server vs client: in **Clients and Servers** test mode each window has its own Output; check both.
7. **Live and published games:** Developer Console (F9, or `/console` in chat) shows Log (client and server), Memory, Network, Script (activity per script), MicroProfiler and ScriptProfiler. Server logs require the right permissions on the experience.
8. **Profiling:** MicroProfiler (Ctrl+Alt+F6 to open, Ctrl+P to pause, verify shortcuts) shows frame timelines; wrap hot code in `debug.profilebegin("Label")` / `debug.profileend()` so it appears by name. ScriptProfiler (Developer Console tab or Studio Script Profiler) samples which functions use CPU.
9. **Bug reports** use the template in the reference: build/place version, steps from a fresh join, expected vs actual, Output lines (both sides), seed or server JobId, and a minimal repro place if possible.

### Example invariant-checked module and its spec

```lua
--!strict
-- ReplicatedStorage/Shared/Inventory.luau
export type Inventory = { capacity: number, slots: { [string]: number } }

local Inventory = {}

local function count(inv: Inventory): number
	local total = 0
	for _, n in inv.slots do
		total += n
	end
	return total
end

function Inventory.new(capacity: number): Inventory
	assert(capacity > 0 and capacity % 1 == 0, "capacity must be a positive integer")
	return { capacity = capacity, slots = {} }
end

function Inventory.add(inv: Inventory, id: string, amount: number): (boolean, string?)
	if amount <= 0 or amount % 1 ~= 0 then
		return false, "bad amount" -- expected failure, not an assert
	end
	if count(inv) + amount > inv.capacity then
		return false, "full"
	end
	inv.slots[id] = (inv.slots[id] or 0) + amount
	assert(count(inv) <= inv.capacity, "invariant: never above capacity")
	return true, nil
end

return Inventory
```

```lua
--!strict
-- tests/inventory.spec.luau (Lune, using the harness from the reference)
local T = require("./harness")
local Inventory = require("../src/shared/Inventory")

T.test("adds within capacity", function()
	local inv = Inventory.new(5)
	T.equal(Inventory.add(inv, "apple", 3), true)
	T.equal(inv.slots.apple, 3)
end)

T.test("rejects overflow and bad amounts", function()
	local inv = Inventory.new(2)
	local ok, why = Inventory.add(inv, "apple", 3)
	T.equal(ok, false)
	T.equal(why, "full")
	T.equal((Inventory.add(inv, "apple", 0.5)), false)
end)

return T
```

## Outputs

- `tests/` with Lune specs and a runner, `*.spec.luau` for in-engine tests, a CI workflow running both.
- Bug reports in the reference template.

## Validation

```bash
lune --version
lune run tests/run          # exits non-zero on any failure
rojo build default.project.json -o build.rbxl   # proves the project still builds
```

For in-engine CI, the job must fail when any spec fails: check the runner's exit code or the Luau execution task's state and output, not just that it ran.

## Pitfalls

- **Requires break under Lune**: Rojo instance paths (`script.Parent.X`) do not exist in Lune. Shared modules should use relative string requires (supported in both Roblox and Lune in current versions; verify with your Luau version) or be wrapped by a loader.
- **Tests depend on order or time**: seed every `Random`, inject `os.time` as a parameter.
- **Only testing the happy path**: test invalid input, which is what exploiters send.
- **`print` debugging left in**: spams Output and costs performance in hot paths. Remove or gate behind a `DEBUG` attribute.
- **Errors swallowed by pcall** with no log: always `warn` the error from a failed `pcall`.
- **Studio-only behaviour**: DataStores, teleports, badges and purchases behave differently or are mocked in Studio. Mark tests that need a live server.

## Limitations

- Lune cannot run code that needs real Instances, physics, rendering or networking.
- Neither tool here proves multiplayer timing bugs; those need multi-client playtests.
- Open Cloud Luau execution has time and quota limits and runs against a saved place version, not a live server; verify current limits in creator docs.
