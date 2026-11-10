# Bee Swarm Simulator

Collection simulator in which the player's bees gather pollen in fields, the player converts it to honey at a hive, and honey buys eggs, tools and bags.

**Evidence strength: moderate for mechanics (fan wiki), thin for visuals.** The wiki host could not be opened; only search summaries of its pages were available. Source ids are in [../sources.md](../sources.md). The game was not played and its code was not inspected.

## UI structure

- **Documented.** Honey is the main currency and pollen is a capacity-limited resource carried in a bag, converted at the hive (G62, G63). The HUD therefore centres on two meters: a currency total and a capacity bar that fills.
- **Documented.** Every bee has a rarity and also a colour class (the wiki lists, for example, a Legendary bee that is blue, and a Common bee that is colourless) (G66). Two independent classifications are shown together.
- **Assumed.** Active buffs appear as a row of small icons with stack counts and a draining timer overlay. Not described in any source retrieved.
- **Assumed.** Visual style is flat and readable: solid colours, bold icons, little gradient.

## UI animation

- **Assumed.** The capacity bar changes colour or pulses when full, prompting the return trip. A full bar is the loop's turn signal.
- **Assumed.** Buff icons pop when a stack is added and their timer overlay resets.

## VFX

- **Documented.** Bees generate ability tokens while gathering, idling or fighting; the player collects them to trigger abilities and buffs; uncollected tokens despawn after a lifespan that stats can extend (G60, G67).
- **Documented.** Some effects trigger on every Nth token of a colour collected (G64). Counted triggers reward sustained collection.
- **Assumed.** Tokens are flat icon discs that spin or hover above the ground and fade or blink before despawning.
- **Assumed.** Gathering shows small floating numbers per collection, coloured by pollen type.

## Animation and game feel

- **Documented.** Bees follow the player, gather from fields and defend the player (G61).
- **Assumed.** Each bee has simple independent motion (fly out, hover, return), so a hive of dozens reads as a living swarm without complex rigs.
- **Documented.** Special eggs guarantee a "gifted" bee, a rarer version of a bee type (G65). **Assumed:** the gifted reveal is marked with a star motif and a stronger burst.

## Technical inferences

All **Assumed**.

- Tokens are world pickups with client-side spin and fade; collection is validated by the server.
- With many bees and tokens on screen, per-object cost has to be tiny: no particle emitter per bee, shared textures, simple parts.
- Floating numbers are merged or rate-limited (F08 gives the general forum guidance).

## Reusable principles

1. A pickup is itself feedback: a spawned, collectable, expiring token turns a passive bonus into an action.
2. Show expiry before it happens (blink or fade in the last moments) so loss feels fair.
3. A filling capacity bar is a pacing device; make "full" unmistakable.
4. Two classification axes need two channels: for example frame colour for rarity and icon or shape for type.
5. A crowd of simple movers beats a few complex ones.

## Sources

G60, G61, G62, G63, G64, G65, G66, G67, F08. See [../sources.md](../sources.md).
