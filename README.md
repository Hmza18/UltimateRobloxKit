# UltimateRobloxKit

A reusable Roblox development toolkit for Claude Code and compatible AI coding agents. It provides 44 consolidated skills, a router that loads only the skills a task needs, subagents and slash commands, Rojo game templates, a tested procedural 3D asset pipeline for Blender, and an installer that can add the kit to any project and remove it cleanly.

![Assets built by the kit's pipeline in Blender](docs/images/example-props.png)

*Ten assets from `examples/asset-batch/props.json` and `templates/asset-pipeline/specs/batch-01.json`, generated, exported to FBX, OBJ and GLB, re-imported and rendered by `scripts/export/asset_batch.py`.*

## What you get

| Area | Contents |
|---|---|
| **Skills** (`skills/`) | 44 skills in 9 categories: Roblox engineering (19), toolchain (2), Blender (4), modeling (9), environments (2), UI (2), gameplay design (2), production (2), orchestration (2). [Catalog](docs/references/skill-catalog.md) |
| **Orchestration** | `roblox-kit-router` skill, `catalog/workflows.json` recipes, and `scripts/automation/route.py`, a deterministic router tested against 25 example tasks |
| **Agents and commands** (`.claude/`) | 6 subagents (architect, Luau engineer, asset pipeline, QA reviewer, game designer, world builder) and 6 `/urk-*` slash commands |
| **Asset pipeline** | `tools/rbxasset` (73 parameterized generators, UV atlas, safe areas, Blender-free validation) and `scripts/blender` (build, FBX/OBJ/GLB export, re-import check, renders), plus QA, contact sheets, approval gates and the `handoff/License<N>` delivery format, with the 51 approved supermarket objects as references |
| **Templates** (`templates/`) | Rojo projects with pinned tools (starter game, simulator, tycoon, obby, UI kit), plus an asset-pipeline layout |
| **Integrations** | Blender MCP (isolated, telemetry off), Roblox Studio MCP config, environment doctor, pinned third-party skill fetcher |
| **Validation** | 46 unit tests, plus CI on Linux, Windows and macOS that also runs Blender 4.2 and the Luau toolchain |

## Quick start

```bash
git clone https://github.com/Hmza18/UltimateRobloxKit.git
```

```bash
python3 UltimateRobloxKit/scripts/install/install.py --target ~/games/MyGame --dry-run
```

```bash
python3 UltimateRobloxKit/scripts/install/install.py --target ~/games/MyGame --with-claude-md
```

Then open a new Claude Code session in `~/games/MyGame` and describe what you want. A few examples:

- "Build a Roblox simulator with pets and rebirths" → `new-game` workflow
- "Create 20 supermarket products" → `asset-batch` workflow, in batches of five with an approval stop after each
- "Players lose their data sometimes" → `roblox-data-persistence`
- `/urk-route add a shop with a currency` shows the plan before any work starts

Python 3.9 or newer is the only requirement for the installer, router and validators. Blender, Rojo and Studio are needed only for the workflows that use them. Run `/urk-doctor` or `python3 scripts/install/doctor.py` to see what is missing.

More: [Quick start](docs/getting-started/quick-start.md) · [Beginner setup](docs/getting-started/beginner-setup.md) · [Advanced setup](docs/getting-started/advanced-setup.md)

## How skill selection works

Claude Code reads every installed skill's short description and activates the ones that match. With 44 skills, the kit adds a second layer so context stays small:

1. The `roblox-kit-router` skill holds a one-line index of every skill and ten workflow recipes.
2. `route.py` maps a task to a workflow and to trigger matches, then adds only direct dependencies. "Create 20 supermarket products" loads 9 skills, not 43.
3. Long material lives in each skill's `references/` folder and is opened only when the skill says so.

See [Agent architecture](docs/architecture/agent-architecture.md).

## Common commands

| Task | Command |
|---|---|
| Install into a project | `python3 scripts/install/install.py --target <dir>` |
| Install for all projects | `python3 scripts/install/install.py --user` |
| Install selected skills | `... --skills roblox-networking,roblox-ui-systems` or `--category modeling` |
| Update or uninstall | `... --update` / `... --uninstall` |
| Check the machine | `python3 scripts/install/doctor.py --project <dir>` |
| Route a task | `python3 scripts/automation/route.py "<task>"` |
| New game from a template | `python3 scripts/automation/new_project.py --template simulator --name MyGame --out <dir>` |
| Build an asset batch | `python3 scripts/export/asset_batch.py examples/asset-batch/props.json --out build/props` |
| Deliver an approved batch | `python3 scripts/export/package_batch.py build/props --license 12 --dest handoff` |
| Fetch reviewed third-party skills | `python3 scripts/install/third_party.py list` |
| Run all kit checks | `python3 scripts/validate/run_all.py` |

## Documentation

- Getting started: [quick start](docs/getting-started/quick-start.md), [beginner setup](docs/getting-started/beginner-setup.md), [advanced setup](docs/getting-started/advanced-setup.md), [installation](docs/getting-started/installation.md)
- Workflows: [new game](docs/workflows/new-game.md), [Blender assets](docs/workflows/blender-assets.md), [asset export](docs/workflows/asset-export.md), [Roblox Studio](docs/workflows/roblox-studio.md), [Studio validation](docs/workflows/studio-validation.md), [MCP integration](docs/workflows/mcp-integration.md), [templates](docs/workflows/templates.md), [skill usage examples](docs/workflows/skill-examples.md)
- Architecture: [blueprint](docs/architecture/BLUEPRINT.md), [agent architecture](docs/architecture/agent-architecture.md), [repository layout](docs/architecture/repository-layout.md), [skill format](docs/architecture/skill-format.md)
- Reference: [skill catalog](docs/references/skill-catalog.md), [repository evaluation](docs/references/repository-evaluation.md), [recovered supermarket pipeline](docs/references/recovered-supermarket-pipeline.md), [validation status](docs/references/validation-status.md)
- [Troubleshooting](docs/troubleshooting/README.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Sources](SOURCES.md) · [Third-party notices](THIRD_PARTY_NOTICES.md) · [Changelog](CHANGELOG.md)

## What is and is not verified

The installer, router, skill structure, links, geometry kit, third-party fetcher and Blender pipeline (on Blender 5.2.3 locally and 4.2 LTS in CI) are covered by automated tests. **Roblox Studio import and Studio MCP were not exercised**, because Studio was not available on the build machine. Those workflows are documented as manual procedures, and the scripts report them as `NEEDS MANUAL REVIEW`. Details: [validation status](docs/references/validation-status.md).

## License

MIT, see [LICENSE](LICENSE). Third-party skills are never bundled. They are fetched at reviewed, pinned commits, together with their own licenses.
