# Project templates

| Template | Builds on | Adds |
|---|---|---|
| `starter-game` | none | Rojo layout, pinned tools, service and controller bootstrap, Net (validated remotes with rate limits), data service with session locking, inventory and economy services, pure-logic modules and Lune tests |
| `simulator` | starter-game | click/collect service, upgrades, rebirth formulas |
| `tycoon` | starter-game | plot claiming, droppers, purchase buttons, tycoon math |
| `obby` | starter-game | checkpoints, kill parts, stage saving |
| `ui` | starter-game | theme tokens, responsive scaling, accessible components, tween helpers |
| `asset-pipeline` | none (not a Rojo project) | spec folder, credits file, batch commands |

```bash
python3 scripts/automation/new_project.py --list
```

```bash
python3 scripts/automation/new_project.py --template tycoon --name MyTycoon --out ~/games/MyTycoon
```

Overlays are folders with an `overlay.json` (`{"base": "starter-game"}`) and only the files they add or replace. `__GAME_NAME__` is replaced with your name. CI composes every template and runs Selene, StyLua, `luau-analyze` (on pure logic) and Lune tests on each.

Each template's README lists its files and next steps.
