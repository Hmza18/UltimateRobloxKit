# __GAME_NAME__

Made from the UltimateRobloxKit `simulator` template, which is `starter-game` plus the simulator overlay.

## Simulator overlay

Adds a clicker-simulator loop on top of `starter-game`. The new project gets every base file plus:

| File | Purpose |
| --- | --- |
| `src/shared/SimConfig.luau` | click value, cooldown and upgrade table (`Power`, `Multiplier`) |
| `src/shared/Logic/SimFormulas.luau` | pure maths: click value, upgrade cost, cooldown, affordable levels |
| `src/server/Services/ClickService.luau` | `Collect` remote: rate-limited, server cooldown, server-computed reward |
| `src/server/Services/UpgradeService.luau` | `BuyUpgrade(upgradeId)` remote, validated against the upgrade list |
| `src/client/Controllers/ClickController.luau` | click or tap to collect, E and Q to buy upgrades |
| `tests/simformulas.spec.luau` | Lune tests for SimFormulas, picked up by `tests/run.luau` |

## Security model

The client never sends an amount. `Collect` takes no arguments, and the server decides the reward
from saved upgrade levels and rebirths. `BuyUpgrade` accepts only ids in `SimConfig.Upgrades`. Both
remotes have a per-player token bucket, and `Collect` also has a server-side cooldown.

## Data

Upgrade levels are saved in `data.progress["upgrade:<Id>"]`, so the base save format is unchanged.
A rebirth (R) resets coins but keeps upgrades. To also reset upgrades, clear those progress keys in
`EconomyService:Rebirth`.

## Next steps

- Show upgrade prices in the HUD. They are mirrored as `Upgrade_<Id>` attributes, and
  `UpgradeService:GetCost` gives the next price.
- Add pets or areas as more `SimFormulas` inputs, with tests first.

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
