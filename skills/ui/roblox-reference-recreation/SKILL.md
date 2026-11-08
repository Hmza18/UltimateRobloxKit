---
name: roblox-reference-recreation
description: Recreates the feel of reference UI screenshots as an original Roblox implementation - analyse layout grid, palette roles, outline weight, typography, card anatomy, iconography and motion cues into a written style brief, map the brief to design tokens and screen specs, build with UrkUI without copying art, names, logos or proprietary icons, compare side by side with preview captures and iterate. Includes a worked analysis of a simulator shop, a premium store and an icon sheet. Use when a user shares screenshots and says make it look like this, match this style, or recreate this shop.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [reference screenshot, screenshot, look like this, match this style, recreate this ui, style brief, ui reference, like this game, copy this shop]
  depends: [roblox-ui-design, roblox-design-system, roblox-icon-design]
---

# Roblox reference recreation

## Purpose

Users show screenshots of games they like. The goal is the same quality and feel, built from the kit's own tokens, components and icons, never a copy of someone else's art, names or logos.

## When to use (and not)

- Use: "make my shop look like this", mood boards, competitor screenshots, a designer's mock-up.
- Not for plain new screens without references: `roblox-ui-generator`. Not for market research on games: `competitor-research`.

## Workflow

1. **Look closely** at each reference. Read the image; note what you actually see, at what size.
2. **Extract principles into a style brief** (template below): layout grid, palette roles, outline weight, typography, card anatomy, iconography, motion cues, copy tone. Describe patterns ("price in a green pill at card bottom"), not assets.
3. **Map the brief to the kit**: which tokens already match (`design/tokens/styles.json`), which need a new style via `extends` (`roblox-design-system`), which elements and template (`python3 $URK/urk.py ui list`), which icons (`python3 $URK/urk.py icons search ...`), and what is missing (new icon in `roblox-icon-design`).
4. **Write the spec(s)** with original titles and copy; validate (`python3 $URK/urk.py ui validate X.json`).
5. **Preview and capture**: `python3 $URK/tools/ui/preview_spec.py X.json -o build/ui/X.html`, then `python3 $URK/tools/ui/capture_server.py build/ui --out build/ui/captures` and open `http://127.0.0.1:8767/X.html?capture=X`.
6. **Compare side by side** with the reference at the same width: hierarchy, density, colour balance, outline weight, text size. List the differences.
7. **Iterate** up to three rounds per difference (tokens first, then spec, then a component request). Then show the user both images and stop for feedback.

## Originality rules

- No copied or traced art, icons, logos, mascots, game names, item names or currency names. Recreate the principle (a gem icon) with the kit's own icon (`gem-color`).
- No proprietary icon packs; import only packs whose licence the user accepted (`roblox-icon-design`).
- No Roblox logo or Robux logo outside Roblox brand guidelines; prices show `R$ 99`.
- Colours and layout patterns are not ownable, but a combination that makes players think it is the other game is: change the brand-level cues (title wording, header colour, mascot).

## Style brief template

```markdown
Style brief: <name>
Layout: <window size, header, columns per breakpoint, section order, spacing>
Palette roles: <header, primary action, gift, sale, premium, cards by category>
Outline: <weight relative to size, colour>
Typography: <title font feel, stroke, sizes, capitals>
Card anatomy: <top to bottom: badge, icon, title, subtitle, price>
Iconography: <illustrated or flat, outline, highlight, background>
Motion cues: <what moves: shine, pulse, pop-in>
Copy tone: <short caps titles, value-led subtitles>
Kit mapping: <style, template, elements, icons, gaps>
```

## Worked example: the user's three references

**Reference 1, simulator shop.** Observed: red header bar with an outlined white title and a red X; wide teal "starter pack" banner first; cards colour-coded purple, blue and orange; ingot/bar packs priced in Robux; a "x2 cash" style pass; section dividers; checker pattern in the window.

| Principle | Kit mapping |
|---|---|
| Red header, outlined title, red X | `window.headerPalette: "red"`, GameWindow title, `buttons.close` |
| Featured teal offer first | `banner` with `palette: "teal"`, sale badge, timer |
| Colour-coded cards by category | `product` palettes purple, blue, orange; one per card |
| Currency packs | `product` with `productId`, icons `money-bag-color`, `gem-stack-color` or a new `ingot` icon (original drawing) |
| x2 multiplier pass | `product` with `gamePassId`, icon `cash-color`, title `x2 CASH` |
| Dividers and checker | `divider` / `heading`, `pattern` token |
Template: `PetSimShop`.

**Reference 2, premium store.** Observed: three-column card grid; green buttons showing R$ prices; purple gift buttons beside them; red circular "!" badges on cards; coin packs with +15%, +50% and +100% bonus badges; darker premium framing.

| Principle | Kit mapping |
|---|---|
| 3 columns, 2 on phones | `grid.columns { phone: 2, tablet: 3, desktop: 3 }` |
| Green R$ buttons | robux `price` (renders `R$ 499` on a `robux` button) |
| Purple gift buttons | `gift: true` (and real gifting server logic, see `roblox-shop-builder`) |
| Red "!" badges | `badge { kind: "attention" }` |
| Bonus coin packs | `badge { kind: "bonus", text: "+50%" }`, amounts computed so the % is true |
| Premium framing | `"style": "midnight"` or keep `cartoon` with `gold` accents |
Template: `PremiumStore`.

**Reference 3, icon sheet.** Observed: items on a neutral grey background, thick dark outlines, saturated fills, top-left highlights, consistent size and centring.

| Principle | Kit mapping |
|---|---|
| Thick dark outline, saturated gradient, top-left gloss | the illustrated `-color` recipe in `tools/icons/illustrate.py` |
| Consistent size and centring | automatic alignment in `tools/icons/build_icons.py`; `validate_icon.py` checks size and centring |
| Grey presentation background | `assets/icons/urk/preview-color.png` uses the reference grey for review only; icons themselves stay transparent |
Gaps become new glyphs in `tools/icons/urk_icons.py` or generated art validated with `validate_icon.py`.

Combined brief result: `cartoon` style unchanged (palettes and outline already match), PetSimShop and PremiumStore templates with original titles ("STARTER PACK" is generic; product names invented), `-color` icons, honest bonus maths. Compare captures with the references and adjust spacing and banner height first; those are usually the visible differences.

## Conventions

- The brief is written down and shown to the user before building.
- Keep a `references/` folder in the game project with the user's screenshots and a note of where they came from; never ship them.
- Every difference list names the token or spec field that will change.

## Common mistakes

- Pixel-matching instead of principle-matching: copying layout exactly plus colours plus names is imitation.
- Sampling exact hex values from a screenshot (compression shifts them) instead of choosing from palettes.
- Reproducing the other game's currency or item names.
- Ignoring phone layout because the reference was a desktop screenshot.
- Skipping honesty checks because the reference used fake discounts.

## Validation

- `python3 $URK/urk.py ui validate` passes for every spec.
- Side-by-side capture vs reference reviewed; differences listed with the planned fix or "intended".
- Originality check: no names, logos, art or icons from the reference in the spec or assets.

## Limitations

- Screenshots hide motion, sound and interaction; ask or infer, and say what was inferred.
- HTML captures approximate Roblox; the final comparison needs Studio.
- "Feels the same" is a judgement; the user decides when it is close enough.
