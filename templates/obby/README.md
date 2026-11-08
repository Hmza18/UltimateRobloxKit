# __GAME_NAME__

Made from the UltimateRobloxKit `obby` template, which is `starter-game` plus the obby overlay.

## Obby overlay

Adds saved obby progress on top of `starter-game`. The new project gets every base file plus:

| File | Purpose |
| --- | --- |
| `src/shared/Logic/StageProgress.luau` | pure rules: sanitise saved stage, advance one stage at a time, percent |
| `src/server/Services/CheckpointService.luau` | checkpoints, kill bricks, respawn at the saved stage |
| `src/server/Services/ObbyWorldService.luau` | builds a five-stage sample course if the place has no checkpoints |
| `tests/stageprogress.spec.luau` | Lune tests for StageProgress |

## Building your own course

Tag parts in Studio (Properties > Tags, or the Tag Editor):

- **Checkpoint**: a Part with a whole-number `Stage` attribute. Stage 1 is the start, and stages must
  go up by one along the course.
- **KillPart**: a Part that resets any character touching it.

Once any Checkpoint-tagged part exists, the sample course is not built. You can also set
`BUILD_DEMO_WORLD = false` in `ObbyWorldService.luau`.

## Rules the server enforces

- A checkpoint saves progress only when it is exactly the next stage (`StageProgress.advance`).
  Touching a later checkpoint after an exploit teleport does not count.
- The stage is saved in `data.progress["obby:stage"]`, sanitised on load, and mirrored to the player's
  `Stage` attribute for UI such as a stage counter or a progress bar (`StageProgress.percent`).
- Characters respawn on the checkpoint for their saved stage. A missing checkpoint falls back to stage 1.

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
