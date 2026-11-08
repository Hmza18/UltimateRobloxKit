# __GAME_NAME__

Made from the UltimateRobloxKit `tycoon` template, which is `starter-game` plus the tycoon overlay.

## Tycoon overlay

Adds a classic tycoon loop on top of `starter-game`. The new project gets every base file plus:

| File | Purpose |
| --- | --- |
| `src/shared/TycoonConfig.luau` | tag names, drop limits, demo-world switch |
| `src/shared/Logic/TycoonMath.luau` | pure rules: next free plot, prerequisite lists, drop value, income |
| `src/server/Services/PlotService.luau` | claim and release plots, ownership lookups, spawn on your plot |
| `src/server/Services/PurchaseButtonService.luau` | step-on buttons with cost and prerequisites, saved purchases |
| `src/server/Services/DropperService.luau` | timed drops, server-owned physics, collectors pay the owner |
| `src/server/Services/TycoonWorldService.luau` | builds two sample plots if the place has none |
| `tests/tycoonmath.spec.luau` | Lune tests for TycoonMath |

## Building your own plots

Tag instances in Studio with the names in `TycoonConfig.Tags`:

- **Plot**: a Model holding one tycoon. Optional `PlotIndex` attribute (claim order), a Part named
  `Spawn`, and a Folder named `Purchases`.
- **PurchaseButton**: a Part with attributes `ButtonId` (string), `Cost` (number), `Unlocks` (name of a
  child of `Purchases`) and optional `Requires` (comma-separated ButtonIds).
- **Dropper**: a Part with optional `DropValue` and `Interval` attributes.
- **Collector**: a Part. Drops that touch it pay the plot owner.

Once any Plot-tagged instance exists, the demo world is not built.

## Rules the server enforces

- A plot is claimed only after the player's data loads. It is released when they leave, and every
  purchase is hidden again for the next owner.
- Only the plot owner can buy its buttons. Each button checks its prerequisites and cost on the server.
  Hidden buttons have `CanTouch` turned off.
- Drops belong to the owner who spawned them, so a collector pays only that player. Their physics is
  server-owned, and the number per plot is capped.
- Purchases are saved as `data.progress["tycoon:<ButtonId>"] = 1` and restored on the next claim.

## Base project

Everything from `starter-game` is included: the service and controller loaders, `Net`,
`PlayerDataService`, `EconomyService`, `InventoryService`, the pure `src/shared/Logic` modules and the
Lune tests. See the UltimateRobloxKit `templates/starter-game/README.md` for the full structure and
type-checking setup.

```bash
rokit install               # install the pinned tools
rojo serve                  # live-sync into Studio
rojo build -o game.rbxl     # build a place file
selene src tests            # lint
stylua --check src tests    # formatting check
lune run tests/run          # logic tests, including this template's spec file
```
