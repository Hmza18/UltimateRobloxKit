---
name: release-management
description: Release gate for Roblox games built with the kit - run `urk release check` (lint, tests, Rojo build, security and licence audit, placeholder product ids, clean git tree) and the manual items (odds disclosure, device sizes), write release notes and rollback steps with `urk release notes`, and hand publishing to the owner. Never publishes, uploads or changes a live place. Use when preparing an update, a launch, a hotfix, or when asked whether a game is ready to ship.
license: MIT
metadata:
  category: production
  version: 1.0.0
  triggers: [release check, ready to ship, prepare a release, publish checklist, release notes, rollback plan, hotfix, launch checklist]
  depends: [roblox-publishing-liveops, roblox-security-anti-exploit]
---

# Release management

## Workflow

1. `python3 $URK/urk.py release check --project <dir>`. Each line is PASS, FAIL or NEEDS MANUAL REVIEW. Fix every FAIL at its cause.
2. Walk through the manual items with the user: odds shown for every paid random item, phone, tablet and console sizes tried in Studio's device emulator, and any feature the tests do not cover.
3. `python3 $URK/urk.py release notes --project <dir> --version 1.2.0` writes `.urk/releases/1.2.0.md` with the changes since the last tag and how to roll back.
4. Tag the commit (`git tag v1.2.0`) only when the user agrees.
5. **Stop.** The user opens the place in Studio and publishes. Report what passed, what is manual and what was not checked.

## Rules

- Never publish, upload, or change a live place, and never ask for Roblox credentials. Publishing needs the owner's explicit go-ahead and their own action.
- Never mark a manual item as passed for the user.
- Data migrations only move forward: before a rollback across a schema change, check the old server refuses newer data (SaveDataLogic does).

## Limitations

- `release check` cannot see the live place, its configured products or its analytics.
- The audit is heuristic: it names files and lines for a person to judge.
