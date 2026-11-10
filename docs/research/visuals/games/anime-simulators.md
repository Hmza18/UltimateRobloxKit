# Anime-style simulators and combat games

Covers the family of anime-themed Roblox games that share presentation habits: unit-summoning tower defence games, anime "fighter" collection simulators, and arena combat games. Named only where a source was found.

**Evidence strength: thin.** Sources cover summon odds and banner structure, not animation. Source ids are in [../sources.md](../sources.md); all are search summaries. No game was played and no code was inspected.

## UI structure

- **Documented.** Units are obtained from "banners" by spending a currency on a single summon or a batch of ten (G91). Limited banners rotate on a schedule (G94).
- **Documented.** Rarity ladders run Rare, Epic, Legendary, Mythic, with a Secret tier above; published odds fall steeply toward the top (G90, G92). Guides disagree on the exact figures.
- **Documented.** The Secret unit on a banner is shown as a silhouette instead of a full render (G91).
- **Documented.** Pity counters guarantee a high rarity after a fixed number of summons (G95), and a separate "shiny" chance applies on top of rarity (G90, G93).
- **Assumed.** Banner screens are art-led: large character art, a rarity-coloured name plate, odds behind an info button, and two large buttons for one and ten.
- **Assumed.** Typography is heavy, italic and outlined, with high-contrast dark panels and saturated accent colours.

## UI animation

- **Assumed.** A batch of ten reveals as a staggered row or grid of cards that flip or drop in one by one (estimate 60 to 120 ms apart), with higher rarities delayed or emphasised.
- **Assumed.** A high-rarity result interrupts the batch with a full-screen moment before the grid appears.
- **Assumed.** A skip control is always present during summons.

## VFX

- **Assumed.** Rarity is signalled before the reveal by the colour of a beam, glow or flash, so the player reads the outcome a beat early (anticipation by colour).
- **Assumed.** Shiny variants get a sparkle overlay and a distinct tint in both the reveal and the roster.
- **Assumed.** Combat effects use anime conventions: speed lines, impact frames (a one or two frame flash or inverted colour), bold coloured outlines, and large numbers.

## Animation and game feel

- **Assumed.** Strong poses and holds: a short freeze on impact (hit stop, estimate 40 to 100 ms), then fast follow-through.
- **Assumed.** Ultimate abilities take camera control briefly for a short cinematic, then return it.
- **Assumed.** Timing is snappier than in pet simulators: shorter eases, sharper overshoot.

## Technical inferences

All **Assumed**.

- Summon results are rolled on the server, pity included; the client plays the reveal for the returned list.
- Impact frames are a full-screen UI flash or a colour-correction change for a few frames. Both must respect a reduced-flashing setting.
- Cinematics temporarily set the camera to scriptable control and must restore it on completion, skip, death or respawn.

## Reusable principles

1. Show the unknown as a silhouette: hiding the top prize raises anticipation at no cost.
2. Batch reveals are staggered, ordered so the best lands last, and always skippable.
3. Telegraph rarity by colour a beat before the reveal.
4. A short hold on impact reads as weight; keep it brief and optional.
5. Taking the camera is a loan: always give it back, on every exit path.

## Sources

G90, G91, G92, G93, G94, G95. See [../sources.md](../sources.md).
