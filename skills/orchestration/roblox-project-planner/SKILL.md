---
name: roblox-project-planner
description: Plans a Roblox game or major feature before code is written - turns an idea into scope, picks an architecture (template, library systems, persistence, networking, UI approach), sequences milestones with validation gates, assigns work to subagents without file overlap, and writes PLAN.md and PROGRESS.md. Use at the start of any new game, large feature, port or rewrite, or when a project has no written plan.
license: MIT
metadata:
  category: orchestration
  version: 1.0.0
  triggers: [plan the game, project plan, plan the architecture, architecture choice, which architecture, roadmap for my game, plan.md, scope the project, milestones, planning, complete game, whole game, generate a game, game from a description, generate a complete, from a short description, urk generate]
  depends: [kit-conventions]
---

# Roblox project planner

Produce a plan the user can approve in five minutes, then hand each step to the right skills. Do not write game code in this skill.

## Inputs

The idea (one sentence is enough), target devices, team size, deadline if any, and whether the project already exists (run `python3 $URK/urk.py check <dir>` if it does).

## Workflow

1. **Clarify only what changes the plan**: genre, single or multiplayer (server size), persistence needs, monetization yes/no, target devices. Assume sensible defaults for the rest and list them as assumptions.
2. **Pick the architecture** with [references/architecture-matrix.md](references/architecture-matrix.md): a template (`starter-game`, `simulator`, `tycoon`, `obby`), the library systems to add (`python3 $URK/urk.py add --list`), persistence (kit SaveData vs ProfileStore), networking (kit Net vs Blink/Zap), UI (UrkUI tags vs code components). Record each decision with one line of why.
3. **Scope an MVP**: the core loop and the fewest systems that make it playable. Everything else goes to "later".
4. **Milestones** (each ends in something playable or testable): M0 scaffold and toolchain → M1 core loop → M2 persistence and economy → M3 UI and onboarding → M4 content (map, assets) → M5 polish, performance, security review → M6 release. Attach the workflow from `catalog/workflows.json` and its gates to each.
5. **Work split**: for each milestone list parallel tasks with an owner (subagent type) and the **files or folders each owns**. Two tasks never own the same file. Shared files (Config, Types, default.project.json) belong to one owner; others request changes through the plan.
6. **Write `PLAN.md`** from [references/plan-template.md](references/plan-template.md), and `PROGRESS.md` with every task as "todo". Show the user the plan and wait for approval before building.
7. After approval, run the first milestone with `/urk-new-game` or `python3 $URK/urk.py setup`, and update `PROGRESS.md` after each task (done, how verified, next).

## Outputs

`PLAN.md`, `PROGRESS.md`, and a list of the commands to start M0.

## Validation

- Every MVP feature maps to a milestone, and every milestone has a gate.
- No two parallel tasks own the same path.
- Every library system named exists (`urk.py add --list`).

## Pitfalls

- Planning every feature in detail up front: plan M0 to M2 precisely, keep the rest coarse.
- Choosing a framework for its popularity: prefer the kit's template plus library systems unless a requirement rules them out.
- Ignoring mobile: most Roblox players are on phones; include a phone-size UI gate in M3.

## Limitations

Estimates are rough and assume one developer with an agent. The plan cannot foresee Roblox platform changes; revisit it at each milestone.
