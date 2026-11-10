---
description: Review a project's visuals against the UltimateVisualsKit quality checklist
argument-hint: [path, default: the client source folder]
---
Audit $ARGUMENTS (default: `src/client` and any `Visuals` usage in `src/shared`). This is read-only: change nothing. Load `uvk-visuals-kit` and its `references/quality-checklist.md`; add `uvk-visual-performance` if effects are heavy.

Look for, with file:line for each finding:
- Hand-written effects that duplicate a preset: `Instance.new("ParticleEmitter")`, `TweenService` chains on UI, manual camera `CFrame` or `FieldOfView` writes, `task.wait` used for effect timing. Name the preset or component in `catalog/visuals.json` that replaces each.
- Visuals that play before the server confirms a result, or reward logic inside client visual code.
- Handles that are never stopped: looping `Attach`, `Objects.animate` loops, `Camera` moves, `UI.bind` bindings, pet animators and followers without a matching stop or destroy.
- Rapid events without a throttle, more than one attention loop on the HUD, high-cost presets on frequent events, shake on every tap.
- Missing accessibility: no way to set reduced motion, reduced flashing or intensity; full-screen flashes; information shown only by colour or hover.
- Rarity colours or timings defined in more than one place; third-party game names in ids, sample data or assets.

Report findings by severity (blocks release, should fix, polish) with a concrete fix for each, then the checklist with every item marked pass, fail, or not checkable here. Items that need Studio, a device or a measurement are `NEEDS MANUAL REVIEW`; do not mark them passed.
