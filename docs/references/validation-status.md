# Validation status

What has been proven, how, and what has not. Updated 2026-11-08 for version 0.1.0.

| # | Check | How | Result |
|---|---|---|---|
| 1 | Skill structure and metadata (44 skills) | `tests/test_skills.py`: frontmatter, unique names, category, triggers, dependencies, size, Limitations section, kit paths exist, no deprecated `wait(` | PASS |
| 2 | Internal links | `tests/test_links.py`: every relative link in every Markdown file | PASS |
| 3 | Installer | `tests/test_installer.py`: dry-run writes nothing; full install then uninstall leaves an empty folder; selective install with dependencies; refuse, then force with backup; update protects edits; version pin; installed router runs | PASS (macOS locally; Linux with Python 3.9 and 3.12, Windows and macOS in CI) |
| 4 | Routing | `tests/test_routing.py`: 25 example tasks, bounded load size, every workflow skill exists | PASS |
| 5 | Script syntax | Python compiles; JSON parses (`test_repo_hygiene.py`); Luau via Selene, StyLua, `luau-analyze` (pure logic) and Lune in the CI `luau` job | PASS. CI run on commit 4f73054: Selene, StyLua, `luau-analyze --mode=strict` (pure logic) and Lune pass for all 5 templates, with 36 to 41 Lune specs per project |
| 6 | Dependencies and versions | Template `rokit.toml` pins checked against the reviewed versions (`test_templates.py`); `doctor.py` run on the build machine | PASS |
| 7 | Blender workflow | `tests/test_blender_pipeline.py` and the two example batches: build, FBX/OBJ/GLB export, re-import, QA | PASS on Blender 5.2.3 (macOS) and Blender 4.2.23 LTS (Linux CI) |
| 8 | Asset export | 10 representative assets; every OBJ also passed `check_obj.py` (closed, consistent winding, under 400 triangles, on the ground) | PASS |
| 8b | License delivery and references | `tests/test_license_delivery.py`: `License<N>/` layout and names, verified zip, unapproved refused, `_previous` archive; all 51 approved supermarket references rebuild closed and within budget; License6 and License10 references rendered in Blender and inspected | PASS |
| 9 | Roblox Studio | Studio was not installed on the build machine | NOT RUN. Manual procedure: [studio-validation.md](../workflows/studio-validation.md) |
| 10 | Licensing and attribution | `test_repo_hygiene.py`: manifest policies, full SHAs for copy and pip, every source listed in SOURCES.md and THIRD_PARTY_NOTICES.md | PASS |
| 11 | Secrets and unsafe installs | Token pattern scan; no download piped into a shell; shell scripts use strict mode; third-party fetch tested against a local repository (pinned commit, short SHA refused, no overwrite, link-only refused) | PASS |
| 12 | Documentation | Every README command was run during development, except the Rokit, Rojo, Studio and Blender MCP steps, which need tools that were not installed here | Partial (stated) |

## 0.4.0 checks (2026-11-08, macOS, local toolchain at the CI pins)

| Check | How | Result |
|---|---|---|
| Library | Selene 0.32.0, StyLua 2.6.0, `luau-analyze --mode=strict` on every new pure module, Lune 0.11.1 (676 specs), Rojo 7.7.1 build | PASS |
| New systems | Lune specs for Pets, Rebirth, Upgrades, Boosts, Worlds, Trading, VFX, WorldGen, FusionBridge (fake Fusion with the real Store) and the Kenney pack catalogs | PASS |
| Server adapters | PetsServer, ProgressionServer, TradingServer, VFXClient, WorldGenBuilder, ProfileStoreAdapter: lint, format and Rojo build only | NOT RUN in Roblox (needs Studio) |
| Wally overlay | `urk packages` on a generated project, then a real `wally install` (Fusion 0.3.0, Promise 4.0.0, ProfileStore 1.0.3) and a Rojo build with Packages mapped | PASS |
| Game generator | Four genres (supermarket simulator with 50 products, pet, obby, tycoon) generated, then Lune (project and kit specs), Selene, StyLua and Rojo build in each | PASS |
| LOD and collision | `asset_batch.py --lod` in Blender 5.2.3: LOD triangle counts drop, bounds kept, hull at most 256 triangles and encloses the mesh (barrel volume ratio 1.005) | PASS locally; added to the Blender 4.2 CI test |
| Visual scoring | Self-comparison scores 100; an unrelated image scores under 70; extraction finds the shop's red, teal and purple accents | PASS (tests) |
| Routing | `urk skills eval`: 32 tuned cases 100%, held-out 50% (10 cases, informed the fallback), held-out2 40% (10 untouched cases) | Reported as measured |
| Audit | Kit audit: 0 HIGH. The insecure fixture triggers client-trusted amount, unvalidated remote, loadstring and require by id | PASS |
| Dashboard | Built with a generated project; all 13 tabs rendered in a browser with no script errors | PASS (visual check) |

## 0.5.0 checks (2026-11-10, Linux, local toolchain at the CI pins)

UltimateVisualsKit. No CI run for this branch had been seen when this was written, and nothing was run in Roblox Studio.

| Check | How | Result |
|---|---|---|
| Visuals pure logic | Lune specs for Core and every `*Logic`, `*Presets` and `*Data` module (`lune run tests/run tests visuals_`) | PASS (@@LUNEV@@) |
| Whole library | `lune run tests/run` | PASS (@@LUNE@@) |
| Strict types | `luau-analyze --mode=strict` on the CI `PURE` list, extended to UVK | PASS (@@PURE@@ modules, @@PUREV@@ in Visuals) |
| Lint and format | StyLua 2.6.0; Selene 0.32.0 with a local config without the Roblox standard library | See [PROGRESS.md](../../PROGRESS.md); Selene with the real standard library runs only in CI |
| Visuals runtime (every module that creates Instances, and the 17 animated components) | `luau-lsp analyze` with Roblox type definitions | Types only. NOT RUN in Roblox (needs Studio) |
| Preset catalog | `lune run tools/export_visuals --check`; `python3 scripts/automation/build_visuals_refs.py --check`; `tests/test_visuals_catalog.py` | PASS |
| VFX textures | `python3 urk.py visuals textures --check` | PASS (25 files reproduce) |
| Icon vault | `tests/test_visuals_icons.py` against a synthetic pack; `urk.py visuals icons status` | PASS. No upload attempted; in-game use NOT RUN |
| Skills and routing | `test_skills.py`, `test_routing.py`, `urk skills eval` | PASS; tuned 100% (42 cases), held-out 50% and 40% as before; untuned probe of 12 visual requests: 2 correct |
| Looks, feel, devices, performance | not possible without Studio | NEEDS MANUAL REVIEW |

## Visual inspection

The contact sheet in `docs/images/example-props.png` was inspected by eye.

CI found three real problems on its first run, all fixed: a StyLua formatting difference in the UI template, no Python 3.9 build on the newest Ubuntu image, and uninstall leaving `__pycache__` behind after installed scripts had run. A dark seam on the coin's wrap panel was found and fixed: the texture painter no longer outlines a panel's wrap edges.

## Not verified

- Live skill activation inside a new Claude Code session. Routing is tested through its deterministic twin, `route.py`.
- Roblox Studio import, Studio MCP, Studio screenshots for the visual loop, and Open Cloud publishing.
- The 0.4 server adapters and builders in a live game.
- Blender MCP through this kit's own launcher. The same setup was exercised in the source project on 2026-11-06.
- Luau behaviour inside Roblox: Lune tests cover pure logic only, and server and client code needs a Studio playtest.
- Windows PowerShell wrapper (`install.ps1`) beyond what CI's Windows job runs, which is the Python installer itself.
