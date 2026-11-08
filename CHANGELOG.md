# Changelog

All notable changes are listed here. Versions follow semantic versioning; the installer records the version in each project's manifest.

## 0.1.0 (2026-11-08)

First release.

- 44 skills across orchestration, Roblox engineering, toolchain, Blender, modeling, environments, UI, gameplay and production.
- `roblox-kit-router` skill, workflow recipes and the deterministic `route.py` router, tested with 25 routing cases.
- 6 subagents and 6 `/urk-*` slash commands.
- Installer with project, user, selective, dry-run, update, uninstall, backup, version-pin, MCP-merge and CLAUDE.md options, plus shell and PowerShell wrappers.
- Environment doctor and a pinned third-party skill fetcher.
- Procedural asset pipeline recovered from the supermarket project: 73 generators (61 recovered, 12 new), UV atlas, Blender build, FBX/OBJ/GLB export, re-import verification, QA, contact sheets, approval gates and packaging.
- `license-folder-delivery` skill: the user's `handoff/License<N>/` delivery format (`package_batch.py --license N`), the 51 approved supermarket objects as rebuildable shape references (`examples/supermarket-reference/`), and Roblox reference sizes.
- Rojo templates: starter game, simulator, tycoon, obby and UI kit, with Lune tests.
- CI on Linux, Windows and macOS, plus Blender 4.2 LTS and Luau toolchain jobs.
