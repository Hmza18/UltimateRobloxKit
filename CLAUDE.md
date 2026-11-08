# UltimateRobloxKit: working in this repository

This repository is the kit's source. Projects receive it through `scripts/install/install.py`.

## Rules

- Skills are canonical only in `skills/<category>/<name>/`. `.claude/skills/` here is install output (git-ignored), so never edit it.
- Follow `docs/architecture/skill-format.md`. After adding, renaming or re-triggering a skill, run `python3 scripts/automation/build_catalog.py` and add a case to `tests/routing_cases.json`.
- Before calling anything done, run `python3 scripts/validate/run_all.py`. It must pass. Set `URK_SKIP_BLENDER=1` only when Blender is unavailable, and say so.
- Kit Python is stdlib-only and runs on Python 3.9+. Code inside `scripts/blender/` runs in Blender's own Python.
- Third-party content: add an entry to `third_party/manifest.json` and `SOURCES.md`. Never copy text from a source without a permissive license, and never run an upstream installer.
- Never claim Studio, Open Cloud or live-service behaviour works without exercising it. Use `NEEDS MANUAL REVIEW`.
- No secrets in files. API keys belong in environment variables or CI secrets.

## Map

| Path | What |
|---|---|
| `skills/` | 51 skills; `orchestration/roblox-kit-router` is the entry point |
| `library/` | Luau library: 36 systems, UrkUI, Icons, Util. Follow `docs/architecture/library-conventions.md`; specs in `library/tests/` |
| `assets/icons/`, `tools/icons/` | URK Icons and their generator; rebuild with `tools/icons/build_icons.py` |
| `urk.py` | single CLI over all scripts |
| `catalog/` | `workflows.json` (hand-written) and `skills.json` (generated) |
| `.claude/agents`, `.claude/commands` | Subagents and `/urk-*` commands (canonical, copied by the installer) |
| `scripts/install` | installer, doctor, third-party fetcher |
| `scripts/automation` | router, catalog builder, project scaffolder |
| `scripts/export`, `scripts/blender`, `tools/rbxasset` | asset pipeline |
| `scripts/validate` | `run_all.py`, `check_obj.py` |
| `templates/` | Rojo game templates and the asset-pipeline layout |
| `tests/` | unittest suites run by `run_all.py` and CI |
