# Blox Fruits

Action RPG with melee, swords, guns and elemental powers, set on islands across seas. Players level up by fighting, and unlock and upgrade abilities.

**Evidence strength: thin.** Search returned beginner guides and many low-quality pages; guides disagree on details, and nothing retrieved describes hit effects, camera response or damage numbers. Source ids are in [../sources.md](../sources.md); all are search summaries. The game was not played and its code was not inspected.

## UI structure

- **Documented.** Health and energy bars sit at the bottom left; energy drains while dashing and refills when the player stops (G01). The developers' own description, relayed by a guide, covers the two bars, a level and experience bar, and a money display (G02).
- **Documented.** A compass is on the left side of the screen (G01).
- **Documented.** A single menu button expands into a small set of buttons (Stats, Allies, Shop are named; another guide describes a four-button grid) (G02, G01). Secondary screens are collapsed behind one control.
- **Documented.** Skills map to Z, X, C, V and F on keyboard and to numbered skill buttons on touch, plus attack and interact buttons; controls cannot be rebound (G03).
- **Assumed.** Skill buttons show a cooldown overlay and sit in the right-hand thumb area on mobile, consistent with platform guidance on thumb zones (P15).
- **Assumed.** Styling is plain: dark semi-transparent panels, white text, little decoration. The spectacle is in the world.

## UI animation

- **Assumed.** Bars animate toward their new value, and a lagging "ghost" segment shows recent damage.
- **Assumed.** Cooldowns are radial or vertical wipes with a small flash when ready.
- **Assumed.** Level-up shows a brief banner.

## VFX

- **Documented.** Upgrading ("awakening") a power improves its moves and adds new visual effects; sources conflict on exact contents (G04, G05).
- **Assumed.** Each element has a consistent colour and particle language (fire warm and rising, ice pale and sharp, light bright and linear) used across all its moves.
- **Assumed.** Large moves are built from layered pieces: a ground ring or shockwave, a burst, lingering particles and a light.
- **Assumed.** A toggled power-up state shows as an aura or body tint.

## Animation and game feel

- **Assumed.** Moves have a short wind-up (anticipation), an active burst and a recovery; bigger moves have longer wind-ups (estimate 0.2 to 0.8 s).
- **Assumed.** Heavy hits use camera shake and sometimes a brief field-of-view kick; light hits do not.
- **Assumed.** Mobility is fast (dashes, air jumps, flight), with trails to keep the character readable at speed.

## Technical inferences

All **Assumed**.

- The server decides hits and damage; clients render effects. Community guidance is that the acting client plays its own effect immediately and the server tells the others (F05, F06).
- In a crowded fight the client must limit other players' effects by distance and count; the platform's mobile emitter rate is a quarter of desktop (P01).
- Effect pieces are reused from a pool, since the same moves repeat constantly.

## Reusable principles

1. Keep combat HUD at the edges and quiet; put the spectacle in the world.
2. One element, one visual language: colour, shape and motion stay consistent across moves.
3. Scale camera response to the weight of the hit; no shake for light hits.
4. Collapse secondary menus behind one button.
5. Every ability has anticipation, action and recovery, with duration proportional to power.

## Sources

G01, G02, G03, G04, G05, P01, P15, F05, F06. See [../sources.md](../sources.md).
