# Pet Simulator X

Predecessor to Pet Simulator 99 by the same studio. Same loop: collect currency with pets, hatch eggs, upgrade pets through variant tiers.

**Evidence strength: thin.** The developer's update posts were found by search but could not be opened; only search summaries were available. Source ids are in [../sources.md](../sources.md). The game was not played and its code was not inspected.

## UI structure

- **Documented.** Variant tiers form a strict ladder: regular, golden, rainbow, dark matter, each made at a dedicated machine (G31, G32, G33). Guides disagree on the multipliers, so none are quoted here.
- **Documented.** A later update added search to the trading and pet index screens (search summary of the developer's update notes; the exact post was not identified). Large collections need search and filters, not only scrolling.
- **Assumed.** Inventory is a grid of square tiles with the pet image, a rarity-coloured frame and small badges for variant and equipped state.
- **Assumed.** The egg purchase prompt appears when the player stands near an egg and lists contents with odds.

## UI animation

- **Documented (first Pet Simulator, 2018).** Shop button and egg information UI are hidden during the egg open animation (G34).
- **Assumed.** Popups open with a scale-in and overshoot and close faster than they open (estimate 200 to 300 ms open, 120 to 180 ms close).

## VFX

- **Observed.** Shiny pets "shine" in the world and in the inventory so they stand out (developer's update post, G30, via summary).
- **Assumed.** Golden is a solid recolour, rainbow is an animated hue cycle, the highest tier is a dark, starry material. Each tier is recognisable in silhouette-level viewing, not only up close.

## Animation and game feel

- **Documented.** A paid option opens three eggs at once (G34, for the first game), and auto hatch chains hatches without a click each time (G35). The reveal must work for 1, 3 or many results and when chained.
- **Assumed.** Hatch timeline as in [pet-simulator-99.md](pet-simulator-99.md): wobble, crack, flash, scale-in, label, hold.

## Technical inferences

All **Assumed**.

- One hatch presenter takes a list of results and lays them out, rather than separate code paths for single and triple.
- Variant visuals are data on the pet (a variant id) applied by one function to model, tile and reveal.
- Auto hatch reuses the presenter with a shortened timeline, not a different effect.

## Reusable principles

1. A variant ladder needs one distinct, cheap visual per rung: recolour, animated gradient, material swap.
2. Build the reveal for N results from the start.
3. Give large collections search and filter.
4. Hide the shop UI during the reveal it triggered.

## Sources

G30, G31, G32, G33, G34, G35. See [../sources.md](../sources.md).
