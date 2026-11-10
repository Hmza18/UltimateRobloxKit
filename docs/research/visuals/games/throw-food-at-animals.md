# Throw Food at Animals

**Name check.** No experience with exactly this title was found. Search consistently returned **"Throw Food For Animals"**, a 2026 experience that guide sites attribute to a developer group and describe as a simulation tycoon with several million visits (G18, G19 summaries; figures unverified). This file assumes that is the game meant and keeps the requested file name.

**Evidence strength: thin.** The game is recent, there is no official documentation, and only search summaries of fan guides were available; two wiki pages could not be opened. Guides contradict each other on shop locations and stat names. Source ids are in [../sources.md](../sources.md). The game was not played and its code was not inspected.

## UI structure

- **Documented.** Core loop: throw food down a lane to attract an animal, collect it, place it in a base where it earns money, spend money on better food and upgrades (G10, G11).
- **Documented.** A throw meter decides distance; guides say to stop it near its top value (20) for the longest throw (G11 and related summaries). One guide calls the underlying stat Throw Power, another Strength.
- **Documented.** Throw Power is trained at a pull-up bar (G17, G19).
- **Documented.** Luck sets how rare the attracted animal can be and builds as the food travels down the lane; better food raises it (G14, G19).
- **Documented.** A Details button shows mutation chances while preparing a throw (G12).
- **Documented.** Paid "lucky throw" options exist (G12, G14).
- **Assumed.** The lane is marked with distance or luck bands so the player can see what a longer throw is worth.
- **Assumed.** Base slots show each animal's income on a floating label.

## UI animation

- **Assumed.** The throw meter oscillates and the player stops it by releasing or tapping; a "perfect" stop gets a distinct flash and sound.
- **Assumed.** Luck is displayed as a number that ticks up while the food is in flight, which makes the flight time itself exciting.

## VFX

- **Documented.** Five mutations named after precious materials and rainbow, with income multipliers rising to the rarest; odds differ between normal and lucky throws (G12, G13). Sizes are a second variant axis (G13).
- **Assumed.** Mutations are whole-model recolours or materials, as in comparable games.
- **Assumed.** The food leaves a trail in flight and a splat or crumb burst on landing; the animal's arrival has a rarity-coloured burst.

## Animation and game feel

- **Assumed.** The throw has a clear arc with anticipation (wind-up while the meter runs), release, flight and landing; the camera may follow the food.
- **Assumed.** The animal approaches the food, eats, and reacts happily before being collected: a three-beat reward (attract, eat, react).

## Technical inferences

All **Assumed**.

- The result (animal, rarity, mutation, size) is rolled by the server when the throw is made; the flight and luck counter are presentation of a known result.
- The projectile is simulated on the throwing client for smoothness.
- Animals in bases are static or lightly animated models with a label, so a full server stays cheap.

## Reusable principles

1. A timing meter turns a purchase into a skill moment; reward the perfect stop distinctly.
2. Let a visible number grow during travel time, so waiting is anticipation.
3. Feeding is a three-beat sequence: food arrives, animal eats, animal reacts.
4. Use two variant axes that read differently: colour or material for mutation, scale for size.
5. Show the odds on request (a details button), not permanently.

These map directly to UVK's `feeding` presets (FoodTrail, FoodSplat, CrumbBurst, HeartBurst, TapPop) and to `Pets` reactions.

## Sources

G10, G11, G12, G13, G14, G15, G16 (listed only), G17, G18, G19. See [../sources.md](../sources.md).
