---
name: project-maintenance
description: Keeps an existing Roblox project healthy - upgrading UltimateRobloxKit skills and library modules safely, bumping Rokit and Wally pins, data schema migrations, refactors without behaviour change, removing dead code, tech-debt triage, and keeping docs and PROGRESS.md current. Use when updating dependencies or the kit, refactoring, cleaning up, or picking up an old project.
license: MIT
metadata:
  category: production
  version: 1.0.0
  triggers: [upgrade, update dependencies, refactor, tech debt, maintenance, bump version, clean up code, old project]
  depends: [kit-conventions]
---

# Project maintenance

## Workflow

1. **Baseline**: `python3 $URK/urk.py check .` and `python3 $URK/urk.py doctor --project .`; run the test suite and record the result before touching anything.
2. **Kit upgrade**: `git -C <kit> pull`, then `python3 <kit>/urk.py upgrade --project . --dry-run`. Read the plan: files you edited are kept and listed. Merge your edits by hand where the kit changed the same file, then run without `--dry-run`.
3. **Tool pins**: change one tool at a time in `rokit.toml`, `rokit install`, run Selene, StyLua and tests. StyLua upgrades can reformat code; commit formatting separately.
4. **Wally packages**: bump one package, read its changelog for breaking changes, `wally install`, test the systems that use it.
5. **Data migrations**: never edit old save shapes in place. Add a migration step (SaveData `migrations`), bump the schema version, test loading a saved sample from each previous version in a Lune spec.
6. **Refactors**: tests first for the behaviour you are keeping; move code in small commits; no behaviour change and refactor in the same commit.
7. **Tech-debt triage**: list items with impact (bugs, slowness, blocked features) and effort; fix high impact / low effort first; schedule the rest in PLAN.md.
8. **Docs**: update READMEs and PROGRESS.md in the same commit as the change.

## Validation

Same tests, Selene and StyLua results as the baseline or better; `urk.py check` shows no ERROR; data migration specs pass.

## Limitations

Upgrades of Roblox engine behaviour (API deprecations) are not detectable by these tools; read the Roblox release notes and DevForum announcements for the period you skipped.
