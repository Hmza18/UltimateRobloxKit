# UltimateRobloxKit: execution master prompt and blueprint

This file is the plan the repository was built from. It is kept so future contributors, human or AI, can see why things are shaped the way they are. Paste the "Master prompt" section into a coding agent to extend the kit the same way.

## Master prompt

> You are maintaining UltimateRobloxKit, a reusable Roblox development toolkit for Claude Code and compatible agents.
> Work in small verified steps. Every skill is a folder `skills/<category>/<name>/` containing `SKILL.md` with YAML frontmatter (`name`, `description`, `metadata.category`, `metadata.triggers`, `metadata.depends`), following `docs/architecture/skill-format.md`.
> Skills are **canonical only in `skills/`**. `.claude/skills/` in any project, including this repository, is install output and is never edited by hand.
> After any change, run `python3 scripts/validate/run_all.py`. It must exit 0. Regenerate the catalog with `python3 scripts/automation/build_catalog.py` when you add, rename or retrigger a skill, and add a routing case to `tests/routing_cases.json`.
> Never copy third-party text or code unless its license allows it. Record every source in `SOURCES.md` and every vendored or fetched item in `third_party/manifest.json` with a pinned commit. Never run an upstream installer.
> Never claim a live integration (Roblox Studio, Blender, Open Cloud) works unless you exercised it. Report `NEEDS MANUAL REVIEW` otherwise.
> Never commit credentials. Never upload to Roblox or change a live place without explicit permission.

## Goals, in priority order

1. Breadth of genuinely useful capability across the whole Roblox production cycle.
2. Working implementations: real scripts, templates and tests, not prose.
3. Reliability through automated validation, in CI and locally.
4. Reuse: one command installs the kit into any project, selectively, reversibly.
5. Token efficiency: progressive disclosure through a router and small skills with references loaded on demand.
6. Honesty: every claim in the docs is backed by a test or marked as manual.

## Phases and how each was executed

| Phase | Output in this repository |
|---|---|
| 1. Recover the supermarket modeling project | `tools/rbxasset/` (Blender-free mesh kit, atlas, safe areas, display grid), `scripts/blender/` (build, export, re-import verify, renders), modeling skills, `docs/references/recovered-supermarket-pipeline.md` (what was recovered and what was not) |
| 2. GitHub research | `docs/references/repository-evaluation.md`, `SOURCES.md`, `third_party/manifest.json` |
| 3. Skill library | `skills/**/SKILL.md`, about forty consolidated skills in nine categories |
| 4. MCP and tools | `integrations/`, `scripts/install/doctor.py`, `templates/starter-game/rokit.toml` pins |
| 5. Orchestration | `skills/orchestration/roblox-kit-router`, `catalog/skills.json`, `scripts/automation/route.py`, `.claude/agents/`, `.claude/commands/` |
| 6. Repository | This layout, described in `docs/architecture/repository-layout.md` |
| 7. Documentation | `README.md`, `docs/**` |
| 8. Installer | `scripts/install/install.py` with shell and PowerShell wrappers |
| 9. Validation | `tests/`, `scripts/validate/`, `.github/workflows/ci.yml` |
| 10. Delivery | Feature branch, commits and pull request on GitHub |

## Architecture decisions

- **Canonical skill location.** `skills/<category>/<name>/`. Categories exist for humans; Claude Code needs a flat `.claude/skills/<name>/`, so the installer flattens. Names are globally unique and checked by tests.
- **Metadata in frontmatter.** Uses the Agent Skills `metadata` map, so Claude Code ignores it safely while the router and tests read it. No PyYAML dependency: frontmatter is restricted to a documented subset parsed by `scripts/lib/frontmatter.py`.
- **Router, not a mega-skill.** The router skill holds a compact table of every skill with one line each and a set of workflow recipes. Claude reads the table, then loads only the two to five skills a task needs. `route.py` gives the same answer deterministically and is tested against example tasks.
- **Stdlib-only tooling.** Installer, validators, router and catalog builder run on any Python 3.9 or newer with no packages. Pillow is optional, needed only for textures and contact sheets.
- **Blender scripts are headless first.** Each stage runs with `blender -b --factory-startup --python-exit-code 1`, reads JSON, writes JSON. The same functions work from Blender MCP.
- **FBX at 0.01 scale is the default Roblox export.** It is the format verified in Studio in the supermarket project. OBJ and GLB are produced and re-imported in Blender, and their Studio behaviour is documented as not verified by this kit.
- **Third-party material is fetched, not copied, by default.** `third_party/manifest.json` pins reviewed commits. `scripts/install/third_party.py` clones those exact commits, refuses to run any script, and copies only selected skills with their license.
- **Templates are Rojo projects** with pinned Rokit tools, Selene and StyLua configs, and pure-Luau logic modules tested with Lune in CI.

## Validation gates

1. Structure: every skill parses, has the required fields, a unique name, and resolvable references.
2. Links: every relative Markdown link in the repository resolves.
3. Routing: every case in `tests/routing_cases.json` returns its expected skills.
4. Installer: dry-run writes nothing; install, update, conflict backup and uninstall behave as documented, on temporary directories.
5. Code: Python compiles; JSON parses; in CI Selene, StyLua and `luau-analyze` check Luau and Lune runs the logic tests.
6. Geometry: generators produce closed, budgeted meshes; atlas rects stay inside the texture.
7. Blender (when available): build, export FBX, OBJ and GLB, re-import and compare dimensions.
8. Security: no secrets, no `curl | sh`, no unpinned third-party fetch.
9. Licenses: every vendored or fetched item has a manifest entry and a license.

## Known limits accepted at design time

- Roblox Studio is not installed on the build machine, so Studio import is documented as a manual procedure (`docs/workflows/studio-validation.md`) and never reported as passed.
- Live skill activation inside Claude Code cannot be unit-tested. The router's deterministic twin is tested instead.
- The Studio MCP server ships inside Studio and cannot run in CI.
