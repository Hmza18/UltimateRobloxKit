# Implementation priorities

How the research maps to UltimateVisualsKit work. Pattern numbers refer to [pattern-matrix.md](pattern-matrix.md); principle numbers to [design-principles.md](design-principles.md); module and preset names to [the architecture document](../../architecture/visuals.md).

Ranking rule: a feature ranks higher when (a) more of the studied games rely on the pattern, (b) the evidence for it is stronger, and (c) it is hard for a game team to build well alone. Where evidence is thin the ranking leans on (c) and says so.

## P0: flagship features

These five are what a visitor to the kit will judge it by. Each should be complete, skippable, reduced-motion aware and budgeted before any P1 work starts.

### 1. Egg hatching

- **Why first.** Central to both pet simulators and the tapping family; reveal quality is the genre's signature. Evidence that the top tier deserves a unique sequence is documented (G21); multi and auto modes are documented (G34, G35). Timeline details are assumed.
- **Patterns.** 1, 2, 3, 4, 5, 6, 48, 50, 54.
- **Build.** `Eggs.hatch` for 1, 3 or many results on one timeline: present eggs on a camera-relative world rig (not a ViewportFrame), `EggEnergy` in the rarity colour, wobble with rising amplitude and `EggShakeDust`, `EggCrack`, `EggFlash`, model swap under the flash, spring scale-in, `HatchBurst`, label, hold. `skip()` and a speed factor for auto mode. HUD lock for the duration.
- **Done when.** Works for 1, 3 and 8 or more results; skip shows every result; camera fully restored on every exit path; reduced-motion form is a fade with no shake; reduced-flashing form has no flash; per-egg particle count scales down with the number of eggs.
- **Risk.** World-rig placement in tight spaces (clipping into walls) is `NEEDS MANUAL REVIEW`.

### 2. Reward reveal

- **Why.** The rarity ladder is the most widely shared pattern across the studied games (pets, units, crops, animals all use it).
- **Patterns.** 1, 4, 5, 12, 15, 46, 47, 48.
- **Build.** `Rewards.reveal` driven entirely by rarity profiles (duration, layers, beam, shake, cue). `Rewards.batch` with staggered cards, best last, and a single full-screen interruption for the highest tier present. Silhouette state for undiscovered items. Currency rewards finish with `UI.flyTo`.
- **Done when.** Seven built-in tiers are strictly ordered in intensity (principle 2.1); each tier is identifiable without colour; two reveals in quick succession collapse to one full plus one fast.

### 3. Tapping feedback

- **Why.** The highest-frequency interaction in the genre, and the one most likely to hurt frame rate if done naively. Evidence for presentation is assumed; the performance constraints are documented or forum-backed (P01, F08).
- **Patterns.** 9, 10, 11, 13, 14, 55, 56.
- **Build.** A `Feedback` recipe for tap: `TapPop` at the touch point, pooled `UI.popup` with merge window and cap, counter pulse with merge, optional escalation by multiplier. Runs locally on the input frame.
- **Done when.** 15 taps per second for 10 s stays under the popup cap and within frame budget on the baseline phone; counter text updates at most once per frame; nothing 3D is spawned per tap on Low.

### 4. Pet selection

- **Why.** Every studied pet game needs a screen that shows type, rarity and variant on small tiles and a larger preview. Search and filter are documented needs for large collections.
- **Patterns.** 7, 8, 22, 24, 30, 31, 46, 51, 52.
- **Build.** `Pets.selection`: grid of tiles (rarity frame, variant treatment, equipped badge, silhouette for undiscovered), staggered entrance, `SelectBounce` and `PetSelect` on choice, one live `Pets.preview` in a ViewportFrame with procedural idle, icon tabs, search. Equip plays `PetEquip` on the world pet.
- **Done when.** At most one or two live ViewportFrames exist at a time; tiles are static images or cheap frames; all states are reachable by touch; the grid survives the largest text size.
- **Known limit.** Glow and particles do not render in the preview (platform notes). The preview fakes glow with UI behind the frame.

### 5. Animal feeding

- **Why.** The newest pattern in the list and the least served by existing kits. Evidence is the thinnest of the five (one recent game, fan guides only), so the design leans on general animation principles.
- **Patterns.** 16, 17, 18, 19, 20.
- **Build.** Throw meter component with a perfect zone; projectile helper with `FoodTrail`; landing `FoodSplat` and `CrumbBurst`; a growing value label bound to flight progress; arrival burst in the rarity colour; three-beat reaction through `Pets.play` (approach, eat with squash, `HeartBurst` and `HappyReaction`).
- **Done when.** The whole sequence runs from one `Feedback` recipe or `Sequence`; the reaction works on any model with a primary part; reduced motion replaces the arc with a short fade-in at the target.

## P0: foundations the five depend on

| Work | Patterns | Module | Note |
|---|---|---|---|
| Spring and tween engine with interruption and restore | 58, 51, 52 | Motion | Already in Core; verify no-jump retargeting |
| Additive camera shake presets and guaranteed restore | 44, 50, 57 | Camera | Restore on respawn is the critical test |
| Effect budget, distance cull, pooling | 55, 56 | VFX, Feedback | Mobile rate is a quarter of desktop |
| Reduced motion and reduced flashing forms for every preset | 60 | Motion, UI, Camera | Read `GuiService.ReducedMotionEnabled` by default |
| Counter and fly-to-counter | 11, 12 | UI | Shared by rewards, tapping and feeding |
| HUD lock during cinematics | 6 | Screens | Must restore after cancel |

## P1: breadth

Ordered by how many studied games use the pattern.

1. Variant and mutation treatments on world objects (patterns 7, 25, 32): recolour, material, shared-clock hue cycle. Used by six of the ten studies.
2. Followers in formation (30) with ground alignment.
3. Floating value labels and status icons on objects (22, 37).
4. Toasts and server-wide announcements with queueing (39).
5. Themes: chunky cartoon tokens for stroke, gradient, corner, depth (53).
6. Milestone moments: `LevelUp`, `Rebirth`, `Prestige`, `AreaUnlock` (15).
7. Capacity bar and progress-to-growth bar (23, 28).
8. Combat set: skill button with cooldown, element language, charge then activate (41, 43, 45).
9. Collectable expiring tokens (27).
10. Shiny overlay in world and UI (8).

## P2: depth

Timed barrier (36), shared-shop countdown (34), buff icon row (29), damage ghost bar (42), hit stop and impact frames (49), fusion ritual (26), layered modifiers (33), weather to outcome (35), stock parade (38), tutorial pointing (59), odds details panel (21).

## Not recommended

- Recreating any specific game's look, names or characters. See [licensing.md](licensing.md).
- Effects that need custom textures to read. The kit must look right with built-in textures.
- Showing reveals inside ViewportFrames to save cost. The loss of particles and post effects defeats the purpose.
- Haptics as a required channel. It is device-dependent; treat as a later optional `Feedback` step.

## Research gaps to close before polishing

These would change tuning, not architecture.

1. Frame-by-frame timing of real hatch and summon sequences. Every duration in this directory is an estimate.
2. HUD layouts of the pet simulators, tapping games and Bee Swarm Simulator, from footage.
3. Mobile layouts of every game studied; only one had documented touch controls.
4. The feeding game's actual meter, lane and arrival presentation.
5. Platform questions listed as "Not confirmed" in [roblox-platform-notes.md](roblox-platform-notes.md), to be answered in Studio.
