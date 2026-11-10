# Repository layout

| Path | Responsibility | Installed to |
|---|---|---|
| `skills/<category>/<name>/` | Canonical skills (SKILL.md, references/, templates/) | `.claude/skills/<name>/` |
| `.claude/agents/` | Subagent definitions (canonical) | `.claude/agents/` |
| `.claude/commands/` | `/urk-*` slash commands (canonical) | `.claude/commands/` |
| `.claude/settings.json` | Permission allowlist for developing the kit itself | not installed |
| `catalog/` | Workflow recipes (hand-written), skill index and visuals preset catalog `visuals.json` (generated) | `$URK/catalog/` |
| `scripts/install/` | installer, doctor, third-party fetcher | `$URK/scripts/` |
| `scripts/automation/` | router, catalog builder, visuals preset tables builder, project scaffolder | `$URK/scripts/` |
| `scripts/export/` | asset batch, packager, Studio checker | `$URK/scripts/` |
| `scripts/blender/` | Blender-side stages (run inside Blender) | `$URK/scripts/` |
| `scripts/validate/` | `run_all.py`, `check_obj.py` | `$URK/scripts/` |
| `scripts/lib/` | shared stdlib helpers | `$URK/scripts/` |
| `tools/rbxasset/` | Blender-free mesh, UV and texture kit | `$URK/tools/` |
| `templates/` | Rojo game templates, asset-pipeline layout | `$URK/templates/` |
| `integrations/` | MCP configs, Blender MCP launchers | `$URK/integrations/` |
| `examples/` | example batch spec | `$URK/examples/` |
| `third_party/manifest.json` | reviewed external repositories with pins and policies | not installed |
| `docs/` | documentation (`docs/workflows` is also installed) | partly |
| `tests/` | unittest suites | not installed |
| `.github/` | CI, issue and PR templates | not installed |

`$URK` is `.claude/ultimate-roblox-kit` in an installed project and the repository root here. Skill folders under `skills/` are named by category for people. Claude Code needs them flat, so the installer flattens them and tests guarantee unique names.

Why `skills/` instead of `.claude/skills/` in this repository: a single canonical copy avoids two diverging trees. Developing the kit with its own skills active is one command away: `python3 scripts/install/install.py --target .` (output is git-ignored).
