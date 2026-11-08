# __GAME_NAME__

A Rojo project made from the UltimateRobloxKit `starter-game` template. It has a service and
controller loader, validated and rate-limited networking, session-locked player data, an inventory,
an economy with rebirths, and pure Luau game logic tested with Lune.

## Structure

```
default.project.json      Rojo tree: src/shared -> ReplicatedStorage.Shared,
                          src/server -> ServerScriptService.Server,
                          src/client -> StarterPlayer.StarterPlayerScripts.Client
rokit.toml                pinned tools (rojo, wally, selene, stylua, lune, luau-lsp)
wally.toml                packages (none yet; ProfileStore example in comments)
selene.toml stylua.toml .luaurc   lint, format and strict type-check settings
src/
  shared/
    Config.luau           tunable settings (no secrets: clients can read it)
    Types.luau            shared types (Module, RemoteHandler)
    Loader.luau           runs Init on every module, then Start
    Net.luau              RemoteEvents with server validation and per-player rate limits
    Signal.luau Trove.luau  events and cleanup
    Logic/                PURE Luau, no Roblox APIs, tested by Lune
      RateLimiter.luau    token bucket (caller passes `now`)
      Inventory.luau      slots, stacking, capacity
      Economy.luau        prices, rebirth multiplier, safe rounding
      Validate.luau       payload checkers for remotes
      DataSchema.luau     save format, migrations, session-lock rules
  server/
    init.server.luau      loads Services/
    Services/             PlayerDataService, EconomyService, InventoryService
  client/
    init.client.luau      loads Controllers/
    Controllers/          UIController (HUD), InputController (key bindings)
tests/
  run.luau                Lune runner: requires every tests/*.spec.luau
  lib/t.luau              assertion helpers
  *.spec.luau             one file per Logic module
```

### How the pieces fit

- **Services and controllers.** Every ModuleScript in `Services/` (server) or `Controllers/` (client)
  is a table with optional `Name`, `Priority`, `Init` and `Start`. The loader calls every `Init` in
  priority order (lower first), then calls each `Start` in its own thread. `Init` must not yield. To add
  a feature, add a file. Nothing has to be registered.
- **Networking.** `Net.onServerEvent(name, { validate = ..., rateLimit = ... }, handler)` needs a
  validator built from `Logic/Validate`. Requests over the per-player token bucket, or that fail
  validation, are dropped before the handler runs. Never trust a client value you have not validated.
- **Player data.** `PlayerDataService` keeps one record per player, locked to one server at a time with
  `UpdateAsync`. It retries with backoff, autosaves, and saves everything in `game:BindToClose`. Read
  with `:Get(player)` and change with `:Update(player, function(data) ... end)`. Add a field by bumping
  `DataSchema.VERSION` and adding a migration. **For a live game, use ProfileStore** (see `wally.toml`).
  The built-in service is a readable reference, and it is fine for prototypes.
- **Pure logic.** Anything that is just maths or rules goes in `src/shared/Logic` with no Roblox
  globals and only `require("./Name")` requires, so Lune can test it outside Roblox.

## Commands

```bash
rokit install                       # install the pinned tools
rojo serve                          # live-sync into Studio (Rojo plugin required)
rojo build -o game.rbxl             # build a place file
selene src tests                    # lint
stylua --check src tests            # formatting check (stylua src tests to fix)
lune run tests/run                  # run the logic tests
```

`lune run tests/run` must run from the project root. Each `tests/*.spec.luau` returns a table of
`test name -> function`. A test fails by raising an error, and the runner exits with code 1 if any
test fails.

### Type checking

Files in `src/shared/Logic` are pure Luau, so plain `luau-analyze src/shared/Logic` checks them. Code
that uses Roblox APIs needs Roblox type definitions and a Rojo sourcemap so instance requires resolve:

```bash
rojo sourcemap default.project.json -o sourcemap.json
curl -L -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --base-luaurc=.luaurc src
```

For reproducible CI, replace `main` in that URL with the luau-lsp tag pinned in `rokit.toml`. To
type-check `tests/`, run `lune setup` first. It writes the `@lune/*` type definitions.

## Studio notes

- Turn on **Game Settings > Security > Enable Studio Access to API Services** to test saving in Studio.
  Without it, `PlayerDataService` runs in memory-only mode and warns once.
- Press **R** in game to request a rebirth (it costs `Config.RebirthBaseCost` coins).

## Adding packages

1. Add the dependency to `wally.toml` and run `wally install`.
2. Map the folder in `default.project.json` under `ReplicatedStorage`:
   `"Packages": { "$path": "Packages" }`. Only add this once the folder exists, because Rojo fails on
   a missing path.
