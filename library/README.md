# UltimateRobloxKit Luau library

Reusable, genre-neutral game systems and an original UI framework, written to [the library conventions](../docs/architecture/library-conventions.md). Every system splits pure rules (`<Name>Logic.luau`, tested with Lune) from thin Roblox adapters (`<Name>Server.luau` and `<Name>Client.luau`, which need a Studio playtest). The server is always authoritative.

## Use it in a game

```bash
python3 urk.py add --list
```

```bash
python3 urk.py add UI Systems/Inventory Systems/Shop --project ~/games/MyGame
```

Modules are copied to `src/shared/Urk/` with their dependencies and tests. Edits you make are kept on `--update`. Alternatively, `rojo build library -o UltimateRobloxKit.rbxm` gives one model to insert into ReplicatedStorage.

## Contents

| Module | What it gives you |
|---|---|
| [UI](src/UI/README.md) | UrkUI: tag- and attribute-driven panels, buttons, data binding, tabs, tooltips, toasts, context menus, drag and drop, themes, responsive layouts, gamepad navigation, localisation, animation, and code components |
| [Icons](src/Icons/) | 92 original MIT icons as tintable sprite sheets, with search, aliases and imported packs (see `assets/icons/`) |
| Util | Signal, Trove (cleanup), RateLimiter (token bucket), Validate (remote argument checks) |

### Items and economy

| System | What it does |
|---|---|
| [Inventory](src/Systems/Inventory/README.md) | Slot inventory with an item registry, stacking, a capacity, a hotbar, filtering and sorting |
| [Pickup](src/Systems/Pickup/README.md) | World item pickup |
| [Equipment](src/Systems/Equipment/README.md) | Configurable equipment slots, equip and unequip rules with level and tag requirements, and stat aggregation with flat bonuses and multipliers |
| [Crafting](src/Systems/Crafting/README.md) | Recipes with inputs, outputs, a duration and an optional station tag; an atomic craft transaction against an inventory value; and a timed job queue driven by an... |
| [Resources](src/Systems/Resources/README.md) | Gatherable resource nodes: health, a weighted yield table rolled with an injected random source, respawn timers, tool tiers and per-player gather cooldowns |
| [Shop](src/Systems/Shop/README.md) | A catalog priced in any Currency currency, with global stock, per-player purchase limits and timed sales, plus an idempotent Robux developer product receipt handler |
| [Currency](src/Systems/Currency/README.md) | Multi-currency wallets with overflow and negative protection, atomic multi-currency spending, transfers, a transaction log ring buffer tagged with sources and sinks,... |

### Progression and retention

| System | What it does |
|---|---|
| [Quests](src/Systems/Quests/README.md) | Data-driven quests and missions |
| [Achievements](src/Systems/Achievements/README.md) | Achievements driven by event counters (kills, crafts, purchases) or observed stats (level, best score), with hidden achievements, progress for UI, idempotent unlocks... |
| [DailyRewards](src/Systems/DailyRewards/README.md) | Daily login rewards with streaks |
| [Leaderboards](src/Systems/Leaderboards/README.md) | Global and in-server leaderboards |

### Persistence and settings

| System | What it does |
|---|---|
| [SaveData](src/Systems/SaveData/README.md) | Player data persistence: schema versions with a migration chain, reconciling defaults, session-lock decisions, retries with exponential backoff, request-budget... |
| [Settings](src/Systems/Settings/README.md) | Player settings from a schema: booleans, number ranges with steps, enums and keybinds, with defaults, validation and clamping, versioned saves with migrations, and... |

### World and characters

| System | What it does |
|---|---|
| [NPC](src/Systems/NPC/README.md) | Behaviour for non-player characters: a finite-state machine, a small behaviour tree, perception tests, patrol routes and stuck detection, all pure and tested |
| [Dialogue](src/Systems/Dialogue/README.md) | Branching conversations as data: nodes with text, choices that show only when their conditions pass, and actions that change variables or emit effects |
| [Zones](src/Systems/Zones/README.md) | Region detection: shops, safe zones, music areas and capture points |
| [Checkpoints](src/Systems/Checkpoints/README.md) | Stage progression for obbies, races and level-based games |
| [Vehicles](src/Systems/Vehicles/README.md) | Arcade vehicle driving built on Roblox constraints |
| [Placement](src/Systems/Placement/README.md) | Grid building for tycoons, sandboxes and housing: snapping, rotation steps, footprint collision, plot bounds, per-item and per-plot limits, save and load |
| [Binder](src/Systems/Binder/README.md) | Binds a class to a CollectionService tag |

### Match flow and social

| System | What it does |
|---|---|
| [Rounds](src/Systems/Rounds/README.md) | A round loop for any round-based game: Intermission, Starting, InProgress, Ending, then back to Intermission |
| [Teams](src/Systems/Teams/README.md) | Team assignment and balancing (by player count, optionally by skill), friendly-fire and self-damage rules, team scores and standings |
| [Matchmaking](src/Systems/Matchmaking/README.md) | Queue players (solo or as parties) across servers and send each assembled match to a reserved server |

### Player experience

| System | What it does |
|---|---|
| [Notifications](src/Systems/Notifications/README.md) | Server-to-client notifications (toasts, banners, reward pop-ups) with types, priorities, a dedupe window, per-player rate limits and a client display queue |
| [Loading](src/Systems/Loading/README.md) | A loading screen controller: waits for `game.Loaded`, preloads assets with `ContentProvider:PreloadAsync` in batches, smooths the progress bar, keeps the screen up... |
| [Input](src/Systems/Input/README.md) | One action map for keyboard, mouse, gamepad and touch |

### Operations

| System | What it does |
|---|---|
| [Analytics](src/Systems/Analytics/README.md) | A safe front end for Roblox `AnalyticsService` |

## Testing

From `library/`: `lune run tests/run` runs every spec. CI also runs Selene, StyLua, strict `luau-analyze` on the pure modules, a whole-library `luau-lsp` type check (report-only), and `rojo build`.

**What is not verified:** server and client adapters, and UI runtime behaviour, need a Studio playtest. Each README ends with a checklist. The adapters were written without a Studio run, and the READMEs list the Roblox API names to confirm.
