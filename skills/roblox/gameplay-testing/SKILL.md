---
name: gameplay-testing
description: Tests Roblox gameplay end to end - unit tests for pure logic with Lune, scripted playtest checklists per feature, multi-client tests in Studio (Clients and Servers), device emulation for UI, network-lag simulation, soak tests for leaks, regression lists, and bug reports that reproduce. Use before calling a feature done, before a release, or when asked to playtest or QA a game.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [playtest, test the game, qa pass, test plan, regression, multi client test, test checklist, does it work]
  depends: [roblox-testing-debugging]
---

# Gameplay testing

Automate what is pure, script what is not, and say plainly which parts a person must still play.

## Workflow

1. **Automated layer**: `lune run tests/run` (kit library specs live in `tests/urk/`, run with `lune run tests/urk/run tests/urk`). Every rule (prices, rewards, cooldowns, progression) must have a spec. Add missing ones first.
2. **Static layer**: `selene src`, `stylua --check src`, and `python3 $URK/urk.py check .` for configuration.
3. **Feature checklist**: write one per feature from the template below and run it in Studio. Record pass/fail per line.
4. **Multiplayer**: Test → Clients and Servers with 2-3 players. Check replication (what others see), ownership (who can use what), and joining mid-round.
5. **Devices**: Device emulator for phone (portrait and landscape), tablet, 1080p and 4K desktop, and console (10-foot UI, gamepad only). Every action must be reachable without a keyboard.
6. **Network**: Studio Settings → Network → Incoming Replication Lag 0.2-0.5 s. Look for double purchases, rubber-banding, UI that trusts its own prediction.
7. **Exploit pass**: from the client, call each remote with wrong types, negative numbers, other players' ids and at high frequency (in a test place). The server must reject all of them (`roblox-security-anti-exploit`).
8. **Soak**: run 20-30 minutes with the Developer Console Memory tab open; memory must plateau.
9. **Report** with the bug template; group by severity.

## Feature checklist template

```
Feature: <name>        Build: <commit>        Tester: <who>      Date:
[ ] Happy path: <steps> -> <expected>
[ ] Limits: zero, max, full inventory, no money
[ ] Repeat fast: double-click / spam the action
[ ] Leave and rejoin: state persists
[ ] Two players at once: no duplicates, no stealing
[ ] Phone + gamepad: reachable and readable
[ ] Lag 0.3 s: no double effects
```

## Bug report template

Title (what, where), steps to reproduce from a fresh join, expected, actual, frequency, client or server error text, build or commit, device, severity (crash or data loss, blocks play, wrong but playable, cosmetic).

## Limitations

Studio playtests, device feel and fun are human judgements. An agent can prepare checklists, run automated layers and read Studio output through Studio MCP, but must report manual items as not yet run.
