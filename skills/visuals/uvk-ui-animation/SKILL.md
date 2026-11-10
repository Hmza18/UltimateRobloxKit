---
name: uvk-ui-animation
description: UI animation with UltimateVisualsKit's Visuals.UI - 70 presets for buttons, panels, cards, text, navigation and notifications, button state bindings (hover, press, release, selected, disabled), show and hide, staggered lists, number counters, typewriter text, shine, ripple, screen flash, floating popups and currency that flies to its counter. Use when a button, panel, shop, HUD or menu should feel animated, polished, juicy or premium, or when adding count-up numbers, damage popups or fly-to-counter coins.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [ui animation, animated button, button hover, press animation, panel transition, popup animation, count up, number counter, floating number, damage popup, fly to counter, typewriter text, shine effect, animated ui, polished animations, ui feel]
  depends: [uvk-visuals-kit]
---

# UVK UI animation

## When to use

- Hover, press and selected states on any button; entrances and exits for panels, modals, toasts and cards.
- Counters that roll, text that types, numbers that float up, coins that fly to the HUD.

When not to use: building the screen itself (`roblox-ui-generator`, `urk-ui-framework`); ready animated components such as PremiumButton or XPBar (`uvk-simulator-screens`); one call per gameplay event (`uvk-gameplay-feedback`).

## Inputs

- The GuiObjects to animate. Fades need a CanvasGroup; a plain Frame with children shows scale and travel only.
- Whether the object sits inside a UIListLayout or UIGridLayout (then only scale, rotation and size presets apply).

## Workflow

1. **Find the preset.** All 70 ids by category are in [references/ui-presets.md](references/ui-presets.md); or search the catalog:

   ```bash
   grep -n -i -A3 '"id": "Pop' $URK/catalog/visuals.json
   ```

2. **Bind buttons once** instead of animating in input handlers. The binding reacts on the input frame.

   ```lua
   local UI = Visuals.UI
   local binding = UI.bind(buyButton, "Premium", {
   	onActivated = function() requestPurchase() end,
   })
   binding.setSelected(true)
   binding.setDisabled(false)
   binding.destroy()                       -- or call binding() to clean up
   ```

   Styles: `BouncyPress` (default), `Soft`, `Snappy`, `Premium` (shine on hover), `Arcade` (ripple on press), `Minimal`.

3. **Show and hide with presets**, so a show during a hide wins and the object returns to rest.

   ```lua
   UI.show(panel, "PopIn")                 -- sets Visible, plays the entrance
   UI.hide(panel, "PopOut")                -- plays the exit, then hides and restores rest
   UI.stagger(tiles, "BadgePop", { interval = 0.08, order = "center" })
   UI.animate(buyButton, "Error")          -- refused purchase
   UI.animate(card, "CardFlip", { onMarker = function() face.Image = revealed end })
   ```

4. **Numbers and currency.**

   ```lua
   UI.countTo(coinLabel, 2400, { format = "abbrev" })          -- 0.4-1.2 s by size of change
   UI.popup(125, hitPosition, { style = "crit" })               -- damage, currency, crit, heal
   UI.flyTo(chestPart, coinCounter, {
   	count = 10,
   	onDone = function() UI.countTo(coinLabel, newTotal, { format = "abbrev" }) end,
   })
   UI.typewriter(dialogLabel, "Welcome back!", { speed = 40 })
   ```

5. **Overlays.** `UI.shine(gui, options?)`, `UI.ripple(gui, options?)`, `UI.flash(color?, options?)` (honours reduced flashing; returns nil without a PlayerGui), `UI.backdrop(parent, options?)` for a dim layer whose `stop()` fades it out.

6. **Stop and restore.** Every handle has `stop(restore?)`, `cancel`, `finish()` and `isDone()`. `UI.stop(gui, true)` ends every preset on an object and returns it to rest. Call `UI.rest(gui)` after you change an object's scale, rotation or fade yourself.

7. **Custom motion stays in the registry.** A preset is a recipe of steps relative to rest:

   ```lua
   UI.registry:register({
   	id = "ShopBump", name = "Shop bump", category = "buttons",
   	description = "A quick dip and a bouncy return for the shop button.",
   	data = { steps = {
   		{ props = { Scale = 0.9 }, duration = 0.07, easing = "quadOut" },
   		{ props = { Scale = 1 }, spring = "Bouncy" },
   	} },
   })
   assert(#UI.Logic.validate(UI.registry:get("ShopBump").data) == 0)
   ```

## Outputs

- Bindings and preset calls in client UI code, with handles or bindings cleaned up when the screen closes.

## Validation

```bash
lune run tests/urk/run tests/urk
```

In the kit repository: `cd library && lune run tests/run tests visuals_ui`. Then the Studio checklist at the end of the module's README (`library/src/Visuals/UI/README.md`): button feel with mouse, touch and gamepad; show during hide; popup and fly-to positions at several resolutions; reduced motion and Low quality. All of it is `NEEDS MANUAL REVIEW` until run.

## Pitfalls

- **No fade on entrances.** `GroupFade` fades a CanvasGroup as a whole; on a plain Frame only its own background, image and text fade.
- **Offset presets inside layouts** do nothing useful: the layout owns `Position`. Use scale presets (`PopIn`, `BadgePop`).
- **Two presets on one channel.** A newer preset on the same property replaces the older one unless the older has a higher `priority`. A shine can run over a press.
- **More than one attention loop.** `Pulse`, `Glow`, `AttentionPing` and looping shine compete; keep one on the HUD.
- **Calling `flyTo` with a huge count.** Pass a small `count` (8-12); the counter roll carries the amount.
- **Animating in `MouseEnter` handlers** as well as `UI.bind` doubles the motion. Bind only.

## Limitations

- `UILogic` and `UIPresets` are covered by Lune specs (every preset validates, timing bounds, state machine). `UIAnimations.luau` creates and animates Instances and was not run in Studio.
- `ripple` clips to the object's rectangle, not its rounded corners, unless it is a CanvasGroup. The typewriter counts code points and does not skip RichText tags.
- `popup` and `flyTo` positions against the GUI inset are unverified on devices.
