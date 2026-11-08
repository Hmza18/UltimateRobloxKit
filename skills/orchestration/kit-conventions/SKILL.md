---
name: kit-conventions
description: Shared rules for every UltimateRobloxKit workflow - units and axes, naming, folder layout, validation gates, checkpoints, error recovery, honesty about what was and was not verified, and the stop rules for publishing and approvals. Use once at the start of any kit workflow, and whenever deciding whether a step is done or may proceed.
license: MIT
metadata:
  category: orchestration
  version: 1.0.0
  triggers: [conventions, naming convention, checkpoint, approval, definition of done, stop rule]
  depends: []
---

# Kit conventions

## Stop rules (never break)

1. Never publish, upload to Roblox, change a live place or spend Robux without the user's explicit permission in chat for that action.
2. Never mark work approved without the user saying so. Batches wait at `awaiting-approval`.
3. Only the user signs in to Roblox, GitHub or any service. Never handle passwords. API keys live in environment variables or CI secrets, never in files.
4. Never claim a check passed that did not run. Studio import, live playtests and device tests are `NEEDS MANUAL REVIEW` until someone does them.
5. Never run a third-party installer script. Fetch pinned commits with `scripts/install/third_party.py` and read what you copy.

## Units, axes and naming

- 1 Blender unit = 1 stud. Blender: front -Y, up +Z, origin bottom-centre on Z = 0, transforms applied. Roblox: front -Z, up +Y after the FBX conversion.
- Meshes `SM_<Asset>`, materials `M_<Asset>`, textures `T_<Asset>.png` or `<Asset>.png`, one asset per folder `<out>/<Asset>/`.
- Luau: PascalCase modules and services, camelCase locals, `--!strict` at the top, one module per file.
- Server code in `src/server`, client in `src/client`, shared in `src/shared` (Rojo).

## Project memory

At the start of a task in a game project, read `python3 $URK/urk.py memory context --project <dir>` and follow the recorded decisions and conventions. When the user settles a decision, record it with `urk memory add decision "..."`. Never store secrets or personal data there.

## Checkpoints

After each step write a short progress line to the user: what is done, what was verified and how, what is next. For multi-hour work keep `PROGRESS.md` in the project with the same three columns, so a new session can resume.

## Validation gates

| Area | Gate |
|---|---|
| Luau | `selene src`, `stylua --check src`, `lune run tests/run` (pure logic) pass; Studio playtest is manual |
| Data | Schema version bumped with a migration; session lock tested with two Studio servers or marked manual |
| Assets | `asset_batch.py` reports no FAIL; renders inspected by eye; Studio import manual |
| UI | Checked at phone, tablet and desktop sizes in Studio's device emulator |
| Release | `production-management` release checklist complete |

## Parallel agents

One owner per file, contracts in `Types.luau`/`Config.luau` first, claim tasks in `PROGRESS.md`, and a read-only reviewer last. Details and the role table: `docs/architecture/agent-cooperation.md`.

## Error recovery

1. Read the actual error (log file, Output window, exit code). Do not guess.
2. Fix the cause in shared code or the generator, not one output.
3. Re-run only the failed stage, then the full gate.
4. After three failed attempts on the same issue, stop, report what was tried and ask.

## Limitations

These rules are instructions; agents follow them, but only CI and the scripts enforce them mechanically.
