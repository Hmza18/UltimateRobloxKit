# Progress

Status of the V2 expansion (`feat/v2-expansion`, version 0.2.0). Each item's "Verified" column says how it was checked. "CI" means the GitHub Actions run on the pull request; local checks ran on macOS with Python 3.9 and Blender 5.2.3. Luau tools are not installed locally, so every Luau result comes from CI.

## Completed

| Area | Item | Verified |
|---|---|---|
| UI | UrkUI framework: 18 tags, 11 built-in actions, Store binding, 10 components, themes, responsive, gamepad, localisation, motion | Pure Core modules: 119 Lune specs in CI. Runtime, Behaviours and Components: NOT playtested in Studio |
| Icons | 92 original icons, sprite sheets, catalog, Luau API, gallery, importer | Python tests (reproducible build, geometry, importer); Lune catalog spec in CI; preview inspected by eye in dark and light |
| Library | 27 systems with READMEs | Pure Logic: about 400 Lune specs in CI. Adapters: NOT playtested in Studio |
| CLI | `urk.py` setup, new, add, check, upgrade, uninstall, icons, dashboard | `tests/test_urk_cli.py` (10 cases) locally and on Linux, Windows and macOS in CI |
| Dashboard | Self-contained HTML | Built and used in a browser: router, icon search, phone-width layout fixed and rechecked |
| Security | Backdoor scanner (Python and Lune), fixtures | Python tests locally; Lune scan of a Rojo-built binary model in CI |
| CI | SHA-256-verified binaries, SHA-pinned actions, library job, Rojo builds, report-only type check | CI on the pull request |
| Skills | 7 new skills, testing skill corrected, Studio MCP refreshed | `tests/test_skills.py`, routing cases (32) |
| Agents | 3 new agents, cooperation rules | Structure only; agent behaviour is not unit-testable |
| Research | 66 candidates, gap analysis, roadmap | Licences read from the repos' LICENSE files; Wally names checked against the registry |
| Icon pack request | BuiltByBit Free Icon Pack (54420): licence could not be verified (bot protection on builtbybit.com), so nothing was redistributed; a local import path was built instead | Documented in `assets/icons/LICENSE.md` |

## Remaining (in order)

See [docs/references/roadmap.md](docs/references/roadmap.md) for details and effort estimates.

1. Fix anything the first CI run finds in the new Luau code (format, lint, strict types, specs), then make the full type check blocking.
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
