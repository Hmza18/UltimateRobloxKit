---
name: uvk-visual-testing
description: Testing visuals built with UltimateVisualsKit - Lune specs with a stepped clock for timing, cancellation, restoration, budgets and preset validity, the lint, format and type checks, the catalog freshness checks, and the manual Roblox Studio checklist for everything that cannot be proven without the engine (looks, feel, devices, input, performance). Use when writing a spec for a new preset or recipe, deciding what a visual change needs to be called done, or reporting honestly what was and was not verified.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [visual testing, test the effect, test the animation, visuals spec, stepped clock, studio checklist, manual review, verify visuals, test preset, playtest checklist, test the visuals]
  depends: [uvk-visuals-kit]
---

# UVK visual testing

Two layers. Pure logic is proven with Lune. Anything that creates an Instance or must be judged by eye is `NEEDS MANUAL REVIEW` until a person runs it in Studio. Never merge the two in a report.

## When to use

- A preset, recipe, rarity, theme or timing plan was added or changed.
- A visual feature is about to be called done.

When not to use: gameplay system tests (`gameplay-testing`); static UI spec validation and screenshot comparison (`roblox-ui-testing`).

## Inputs

- What changed: data (preset, recipe, profile), pure logic, or runtime code that touches Instances.
- The toolchain: `lune`, `stylua`, `selene`, and `rojo` for a build check.

## Workflow

1. **Put decisions in pure modules.** Timing plans, layouts, state machines and budgets belong in a `*Logic.luau`, `*Presets.luau` or `*Data.luau` file with no Roblox globals. Runtime files stay thin. That is what makes them testable.

2. **Write a spec with a stepped clock.** Specs return a table of test name to function; a test fails by raising an error.

   ```lua
   --!strict
   -- tests/visuals_chest.spec.luau (in a project: tests/urk/...)
   local Clock = require("../src/Visuals/Core/Clock")
   local Sequence = require("../src/Visuals/Core/Sequence")
   local t = require("./lib/t")

   return {
   	["a skipped chest sequence still opens the chest and cleans up once"] = function()
   		local clock = Clock.new()
   		local played: { string } = {}
   		local opened, cleaned = false, 0
   		local sequence = Sequence.new({
   			clock = clock,
   			play = function(name: string) table.insert(played, name) return nil end,
   		})
   			:Play("TreasureOpen")
   			:Wait(0.5)
   			:Call(function() opened = true end)
   			:Play("CoinBurst")
   			:Cleanup(function() cleaned += 1 end)
   			:Start()
   		clock:step(0.1)
   		sequence:Skip()
   		clock:step(1)
   		t.equal(opened, true)          -- Call steps still fire when skipped
   		t.equal(cleaned, 1)
   		t.equal(clock:count(), 0)      -- nothing left running
   	end,
   }
   ```

   Model new specs on `visuals_engine.spec.luau` and `visuals_sequence.spec.luau` in the library's tests; check the helper names in `tests/lib/t.luau` before using them.

3. **What a spec should prove.**
   - Every new preset validates (`EffectLogic.validate`, `UILogic.validate`, `Registry.validate`) and has id, name, category, description.
   - Timing: total duration, the order of beats, and that rarity tiers never get shorter or simpler with rank.
   - Cancel and skip: state ends correct, cleanup runs exactly once, stopping twice is harmless.
   - Restoration: values return to rest after `stop(true)`.
   - Budgets: the preset's cost on Low and High stays inside the profile.
   - Reduced motion and reduced flashing: loops do not start, flashes are removed.
   - Throttle and coalescing for anything fired rapidly.

4. **Run the checks.**

   ```bash
   lune run tests/urk/run tests/urk
   ```

   ```bash
   stylua --check src tests && selene src
   ```

   ```bash
   rojo build -o game.rbxl
   ```

   In the kit repository:

   ```bash
   cd library && lune run tests/run tests visuals_ && stylua --check src tests examples && selene src tests examples
   ```

   ```bash
   cd library && lune run tools/export_visuals --check && cd .. && python3 scripts/automation/build_visuals_refs.py --check
   ```

   The last line fails when `catalog/visuals.json` or the generated preset tables are stale; regenerate with the same commands without `--check`.

5. **Run the manual Studio pass** with [references/studio-checklist.md](references/studio-checklist.md). Record each item as done, failed or not run, with the device or emulator profile. Use the `Visuals.Debug` overlay while testing.

6. **Report in three parts**: what was run and its result (commands and numbers), what was not run and why, and the `NEEDS MANUAL REVIEW` list. Do not write "works" or "verified" for anything in the third part.

## Outputs

- A spec file per changed pure module, passing; a filled Studio checklist or an explicit list of unrun items.

## Validation

The spec suite passes, the formatter and linter are clean, the project builds with Rojo, and the report separates proven from unproven.

## Pitfalls

- **Testing with real time** (`task.wait`) instead of stepping a clock: slow, flaky and unable to test cancellation.
- **Logic inside the runtime file**, where no spec can reach it.
- **Asserting on looks** in a spec ("looks bouncy"). Assert on numbers: overshoot above 1, settle time under a bound.
- **Calling a Rojo build a playtest.** A build proves the tree compiles into a place file, nothing more.
- **Reporting Lune results as Studio results.**
- **Skipping the reduced-motion and Low-quality paths**; they take different code paths by design.

## Limitations

- Lune cannot create Instances, render, play sound or read input. It proves logic only.
- `luau-lsp` with Roblox type definitions catches wrong property and method names, not wrong behaviour.
- No automated in-engine test runs in this kit's CI; device performance and feel always need a person.
