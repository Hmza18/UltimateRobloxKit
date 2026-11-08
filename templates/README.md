# Templates

Rojo project templates for Roblox games. `starter-game` is a complete project. The other templates are
**overlays**: they hold only the files they add or replace, at the same relative paths, plus an
`overlay.json` naming their base.

| Template | Kind | What you get |
| --- | --- | --- |
| `starter-game` | base | Loader for services and controllers, `Net` (validated, rate-limited remotes), session-locked `PlayerDataService`, inventory, economy with rebirths, HUD, pure `Logic/` modules, Lune tests, pinned Rokit tools |
| `simulator` | overlay | server-validated click collecting with a cooldown, upgrades, `SimFormulas` with tests |
| `tycoon` | overlay | plot claiming and ownership, purchase buttons with prerequisites, droppers and collectors, `TycoonMath` with tests |
| `obby` | overlay | tagged checkpoints and kill bricks, saved stages that advance one at a time, `StageProgress` with tests |
| `ui` | overlay | Theme tokens, responsive UIScale, accessible Button, Panel and Label, tween helpers, a replacement HUD |

`asset-pipeline/` is not a Rojo template and is not composed this way.

## Creating a project

```bash
python3 scripts/automation/new_project.py --template <name> --name <Game> --out <dir>
```

The script builds the project in this order:

1. Copy `templates/starter-game/` to `<dir>`.
2. If `<name>` is not `starter-game`, copy every file of `templates/<name>/` over it, keeping relative
   paths and overwriting files that already exist. `overlay.json` is skipped, and the overlay's
   `README.md` replaces the base README. Overlay READMEs are written as full
   project READMEs that start with the `__GAME_NAME__` token.
3. Replace the token `__GAME_NAME__` with `<Game>` in `default.project.json` (the Rojo `"name"`) and in
   `README.md`.

Every overlay names `"base": "starter-game"` in its `overlay.json`, so overlays never depend on each
other. Each one adds new services or controllers, which the base loaders pick up automatically. The
only file an overlay replaces is `ui`'s `src/client/Controllers/UIController.luau`.

## Conventions every template follows

- `--!strict` at the top of every Luau file, and `.luaurc` sets strict mode too.
- `src/shared/Logic/` holds pure Luau only: no Roblox globals, and only relative `require("./Name")`
  requires inside `Logic/`. Lune tests use these modules directly, for example
  `require("../src/shared/Logic/Inventory")`.
- Tests are `tests/*.spec.luau` files that return a table of `name -> function`. `tests/run.luau`
  finds every spec file, so an overlay adds tests just by adding spec files. Run them with
  `lune run tests/run` from the project root.
- Roblox code requires shared modules with `ReplicatedStorage:WaitForChild("Shared")` paths. Type
  checking it needs a Rojo sourcemap and the Roblox definitions (see the starter-game README).
- Every client-to-server remote is registered with `Net.onServerEvent`, which requires a validator and
  applies a per-player rate limit.
- Formatting follows `stylua.toml` (tabs, 120 columns) and linting follows `selene.toml` (`std = "roblox"`).

## Checking a template

From a generated project, or from `templates/starter-game` (overlay files are checked once composed):

```bash
rokit install
selene src tests
stylua --check src tests
lune run tests/run
```
