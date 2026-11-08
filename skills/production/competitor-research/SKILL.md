---
name: competitor-research
description: Structured clean-room analysis of reference Roblox games - core loop, onboarding, progression, monetization, retention hooks, social features and UI - using public information and normal play only, with an output template that turns observations into original design principles. Use when studying a popular or competing Roblox game, choosing references for a pitch, or explaining why a genre leader retains players.
license: MIT
metadata:
  category: production
  version: 1.0.0
  triggers: [competitor research, reference game, competitor analysis, clean room, market research, genre analysis, teardown]
  depends: [game-design-core]
---

# Competitor research

## When to use

- Picking 2-3 reference games for a new concept.
- Understanding how a genre leader onboards, retains and monetizes.
- Checking whether an idea is already done well, and how to be different.

When not to use: designing your own loops (use `game-design-core`), planning a whole roadmap (use `production-management`), pricing your products (use `monetization-economy-design`).

## Clean-room rules

1. Public information only: playing normally as a player, the public experience page, public update logs, official community posts and public talks or videos.
2. Never decompile, extract, download or copy assets, scripts, maps, UI art, sounds, names or text. No exploit tools, no "copy game" tools.
3. Record observations and the principle behind them, not implementations. Your team designs its own solution from the principle.
4. Do not reuse distinctive names, characters or trade dress. Mechanics and genre conventions are fine; expression is not.
5. Note public numbers (visits, favourites, active players) with the date, and treat them as rough signals.

## Workflow

1. **Pick references.** 2-3 games: one genre leader, one rising game, one adjacent genre. Note why each was chosen.
2. **Play fresh.** New account state if possible (only your own accounts; never use another person's account). Record the first 10 minutes with timestamps: when you first act, first reward, first upgrade, first prompt to buy.
3. **Play deeper.** 1-2 hours across sessions: meta loop, rebirth or prestige, social features, events.
4. **Fill the template** in [references/output-template.md](references/output-template.md) for each game.
5. **Compare.** One table across games: what everyone does (genre expectation), what only the leader does (possible advantage), what players complain about in public comments (opportunity).
6. **Write principles.** 5-10 lines in the form "Players expect X because Y; we will do Z". Feed them into `docs/gdd.md`.

## Outputs

- `docs/research/<game-slug>.md` per game, and `docs/research/summary.md` with the comparison and principles.

## Validation

- Every claim cites its source type (played on date, experience page, update log).
- No copied assets, text or code anywhere in the project from the reference.
- Principles are phrased so the implementation is your own.

## Pitfalls

- Copying surface features (UI layout, art style) instead of the reason they work.
- Judging monetization fairness from your own spending tolerance; look at it through a child player's eyes too.
- Over-trusting player counts; featuring and trends move them.

## Limitations

- Sees only what players see; internal metrics of other games are unknown.
- Public numbers and trends change quickly; date every observation.
- Not legal advice on IP; ask a qualified person if a design feels close to someone else's.
