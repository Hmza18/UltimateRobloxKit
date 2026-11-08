# Generate a game, then improve it in a loop

From one sentence to a project that builds, then a repeatable loop that measures and improves it. Every step runs a real tool. Nothing is published or uploaded.

## 1. Generate

```bash
python3 urk.py generate "supermarket simulator with 50 products and 3 worlds" --name MegaMart --out ~/games/MegaMart --dry-run
```

```bash
python3 urk.py generate "supermarket simulator with 50 products and 3 worlds" --name MegaMart --out ~/games/MegaMart
```

You get GameConfig (products, pets, eggs, worlds, upgrades, rebirths, passes), `UrkGameService` wiring Currency, Pets and Progression, screen specs, `assets/asset-plan.json`, `tests/gameconfig.spec.luau`, `economy.json` with a report, and `GAME_PLAN.md`.

## 2. Verify

```bash
cd ~/games/MegaMart && rokit install
```

```bash
python3 ~/UltimateRobloxKit/urk.py build --project ~/games/MegaMart
```

Selene, StyLua, Lune (your specs and the kit's) and a Rojo build. Each step prints PASS, FAIL or MISSING TOOL.

## 3. Data and packages

```bash
python3 ~/UltimateRobloxKit/urk.py packages --project ~/games/MegaMart
```

Then pass `ProfileStoreAdapter.new({ ProfileStore = ..., name = "PlayerData_v1" }).section("currency")` (and `"pets"`, `"progression"`) as the `store` of each server in `UrkGameService`.

## 4. The improvement loop

Run whichever loop the next task needs, as often as needed:

| Loop | Measure | Fix | Done when |
|---|---|---|---|
| Economy | `urk economy sim economy.json --players 50` | curve base and growth in `economy.json`, then GameConfig | `--strict` passes against your targets |
| Art | `urk assets suggest "<thing>"` first, then `urk assets assets/asset-plan.json --out build/products --lod` | generator parameters and colours; look at every render | QA has no FAIL and you approved each asset |
| UI | `urk ui extract ref.png`, preview and capture, `urk ui compare ref.png cap.png --diff d.png` | the lowest rubric part first | score and your eye agree |
| Security | `urk audit --project .` | the named file and line | no HIGH finding |
| Routing (kit work) | `urk skills eval` | triggers or descriptions, never against `heldout2` | tuned 100% and held-out no worse |

Record each decision so the next session knows it:

```bash
python3 ~/UltimateRobloxKit/urk.py memory add decision "First rebirth targets 20-40 minutes" --project ~/games/MegaMart
```

## 5. Release

```bash
python3 ~/UltimateRobloxKit/urk.py release check --project ~/games/MegaMart
```

```bash
python3 ~/UltimateRobloxKit/urk.py release notes --project ~/games/MegaMart --version 1.0.0
```

Fill the game pass ids, show egg odds, test device sizes in Studio, then publish yourself from Studio. The kit stops before this step on purpose.
