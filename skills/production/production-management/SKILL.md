---
name: production-management
description: Runs Roblox game production - roadmap with prototype, vertical slice, alpha, beta and launch milestones, task breakdown sized for AI agents, bug triage with a severity and priority matrix, release management checklist, update cadence, live ops calendar, clean-room competitor and retention research, and postmortems, with templates for roadmap, bug report and release checklist. Use when planning a project or milestone, splitting work into tasks, triaging bugs, preparing a release or update, or reviewing what went wrong.
license: MIT
metadata:
  category: production
  version: 1.0.0
  triggers: [roadmap, milestone, vertical slice, task breakdown, bug triage, release checklist, live ops calendar, postmortem, update cadence, production plan]
  depends: [game-design-core, roblox-publishing-liveops, competitor-research]
---

# Production management

## When to use

- Turning a GDD into milestones and tasks.
- Splitting work so agents or people can work in parallel.
- Triage of a bug backlog, release preparation, planning updates and events.
- After a launch, update or incident: postmortem.

When not to use: what the game should be (use `game-design-core`), publishing mechanics in Studio and the Creator Dashboard (use `roblox-publishing-liveops`), analysing a specific reference game (use `competitor-research`).

## Inputs

- `docs/gdd.md` with MVP scope.
- Team: people and agents, their strengths, hours per week.
- Hard dates (events, holidays, school breaks) if any.

## Workflow

1. **Milestones.** Copy [references/roadmap.md](references/roadmap.md). Each milestone has an exit test, not a feature list:
   | Milestone | Exit test |
   |---|---|
   | Prototype | Core loop playable in greybox; 5 testers find it fun for 10 min |
   | Vertical slice | One zone at final quality: art, UI, sound, saving, FTUE |
   | Alpha | All MVP systems in, content placeholder allowed, no blocker bugs in core loop |
   | Beta | Content complete for launch, private or limited public test, performance on low-end phone in budget |
   | Launch | Release checklist passed, monitoring ready, first update planned |
2. **Task breakdown for agents.** Each task:
   - fits one session (about 1-4 hours of agent work), touches a small set of files;
   - states the skill to load (for example `roblox-ui-systems`), inputs, the files to create or change, and an acceptance test that can be run or observed;
   - lists dependencies; independent tasks run in parallel, tasks touching the same module run in sequence;
   - ends with evidence (test output, screenshot path), never just "done".
   Template line: `[ID] [skill] Goal - Files - Acceptance - Depends on`.
3. **Bug triage.** Log with [references/bug-report.md](references/bug-report.md). Rate severity (impact) and priority (when to fix):
   | Severity \ Reach | Most players | Some players | Rare |
   |---|---|---|---|
   | S1 Data loss, purchase not granted, exploit, crash | P0 now, hotfix | P0 | P1 |
   | S2 Core loop blocked, progression broken | P0 | P1 | P2 |
   | S3 Feature wrong, workaround exists | P1 | P2 | P3 |
   | S4 Cosmetic, typo | P2 | P3 | P3 |
   P0: drop other work, P1: this release, P2: next release, P3: backlog. Re-triage weekly; close stale P3s.
4. **Releases.** Use [references/release-checklist.md](references/release-checklist.md) for every publish. Version the place (`vMAJOR.MINOR.PATCH`), keep a changelog, and know how to roll back (Studio version history or republishing the previous build; verify current options).
5. **Update cadence.** Pick a sustainable rhythm the team can keep, for example: small update every 1-2 weeks, content update monthly, big update per season. Announce dates only when the build is in beta. Never ship on a day nobody can watch the servers.
6. **Live ops calendar.** A 3-month rolling table: date, event or update, goal (retention, re-engagement, new players), owner, dependencies, analytics to watch. Align with school holidays in key regions. Events should be fun on their own, not only urgency mechanics; avoid stacking limited-time pressure.
7. **Research (clean-room).** Study other games' mechanics, pacing, onboarding and monetization from public play and public information only, with `competitor-research`. Never copy assets, code, maps, UI art, names or text. Write findings as principles, then design your own implementation.
8. **Retention research.** For each retention problem, form a hypothesis from data (funnel drop-off, D1) and playtests, propose one change, measure with a holdout or before/after with noted caveats (see `monetization-economy-design`).
9. **Postmortems.** Within a week of a launch, major update or incident. Blameless. Sections: summary, timeline, what went well, what went wrong, root causes (5 whys), action items with owners and dates. Track action items as tasks.

## Outputs

- `docs/roadmap.md`, `docs/tasks.md` (or the tracker), `docs/bugs/` reports, `docs/releases/<version>.md` checklists, `docs/liveops-calendar.md`, `docs/postmortems/<date>.md`.

## Validation

1. Every milestone has a testable exit criterion and a date range with buffer (add 30% for unknowns).
2. Every task has an acceptance test and a skill; no task larger than one session.
3. No open P0 at release; every P1 either fixed or consciously deferred with a note.
4. Release checklist signed for each publish; rollback tested at least once before launch.
5. Postmortem action items appear in the task list within a day.

## Pitfalls

- Feature lists as milestones; nobody knows when it is done.
- Polishing before the prototype proves fun.
- Huge agent tasks that touch many systems; they conflict and are hard to review.
- Publishing on Friday night with no one available.
- Treating every bug as urgent; priority must reflect reach.
- Live ops calendars that burn the team out; leave empty weeks.

## Limitations

- Estimates are guesses until the team has velocity data from 2-3 milestones.
- Cannot publish or check Creator Dashboard data; publishing requires a person with access and explicit permission.
- Platform features for rollback, experiments and events change; verify in creator docs.
