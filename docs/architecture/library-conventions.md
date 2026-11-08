# Luau library conventions

The kit's Luau library lives in `library/`. `rojo build library -o UltimateRobloxKit.rbxm` turns it into one model. Projects either drop that model into `ReplicatedStorage`, or copy selected modules with `scripts/automation/add_module.py`. These rules keep every module reusable, testable and safe to combine.

## Layout

```
library/
├── default.project.json      builds src/ as one ModuleScript tree named UltimateRobloxKit
├── src/
│   ├── Util/                 Signal, Trove, RateLimiter, Validate (shared by everything)
│   ├── UI/                   UrkUI: tag- and attribute-driven UI framework
│   ├── Icons/                icon catalog data and the Icon component
│   └── Systems/<Name>/       one folder per game system
│       ├── <Name>Logic.luau  pure Luau: rules and state transitions, no Roblox globals
│       ├── <Name>Server.luau server adapter (remotes, persistence hooks, validation)
│       ├── <Name>Client.luau client adapter (optional)
│       ├── <Name>Config.luau defaults (optional)
│       └── README.md         API, configuration, example, limitations
├── tests/                    Lune specs: tests/<area>_<name>.spec.luau, run with `lune run tests/run`
└── examples/                 small, runnable usage examples (place scripts)
```

## Rules

1. `--!strict` at the top of every file, Luau types for public APIs, `export type` for data shapes.
2. **Requires are relative strings** (`require("./RateLimiter")`, `require("../../Util/Signal")`). Roblox's require-by-string and Lune both resolve these relative to the requiring file, so the library works wherever it is placed. Never require by instance path inside the library.
3. **Logic modules are pure.** They take a `now` or a random source as an argument instead of calling `os.clock`, `tick` or `Random`. They never touch `game`, `workspace`, `Instance`, `task` or services. They return new tables or explicit results, and they validate inputs. All rules worth testing live here.
4. **Adapters are thin.** Server and Client modules wire Logic to Roblox: remotes (server-validated and rate-limited with `Util/RateLimiter`), DataStore hooks, CollectionService tags and attributes. They return a constructor or `start(config)` and a cleanup.
5. **The server is authoritative.** Clients send intents, never results. Every remote argument is type- and range-checked with `Util/Validate`.
6. **Genre-neutral and configurable.** No hard-coded item ids, currencies or UI paths. Callers pass config tables with documented defaults.
7. **Persistence is injected.** Systems that save expose `serialize(state)` / `deserialize(data)` and accept a `store` interface; they do not call DataStoreService themselves. (The templates' PlayerDataService or ProfileStore can provide the store.)
8. **Cleanup.** Every connection is owned by a `Trove`. Adapters return a function or object that disconnects everything.
9. **Formatting** follows `library/stylua.toml` (tabs, 120 columns, double quotes, parentheses always). Selene `std = "roblox"`, with no warnings.
10. **Tests.** Every Logic module has a spec covering normal use, limits and invalid input. A spec returns `{ ["test name"] = function() ... end }` and uses `tests/lib/t.luau` (`require("./lib/t")`).
11. **Docs.** Every system has a README: purpose, API table, config table with defaults, a short example, events, persistence shape, limitations, and what needs a Studio playtest.
12. **No third-party code** is copied into `library/` unless its license is MIT, Apache-2.0, BSD, MPL-2.0 or CC0, and it is recorded in `SOURCES.md`.

## What tests can and cannot prove

Lune runs Logic modules and pure UI helpers (layout maths, theming, focus graphs, binding paths). Instance creation, CollectionService, TweenService, input and rendering run only in Roblox, so adapters are checked by Selene, StyLua and `luau-analyze` in CI and need a Studio playtest. Each README says what is unverified.
