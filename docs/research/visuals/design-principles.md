# Design principles

Distilled from the game studies in [games/](games/pet-simulator-99.md), the [pattern matrix](pattern-matrix.md) and the [platform notes](roblox-platform-notes.md). Written so an implementer can build to them and a reviewer can check a build against them.

Status of the numbers: every duration, count and size below is an **estimate** chosen as a sensible starting range. None was measured in a game. Platform limits are the exception: they are documented and cited. Tune ranges in Studio; do not treat them as facts about any game.

Evidence tags: **(D)** documented in a cited source, **(A)** assumed.

## 1. Motion timing

1.1 **Respond on the input frame.** The first visible change after a tap or click happens in the same frame, before any server reply. (A; standard practice, and forum guidance has the acting client play its effect first, F05.)

1.2 **Timing ranges (estimates).**

| Motion | Range | Notes |
|---|---|---|
| Button press down | 60 to 120 ms | Scale to 0.92 to 0.96 |
| Button release | 150 to 250 ms | Spring with slight overshoot |
| Hover lift (pointer devices only) | 100 to 160 ms | Scale to 1.03 to 1.06 |
| Popup or panel open | 200 to 320 ms | Scale from 0.85 to 0.9 plus fade, overshoot allowed |
| Popup or panel close | 120 to 180 ms | No overshoot; always faster than open |
| Toast in / hold / out | 200 ms / 2 to 4 s / 200 ms | Hold scales with text length |
| Counter count-up | 300 to 800 ms | Longer for larger changes, never above 1 s |
| Counter pulse | 100 to 200 ms | Merge at high frequency |
| Floating number | 400 to 700 ms | Rise 30 to 60 px, fade in the last third |
| Currency fly-to-counter | 350 to 600 ms per icon | Stagger 30 to 60 ms |
| Stagger between list items | 30 to 80 ms | Total stagger capped near 600 ms |
| Stagger between reveal cards | 60 to 120 ms | Best result last |
| Screen flash | 80 to 150 ms | Replaced by a soft glow under reduced flashing |
| Camera shake, light / heavy | 100 to 200 ms / 300 to 500 ms | Additive, decaying |
| Hit stop | 40 to 100 ms | Heavy hits only |
| Egg anticipation | 0.6 to 1.2 s | Rising amplitude |
| Common reveal, total | 1.2 to 2.0 s | |
| Top-tier reveal, total | 3.5 to 6 s | Skippable |
| Fast or auto mode reveal | 0.3 to 0.6 s | Result still shown |
| Milestone moment | 1.5 to 2.5 s | Skippable |

1.3 **Open slower than you close.** Opening is a moment; closing must never delay the player. (A)

1.4 **Springs for anything interruptible.** Hover, press, drag, follow and counters retarget mid-flight without a jump. Fixed-duration curves are for one-shot sequences. Native tweens cancel each other when they touch the same property (D, P11), which is why interruption needs an engine.

1.5 **Anticipation before, follow-through after.** Every big moment has a wind-up proportional to its importance, and settles with overshoot or secondary motion instead of a hard stop. (A; architecture rule 11.)

1.6 **Squash and stretch on cartoon subjects only**, preserving volume (stretch on one axis is compensated on the others). Not on UI text, not on realistic models. (A)

1.7 **One timing hierarchy per screen.** The most important element moves first or largest; supporting elements follow with stagger. Nothing else moves during a reveal. (A; the hidden-UI pattern is documented for an early pet simulator, G34.)

1.8 **Loops are slow and few.** An idle loop has a period of 1.5 s or more and at most one attention loop runs on screen at a time. Movement draws attention and must be used in moderation (D, P21).

## 2. Rarity hierarchy

2.1 **Rarity is a ladder of layers.** Each tier adds exactly one perceivable layer to the tier below. Suggested ladder (A):

| Tier | Colour cue | Reveal layers added | Duration | Camera |
|---|---|---|---|---|
| Common | Neutral | Scale-in, small burst | Shortest | None |
| Uncommon | Green family | Larger burst | | None |
| Rare | Blue family | Glow behind subject | | None |
| Epic | Purple family | Beam, second sound layer | | Light shake |
| Legendary | Gold family | Longer anticipation, confetti, text shine | | Zoom plus shake |
| Mythic | Red or magenta family | Screen tint, rays, longer hold | | Short cinematic |
| Secret | Dark with prismatic accent | Unique sequence: silhouette first, then reveal | Longest | Cinematic |

The colour families are a common convention, not taken from one game. Themes may remap them.

2.2 **Only the top tier gets a unique sequence** (D for one pet simulator, G21). Everything below shares one parameterised sequence.

2.3 **Never colour alone.** Each rarity also has a text label or icon. Over 5 percent of people have some colour blindness and the platform guidance is to pair colour with symbols (D, P18).

2.4 **Telegraph, then confirm.** The rarity colour appears 0.3 to 0.6 s before the subject is shown. (A)

2.5 **One language in three places.** The same colour, frame and overlay identify a rarity or variant on the world model, on the inventory tile and in the reveal. (O for shiny pets shining in world and inventory, G30.)

2.6 **Variants are cheap treatments**: recolour, material, animated gradient, scale. An emitter is reserved for the top one or two. (O, recolour mutations in two games; cost reasoning from P01 and P19.)

2.7 **Unknown is a silhouette.** Undiscovered or secret entries are shown as a dark shape, not hidden. (D, G91.)

2.8 **Intensity budget.** If more than one reveal happens within a few seconds, only the highest tier plays in full; the rest use the fast form. (A)

## 3. Feedback loops

3.1 **Every player action gets feedback on three channels where possible**: motion at the point of action, a number or state change, and a sound cue. Sound is never the only channel (D, P18).

3.2 **Feedback is located.** It appears where the action happened (touch point, target object) and then connects to where the result is stored (fly to the counter). (A)

3.3 **Feedback scales with value, with a ceiling.** Size, colour warmth and layer count grow with the amount; beyond the ceiling only the number changes. (A)

3.4 **High-frequency feedback is cheap, pooled, capped and merged.** Anything that can fire more than about five times per second uses pooled 2D elements, a hard cap, and merging inside a 100 to 200 ms window. Text and billboards are not cheap (forum guidance, F08).

3.5 **The loop's turning points are unmistakable**: bag full, ready to rebirth, shop restocked, lock expiring. Each has a distinct state change that persists until acted on. (D for capacity and restock mechanics, G63, G75; presentation A.)

3.6 **Waiting is turned into anticipation** with a visible value that changes during the wait: a countdown, a growing luck number, a filling bar. (D for luck growing in flight, G19, and the shared restock timer, G75.)

3.7 **Rewards with a subject react.** When a pet or animal is involved, it visibly responds (eat, bounce, hearts) instead of only a number appearing. (A)

3.8 **Server decides, client presents.** No visual module computes a result. Local feedback for the player's own input may play before the server confirms; rewards play only after. (D, architecture document; forum practice F05, F06.)

3.9 **Persistent visuals come from state, not events.** An aura or lock barrier is derived from replicated state so late joiners see it (forum note that one-shot broadcasts miss late joiners, F07).

## 4. HUD layout

4.1 **Centre is for the world.** Persistent HUD lives on the edges. (D for one action game's edge layout, G01; D, P23 on placing peripheral information at the sides.)

4.2 **Hierarchy by region** (D, P23): objective and primary currency at the top; the action in the middle; player state and secondary controls at the sides and bottom edges.

4.3 **Show only what the current activity needs.** Contextual actions appear when relevant, not permanently (D, P15, P21).

4.4 **Collapse secondary screens** behind one menu button or a short icon column of at most five or six. (D for one action game, G02; A for the limit.)

4.5 **Status belongs on its object** when that frees HUD space (D, G50).

4.6 **Group related elements; separate unrelated ones with space** (D, P21).

4.7 **Conventions are kept**: X closes, grey means unavailable, a lock means not yet unlocked (D, P21).

4.8 **Buttons look pressable**: a container, and depth from a highlight or shadow (D, P21). In UVK themes: fill gradient, stroke, corner radius, and a darker offset layer for depth.

4.9 **Numbers are abbreviated consistently** (1.2K, 3.4M) with a fixed-width container so the layout does not jump while counting. (A)

4.10 **One modal at a time.** A cinematic or popup that owns the screen hides or dims the HUD and restores it afterwards (D for the early pet simulator, G34).

## 5. Mobile

5.1 **Keep the bottom corners clear.** Default touch controls occupy the bottom-left and bottom-right corners (D, P15).

5.2 **Frequent actions sit in the thumb zone**, positioned relative to the jump button; do not assume a phone layout works on a tablet (D, P15).

5.3 **Touch targets are at least 44 px** on the short side with 8 px between them. (A; industry convention, not found in the Roblox docs read.)

5.4 **No hover-only information.** Hover effects do not exist on touch; every hover state has a press equivalent. (A; noted in forum discussion.)

5.5 **Respect safe areas.** Interactive UI uses the default core-UI safe insets; only non-interactive backgrounds extend under cutouts (D, P14). Top-edge elements follow `TopbarInset` changes (D, P13).

5.6 **Choose layout and default quality from display size** (`ViewportDisplaySize`: Small, Medium, Large) (D, P13), then adapt with measured frame time.

5.7 **Budget for a quarter of desktop particles.** A mobile emitter is limited to 100 particles per second against 400 on desktop (D, P01). Effects are authored to read at the mobile rate first.

5.8 **Large transparent effects are the expensive ones on phones**: full-screen glows, big particles and screen-covering highlights (D, P01, P05). Scale size as well as count.

5.9 **Text stays readable at small sizes**: body text at least 14 px after scaling, strong contrast against the busy 3D world via stroke or a panel (D, P18 for contrast and text size; the pixel value is A).

5.10 **Test on a real low-end phone.** The Studio emulator is not accurate for memory (D, P20).

## 6. Accessibility

6.1 **Follow the platform's Reduce Motion setting.** When `GuiService.ReducedMotionEnabled` is true: travel becomes a fade or a jump, loops stop, camera shake and zoom kicks are off (D, P13, P18 for the setting and the snap or fade approach; the exact UVK mapping is the architecture's rule 8).

6.2 **Reduced flashing is separate and kit-level.** No full-screen flash; use a soft glow or tint with a rise time of at least 150 ms. No platform flashing setting was found in the docs read, so the game must expose this one (A).

6.3 **Never more than three flashes per second**, in any mode. (A; widely used photosensitivity threshold, not from the Roblox docs.)

6.4 **Apply preferred transparency** to panel backgrounds by multiplying background transparency with `PreferredTransparency` (D, P18).

6.5 **Tolerate larger text.** Layouts survive the player's preferred text size up to the largest step without clipping (D, P13 for the setting).

6.6 **Colour is never the only carrier** of rarity, team, state or error (D, P18).

6.7 **Sound is never the only carrier** of an event (D, P18).

6.8 **Nothing gameplay-critical is hidden by an effect.** Effects do not cover prompts, timers, health or the player's character for longer than a flash. (A; architecture rule 11.)

6.9 **Every long sequence is skippable** and its result is shown even when skipped. (A)

6.10 **An intensity setting scales juice globally** (shake amplitude, particle count, popup size) without disabling information. (A; exists as `Host.settings().intensity`.)

## 7. Performance

7.1 **Configure emitters once.** Changing emitter properties at runtime can be costly (D, P19). Use `Emit(count)` on pooled, pre-configured emitters (D, P02 for `Emit`).

7.2 **Highlights are pooled and counted.** At most 255 display, disabled ones still hold a slot, and adding or removing one can spike (D, P05). Low quality uses none.

7.3 **ViewportFrames are for static previews.** No post-processing or shadows render in them (D, P10); developers report no particles or highlights either (F01, F02). Reveals happen in the world.

7.4 **CanvasGroup only for short group fades** on a few panels, with stable size, under a ScreenGui using sibling z-index behaviour (D, P09).

7.5 **Do not tween text stroke thickness** (D, P06). Scale instead.

7.6 **Animate transform-like properties** (`UIScale`, position, rotation, transparency) and avoid animating layout-affecting sizes of containers with many children. (A)

7.7 **Other players' effects are second-class**: lower budget, distance-culled, never camera effects. (A)

7.8 **Everything has an owner and a lifetime.** No effect, loop or connection outlives its target. Stopping twice is harmless. (D, architecture rules 5 and 6.)

## Quality checklist

Each line is a statement that is either true or false of a build. A reviewer marks each one. Items that need Studio are `NEEDS MANUAL REVIEW` until someone has run them there.

### Motion

- [ ] Pressing any bound button changes its scale within one frame of input.
- [ ] No popup takes longer to close than to open.
- [ ] Interrupting any hover, press or panel animation midway produces no visible jump.
- [ ] No more than one attention loop (pulse or shine) is active on the HUD at once.
- [ ] Every sequence longer than 1.5 s can be skipped, and skipping shows the final state.
- [ ] After any cinematic ends, is skipped, or the character respawns, CameraType, CFrame and FieldOfView equal their values from before it started.

### Rarity

- [ ] Each rarity is distinguishable in a greyscale screenshot by label, icon or layout.
- [ ] Each rarity tier's reveal has strictly more layers or duration than the tier below.
- [ ] The same rarity uses the same colour on the world model, the inventory tile and the reveal.
- [ ] Two reveals triggered within 2 s do not both play in full.
- [ ] Preset ids, sample data and docs contain no third-party game, pet or character names.

### Feedback

- [ ] Tapping 15 times per second for 10 s never shows more floating numbers than the configured cap.
- [ ] Under that load, frame time on the baseline phone stays within budget (state the measured value).
- [ ] A currency gain updates the counter text at most once per frame.
- [ ] Fly-to-counter spawns no more than the configured icon cap for any amount.
- [ ] Every sound cue used by a feedback recipe has a visual step in the same recipe.
- [ ] No reward visual plays before the server result is known.

### HUD and mobile

- [ ] On a phone-sized viewport no interactive element overlaps the thumbstick or jump button areas.
- [ ] No interactive element is narrower or shorter than 44 px at phone size.
- [ ] No information is reachable only by hover.
- [ ] With the largest preferred text size, no label clips or overlaps.
- [ ] During a hatch or reveal the HUD is hidden or dimmed, and it is restored afterwards, including after cancel.
- [ ] Interactive ScreenGuis use the default safe insets.

### Accessibility

- [ ] With Reduce Motion enabled, no camera shake, no looping animation and no positional travel occurs; elements fade or jump.
- [ ] With reduced flashing enabled, no full-screen flash occurs anywhere, including the top-tier reveal.
- [ ] No effect flashes more than three times in any one-second window.
- [ ] Panel backgrounds become opaque when preferred transparency is 0.
- [ ] No effect covers a prompt, timer or health display for more than 150 ms.

### Performance

- [ ] No preset sets an emitter rate that relies on more than 100 particles per second to read correctly.
- [ ] On Low quality, no highlights are created and no post-processing instance is added.
- [ ] The number of live highlights never exceeds the configured pool size, which is far below 255.
- [ ] No emitter property is written every frame.
- [ ] After stopping all effects, effect stats report zero live instances and zero clock jobs.
- [ ] Destroying a target mid-animation raises no error and leaves no job running.
- [ ] No ViewportFrame is used to show particles, highlights or bloom.
