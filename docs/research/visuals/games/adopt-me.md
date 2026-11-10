# Adopt Me!

Pet-raising and trading role-play game. Players hatch eggs, complete pet needs to age pets, fuse pets into glowing variants, and trade.

**Evidence strength: moderate for UI changes (one official news post found), thin for animation.** Source ids are in [../sources.md](../sources.md); all are search summaries. The game was not played and its code was not inspected.

## UI structure

- **Documented.** A 2024 revamp moved pet needs to icons shown directly above the pet's or baby's head, which freed HUD space (official news post, G50). Players who prefer the old menu can restore it in Settings (G51).
- **Documented.** Backpack category tabs changed from text to icons and the second page was removed (G52). A later update added a separate Storage space beside the Backpack (G53).
- **Documented.** A Journal screen shows collection progress and pet ages (G54).
- **Documented.** Progress toward the next age is a bar, and a later friendship bar works the same way (summary found with G53, G54).
- **Assumed.** The palette is soft and pastel with rounded panels and large icons, suited to a young audience; text is short.
- **Assumed.** Trading uses a two-column confirm screen with explicit accept states and a delay before confirming, to slow down mistakes and scams.

## UI animation

- **Assumed.** Need icons above the pet bob or pulse gently and show a fill or ring as the need completes.
- **Assumed.** Completing a need plays a small reward moment: icon pops, currency flies to the counter.

## VFX

- **Documented.** The higher fused tier's glow shifts through rainbow colours (G56 and related guides). That the glow sits on designated body parts and not the whole model is **Assumed**. One guide (among G55 to G57; the summary did not say which) says the colour changes every 1 to 2 seconds (estimate, unverified). A 2025 update lets players choose the palette (G58).
- **Documented.** Neon pets have their own named age stages (G57). Progress is expressed in the fiction, not only as a number.
- **Documented.** Fusion happens by placing four pets on four marked circles in a dedicated place (G55). The ritual location and layout are part of the reward.

## Animation and game feel

- **Assumed.** Egg hatching is slow by design: the egg is carried and cared for like a pet, then cracks with a short reveal. The delay is the anticipation.
- **Assumed.** Pets have idle, follow, sit and trick animations; ride and fly are mount states with their own camera feel.
- **Assumed.** Motion is gentle: slow eases, small overshoots, no camera shake.

## Technical inferences

All **Assumed**.

- Need icons are BillboardGuis attached to the pet, visible mainly to the owner, culled by distance.
- The glow is a material or colour change on designated parts driven by a client-side loop; one timer shared by all cycling pets is cheaper than one per pet.
- Offering a setting to revert a UI change (G51) suggests the old and new UIs read the same state.

## Reusable principles

1. Put status on the object it describes when that frees HUD space.
2. Replace text tabs with icons once the set is stable, and keep labels available for accessibility.
3. A glow variant should be a few designated parts with a slow colour cycle, not a whole-model effect.
4. Match motion energy to audience and fiction: a nurturing game uses soft, slow motion.
5. Let players opt out of a big UI change.

## Sources

G50, G51, G52, G53, G54, G55, G56, G57, G58. See [../sources.md](../sources.md).
