---
name: roblox-ui-design
description: Professional Roblox game UI design principles - the simulator and cartoon look (chunky outlined titles, thick dark outlines, gradient panels, colour-coded cards, price pills, badges), layout grids, spacing rhythm, visual hierarchy with one primary action, colour roles, readable text minimums on phones, and when not to use the cartoon style. Use when designing or critiquing a shop, HUD, reward or menu screen, choosing palettes and sizes for a spec, or when a screen looks cluttered, flat or amateur.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [ui design, simulator ui, cartoon ui, game ui style, visual hierarchy, ui layout, polished ui, make the ui look good, chunky ui, ui looks bad]
  depends: [roblox-design-system]
---

# Roblox UI design

## Purpose

Turn a request into a screen that looks like a polished, top-chart Roblox game: instantly readable on a phone, one obvious action, consistent outlines and colours. This skill is the "why" and the rules; the tokens are in `roblox-design-system`, the build path in `roblox-ui-generator`.

## When to use (and not)

- Use: before writing a spec, when reviewing a screen, when picking palettes, sizes, badges and copy.
- Not for implementation details (tags, components): `urk-ui-framework`. Not for device scaling: `roblox-responsive-layout`. Not for a structured audit report: `roblox-ui-audit`.

## Workflow

1. **Name the job of the screen** in one sentence ("sell the starter pack, then passes"). That decides the primary action.
2. **Pick the screen kind**: window (shop, list), hud (always on), popup (reward, confirm).
3. **Block the layout on the grid** (below): header, featured row, section heading, card grid, footer.
4. **Assign colour roles**, one palette per card, neighbours different.
5. **Set hierarchy**: sizes from the `text` tokens, one display or title per screen, prices in pills.
6. **Write short copy**: titles in capitals under 20 characters, subtitles that say what the player gets.
7. **Check against the rules** in Design guidelines, then preview (`python3 $URK/urk.py ui preview <spec> --open`) at phone width.

## The cartoon simulator look

| Ingredient | Rule | Token |
|---|---|---|
| Titles | chunky rounded font, white fill, dark text stroke 3 px (2 px under 18 px) | `fonts.title`, `textStroke` |
| Outlines | every panel, card, button and icon has the same near-black outline | `outline.regular` 3, `thick` 4 for windows |
| Panels | vertical gradient light top -> darker bottom, soft gloss on the upper half, drop shadow 4 px | `palette.*`, `gloss`, `shadow` |
| Cards | colour-coded by category or tier, big illustrated icon, title, price pill at the bottom | `sizes.card`, `-color` icons |
| Price pills | dark `price` surface or green `buy`/`robux` button, number font | `buttons.price`, `fonts.number` |
| Badges | corner pills: sale red, bonus yellow (`+50%`), attention red circle `!`, NEW blue, BEST gold ribbon | `badges.*` |
| Window | white or light window surface, red header bar with outlined title, red X close top right | `surfaces.window`, `headerPalette` |
| Background pattern | faint checker inside windows, never behind text-heavy areas | `pattern` |

## Layout grid and spacing rhythm

- Work on a 4 px base; use only `spacing` tokens: 4, 8, 12, 16, 24, 32. Inside a card 8-12, between cards 12, between sections 24.
- Window anatomy: header (about 56-64 px at 1x) / padding `lg` / featured banner (`sizes.banner` 110) / section heading with divider / grid / footer actions.
- Grids: 2 columns on phone, 3 on tablet and desktop for shop cards; 3-4 for small reward tiles; never more than 6. Card aspect 1.2-1.3 (tall cards) so icon, title and price fit.
- Align everything to the content edge of the window; badges are the only things allowed to overhang (corner anchored).
- HUD: currencies top-left or bottom-centre, menu rail on the left, contextual buttons on the right, nothing in the centre third where the character is.

## Hierarchy and the primary action

- One primary action per screen, visually loudest: the green buy button on the featured banner, CLAIM on today's reward. Secondary actions are smaller or neutral; destructive ones are red and never next to the primary.
- Size steps follow the tokens: display 44 > title 32 > heading 24 > label 18 > caption 14. Skipping two steps between neighbours reads as a mistake.
- Featured content goes first and widest (banner), then the grid. Best value gets the `best` badge and gold, not a bigger card.
- Prices sit in the same place on every card (bottom). Players compare by scanning one line.

## Colour roles

| Role | Palette |
|---|---|
| Buy / confirm / Robux | green |
| Gift | purple |
| Close / danger / sale | red |
| Premium / best value / legendary | gold |
| Info / primary navigation | blue |
| Featured or starter offer | teal or orange |
| Locked / disabled | gray |
| Rarity frames | `rarity` tokens only |

Colour never carries meaning alone: pair it with an icon or word (colour-blind players, roughly 1 in 12 men).

## Readability on phones

- Minimum text 12 px at 1x after UIScale (`text.minimum`), 14 for anything a player must read to decide, 18 for buttons.
- Titles at most about 20 characters; validator hard limits are 60 (title) and 90 (subtitle).
- Buttons at least 44 px tall in screen pixels (see `roblox-responsive-layout`).
- Numbers abbreviated (`1.2K`, `3.4M`) through formats, never raw `1234567`.

## When NOT to use the cartoon style

- Horror, realistic shooters, serious roleplay or narrative games: use a flatter UrkUI theme (`dark`, `light`, `highContrast`) or a custom `extends` style with thin outlines and muted palettes.
- Dense data screens (settings, long leaderboards, trading logs): keep outlines `thin`, no gloss or pattern, more whitespace.
- Brand-led games with an existing art direction: copy their palette into a new style instead.
- Accessibility needs: offer the `highContrast` theme and reduced motion regardless of style.

## Conventions

- All colours from palettes or surfaces (no hex in specs except rare `text.color`).
- Illustrated `-color` icons on cards and HUD buttons; monochrome glyphs inside small buttons, toggles and lists.
- Copy in capitals for titles and buttons, sentence case for subtitles and body text.
- Robux prices show as `R$ 99`; no official logo is shipped.

## Common mistakes

- Every card the same colour: no scanning cues. Every card a different colour with no meaning: noise. Colour by category or tier.
- Three equally loud buttons; no primary action.
- Mixed outline weights (2 px on cards, 5 px on buttons) and mixed corner radii.
- Gradients that go dark-to-light (looks sunken) or jump too far (stripes).
- Text over the checker pattern or over busy icons without a stroke.
- Fake urgency: countdowns that reset, "-90%" off a price that never existed. See `roblox-shop-builder`.
- Shrinking text to fit instead of shortening copy.

## Example

"Pet sim shop": red header `SHOP`; teal `STARTER PACK` banner with a sale badge, timer and one green `R$ 99` button (primary); heading `GAMEPASSES`; 3-column grid of purple, blue and pink pass cards with `-color` icons and gift buttons; heading `GEMS`; green, orange and gold gem packs with `+10%`, `+25%` bonus badges and `BEST` on the largest. Full spec in `roblox-ui-generator`.

## Validation

- `python3 $URK/urk.py ui validate <spec.json>` (names, limits, prices).
- `python3 $URK/urk.py ui preview <spec.json> --open`, then narrow the browser to phone width; squint test: the primary action should still be the first thing you see.
- `roblox-ui-audit` for a full checklist and report.

## Limitations

- Principles, not proof: taste still needs a human look at the preview and in Studio.
- The HTML preview approximates Roblox fonts and strokes.
- Colour-blind and contrast checks for gradient fills are manual.
