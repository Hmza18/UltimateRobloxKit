# Grow a Garden

Farming game: buy seeds from a rotating shop, plant, wait, harvest and sell. Weather events apply "mutations" to crops that multiply their value.

**Evidence strength: moderate for mutations (many guides, some conflicting), thin for UI.** Several search results concerned a sequel or a similar game and were not used. Source ids are in [../sources.md](../sources.md); all are search summaries. The game was not played and its code was not inspected.

## UI structure

- **Documented.** The seed shop's stock refreshes every 5 minutes and is identical for everyone in the experience; other shops restock on a cycle too; a restock can be bought early (G75, G74).
- **Documented.** Seed rarities run Common, Uncommon, Rare, Legendary, Mythical, Divine, Prismatic (G74). Sources do not describe the colours used.
- **Assumed.** The shop is a scrolling list of rows with icon, name, rarity-coloured label, stock count and price, with a countdown to the next restock at the top.
- **Assumed.** The HUD is sparse: currency, a few shortcut buttons, the tool hotbar. The world carries the information.

## UI animation

- **Assumed.** A notification announces restocks and weather events to the whole server.
- **Assumed.** The countdown is the main recurring motion in the shop; out-of-stock rows are greyed, following the convention that grey means unusable (P21).

## VFX

- **Documented.** Mutations change how a crop looks and multiply its sale value (G70).
- **Observed (guide and fan-wiki descriptions).** Examples of mutation looks: semi-transparent with flashing colours (G71); bright neon green, with a related variant in darker green (G72); a golden glow; a rainbow pulse; a purple glow with recolouring; a red mist (G73 and the summary of G70).
- **Documented.** Weather events are the main source of mutations (G78). The cause is visible in the sky and the result is visible on the plant.
- **Assumed.** Mutations combine on one crop, so the visual system layers recolour, material and particle effects.

## Animation and game feel

- **Assumed.** Plants grow in visible stages; harvest gives a small pop and a pickup.
- **Assumed.** Pace is calm. Excitement comes from scarcity (a rare seed in stock) and from weather, not from fast motion.

## Technical inferences

All **Assumed**.

- Shop stock is server state replicated to all clients, which is what makes the shared restock a social event.
- A mutation is a small data tag on the crop; the client maps each tag to a recolour, material or emitter. This keeps hundreds of crops cheap to replicate.
- With hundreds of plants per plot, per-crop particles must be few, low-rate and distance-culled (P01 gives the mobile rate limit). A recolour or material is nearly free; an emitter is not.

## Reusable principles

1. Tell value with appearance: a variant should look different in the world, so players can spot it without opening a menu.
2. Layer cheap modifiers first (colour, material), then one small emitter, and only for the rarest add light.
3. A shared, timed shop creates anticipation with almost no animation: a countdown is enough.
4. Tie world events to visible outcomes so cause and effect can be seen.
5. Keep the HUD quiet when the world already shows the state.

## Sources

G70, G71, G72, G73, G74, G75, G76, G77, G78, P01, P21. See [../sources.md](../sources.md).
