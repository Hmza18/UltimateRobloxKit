# Steal a Brainrot

Base-building and raiding game. Characters walk along a central path and can be bought; they stand in the player's base earning money; other players can carry them off unless the base is locked.

**Evidence strength: moderate for mechanics, thin for visuals, with conflicting numbers between guides.** Source ids are in [../sources.md](../sources.md); all are search summaries. The game was not played and its code was not inspected.

## UI structure

- **Documented.** Eight rarity tiers ordered from Common up to tiers above Mythic (G82). The ladder extends past the usual top with named ultra tiers.
- **Documented.** Each owned unit generates money over time; rarer costs more and earns more (G82).
- **Documented.** Rebirth resets cash, units and upgrades for permanent multipliers, longer lock time, more slots and new gear (G83).
- **Assumed.** Each unit shows a floating label with name, rarity, mutation and income rate, so a visitor can price a base at a glance. No source retrieved describes it.
- **Assumed.** The HUD is small: cash, rebirth, shop, index. Most information is on world labels.

## UI animation

- **Assumed.** A server-wide notification announces very rare spawns, pulling players to the same spot.
- **Assumed.** A victim gets an urgent alert (sound plus screen-edge or banner cue) when one of their units is being taken.

## VFX

- **Documented.** A base can be locked for a limited time (guides give 30, 50 or 60 seconds to start, more with rebirths) and the lock is drawn as a laser barrier, red by default and other colours with certain base skins (G80, G84).
- **Documented.** A unit can have one mutation, a permanent visual change that multiplies income, and several stackable traits (G86).
- **Observed (guide descriptions).** Mutation looks are whole-model recolours or materials: fully golden; blue and crystal-like; rainbow; red; neon purple. Newer seasonal mutations use a special texture (G85, G88, G89).

## Animation and game feel

- **Documented.** Units for sale walk toward players along a central path or conveyor (G82, G83). The shop is a parade in the world, not a menu.
- **Assumed.** Carrying a stolen unit slows or marks the thief, creating a visible chase.
- **Assumed.** Motion is deliberately crude and comic; humour comes from the characters, not from polish.

## Technical inferences

All **Assumed**.

- Lock state and timer are server-authoritative and replicated; the barrier is a client visual bound to that state.
- Mutations are a material or colour override applied to all parts of the model: almost free, and it scales to a server full of units.
- Floating labels are BillboardGuis with a distance limit; with dozens per base they must be static text, not animated (F10 notes that editing billboard content often costs performance).

## Reusable principles

1. A timed protection needs a visible barrier, a visible countdown and a clear end state.
2. Whole-model recolour is the cheapest strong variant signal.
3. Putting stock in the world (a parade, a conveyor) turns browsing into an event others can see.
4. Server-wide announcements of rare spawns create shared moments.
5. One mutation plus stackable traits: one dominant look, with small additive badges.

## Sources

G80, G81, G82, G83, G84, G85, G86, G87, G88, G89, F10. See [../sources.md](../sources.md).
