# Visual research for UltimateVisualsKit

Research into how successful Roblox games present UI, motion, effects and rewards, and what the platform allows, as input to UltimateVisualsKit (UVK). The kit's design is in [the architecture document](../../architecture/visuals.md).

Date: 2026-11-10.

## Scope

Ten studies: Blox Fruits, Throw Food For Animals, Pet Simulator 99, Pet Simulator X, tapping and clicker simulators, Adopt Me!, Bee Swarm Simulator, Grow a Garden, Steal a Brainrot, and anime-style simulators and combat games. For each: UI structure, UI animation, VFX, animation and game feel, and technical structure as far as it can be inferred from outside.

Plus the Roblox platform facts that constrain any implementation.

## Method

- Public sources only: Roblox Creator Hub documentation, DevForum threads, fan wikis, guide and news sites, one official game news post, and open-source Roblox libraries.
- 30 web searches and 52 documents read in full, in one time-boxed session.
- No game was played. No game's code, assets or private data were inspected. No exploit tools, decompiled or leaked material were used; search results advertising exploit scripts were discarded.
- Patterns are generalised. Nothing here recommends copying a game's names, assets or exact look. See [licensing.md](licensing.md).

## Evidence levels

Every claim in the game files carries one of three tags.

| Tag | Meaning |
|---|---|
| **Documented** | A cited source states it |
| **Observed** | A cited guide, wiki or developer post describes how something looks or behaves on screen |
| **Assumed** | Inference from the above, from platform documentation, or from unverified general knowledge of the genre. Not checked against footage in this session |

Timing values are estimates everywhere, whatever the tag of the sentence around them.

## Limitations

Read these before relying on anything here.

1. **Game sources were not opened.** The session's network policy refused every game wiki, guide site, DevForum and Creator Hub host. For games and forum threads, "Documented" and "Observed" therefore rest on the search tool's summary of a page, not on the page. Summaries can be wrong or incomplete. [sources.md](sources.md) marks every source as Full, Summary or Listed.
2. **Platform documentation was read in full**, but from the public documentation source repository, not the Creator Hub site. Creator Hub URLs are given for convenience and were derived from repository paths.
3. **No footage was reviewed.** Almost everything about animation timing, hatch sequences, camera behaviour and HUD layout is tagged Assumed. The research is strong on mechanics and platform limits and weak on frame-level presentation.
4. **Guides conflict** on numbers (odds, multipliers, timers). No such number is used as a design input.
5. **Games change.** Several studied games update weekly; details may be out of date.
6. **One title could not be matched exactly.** "Throw Food at Animals" was requested; the experience found is "Throw Food For Animals". See [games/throw-food-at-animals.md](games/throw-food-at-animals.md).
7. **Nothing was exercised in Roblox Studio.** Platform behaviour is as documented, not as tested: `NEEDS MANUAL REVIEW`.

Evidence strength by study:

| Study | Mechanics | Visual presentation |
|---|---|---|
| Blox Fruits | Moderate | Thin |
| Throw Food For Animals | Moderate, fan guides only | Thin |
| Pet Simulator 99 | Moderate | Thin |
| Pet Simulator X | Moderate | Thin |
| Tapping simulators | Moderate | Thin |
| Adopt Me! | Good, one official post | Thin to moderate |
| Bee Swarm Simulator | Good, fan wiki summaries | Thin |
| Grow a Garden | Good | Moderate for mutation looks, thin otherwise |
| Steal a Brainrot | Moderate, conflicting numbers | Moderate for mutation looks, thin otherwise |
| Anime simulators | Moderate | Thin |
| Roblox platform | Strong, full documents | Not applicable |

## Index

| File | Contents |
|---|---|
| [pattern-matrix.md](pattern-matrix.md) | 60 reusable patterns mapped to UVK modules with priorities, and a cross-game comparison table |
| [design-principles.md](design-principles.md) | Numbered principles for timing, rarity, feedback, HUD, mobile, accessibility and performance, with a quality checklist |
| [implementation-priorities.md](implementation-priorities.md) | Ranked work list: the five P0 flagship features, foundations, P1 and P2 |
| [roblox-platform-notes.md](roblox-platform-notes.md) | Documented engine facts and limits, with what could not be confirmed |
| [sources.md](sources.md) | Every source with its retrieval class and access date |
| [licensing.md](licensing.md) | What may and may not be reused |

Game studies:

| File | Study |
|---|---|
| [games/blox-fruits.md](games/blox-fruits.md) | Blox Fruits |
| [games/throw-food-at-animals.md](games/throw-food-at-animals.md) | Throw Food For Animals |
| [games/pet-simulator-99.md](games/pet-simulator-99.md) | Pet Simulator 99 |
| [games/pet-simulator-x.md](games/pet-simulator-x.md) | Pet Simulator X |
| [games/tapping-simulators.md](games/tapping-simulators.md) | Tapping and clicker simulators |
| [games/adopt-me.md](games/adopt-me.md) | Adopt Me! |
| [games/bee-swarm-simulator.md](games/bee-swarm-simulator.md) | Bee Swarm Simulator |
| [games/grow-a-garden.md](games/grow-a-garden.md) | Grow a Garden |
| [games/steal-a-brainrot.md](games/steal-a-brainrot.md) | Steal a Brainrot |
| [games/anime-simulators.md](games/anime-simulators.md) | Anime-style simulators and combat games |

## How to use this

1. Implementers start with [implementation-priorities.md](implementation-priorities.md), then the matching rows of the pattern matrix.
2. Reviewers use the quality checklist at the end of [design-principles.md](design-principles.md).
3. Anyone about to rely on an engine behaviour checks [roblox-platform-notes.md](roblox-platform-notes.md) first, and treats "Not confirmed" rows as questions for Studio.

## Extending the research

Allow the refused hosts listed at the end of [sources.md](sources.md), read the cited pages in full, and review public gameplay footage frame by frame for the timings listed under "Research gaps" in [implementation-priorities.md](implementation-priorities.md). Upgrade tags from Assumed only when a source or footage supports them.
