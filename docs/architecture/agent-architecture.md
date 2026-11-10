# Agent architecture

## Layers

```
User request
   │
   ▼
Claude Code skill matching ── reads each installed skill's description (always in context, about 1 line each)
   │
   ▼
roblox-kit-router (skill) ── one-line index of all skills + 14 workflow recipes + gates
   │        └── route.py ── the same decision, deterministic and tested (tests/routing_cases.json)
   ▼
kit-conventions ── stop rules, naming, checkpoints, error recovery (read once per session)
   │
   ▼
2 to 8 domain skills ── loaded for the current step only
   │        └── references/ ── opened only when the skill says so
   ▼
Subagents (.claude/agents) ── parallel steps, each with only its skills
   │
   ▼
Scripts (scripts/, tools/) ── do the work and produce machine-checkable results
   │
   ▼
Validation gates ── tests, QA files, NEEDS MANUAL REVIEW for anything unprovable, user approval
```

## Token efficiency

- Skill bodies are capped at about 250 lines (enforced by tests); detail lives in `references/`.
- The router adds only direct dependencies (`depth=1`). The installer still copies transitive dependencies so links never dangle.
- Workflows list the minimum skill set. Trigger matches add at most three feature skills.
- Scripts print compact summaries and write full detail to JSON files that agents read only on failure.

## Skill discovery and dependencies

- `scripts/lib/skills.py` discovers skills in the repository (`skills/<category>/<name>`) or in an installed project (flat `.claude/skills/<name>`, kit skills identified by `metadata.category`).
- `metadata.depends` means "read alongside". Cycles are allowed (networking ↔ security) and resolution stops at visited nodes.
- `build_catalog.py` regenerates the router index, `catalog/skills.json` and the docs catalog. CI fails if they are stale.

## Parallelism

Recipes split naturally: in `new-game`, the core loop, UI, world and assets are independent after scaffolding. Give each subagent its step's skills and a clear done-condition, then run `urk-qa-reviewer` last over the combined result.

## Progress checkpoints and recovery

`kit-conventions` defines the checkpoint line (done, verified how, next), and `PROGRESS.md` for long tasks so a new session can resume. Batch tools persist state (`status.json`), so an interrupted batch resumes with `--only`. Error recovery follows read the error, fix the cause, rerun the failed stage, then the gate. After three failed rounds on one issue the agent stops and asks.

## Limits

Claude Code decides activation from descriptions. The router raises the odds of good choices but cannot force them, and live activation is not unit-testable. `route.py` is the tested proxy.
