---
description: Find and apply the right UltimateVisualsKit presets and components for a visual task
argument-hint: <what should look or feel better>
---
Task: $ARGUMENTS. Load `uvk-visuals-kit`, then only the `uvk-*` skill it points to for this task.

1. Search the preset catalog before proposing anything: `.claude/ultimate-roblox-kit/catalog/visuals.json` (inside the kit repository: `catalog/visuals.json`). Match by what the player should see, and list the candidate ids with their kind, cost and usage line.
2. Check the library is in the project (`src/shared/Urk/Visuals`); if not, propose `python3 .claude/ultimate-roblox-kit/urk.py add Visuals --project .` and wait for a yes.
3. Present a short plan: the trigger and how often it fires, the beats, the preset ids or components for each, the server event it waits for, and what stops it. Do not start implementing until the user confirms, unless they asked you to proceed.
4. Implement with the facade (`Visuals:Play`, `Visuals.UI`, `Visuals.Feedback`, `Visuals.Sequence` and the rest). Write a new preset only when nothing fits, register it through the registry, and say why.
5. Run the project's checks (`lune run tests/urk/run tests/urk`, `selene src`, `stylua --check src`) and report the results.

End with a `NEEDS MANUAL REVIEW` list: looks, feel, devices and frame cost cannot be confirmed without Roblox Studio.
