# Visual quality checklist

Review every visual change against this list. It is the kit's own checklist from the UVK design research, shortened to what can be checked in a project. Items that need Studio or a device are `NEEDS MANUAL REVIEW` until someone has done them; say so in the report instead of ticking them.

## Animation principles (definition of done)

- Anticipation before big moments (a squash, a pull back, a wobble) and none before frequent ones.
- Follow-through: springs settle, nothing stops dead. Use `Core/Springs` names, not linear tweens.
- Secondary motion: the icon, glow or sparkle lags slightly behind the main move.
- Squash and stretch on cartoon objects, keeping volume.
- A clear timing hierarchy: press 60-90 ms, release spring 180-260 ms, hover 100-140 ms, popup in 250-350 ms with overshoot and out in 140-200 ms, toast 250 ms in and 180 ms out, counters 0.4-1.2 s by size of change, reveals 1.2 s (common) to about 3.5 s (top tiers).
- Rarity hierarchy: common is pleasant, the top tier is exceptional, and no tier outshines the one above it.
- Immediate response: the first visual change happens on the frame of the input.
- Nothing covers gameplay-critical information.

## Motion

- [ ] Pressing any bound button changes its scale within one frame of input.
- [ ] No popup takes longer to close than to open.
- [ ] Interrupting a hover, press or panel animation midway produces no visible jump.
- [ ] At most one attention loop (pulse or shine) is active on the HUD at once.
- [ ] Every sequence longer than 1.5 s can be skipped, and skipping shows the final state.
- [ ] After a cinematic ends, is skipped, or the character respawns, CameraType, CFrame and FieldOfView equal their earlier values.

## Rarity

- [ ] Each rarity is distinguishable without colour (label, icon or layout).
- [ ] Each tier's reveal has more layers or duration than the tier below.
- [ ] The same rarity uses the same colour on the world model, the inventory tile and the reveal.
- [ ] Two reveals triggered within 2 s do not both play in full.
- [ ] Preset ids, sample data and docs contain no third-party game, pet or character names.

## Feedback

- [ ] Tapping 15 times per second for 10 s never shows more floating numbers than the configured cap.
- [ ] A currency gain updates the counter text at most once per frame.
- [ ] Fly-to-counter spawns no more than the configured icon cap for any amount.
- [ ] Every sound cue in a feedback recipe has a visual step in the same recipe.
- [ ] No reward visual plays before the server result is known.

## HUD and mobile

- [ ] On a phone-sized viewport no interactive element overlaps the thumbstick or jump button areas.
- [ ] No interactive element is smaller than 44 px at phone size.
- [ ] No information is reachable only by hover.
- [ ] During a hatch or reveal the HUD is hidden or dimmed, and restored afterwards, including after cancel.

## Accessibility

- [ ] With reduced motion: no camera shake, no looping animation, no positional travel; elements fade or jump.
- [ ] With reduced flashing: no full-screen flash anywhere, including the top-tier reveal.
- [ ] No effect flashes more than three times in one second.
- [ ] No effect covers a prompt, timer or health display for more than 150 ms.

## Performance

- [ ] No preset relies on more than 100 particles per second to read correctly.
- [ ] On Low quality no highlights and no post-processing instances are created.
- [ ] No emitter property is written every frame.
- [ ] After stopping all effects, `Visuals:Stats()` reports zero live effects and zero clock jobs.
- [ ] Destroying a target mid-animation raises no error and leaves no job running.
- [ ] No ViewportFrame is used to show particles, highlights or bloom (it cannot render them).
