---
name: roblox-ui-testing
description: Testing Roblox UI built with UrkUI - what can be automated (Lune specs for pure Core and Spec modules, Python spec validation with shared Luau parity fixtures in tests/fixtures/ui-specs, HTML preview capture for visual regression with capture_server and ?capture) and what needs Studio (the playground checklist, multi-device emulation, a gamepad-only pass, reduced motion, purchase prompt tests), with honest reporting of each. Use when adding tests for UI code, before shipping a screen, after changing tokens, specs or components, or when asked whether the UI works.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [test the ui, ui tests, visual regression, ui snapshot, spec fixtures, playground checklist, gamepad-only test, ui test plan, ui interaction, test our ui, screenshot my ui, compare with the reference, compare it with the reference, score the ui]
  depends: [gameplay-testing]
---

# Roblox UI testing

## Purpose

Prove as much of the UI as possible with machines, then run a short, fixed manual pass for the Roblox-only parts, and report the two separately.

## When to use (and not)

- Use: new screen, new component, token or style change, spec format change, release candidate.
- Not for gameplay systems: `gameplay-testing`. Not for a design review: `roblox-ui-audit`.

## What can be automated

| Layer | Tool | Command |
|---|---|---|
| Pure UI logic (`Core/*`: Breakpoints, TextFit, MotionPresets, SpatialNav, Store, Format, Contrast ...) and `Spec/SpecSchema` | Lune specs in `library/tests/ui_*.spec.luau` | `cd library && lune run tests/run` |
| Spec rules (Python twin) and every built-in screen | `tests/test_ui_specs.py` | `python3 -m unittest tests/test_ui_specs.py` |
| Python vs Luau validator parity | shared fixtures `tests/fixtures/ui-specs/valid` and `invalid`, read by both test suites | both commands above |
| Your game's specs | the validator | `python3 $URK/urk.py ui validate src/shared/UrkScreens/*.json` |
| Tokens up to date | build check | `python3 $URK/urk.py ui tokens --check` (kit repo) |
| Icons | catalog tests and art validator | `python3 -m unittest tests/test_icons.py`, `python3 $URK/tools/icons/validate_icon.py <png>` |
| Visual regression (approximate) | preview + capture | below |
| Static checks of Roblox modules | Selene, StyLua, luau-analyze | CI (`.github/workflows/ci.yml`) |

## Workflow

1. **Pure logic first.** Put decisions in pure modules (what to show, which state, fits or not) so they can be Lune-tested. Example spec skeleton:
   ```lua
   --!strict
   local t = require("./lib/t")
   local TextFit = require("../src/UI/Core/TextFit")
   -- assert that a 20-character title fits a 150 px card at the minimum size or reports overflow
   ```
   Follow the style of `library/tests/ui_textfit.spec.luau` and `ui_motionpresets.spec.luau`.
2. **Spec fixtures.** When you add a validation rule, add one valid and one invalid fixture to `tests/fixtures/ui-specs/` with the expected message; both validators must agree (the Luau side is the parity spec in `library/tests/`).
3. **Validate all game specs** in CI with `urk.py ui validate` (exit 1 on any failure).
4. **Visual regression**:
   ```bash
   python3 $URK/tools/ui/preview_spec.py --all -o build/ui
   python3 $URK/tools/ui/capture_server.py build/ui --out build/ui/captures --port 8767
   # open http://127.0.0.1:8767/PetSimShop.html?capture=PetSimShop in a browser; the page posts its PNG
   ```
   Keep approved captures (for example `docs/images/ui/`) and compare new ones side by side or with an image diff. It catches layout, palette and copy regressions, not Roblox rendering.
5. **Studio playground pass** (`library/examples/playground`, `rojo serve library/examples/playground/playground.project.json`), checklist below.
6. **Report** with the template in Validation.

## Studio checklist (manual, NEEDS MANUAL REVIEW until done)

- [ ] Every screen in "All screens" builds without errors in Output.
- [ ] Device emulator: small phone landscape, notched phone, tablet, 1080p desktop, Xbox console (see `roblox-responsive-layout`).
- [ ] Gamepad-only pass: open, navigate, buy, close every window with a controller; focus visible, B closes, no traps.
- [ ] Keyboard and mouse: hover states, Escape closes.
- [ ] Reduced motion: `UrkUI.setReducedMotion(true)`; every animation jumps to its end, nothing is stuck mid-state, claim and purchase feedback still visible.
- [ ] Animation gallery: each `MotionPresets.names()` preset plays and Stop restores.
- [ ] Binds: change `Stats.Cash` and `Stats.Level` attributes on the player; counters and bars follow.
- [ ] Purchase prompts: with real ids in a test place, a product and a game pass prompt appears (Studio test purchase), the server grants once, the card shows owned. The playground itself has no server, so test grants in your game place.
- [ ] Open and close each window 10 times; `#PlayerGui:GetDescendants()` returns to the same number.

## Conventions

- Test names say the behaviour ("title over 60 characters is rejected").
- Fixtures are small, one problem each, named for the problem (`bad-palette.json`).
- Captures are named after the spec id and reviewed by a person before they become the baseline.

## Common mistakes

- Calling a screen "tested" because the spec validates.
- Calling a screen "works in Roblox" from an HTML preview.
- Testing Roblox-only modules (Game components, Builder) in Lune: they need Roblox globals; test their pure helpers instead.
- Changing a validator rule without a fixture: Python and Luau drift.
- Skipping the gamepad pass because "nobody uses controllers": console players do, and focus bugs are often S1.

## Example

Adding a `badge` length rule: add `invalid/badge-too-long.json` (13 characters), update `tools/ui/spec_rules.py` and `Spec/SpecSchema.luau`, run both suites, then preview `PremiumStore` to confirm existing badges still fit.

## Validation

Report template:

```markdown
UI test report <date>
Automated: lune run tests/run PASS (n specs) | test_ui_specs PASS | urk.py ui validate 6/6 PASS
Preview captures: build/ui/captures/*.png compared with baseline: 1 intended change (PetShop banner)
Studio: NOT RUN (Studio unavailable) -> every Studio checklist item NEEDS MANUAL REVIEW
```

Never merge these lines into one "all tests pass".

## Limitations

- Builder, Game components and Runtime services have no automated runtime tests here; only Studio proves them.
- HTML captures approximate fonts, UIStroke and gradients.
- Real purchases, console hardware and phone performance cannot be automated from this kit.
