# Progress

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
