---
name: roblox-ui-audit
description: Checklist-driven audit of a Roblox interface - visual (alignment, outline consistency, text fit, contrast, hierarchy), usability (touch target sizes, focus order, reachable back and close, press feedback, loading and empty states), platform (phone, tablet, desktop, console) and economy honesty (real bonuses, disclosed odds), with the automated parts (urk.py ui validate, preview capture, validate_icon.py) and a severity-ranked report template. Use when asked to review, audit, critique or QA a UI, before shipping a screen, or when players report confusing menus.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [ui audit, review the ui, ui review, critique the ui, ui qa, ui checklist, usability review, audit the shop, usability, audit our, visual problems]
  depends: [roblox-ui-design, roblox-responsive-layout]
---

# Roblox UI audit

## Purpose

A repeatable review that finds real problems, ranks them by player impact and separates what was proven by tools from what was only looked at.

## When to use (and not)

- Use: before release, after a big UI change, on a reference recreation, on user request "review my UI".
- Not for fixing performance: `roblox-ui-performance`. Not for writing tests: `roblox-ui-testing`.

## Workflow

1. **Collect inputs**: the specs (`src/shared/UrkScreens/*.json`), screenshots or a place file, the target platforms, and the monetised items.
2. **Run the automated checks** (record exact output):
   ```bash
   python3 $URK/urk.py ui validate src/shared/UrkScreens/*.json
   python3 $URK/tools/ui/preview_spec.py --all -o build/ui            # built-in screens; or one spec with -o
   python3 $URK/tools/ui/capture_server.py build/ui --out build/ui/captures --port 8767
   # open http://127.0.0.1:8767/<Name>.html?capture=<Name> to save PNGs for side-by-side review
   python3 $URK/tools/icons/validate_icon.py assets/icons/custom/*.png  # only for custom icon art
   python3 $URK/urk.py ui tokens --check                               # in the kit repo, after token edits
   ```
3. **Walk the checklists** below on each screen at phone and desktop width (preview) and in Studio if available.
4. **Rank findings** by severity, one line each with location and fix.
5. **Write the report** (template below). Do not fix while auditing unless asked; propose fixes.

## Checklists

### Visual

- [ ] Content aligned to one edge per container; badges are the only overhangs.
- [ ] One outline weight family (`outline` tokens) and one corner radius family across cards and buttons.
- [ ] No text truncated, overflowing or below 12 px after scaling; titles fit without shrinking below `heading`.
- [ ] Contrast: outlined white titles keep the dark stroke; plain body text >= 4.5:1 on its surface.
- [ ] Hierarchy: exactly one primary action per screen; size steps follow the text tokens.
- [ ] Palettes by role (green buy, red close and sale, gold premium, purple gift); no hardcoded colours.
- [ ] Icons consistent (all `-color` on cards, all glyphs in small buttons), centred, same optical size.

### Usability

- [ ] Touch targets >= 44 px on screen, >= 8 px apart.
- [ ] Close X or Back reachable on every window by touch, mouse and gamepad B.
- [ ] Gamepad focus order follows reading order; first focus lands on the primary action; no traps.
- [ ] Every press gives feedback within 100 ms (press scale, sound) and disabled states look disabled.
- [ ] Loading, empty ("no pets yet") and error states exist; purchases show pending state until the server answers.
- [ ] Destructive actions (sell, delete, reset) confirm; primary and destructive never adjacent.
- [ ] Reduced motion: screens still read with animations jumped to their end.

### Platform

- [ ] Phone landscape: nothing under the notch or top bar, window fits, grid 2 columns.
- [ ] Tablet: more columns, no stretched art.
- [ ] Desktop: hover states, keyboard Escape closes.
- [ ] Console: full gamepad-only run, visible focus, readable at distance.

### Economy honesty

- [ ] Bonus badges (`+50%`) match the real rate against the base pack.
- [ ] Sale badges reflect a real former price; timers do not reset to fake urgency.
- [ ] Odds disclosed before buying any paid random reward.
- [ ] Prices visible before the prompt; owned items marked owned, not sold again.
- [ ] Client never grants; ids are real (no `0` placeholders in a published place).

## Severity

| Level | Meaning | Example |
|---|---|---|
| S1 blocker | broken or harmful: cannot proceed, wrong charge, policy breach | close unreachable on console, fake discount, client-side grant |
| S2 major | many players hurt | text 9 px on phones, no primary action, focus trap in one path |
| S3 minor | polish | 2 px misalignment, mixed outline weights |
| S4 note | suggestion | nicer icon for a card |

## Report template

```markdown
# UI audit: <screen or game>, <date>
Scope: <screens>, platforms <list>. Inputs: <specs, screenshots, place>.

## Automated results
- urk.py ui validate: <PASS n / FAIL n, paste failures>
- preview captures: <paths>
- validate_icon.py: <PASS/FAIL or not run>

## Findings (most severe first)
| # | Sev | Screen / element id | Problem | Evidence | Fix |
|---|---|---|---|---|---|
| 1 | S1 | PremiumStore / coins1000 | "+100%" badge but rate is +40% | 500 R$ for 1400 vs base 1000 per 500 | change to +40% or the amount |

## Not verified
- <Studio playtest / console hardware / real purchase> - NEEDS MANUAL REVIEW
```

## Conventions

- Cite element ids from the spec (`body[2].items[3]` or `id`), not vague areas.
- Evidence is a number, a capture path or a validator line.
- Keep "checked in preview", "checked in Studio" and "not checked" separate.

## Common mistakes

- Treating a passing validator as a passing audit: it checks structure, not looks or usability.
- Auditing only at desktop width.
- Flagging taste issues as S1.
- Missing the economy section because "it is just UI".

## Example

Audit of `PetSimShop` on phone: S2 "subtitle under 12 px at 0.6 scale on gem cards" (fix: shorten copy, raise caption); S3 "gift and buy buttons 6 px apart" (fix: `gap` md); S1 none; Not verified: console focus (no Studio).

## Validation

The audit is complete when every checklist line is ticked, marked N/A with a reason, or listed under Not verified, and every finding has a severity and a fix.

## Limitations

- Automated tools cover spec structure, icon art and HTML captures, not Roblox rendering.
- Contrast on gradients and colour-blind safety need manual judgement.
- Without Studio or devices, platform items stay NEEDS MANUAL REVIEW.
