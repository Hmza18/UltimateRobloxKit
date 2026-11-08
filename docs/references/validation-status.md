# Validation status

What has been proven, how, and what has not. Updated 2026-11-08 for version 0.1.0.

| # | Check | How | Result |
|---|---|---|---|
| 1 | Skill structure and metadata (43 skills) | `tests/test_skills.py`: frontmatter, unique names, category, triggers, dependencies, size, Limitations section, kit paths exist, no deprecated `wait(` | PASS |
| 2 | Internal links | `tests/test_links.py`: every relative link in every Markdown file | PASS |
| 3 | Installer | `tests/test_installer.py`: dry-run writes nothing; full install then uninstall leaves an empty folder; selective install with dependencies; refuse, then force with backup; update protects edits; version pin; installed router runs | PASS (macOS locally; Linux, Windows, macOS in CI) |
| 4 | Routing | `tests/test_routing.py`: 23 example tasks, bounded load size, every workflow skill exists | PASS |
| 5 | Script syntax | Python compiles; JSON parses (`test_repo_hygiene.py`); Luau via Selene, StyLua, `luau-analyze` (pure logic) and Lune in the CI `luau` job | Python and JSON PASS. Luau: see CI on the pull request |
| 6 | Dependencies and versions | Template `rokit.toml` pins checked against the reviewed versions (`test_templates.py`); `doctor.py` run on the build machine | PASS |
| 7 | Blender workflow | `tests/test_blender_pipeline.py` and the two example batches: build, FBX/OBJ/GLB export, re-import, QA | PASS on Blender 5.2.3 (macOS). CI job on Blender 4.2.23 LTS |
| 8 | Asset export | 10 representative assets; every OBJ also passed `check_obj.py` (closed, consistent winding, under 400 triangles, on the ground) | PASS |
| 9 | Roblox Studio | Studio was not installed on the build machine | NOT RUN. Manual procedure: [studio-validation.md](../workflows/studio-validation.md) |
| 10 | Licensing and attribution | `test_repo_hygiene.py`: manifest policies, full SHAs for copy and pip, every source listed in SOURCES.md and THIRD_PARTY_NOTICES.md | PASS |
| 11 | Secrets and unsafe installs | Token pattern scan; no download piped into a shell; shell scripts use strict mode; third-party fetch tested against a local repository (pinned commit, short SHA refused, no overwrite, link-only refused) | PASS |
| 12 | Documentation | Every README command was run during development, except the Rokit, Rojo, Studio and Blender MCP steps, which need tools that were not installed here | Partial (stated) |

## Visual inspection

The contact sheet in `docs/images/example-props.png` was inspected by eye. A dark seam on the coin's wrap panel was found and fixed: the texture painter no longer outlines a panel's wrap edges.

## Not verified

- Live skill activation inside a new Claude Code session. Routing is tested through its deterministic twin, `route.py`.
- Roblox Studio import, Studio MCP and Open Cloud publishing.
- Blender MCP through this kit's own launcher. The same setup was exercised in the source project on 2026-11-06.
- Luau behaviour inside Roblox: Lune tests cover pure logic only, and server and client code needs a Studio playtest.
- Windows PowerShell wrapper (`install.ps1`) beyond what CI's Windows job runs, which is the Python installer itself.
