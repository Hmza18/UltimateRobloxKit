# Visuals / UI

UI animation for the visuals kit: 70 presets as data, a player that runs them on any GuiObject
through `Runtime/Motion`, and the HUD pieces games ask for most: button bindings, show / hide,
staggered lists, number counters, typewriter text, shine, ripple, screen flash, backdrops,
floating popups and currency that flies to its counter.

```lua
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)
local UI = Visuals.UI

UI.animate(button, "BouncyPress")
UI.show(panel, "PopIn")
UI.hide(panel, "PopOut")
local binding = UI.bind(button, "Premium")        -- hover / press / release / selected / disabled
UI.countTo(coinsLabel, 2400, { format = "abbrev" })
UI.popup(125, hitPosition, { style = "crit" })
UI.flyTo(chestPart, coinCounter.Instance, { count = 10, onDone = refreshCoins })
```

| File | Kind | What |
|---|---|---|
| `UIPresets.luau` | pure data | The preset catalogue, registered in a `Core/Registry` of kind `ui` |
| `UILogic.luau` | pure | Recipe validation, scaling, scheduling, relative-offset maths, counter, typewriter, stagger, popup, fly path, ripple, button state machine, XP overflow, cooldown |
| `UIAnimations.luau` | runtime | The player and every function below (`Visuals.UI`) |

The game components in `UI/Game` (PremiumButton, TabBar, Modal, Tooltip ...) take their motion
from this module, so components and hand-built UI move alike.

## Recipes

A preset is a recipe: numbers and names, relative to the object's rest state.

```lua
{ steps = {
	{ props = { Scale = 0.92 }, duration = 0.07, easing = "quadOut" },
	{ props = { Scale = 1 }, spring = "Bouncy" },
} }
```

| Step field | Meaning |
|---|---|
| `props` | Goals (see the property table) |
| `from` | Start values; without it the step continues from where the object is |
| `duration`, `easing` | Timed step; easing is a `Core/Curves` name (default `quadOut`) |
| `spring` | Spring step: a `Core/Springs` name or `{ frequency, damping }` |
| `delay` | Seconds before the step starts |
| `join` | Start together with the previous step (a quick fade beside a slow spring) |
| `marker` | `options.onMarker(name)` is called when the step starts (`CardFlip` fires `flip`) |
| `essential` | Still animates under reduced motion (fades) |

| Property | Relative to rest | Scaled by `intensity` |
|---|---|---|
| `Scale` | multiplier of the rest scale (the `UrkScale` UIScale) | yes |
| `Rotation` | degrees added | yes |
| `GroupFade` | 0 = as visible as at rest, 1 = invisible | no |
| `OffsetX`, `OffsetY` | pixels from the rest position | yes |
| `OffsetXSize`, `OffsetYSize` | fraction of the object's own width / height | no |
| `Width`, `Height` | multiplier of the rest Size | no |

| Recipe field | Meaning |
|---|---|
| `layers` | Overlay effects run beside the steps: `shine`, `glow` (`flash`, `pulse`, `on`, `off`), `ripple`, `tint`, `border`, `textGlow` |
| `loop`, `gap` | Repeats until stopped, with a pause between cycles. Never starts under reduced motion |
| `out` | Leaves the object away from rest on purpose (exits) |
| `reduced` | Reduced motion: a preset id to play instead, or `false` to skip |
| `travel` | Springs the rest position / size to `options.position` / `options.size` (`IndicatorSlide`) |

Springs count as finished for timing once within 5 % of the goal (`UILogic.SETTLE`); the engine
settles the rest on its own. Register your own preset with
`UI.registry:register(preset, { override = true })`; `UILogic.validate(recipe)` lists problems.

## API

| Function | Returns | Notes |
|---|---|---|
| `UI.animate(gui, presetId, options?)` | Handle | Options: `duration` (total seconds) or `speed`, `intensity`, `delay`, `easing`, `spring`, `mirror`, `priority`, `restore`, `color`, `colors`, `at`, `position`, `size`, `onDone(completed)`, `onMarker(name)` |
| `UI.stop(gui, restore?)` | | Stops every preset on `gui`; `restore = true` returns it to rest and removes overlays |
| `UI.rest(gui)` | | Recaptures the rest state after you move, resize or restyle an object yourself |
| `UI.isAnimating(gui)` | boolean | A preset chain is running |
| `UI.show(gui, presetId?, options?)` | Handle | Sets `Visible = true`, plays an entrance (default `PopIn`) |
| `UI.hide(gui, presetId?, options?)` | Handle | Plays an exit (default `PopOut`), then hides and restores rest. A newer `show` wins: a stale hide never hides |
| `UI.bind(button, style?, options?)` | Binding | Styles: `BouncyPress` (default), `Soft`, `Snappy`, `Premium`, `Arcade`, `Minimal`. Options: `target`, `enabled()`, `selected`, `disabled`, `color`, `onActivated`, `onState(status)` |
| `UI.stagger(guis, presetId, options?)` | Handle | Extra options: `interval` (0.05), `order` (`forward`, `reverse`, `center`, `edges`, `random`), `seed`, `show`. `onDone` fires once at the end |
| `UI.countTo(label, to, options?)` | Handle | `from`, `duration` (default 0.4-1.2 s by size of change), `easing`, `format` (Core/Format spec), `prefix`, `suffix`, `pop`, `onStep`, `onDone` |
| `UI.typewriter(label, text, options?)` | Handle | `speed` (characters per second, 40), `onChar`, `onDone`. Uses `MaxVisibleGraphemes` when the object has it |
| `UI.shine(gui, options?)` | Handle | `duration`, `delay`, `angle`, `width`, `alpha`, `color`, `loop`, `interval` |
| `UI.ripple(gui, options?)` | Handle | `at` (AbsolutePosition space), `color`, `duration`, `alpha` |
| `UI.flash(color?, options?)` | Handle? | Full-screen flash; `duration`, `alpha` |
| `UI.backdrop(parent, options?)` | Handle | `handle.Instance` is the dim layer; `stop()` fades it out and destroys it. `color`, `transparency`, `zIndex`, `modal`, `onActivated` |
| `UI.popup(text, at, options?)` | Handle? | `style` (`damage`, `currency`, `crit`, `heal`), `color`, `size`, `duration`, `format`, `font`, `offset`, `onDone` |
| `UI.flyTo(from, toGui, options?)` | Handle | `count`, `image`, `color`, `size`, `spread`, `duration`, `stagger`, `seed`, `punch`, `onArrive(index)`, `onDone`. `handle.count` is the number actually flown |
| `UI.stats()` | table | `{ chains, popups, flyers }` |
| `UI.registry`, `UI.Logic` | | The preset registry and `UILogic` |

Every Handle has `stop(restore?)`, `cancel` (alias), `finish()` and `isDone()`. Stopping twice is
harmless. `popup` and `flash` return nil when there is no local PlayerGui.

A Binding has `setSelected(bool)`, `setDisabled(bool)`, `status()` and `destroy()`; calling the
binding like a function also cleans up.

Deviations from `docs/architecture/visuals.md`: `bind` returns a Binding object (callable as the
cleanup function) rather than a bare function; `ripple`, `backdrop`, `rest`, `isAnimating` and
`stats` are additions.

### Rules the player keeps

- **Rest state.** Position, size, rotation, scale and fade are captured on first use and recipes
  are applied relative to them. Position and size are re-read on the next play whenever this
  module is not holding the object away from rest, so layouts can move objects freely. Scale,
  rotation and fade are captured once; call `UI.rest(gui)` after changing them yourself.
- **One owner per channel.** Two presets that animate the same thing (scale, rotation, fade,
  position, size, or the same layer kind) cannot run on one object: the newer replaces the older
  unless the older has a higher `priority`. A shine can run over a press.
- **Chains.** Steps start from `Host.clock` timers at their scheduled time. Stopping a handle
  cancels the timers, the running tracks and the layers. A loop's `stop()` restores rest.
- **Start pose.** A recipe's `from` values are written at the call, even with a delay, so
  staggered entrances wait hidden instead of flashing at rest.

## Presets

70 presets. Ids in **bold** loop until stopped.

| Category | Ids |
|---|---|
| buttons (19) | HoverScale, HoverReset, PressDown, ReleaseSpring, BouncyPress, Bounce, Wiggle, **Pulse**, Shine, **Glow**, Ripple, Confirm, Error, **Loading**, **Spinner**, Selected, Deselected, Disabled, Enabled |
| panels (22) | PopIn, PopOut, SlideInLeft / Right / Up / Down, SlideOutLeft / Right / Up / Down, FadeIn, FadeOut, ScaleIn, ScaleOut, ElasticIn, SpringIn, ModalIn, ModalOut, DrawerIn, DrawerOut, BackdropIn, BackdropOut |
| text (5) | TextBounce, **TextPulse**, **TextGlow**, RewardTextReveal, LevelUpText |
| cards (9) | HoverLift, HoverDrop, SelectGlow, CardFlip, CardReveal, **RarityBorder**, UpgradePulse, InventorySelect, Highlight |
| navigation (11) | TabSwitch, IndicatorSlide, SidebarIn, SidebarOut, DropdownOpen, DropdownClose, AccordionOpen, AccordionClose, PageNext, PagePrev, ScrollReveal |
| notifications (4) | ToastIn, ToastOut, BadgePop, **AttentionPing** |

HoverReset, Spinner and Highlight are additions to the required list. `SlideInLeft` enters from
the left, `SlideInUp` enters moving up (from below); `SlideOutLeft` leaves to the left,
`SlideOutUp` leaves upward. `TabSwitch`, `SidebarIn` and `SidebarOut` take `mirror = true` for
the other direction. Every preset has the params `intensity` (0-2), `speed` (0.25-4) and
`delay`; `UI.registry:describe(id)` returns the metadata.

Timing: press 70 ms, hover about 110 ms, release spring about 230 ms, panel entrances 160-380 ms,
panel exits 140-200 ms, toast in about 160 ms and out 180 ms (to within 5 % of rest).

### Button styles

| Style | Hover | Press | Release | Extra |
|---|---|---|---|---|
| BouncyPress | 1.06, Snappy | 0.92 | Bouncy | |
| Soft | half travel, Soft | half | Soft | |
| Snappy | 0.7x | 0.75x, faster | Snappy | |
| Premium | 0.8x, Premium | 0.7x | Premium | shine on hover |
| Arcade | 1.6x, Bouncy | 1.4x | Elastic | ripple on press |
| Minimal | none | 0.4x | Snappy | |

All styles share Selected, Deselected, Disabled and Enabled. `UILogic.buttonEvent(state, event)`
is the state machine (events: enter, leave, focus, blur, press, release, select, deselect,
disable, enable); events are idempotent, so mouse and touch may both report one press.

## Example

```lua
-- Reward moment: list pops in, coins fly to the counter, the counter rolls.
UI.stagger(rewardTiles, "BadgePop", { interval = 0.08, order = "center" })
UI.flyTo(claimButton, coinCounter.Instance, {
	count = 12,
	onDone = function()
		UI.countTo(coinLabel, newTotal, { format = "abbrev" })
	end,
})

-- Flip a card and swap its face at the midpoint.
UI.animate(card, "CardFlip", { onMarker = function() face.Image = revealedImage end })

-- Error feedback on a refused purchase.
UI.animate(buyButton, "Error")
```

## Accessibility and quality

- **Reduced motion** (`Host.settings().reducedMotion`): loops, shines and ripples do not start;
  entrances and exits that travel play `FadeIn` / `FadeOut` instead; everything else jumps to its
  end pose (state glows still switch). Counters and typewriters complete at once. Popups keep
  their rise but lose the pop, drift and wobble. `flyTo` flies nothing: the target pops once and
  the callbacks fire immediately. Stagger intervals become zero.
- **Reduced flashing**: `flash` is capped at 15 % opacity and lasts twice as long; `tint` layers
  (Error, Highlight) are 40 % as strong.
- **Intensity** (`Host.juice("scale")`) multiplies every preset's intensity.
- **Quality profile**: looping shine, `RarityBorder`, `TextGlow` and the pulsing `Glow` are off
  when `profile.uiShine` is false (Low), where `Glow` becomes a steady outline. `flyTo` counts
  follow `profile.particleScale`. Popups are capped at `profile.maxPopups`; the oldest is recycled.

## Performance

- No per-frame work while idle. Presets run as engine tracks plus clock timers. Popups and
  flying items share one clock job that ends when none are alive; a counter or typewriter is one
  job each for its duration.
- Popup labels and flying items are pooled (32 idle each) inside one ScreenGui (`UvkOverlay`,
  `ResetOnSpawn = false`, `IgnoreGuiInset = true`, DisplayOrder 90) created on first use.
- Overlays (`UvkShine`, `UvkGlow`, `UvkRipple`, `UvkTint`, `UvkBorderGradient`) are created on
  demand and destroyed when the effect ends or is stopped. They carry the `UrkInternal` attribute.
- Tracks on destroyed objects are dropped by the engine; chains and jobs check the object each
  time they fire.

## Limitations

- `GroupFade` fades a CanvasGroup as a whole. On any other object it fades only that object's own
  background, image and text, so entrances on a plain Frame with children show scale and travel
  but no fade. Use a CanvasGroup when the fade matters (it clips content at its edge).
- Offsets move `Position`, which UIListLayout and UIGridLayout control: inside layouts use scale,
  rotation and `Width` / `Height` presets.
- A step that sets one offset axis leaves the other at rest; keep both axes in one step.
- `ripple` is clipped to the object's rectangle, not its rounded corners, unless the object is a
  CanvasGroup.
- `RarityBorder` needs a border UIStroke on the object or its `Body` child; without one it draws
  its own outline.
- The typewriter counts UTF-8 code points, not grapheme clusters, and does not skip RichText tags.
- `Vector2` anchors for `popup` and `flyTo` are viewport pixels (as `WorldToViewportPoint` and
  `GetMouseLocation` return); GuiObject anchors add the GUI inset to `AbsolutePosition`.

## Verification

| Part | Verified by |
|---|---|
| `UILogic.luau`, `UIPresets.luau` | `lune run tests/run tests visuals_ui` (25 tests: every preset validates with full metadata, required ids, timing bounds, scaling, scheduling, channels, recipes played through the real engine, counter, typewriter, stagger, popup, fly path, ripple, button state machine, XP, cooldown); `luau-analyze --mode=strict` |
| `UIAnimations.luau` | StyLua, Selene, `luau-lsp analyze` with Roblox types only |

## Not verified in Studio

`UIAnimations.luau` creates and animates Instances and was NOT run in Studio. NEEDS MANUAL REVIEW:

- [ ] Feel of each button style with mouse, touch and gamepad; touch release returns to rest.
- [ ] `show` / `hide` on CanvasGroups and plain frames; a show during a hide stays visible.
- [ ] Glow outline radius matches the object's corners; shine stays inside rounded corners.
- [ ] Ripple origin under mouse and touch (inset handling), and clipping.
- [ ] `RarityBorder`: UIGradient on a UIStroke rotates as a travelling highlight.
- [ ] Popup and flyTo positions against the GUI inset, at several resolutions and with UIScale.
- [ ] `typewriter` with `MaxVisibleGraphemes`; `countTo` pop at the end.
- [ ] Reduced motion and reduced flashing paths; Low quality profile.
- [ ] Cleanup: no `Uvk*` instances left after stop, destroy or respawn.
