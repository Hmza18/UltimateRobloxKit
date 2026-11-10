# Pet Simulator 99

Pet-collecting simulator by BIG Games Pets, released 1 December 2023 (Documented, G22). Players break objects for currency with a team of pets, buy eggs, and hatch for rarer pets (Documented, G23).

**Evidence strength: thin to moderate.** Mechanics are well covered by guides. Visual behaviour is mostly not described in any source retrieved, and the official update posts could not be opened. Source ids are in [../sources.md](../sources.md); all game sources here are search summaries, not full pages. The game was not played and its code was not inspected.

## UI structure

- **Assumed.** HUD follows the common simulator layout: currency counters along one edge, a column or cluster of round icon buttons (inventory, shop, settings) on a side edge, and contextual prompts at world objects. No source retrieved describes the layout; this is general knowledge of the genre and must be checked against footage before being quoted.
- **Documented.** Pets have variant tiers made by combining pets at machines (gold from ten normal, rainbow from ten gold) and a rare "shiny" outcome (G24). The inventory therefore has to show type, variant and rarity on one small tile.
- **Assumed.** Variant is shown on the tile by treatment (tint, animated gradient, sparkle overlay), not only by text, because the predecessor's developer notes say shiny pets shine both in the world and in the inventory (G30, a different game by the same studio).
- **Assumed.** Mobile uses the same screens scaled down; large touch targets and few text labels.

## UI animation

- **Assumed.** Buttons scale on press and overshoot on release (estimate 80 to 120 ms down, 150 to 250 ms back).
- **Assumed.** Currency counters tick up rather than jump, and gain a short scale pulse when a pickup arrives (estimate 100 to 200 ms).
- **Documented (predecessor only).** In the first Pet Simulator the egg shop button and information panel were made invisible during the open animation (G34). The principle carries: hide competing UI while a cinematic owns the screen.

## VFX

- **Documented.** The top rarity tier has a hatch animation made specifically for it (G21). Reveal intensity scales with rarity up to a unique sequence at the top.
- **Assumed.** Rare variants carry a persistent world effect (sparkle or glow) so other players can read them at a distance.
- **Assumed.** Pickups travel toward the player before being counted (magnet behaviour), which turns many small rewards into one readable stream.

## Animation and game feel

- **Assumed.** Hatch sequence shape: egg presented in front of the camera, wobble with increasing amplitude (anticipation, estimate 0.6 to 1.2 s), crack and flash (estimate 100 to 200 ms), pet scales in with overshoot, name and rarity text appear, short hold, dismiss. Multi-hatch shows several eggs side by side on the same timeline.
- **Assumed.** Pets follow in a loose formation behind the player with smoothing, and move out to targets when working.
- **Assumed.** Repeated hatching is shortened or skippable. Auto hatch is documented for the predecessor (G35); a loop performed thousands of times cannot keep a long cinematic.

## Technical inferences

All **Assumed**, from observable behaviour and platform documentation, not from the game's code.

- Hatch results are decided by the server; the client only plays the reveal. Anything else would be exploitable.
- The hatch model is placed in the world relative to the camera, not in a ViewportFrame, if particles are shown around it. Developers report that ViewportFrames hide particles and highlights (F01, F02).
- Pet movement is simulated on each client for smoothness; the server tracks ownership and results.
- Inventory tiles use pre-rendered images or a capped number of live previews.
- Effects for other players' pets are reduced or culled by distance; mobile particle rates are a quarter of desktop (P01).

## Reusable principles

1. Reveal intensity is a ladder: each rarity adds a layer, and only the top tier gets a unique sequence.
2. A cinematic owns the screen: hide or dim other UI for its duration.
3. A repeated reveal needs a fast path and a skip from day one.
4. Variants must read in three places with one visual language: world model, inventory tile, reveal.
5. Many small rewards are merged into streams and counters, never one popup each.

## Sources

G21, G22, G23, G24, G25 (listed only), G30, G34, G35, F01, F02, P01. See [../sources.md](../sources.md).
