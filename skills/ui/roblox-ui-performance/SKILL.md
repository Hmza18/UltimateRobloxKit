---
name: roblox-ui-performance
description: Rendering, memory and animation costs of Roblox UI - instance counts, ScreenGui count and DisplayOrder, ClipsDescendants, UIGradient and UIStroke cost notes, image atlases and sprite sheets vs many separate images, one shared ticker instead of per-element loops, cancelling tweens, pooling toasts and rows, hiding vs destroying, avoiding per-frame property writes, a low-end mobile budget table, and measuring with the MicroProfiler and the Developer Console Gui memory. Use when menus stutter, opening a shop hitches, UI memory grows, or a HUD costs frames on phones.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [ui lag, ui performance, gui memory, ui stutter, too many screenguis, ui instance count, sprite sheet performance, tween leak, ui hitch]
  depends: [roblox-performance]
---

# Roblox UI performance

## Purpose

Keep UI cheap: no per-frame work while idle, few instances, few textures, no leaks. UrkUI and the Game components are built this way; this skill is how to keep it that way in game code and how to measure.

## When to use (and not)

- Use: hitches when opening windows, frame drops with the HUD visible, UI memory climbing over a session, long inventory lists.
- Not for world rendering, streaming or scripts unrelated to UI: `roblox-performance`.

## Workflow

1. **Measure first** (Validation below): Developer Console (F9) > Memory > `Gui` and `GraphicsTexture`; MicroProfiler (Ctrl+F6, or Ctrl+Alt+F6 on some layouts) for frame spikes, look for `Render` UI work and Lua scripts.
2. **Count instances**: in the command bar, `#game.Players.LocalPlayer.PlayerGui:GetDescendants()`. Compare against the budget table.
3. **Find per-frame work**: search game code for `RenderStepped`, `Heartbeat`, `while true do` loops that touch GUI properties.
4. **Apply the fixes** below in order of measured cost, then measure again with the same steps.

## Cost notes

| Thing | Cost and advice |
|---|---|
| Instances | every GuiObject, UICorner, UIStroke, UIGradient and layout is an instance to update and lay out. A Game card is roughly 15-25 instances; 200 cards is several thousand. Virtualise long lists |
| ScreenGuis | each is a separate layer; keep a handful (HUD, windows, modal, toasts). Use `DisplayOrder` (UrkUI layers: hud 0, panel 10, modal 50, toast 80, tooltip 90) instead of new ScreenGuis per element |
| Layout objects | UIListLayout, UIGridLayout and AutomaticSize recompute when children change; batch child changes (parent last) and avoid AutomaticSize chains several levels deep |
| ClipsDescendants | needed for scrolling and masks, but adds clipping work and breaks rotation of children; do not set it on every card "just in case" |
| UIGradient | cheap to draw; animating `Offset` or `Rotation` every frame is a property write per frame per gradient |
| UIStroke | each stroke re-renders with its parent; text strokes on hundreds of small labels add up. Keep strokes on titles and outlines, not on every caption in long lists |
| Images | each distinct texture costs memory and a download. Sprite sheets (1024 px, 128 px cells, `ImageRectOffset` / `ImageRectSize`) put 64 icons in one texture; the URK icons ship as sheets for this reason |
| Tweens | one TweenService tween per property set is fine; thousands of simultaneous tweens are not. Cancel before starting a new one on the same object (`Runtime/Motion` does this; `Motion.stop(instance)`) |
| Text | `TextScaled` and TextFit re-measure on resize; avoid changing text every frame |

## Fixes and patterns

- **One shared ticker.** Countdowns, count-ups and rainbows use `Game/Ticker` (`Ticker.frame(fn)`, `Ticker.slow(fn)` at about 4 Hz for clocks), a single job on `Runtime/Driver` that connects only while something runs. Do not give each timer its own `Heartbeat` connection; a clock needs a 4 Hz update, not 60.
- **No per-frame property writes while idle.** Write only on change: bind to the Store (`bind` in specs, `UrkBind` tags) so labels update when the value changes.
- **Hide vs destroy.** Frequently reopened windows: hide (`Visible = false` or `window:close()`) and keep them. Rarely used heavy screens: build on first open (`Window.define`, `UrkUI.definePanel`) and `screen:destroy()` when leaving a mode. Destroying through the component (`:destroy()`) cleans its Trove; destroying the Instance directly may leave connections.
- **Pooling.** Toasts, tooltips and context menu rows are pooled by UrkUI. Pool your own repeated rows (chat, kill feed, leaderboards): reuse frames, change text, never create and destroy per message.
- **Virtualise long lists.** Over about 100 rows, render only visible rows plus a margin in a ScrollingFrame and reuse them as the canvas scrolls.
- **Sheets, not singles.** Upload icon sheets once and map them with `Icons.configure({ sheets = {...} })`; avoid 90 separate decals.
- **Reduced motion and hidden objects.** Decorative effects already skip hidden objects and stop under reduced motion; keep custom effects the same.
- **Disconnect.** Every connection a screen makes belongs to its Trove; a leaked `Changed` connection on a destroyed label keeps memory and runs code.

## Low-end mobile budget (starting points, measure on device)

| Area | Budget |
|---|---|
| GuiObjects in PlayerGui (all screens built) | under 3,000; visible under 1,000 |
| ScreenGuis | under 8 |
| Distinct UI textures loaded | under 30 (icons in sheets count once per sheet) |
| Simultaneous tweens | under 50 during transitions, near 0 idle |
| Per-frame UI callbacks while idle | 0 |
| `Gui` memory in Developer Console | under about 50 MB on phones |
| Window open hitch | under one frame (16 ms) after first build |

## Conventions

- Build screens once, update with `screen:update(id, props)`; never rebuild a screen to change a number.
- Use `Ticker` or `Runtime/Driver` for frame work; no direct `RenderStepped` in UI code.
- Long lists in their own ScrollingFrame with virtualisation.

## Common mistakes

- Spinning shine effects on every card in a 60-card grid.
- Recreating the whole inventory grid on every item change.
- A `while true do task.wait() label.Text = ... end` clock per timer.
- Separate image uploads for every icon and rarity frame.
- Tweens started on hover without cancelling: rapid hover queues dozens.
- New ScreenGui per toast.

## Example

Inventory with 400 pets hitched 120 ms on open and used 80 MB Gui memory. Fixes: virtualised grid (24 visible cards reused), icons moved to sheets, rarity rainbow only on visible secret pets, built once and hidden instead of destroyed. Result measured again: open under 16 ms after first build, Gui memory 22 MB.

## Validation

- Developer Console > Memory: note `Gui` and `GraphicsTexture` before and after opening every screen ten times; growth that never falls is a leak.
- MicroProfiler: record while opening the heaviest screen; the spike frame should not exceed the budget.
- `#PlayerGui:GetDescendants()` before and after open/close cycles: back to the same number.
- Test on the lowest phone you support; Studio on a desktop hides most problems. Report emulator measurements as emulator.

## Limitations

- Exact costs of UIStroke, UIGradient and clipping are engine internals that change; treat the notes as guidance and measure.
- The budget table is a starting point, not a Roblox-published limit.
- Studio cannot reproduce phone GPU and memory limits.
