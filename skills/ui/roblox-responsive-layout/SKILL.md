---
name: roblox-responsive-layout
description: Responsive Roblox UI for phone, tablet, desktop and console with UrkUI - Core/Breakpoints classification, UIScale per breakpoint, safe areas with ScreenInsets and the GUI inset, Grid columns per breakpoint, TextFit and UITextSizeConstraint, scrolling frames, adaptive navigation (bottom bar on phones, side rail on desktop), 44 px touch targets, controller focus with UrkNav and SpatialNav, and testing with the Studio device emulator. Use when UI is cut off by a notch, too small on phones, overlaps on tablets, or cannot be used with a gamepad.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [responsive ui, breakpoints, phone layout, notch, screeninsets, uitextsizeconstraint, touch target, device emulator, console ui, ui too small]
  depends: [roblox-ui-systems]
---

# Roblox responsive layout

## Purpose

One UI that works from a 390 px tall phone to a TV, with touch, mouse and gamepad. UrkUI already classifies the device and scales; this skill is how to use it and what to check.

## When to use (and not)

- Use: new screens, HUD placement, anything reported "cut off", "tiny", "overlaps", "can't select with controller".
- Not for general layout objects and scale vs offset basics: `roblox-ui-systems`. Not for visual style: `roblox-ui-design`.

## Breakpoints (Core/Breakpoints)

| Breakpoint | Rule (defaults) | Reference resolution for UIScale |
|---|---|---|
| `phone` | short side under 500 px | 844 x 390 |
| `tablet` | touch with short side under 900 px, or non-touch window narrower than 1000 px | 1180 x 820 |
| `desktop` | everything else | 1920 x 1080 |
| `console` | `GuiService:IsTenFootInterface()` or gamepad last input without keyboard/touch | 1920 x 1080 |

`UrkUI.getBreakpoint()` and `UrkUI.BreakpointChanged(breakpoint, scale)` expose it. The scale is clamped 0.6-1.5 and multiplied by `UrkUI.setUIScale(m)` (a player "interface size" setting). Pure maths: `Breakpoints.classify(viewport, input)`, `Breakpoints.scale(viewport, breakpoint)`, testable in Lune.

## Workflow

1. **Author at 1x** in token pixels (`design/tokens/styles.json` sizes and spacing). Let UIScale do device scaling; do not hand-scale per device.
2. **Use the safe area.** HUDs: Builder and `Hud.new({ insets = "core" })` use `ScreenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets` (clear of the top bar and notch). Full-bleed backgrounds may use `DeviceSafeInsets` or `None`, but never put buttons there. For custom maths use `Layout.safeRect(viewport, insets, padding)`; `GuiService:GetGuiInset()` gives the top bar inset when `IgnoreGuiInset` is true.
3. **Grids**: give columns per breakpoint, `{ "phone": 2, "tablet": 3, "desktop": 3 }`; console falls back to desktop. Use `cellAspect`, not fixed cell pixels.
4. **Windows**: use `sizeClass` (`sm`/`md`/`lg`/`full`); phones get almost the whole screen automatically (`Builder.windowSize`). Window content scrolls (`scroll: true`); put long lists in the content, never make the window taller than the screen.
5. **Text**: GameText fits between `minSize` and `maxSize` with `Core/TextFit` (`TextFit.fit(request)`, `TextFit.ellipsize(text, n)`). For hand-built labels with `TextScaled`, add a `UITextSizeConstraint` with `MinTextSize` 12 (the kit minimum) and a sensible `MaxTextSize`. Prefer shorter copy over smaller text.
6. **Per-breakpoint overrides** without code: tag `UrkResponsive` and set attributes such as `Phone_Size`, `Tablet_Position`, `Console_Visible`, `Desktop_TextSize`; `AutoScale = true` adds the UIScale.
7. **Adaptive navigation**: on phones put primary navigation in a bottom bar (thumb reach) or a compact left rail of 2 columns; on desktop a side rail with labels; on console the same rail with UrkNav focus. Example: `Console_Visible = false` on a "tap to close" hint, `Phone_Position` moving a rail to the bottom.
8. **Touch targets**: every tappable thing at least 44 x 44 px on screen after scaling (HUD buttons are 64 at 1x; at phone scale about 0.6 they stay above 38, so keep 1x hit areas at 72+ for phone-heavy games or pad the hit area with a transparent parent). Keep 8 px between targets.
9. **Controller focus**: tag window content and rails with `UrkNav` (`AutoSelect`, `Remember`, `Wrap`). `Core/SpatialNav` wires `NextSelection*` by nearest neighbour. When a panel opens with a gamepad in use, focus moves in and returns on close; B closes the top dismissible panel. Every action must be reachable without a pointer.
10. **Test** on the emulator list below, then fix and re-test.

## Conventions

- Scale for positions and container sizes, offset for paddings, outlines and icon sizes (UIScale handles offset).
- Anchor HUD elements to their rail corner (`AnchorPoint` matches the corner), so they grow inward.
- No interactive elements in the top 36 px band or the bottom home-indicator area on phones.
- One UIScale per ScreenGui root, never nested UIScales fighting each other.

## Design guidelines

- Phones in landscape have about 390 px of height: a window header plus two card rows is the visible budget; everything else scrolls.
- Thumb zones: bottom corners are easiest on phones; put frequent actions there, rare ones (settings) top.
- Tablets are wide phones with more columns, not small desktops; keep touch sizes.
- Console (10-foot): larger text (label 18 minimum reads at distance), visible focus ring, no hover-only information.
- Respect reduced motion: layout transitions (`slide*`) become instant under `UrkUI.setReducedMotion(true)` or the engine setting.

## Common mistakes

- Pixel layouts built on a 1920 monitor: off-screen on phones.
- `TextScaled` without a constraint: unreadable 6 px text on phones, giant text on TVs.
- Buttons under the Roblox top bar or behind the notch (missing `ScreenInsets`).
- Hover tooltips as the only explanation (no hover on touch or gamepad).
- Grids with fixed `CellSize` in offset that overflow on phones.
- Focus traps: a modal without a close reachable by gamepad, or `Selectable` false on the close button.

## Example

Shop on phone vs desktop: `GameWindow` `sizeClass: "lg"` (full screen on phone), grid `{ phone: 2, tablet: 3, desktop: 3 }`, banner full width, close X in the header (inside safe area), `UrkNav` on content so the gamepad lands on the banner's buy button first.

## Validation

Studio: Test tab > Device emulator. Minimum pass:

| Device class | Example emulator entries | Check |
|---|---|---|
| Small phone, landscape | iPhone SE, Galaxy S-series small | nothing clipped, text >= 12, targets >= 44 px |
| Notched phone | iPhone 14 / 15 Pro | notch and home indicator clear |
| Tablet | iPad, iPad Pro | columns change, no stretched cards |
| Desktop | 1366 x 768 and 1920 x 1080 windows | rail labels, hover states |
| Console | Xbox One (10-foot) | full gamepad-only pass, focus visible, B closes |

Also: rotate or resize mid-session (breakpoint change re-lays out), set interface size small/large with `UrkUI.setUIScale`. Automated: `cd library && lune run tests/run` (ui_breakpoints, ui_spatialnav, ui_textfit specs). Report emulator checks as emulator, not as device tests.

## Limitations

- The emulator approximates resolution and insets; real phones differ in pixel density and thumb reach.
- Console certification behaviour (TV safe area, platform UI) can only be verified on hardware.
- Breakpoint thresholds are heuristics; unusual aspect ratios (foldables, ultrawide) need a manual look.
