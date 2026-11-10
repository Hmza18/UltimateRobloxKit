# Licensing and reuse

This research exists to extract **ideas**. UltimateVisualsKit (UVK) ships no third-party game assets, names, code or text.

## What may be reused

| Kind | Status | Why |
|---|---|---|
| Design ideas, interaction patterns, pacing, layout conventions | Reusable | Ideas and general game mechanics are not protected expression. Every pattern in [pattern-matrix.md](pattern-matrix.md) is stated in generic terms |
| Roblox engine APIs and their documented behaviour | Reusable | Public platform, used as intended |
| Facts from the Creator Hub documentation | Reusable as facts. Quoted prose needs attribution | The documentation repository states CC BY 4.0 for prose and MIT for code samples (L04 in [sources.md](sources.md)). These files paraphrase and cite; they do not copy passages |
| Concepts from open-source libraries (springs, motors, additive shake) | Concept reusable. Code only under its licence | `spr` is MIT (L01). UVK implements its own engine in `library/src/Visuals/Core/` and copies no library code |
| Standard animation principles (anticipation, squash and stretch, follow-through) | Reusable | Long-established craft knowledge |

## What may not be reused

| Kind | Rule |
|---|---|
| Game names, pet names, character names, currency names, rarity names that are distinctive to one game | Never in presets, ids, sample data, screenshots or marketing. Use generic names (`Legendary`, `Secret`, `CoinBurst`) |
| Models, meshes, textures, icons, sounds, music, animations from any game | Never. Not as placeholders, not "temporarily" |
| UI layouts copied pixel for pixel, including a specific game's colour palette plus shapes plus iconography together | Do not clone a recognisable look. Rebuild the principle with UVK themes |
| Text from wikis and guide sites | Wiki text is usually CC BY-SA or all rights reserved; guide sites are all rights reserved. This research summarises in its own words and cites |
| Code from DevForum posts | Licence is unclear unless the post states one. Do not paste it into the kit |
| Code obtained by decompiling, leaks or exploit tools | Never. It was not consulted and must not be |
| Trademarks and likenesses of third-party intellectual property that some games reference | Never. UVK's `Anime` theme is a style direction only: bold outlines, speed lines, high contrast |

## Rules for implementers

1. A preset id or description must not name a game. "Rarity beam" is fine. "<Game> huge reveal" is not.
2. Demo data uses invented, generic items: "Forest Fox", "Common", "Coins".
3. Effects must look right with Roblox built-in particle textures, as required by rule 10 of [the architecture document](../../architecture/visuals.md). Optional textures are supplied by the game through `VFX.configure`.
4. If a contributor adds third-party content anyway, the repository rule applies: an entry in `third_party/manifest.json` and `SOURCES.md`, and only under a permissive licence.
5. When citing this research in user-facing docs, cite the principle, not the game.

## Statement

UVK ships no assets, names, text or code taken from any Roblox game. The games named in this directory are named only to identify where a publicly visible pattern was reported.
