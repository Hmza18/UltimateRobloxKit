---
name: game-design-core
description: Core game design for Roblox experiences - concept development with a pitch one-pager, core and meta loops, first-five-minutes onboarding (FTUE), progression design, difficulty curves, social features, and genre patterns for simulators, tycoons, obbies, RPGs, horror and battle games, plus a GDD and MVP scope template. Use when starting a new game idea, scoping an MVP, fixing poor early retention or a confusing first session, or deciding what to build next.
license: MIT
metadata:
  category: gameplay
  version: 1.0.0
  triggers: [game design, core loop, gdd, mvp, onboarding, ftue, pitch, progression curve, difficulty curve, game concept, genre]
  depends: [roblox-quests-progression, competitor-research]
---

# Game design core

## When to use

- A new idea needs shaping into something buildable.
- Scoping an MVP or a vertical slice.
- Players leave in the first minutes, or the game feels aimless after an hour.

When not to use: prices, currencies and payments (use `monetization-economy-design`), quest and level systems in code (use `roblox-quests-progression`), simulator or tycoon code patterns (use `roblox-simulator-tycoon`), schedules and milestones (use `production-management`).

## Inputs

- The idea in one sentence, target audience (age range, platform), team size and time budget.
- Optional: 2-3 reference games analysed with `competitor-research`.

## Workflow

1. **Pitch one-pager.** Fill the pitch section of [references/gdd-mvp-template.md](references/gdd-mvp-template.md): hook, fantasy, core verb, why it is fun with friends, why it is different from the references. If the hook does not fit in one sentence, it is not ready.
2. **Core loop** (seconds to a minute): act -> reward -> improve -> act again. Write it as a cycle of 3-5 verbs, for example "mine -> sell -> upgrade pick -> mine deeper". Every step needs feedback (sound, number pop, visual change).
3. **Meta loop** (sessions to weeks): what the player is working toward: zones, collections, rebirth/prestige, ranks, building, story. The meta loop must feed back into the core loop with new choices, not only bigger numbers.
4. **First five minutes (FTUE).** Timeline target:
   - 0-10 s: spawn facing the first action; one short instruction, shown not told (arrow, glow, NPC).
   - 10-60 s: first success and first reward.
   - 1-3 min: first upgrade or choice; introduce one system at a time.
   - 3-5 min: a visible next goal (a gate, a rare item, a friend's base) and a reason to come back.
   No menus forced before play, no paywall, no long text. Skippable for returning players. Track each step as an onboarding funnel event (see `monetization-economy-design` for analytics).
5. **Progression.** Choose the progression axes (power, access, cosmetics, mastery, social status). Lay out a level or unlock table in a spreadsheet with time-to-next per step. Rules of thumb: early unlocks every 1-3 minutes, mid-game every 10-30 minutes, long goals over days. Prefer horizontal unlocks (new options) alongside vertical ones (bigger stats).
6. **Difficulty curve.** Teach, test, then twist: introduce a mechanic safely, test it, then combine it with another. Use a saw-tooth curve with rest beats after spikes. Make failure cheap and fast to retry (obbies: checkpoints every 10-30 s of play). Offer catch-up for new players in shared servers.
7. **Social features.** Decide what playing together adds: co-op goals, trading, visiting bases, shared server events, leaderboards, parties. Make it better with friends but complete alone. Respect Roblox chat and safety settings; never require off-platform contact.
8. **Genre pattern.** Start from the matching pattern below, then change one thing meaningfully.
9. **MVP scope.** Fill the MVP section of the template: must-have (the loop playable end to end), should-have, cut. The MVP proves the core loop is fun in a 10-minute session; meta systems come after.
10. **Playtest early.** Watch 5 new players without helping. Note where they stop, ask "what were you trying to do?". Change the design, not the player's understanding.

### Genre patterns

| Genre | Core loop | Meta loop | Watch out for |
|---|---|---|---|
| Simulator | Click/collect -> sell -> upgrade capacity/speed | Zones, pets, rebirth | Pure number inflation; add choices and goals |
| Tycoon | Earn -> buy droppers/buildings -> base grows | Rebirth, decorations, visiting | Long idle waits; keep the player acting |
| Obby | Jump -> checkpoint -> next stage | Stage count, difficulty tiers, cosmetics | Unfair jumps, camera fights, no checkpoints |
| RPG | Fight/quest -> loot/XP -> build | Story, classes, gear sets, bosses | Content treadmill; plan reusable systems |
| Horror | Explore -> threat -> escape/solve | Chapters, lore, co-op roles | Darkness without tension, jump-scare spam, age suitability |
| Battle / PvP | Fight -> eliminate/survive -> rank | Loadouts, ranks, cosmetics | Matchmaking unfairness, pay-to-win, spawn camping |

### Fair engagement rules

- Reward skill and time, not compulsion. No fake scarcity, no punishing streak loss, no FOMO countdowns aimed at children.
- Idle rewards are fine; guilt-based return prompts are not.
- Session end should feel like a satisfying stopping point, not a cliffhanger engineered to trap.

## Outputs

- `docs/gdd.md` (from the template): pitch, loops, FTUE timeline, progression table, MVP scope.
- A progression spreadsheet (CSV) in `docs/`.
- Playtest notes in `docs/playtests/<date>.md`.

## Validation

1. Hook test: three people outside the project can repeat the game's hook after hearing it once.
2. Paper or greybox playtest of the core loop is fun for 10 minutes without meta systems.
3. FTUE: 5 fresh testers reach the first reward under 60 s without help.
4. Progression table: no step exceeds its time target by more than 2x for an average player.
5. After launch: onboarding funnel step drop-off and D1 retention, read with care (see `monetization-economy-design`).

## Pitfalls

- Designing meta systems before the core loop is fun.
- Tutorials that explain everything up front; teach just in time.
- Copying a trending game's surface without its reasons; analyse why it works first.
- Scope creep: every feature not in the MVP list waits.
- Assuming players read text; most skip it, especially on mobile.

## Limitations

- Cannot predict fun; only playtests and live data confirm a design.
- Genre conventions shift with the platform's trends; refresh references with `competitor-research`.
- Retention numbers mentioned are directional, not benchmarks.
