# Progress

## 0.5.0: UltimateVisualsKit

How to read the "Verified" column: "local" means run on the build machine on 2026-11-10 with the Luau tools at the CI pins (Lune 0.11.1, StyLua 2.6.0, Selene 0.32.0, luau-analyze 0.746, luau-lsp 1.70.1, Rojo 7.7.1). Selene ran locally with a config without the Roblox standard library, because that definition could not be downloaded here; CI uses the real one. **No CI run for this branch has been seen yet, and nothing was run in Roblox Studio.** Spec counts are as of writing; rerun `cd library && lune run tests/run | tail -1`.

| Area | Item | Verified |
|---|---|---|
| Core and runtime | Clock, Engine, Springs, Curves, Sequence, Registry, Quality, Effects, Pool; Host, Motion, Props; the `Visuals` facade | Core: Lune specs and strict luau-analyze (local). Host, Motion, Props, facade: StyLua, Selene (local config), luau-lsp with Roblox types. NOT run in Studio |
| VFX | Effect schema, 78 presets in 8 categories, 5 legacy presets bridged, builders, player | EffectLogic, RecipeLogic, the preset data and CatalogData: Lune (schema, budgets at every quality level, rarity and element rules) and strict luau-analyze. Builders and VFX: lint, format and types only. All tuning was done from numbers, not by eye. NOT run in Studio |
| UI animation | 70 presets, bindings, show and hide, stagger, counters, typewriter, shine, ripple, flash, backdrop, popups, fly-to-counter | UILogic and UIPresets: Lune and strict luau-analyze. UIAnimations: lint, format and types only. NOT run in Studio |
| Game components | 17 animated components in `UI/Game`; spec element types, `motion` field and `pack:name` icons | Lint, format and types; the spec validators (Python and Luau) on shared fixtures. Components: NOT run in Studio |
| Camera, Objects, Pets | Shake, FOV, focus, orbit, pan, cinematics; 18 object presets; animator, follower, preview, selection screen | CameraLogic, ObjectsLogic, PetsLogic, SelectionLogic: Lune and strict luau-analyze. Camera, Objects, PetAnimator, PetFollow, PetPreview, PetSelection, DemoPet: lint, format and types only. NOT run in Studio |
| Eggs, Rewards, Feedback, Audio | Hatch cinematic, 7 rarity profiles and reveals, 24 feedback events in 3 packs, 29 cue names | HatchLogic, RewardsLogic, FeedbackLogic, AudioLogic: Lune and strict luau-analyze. Eggs, Rewards, RewardView, Feedback, Audio: lint, format and types only. NOT run in Studio. No sounds are bundled |
| Themes and tokens | 10 themes, 10 new styles in `design/tokens/styles.json` | ThemeData and ThemeLogic: Lune (validity, WCAG contrast, distinctness) and strict luau-analyze; Python token and contrast tests. How each theme looks: not checked |
| Icons | Private icon vault tool, `Visuals.Icons` registry, containers, picker, bridge | Vault tool: Python tests against a synthetic fixture pack. IconVaultLogic: Lune. IconVault runtime: lint, format and types only. NOT run in Studio. Nothing is uploaded; asset ids are mapped after the owner's manual upload |
| VFX textures | 25 generated textures and flipbooks, asset-id map, preview | Python tests; `urk.py visuals textures --check` reproduces the committed files. Not uploaded, not seen in Roblox |
| Presets, Debug | Catalog over the registries; stats overlay and profiler | PresetsLogic and DebugLogic: Lune and strict luau-analyze. Presets and Debug runtime: lint, format and types only |
| Preset catalog | `catalog/visuals.json` (generated), `library/tools/export_visuals.luau`, `build_visuals_refs.py`, generated preset tables | `lune run tools/export_visuals --check` and `build_visuals_refs.py --check` pass (local); `tests/test_visuals_catalog.py` (shape, sorting, cross-references, tables current) |
| Skills | 15 `uvk-*` skills in the new `visuals` category, 13 existing skills extended; 82 skills | `tests/test_skills.py`, `test_links.py`; the Luau example in `uvk-visual-testing` was run under Lune. Other code in the skills uses the real API by reading the source but was not executed |
| Routing | 3 visual workflows, 12 routing cases, 10 tuned eval cases | `test_routing.py`; `urk skills eval`: tuned 100% on 42 cases, held-out 50% and 40% (unchanged, not tuned against). A one-off untuned probe of 12 freshly worded visual requests routed 2 of 12 correctly |
| Agents and commands | `urk-visuals-director`, `urk-vfx-engineer`; `/urk-visuals`, `/urk-visuals-audit`; 15 agents, 8 commands | Structure only; agent behaviour is not unit-testable |
| CI | Strict list extended to UVK pure modules; catalog, table and texture staleness checks; vault status smoke test | The strict list was run locally with the pinned luau-analyze: clean. The workflow file itself has NOT run in GitHub Actions for this branch |
| Docs | Visuals README, quick start, API reference, preset reference, status section in the contract | Links checked by `test_links.py`; signatures taken from the source. Code samples in the docs were not executed |

Local results at the time of writing: **@@LUNE@@** (of which Visuals: @@LUNEV@@); strict luau-analyze clean on @@PURE@@ pure modules (@@PUREV@@ in Visuals); Python suite @@PY@@.

### Remaining for UVK (in order)

1. **Run it in Studio.** Every module that creates Instances is unverified. Work through the "Not verified in Studio" list at the end of each module README and the checklist in `skills/visuals/uvk-visual-testing/references/studio-checklist.md`: effects at Low and High, button feel on mouse, touch and gamepad, the selection screen on each device class, hatch and reveal skip and cancel, camera restoration after respawn, reduced motion and reduced flashing.
2. **Measure on a phone.** The budgets are design choices checked for consistency, not frame-time measurements.
3. **See the first CI run** for this branch and fix what the real Selene standard library and the full `luau-lsp` report find.
4. **Tune by eye.** VFX presets, springs and reveal timings were set from numbers. Expect a tuning pass after the first Studio session.
5. **Upload textures and icons** (owner, manual), then map the asset ids with `urk.py visuals assetmap` and `tools/icons/vault.py registry --map`.
6. **Sounds.** None are bundled; a game registers its own for the 29 cue names.
7. **Routing on unseen phrasing.** The trigger router finds visual skills for the tuned cases and is weak on new wording (2 of 12 in the probe). A better description fallback is the fix, not more triggers.
8. Known gaps: no radial cooldown sweep in HotbarSlot; models squash uniformly; no hit-stop outside the hatch; no mesh or flipbook-authored effects; followers do not path around walls.

## 0.4.0: ecosystem upgrade (`feat/ecosystem-v4`)

| Area | Item | Verified |
|---|---|---|
| Systems | Pets, Rebirth, Upgrades, Worlds, Boosts, Trading, VFX, WorldGen (pure, with specs) | Lune 676/676, Selene, StyLua, strict luau-analyze on each new pure module, Rojo build (local, at CI pins). CI run: see the PR |
| Server adapters | PetsServer, ProgressionServer, TradingServer, PlayerState, VFXClient, WorldGenBuilder | Lint, format, Rojo build. NOT playtested in Studio |
| Integrations | Wally overlay, ProfileStoreAdapter, FusionBridge | Real `wally install` and Rojo build on a generated project; FusionBridge spec with the real Store and a fake Fusion. ProfileStoreAdapter: NOT run in Roblox |
| Licensed art | Kenney icons (203) and UI Pack 2.0 | CC0 licence files beside each pack; per-file hashes in PROVENANCE.md; catalogs register in Lune; previews reviewed by eye |
| Generator | `urk generate`, six genres | Four genres generated and passed Lune, Selene, StyLua and Rojo |
| Tools | economy sim, asset registry, visual extract and compare, audit, build, memory, release, skills eval | `tests/test_v4_tools.py` (23 tests) |
| 3D | LOD1, LOD2, collision hull with QA | Blender 5.2.3 locally; test added for Blender 4.2 in CI |
| Routing | evaluation with held-out sets, description fallback | Tuned 100%, held-out 50% and 40% (reported, not hidden) |
| Dashboard | five new centres | All 13 tabs rendered in a browser |

## 0.3.0: UI generation (`feat/ui-generation`)

| Area | Item | Verified |
|---|---|---|
| Design tokens | `design/tokens/styles.json` generates `StyleTokens.luau` (cartoon, midnight, pastel) | Python: the generator is current, every style resolves, and the outline-vs-palette contrast is at least 3:1. Lune: Style specs (in CI) |
| Game components | 19 components and PurchaseBridge | Selene, StyLua and Lune for the pure parts (MotionPresets, TextFit, Style) in CI. Components: NOT playtested in Studio |
| Screen specs | SpecSchema, Python twin, 16 screens, Builder | All 16 screens and the shared fixtures pass both validators (Python locally, Lune in CI). Builder: NOT run in Studio |
| Previews | `urk.py ui preview`, `capture_server.py` | All 16 screens rendered and captured in a browser and reviewed by eye (`docs/images/ui/`). Fixed during review: grid overflow, timer format, owned cards, popup buttons, divider collapse. These are HTML approximations, not Roblox renders |
| Icons | 272 icons, illustrated style, variants, auto-alignment, validator | All 272 pass `validate_icon.py`; the build is reproducible; sheets inspected by eye |
| Skills | 11 new, roblox-animation extended, game-icons merged | `test_skills`, 43 routing cases, catalog current |
| Playground | `library/examples/playground` | Written against the real framework; NOT run in Studio |

CI on PR #4 (final commit): Selene 0 errors and 0 warnings, StyLua clean, strict luau-analyze clean on 52 pure modules, **637 of 637 Lune specs**. The library `.rbxm`, every template place and a project with every module (UI included) build with Rojo. Kit tests pass on Linux (Python 3.9 and 3.12), Windows and macOS; the Blender 4.2 pipeline passes. The first CI run found 3 Selene warnings, 1 StyLua diff and 2 strict-type errors, all fixed. The report-only luau-lsp check prints 383 lines (down from 454), mostly in 0.2.0 system adapters; it is still item 1 below.


Status of the V2 expansion (`feat/v2-expansion`, version 0.2.0). Each item's "Verified" column says how it was checked. "CI" means the GitHub Actions run on the pull request; local checks ran on macOS with Python 3.9 and Blender 5.2.3. Luau tools are not installed locally, so every Luau result comes from CI (PR #3 runs, 2026-11-08).

## Completed

| Area | Item | Verified |
|---|---|---|
| UI | UrkUI framework: 18 tags, 11 built-in actions, Store binding, 10 components, themes, responsive, gamepad, localisation, motion | Pure Core modules pass their Lune specs and strict luau-analyze in CI; all UI files pass Selene and StyLua. Runtime, Behaviours and Components: NOT playtested in Studio |
| Icons | 92 original icons, sprite sheets, catalog, Luau API, gallery, importer | Python tests (reproducible build, geometry, importer); Lune catalog spec in CI; preview inspected by eye in dark and light |
| Library | 27 systems with READMEs | CI: Selene 0 errors / 0 warnings, StyLua clean, strict luau-analyze clean on 48 pure modules, **511 of 511 Lune specs pass** (40 spec files), Rojo builds `UltimateRobloxKit.rbxm`. A game project with every module added by `urk add` also builds and passes. Adapters: NOT playtested in Studio |
| CLI | `urk.py` setup, new, add, check, upgrade, uninstall, icons, dashboard | `tests/test_urk_cli.py` (10 cases) locally and on Linux, Windows and macOS in CI |
| Dashboard | Self-contained HTML | Built and used in a browser: router, icon search, phone-width layout fixed and rechecked |
| Security | Backdoor scanner (Python and Lune), fixtures | Python tests locally; Lune scan of a Rojo-built binary model in CI |
| CI | SHA-256-verified binaries, SHA-pinned actions, library job, Rojo builds, report-only type check | CI on the pull request |
| Skills | 7 new skills, testing skill corrected, Studio MCP refreshed | `tests/test_skills.py`, routing cases (32) |
| Agents | 3 new agents, cooperation rules | Structure only; agent behaviour is not unit-testable |
| Research | 66 candidates, gap analysis, roadmap | Licences read from the repos' LICENSE files; Wally names checked against the registry |
| Icon pack request | BuiltByBit Free Icon Pack (54420): licence could not be verified (bot protection on builtbybit.com), so nothing was redistributed; a local import path was built instead | Documented in `assets/icons/LICENSE.md` |

## CI history for the new Luau code

The first CI run on PR #2 was the first time the Luau tools saw this code, and PR #2 was merged before it passed. PR #3 then fixed:
- 2 Selene errors and 8 warnings
- 34 strict-typing problems: 24 union-iteration loops and 10 other errors
- 2 specs that asserted the wrong expected value
- 1 spec that depended on the kit's folder layout

All blocking checks pass on PR #3.

## Remaining (in order)

See [docs/references/roadmap.md](docs/references/roadmap.md) for details and effort estimates.

1. Clear the report-only full type check: luau-lsp with Roblox definitions reports 153 issues, mostly in adapters (Analytics, UI Runtime, Binder, Quests). Many are the newer solver's strictness on `pcall` over function unions and nil comparisons. Then make the check blocking.
2. Studio playtest pass over UrkUI and each system adapter, using the checklists in each README. This needs Studio and a person.
3. Real Wally dependencies: a packages overlay with ProfileStore and Roblox Jest, plus a ProfileStore store adapter.
4. Opt-in in-engine CI through rocale-cli (needs an Open Cloud key and a test place from you).
5. Asphalt asset sync and Mantle deploys (each upload or deploy only with explicit permission).
6. Dev-tools overlay (Iris, Cmdr, UI Labs stories), a Blink networking overlay, and Moonwave docs.

## How to continue in a new session

1. `git checkout feat/v2-expansion` (or `main` after merge) and `python3 scripts/validate/run_all.py`.
2. Read this file, then `docs/references/roadmap.md`, and pick the first open item.
3. For Luau work, follow `docs/architecture/library-conventions.md`. Push to a branch and let CI run Selene, StyLua, luau-analyze and Lune, because they are not installed locally.
4. Update this file in the same commit as the work.
