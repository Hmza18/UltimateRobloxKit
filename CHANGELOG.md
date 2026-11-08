# Changelog

All notable changes are listed here. Versions follow semantic versioning; the installer records the version in each project's manifest.

## 0.2.0 (2026-11-08)

Major expansion.

- **Luau library** (`library/`): 27 genre-neutral game systems. Pure Logic modules come with Lune specs, and server and client adapters are server-authoritative, with persistence injected. The library builds into an `.rbxm` model with Rojo.
- **UrkUI**: an original tag- and attribute-driven UI framework, inspired by the ideas in the paid General UI Kit but written independently. It covers panels and modals, actions, Store data binding, tabs, tooltips, toasts, context menus, drag and drop, 10 components, themes with contrast checks, breakpoints and safe areas, spatial gamepad navigation, a localizer with plurals, motion with reduced-motion support, and icons.
- **URK Icons**: 92 original MIT icons, with sprite sheets, a catalog, a Luau API, a gallery and `import_pack.py`. The BuiltByBit Free Icon Pack is not redistributed, because its licence could not be verified and BuiltByBit terms generally forbid redistribution; it can be imported locally instead.
- **`urk.py`**: setup with profiles, new, add (dependency closure, edit protection, remove), check, upgrade, uninstall, icons and dashboard.
- **Dashboard**: a self-contained HTML page for browsing skills, workflows, library modules and icons, building commands, and viewing the environment report.
- **Security**: a backdoor scanner (Python for text formats and source folders, Lune for binary models) with fixtures. CI now verifies binaries by SHA-256 and pins actions by commit.
- **Skills**: roblox-project-planner, luau-debugging, gameplay-testing, project-maintenance, urk-ui-framework, game-icons and component-library, for 51 in total. The testing skill now recommends Roblox Jest and rocale-cli. Studio MCP is refreshed from the official docs (macOS and Windows, 26 tools).
- **Agents**: urk-ui-designer, urk-test-engineer and urk-performance-optimizer, plus file-ownership cooperation rules.
- **Research V2**: 66 evaluated candidates, a gap analysis and a prioritized roadmap.
- **CI**: a library job (lint, format, strict analysis, Lune, rbxm build), Rojo place builds for every template, a project with every module, a scanner check, and a report-only whole-library type check.

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
