---
name: roblox-visual-ui-loop
description: Closed visual loop for Roblox UI - extract palette, outline and layout hints from a reference image, write a screen spec, preview and capture it, compare the capture with the reference using a fixed scored rubric (palette, layout, contrast, outline, colour), and iterate until the score and a human look agree. Covers the HTML capture path, the Roblox Studio MCP screenshot path, and honest reporting of what was actually captured. Use when a user wants a UI to match a reference, asks to score or compare UI screenshots, or wants visual regression on screens.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [visual loop, compare screenshots, score the ui, match the reference, ui score, visual regression, capture and compare, iterate on the ui]
  depends: [roblox-reference-recreation, roblox-ui-generator, roblox-ui-testing]
---

# Roblox visual UI loop

## Purpose

Turn "make it look like this" into a measurable loop: reference, spec, capture, score, fix, repeat. The score guides the work; a person's eye decides when it is done.

## Workflow

1. **Extract hints** from the reference (yours, or one you may use as a reference; it is never copied into the output):
   `python3 $URK/urk.py ui extract ref.png --json build/ui/ref-hints.json`
   Read `suggestion` (style, palettes, light or dark background, grid or panel layout), `accentColours`, `outlineRatio` and `busyGrid`.
2. **Write the spec** with `roblox-ui-generator`, using the suggested palettes and style, original copy and kit icons. Validate it with `python3 $URK/urk.py ui validate X.json`.
3. **Capture**. Pick one path and record which one you used:
   - HTML preview: `python3 $URK/urk.py ui preview X.json -o build/ui/X.html`, then `python3 $URK/tools/ui/capture_server.py build/ui --out build/ui/captures` and open `http://127.0.0.1:8767/X.html?capture=X` in a browser. The PNG lands in `build/ui/captures/X.png`.
   - Studio: with the Roblox Studio MCP connected (`roblox-studio-mcp`), play-test the screen and use the MCP screen capture. Save the image beside the spec.
4. **Score**: `python3 $URK/urk.py ui compare ref.png build/ui/captures/X.png --diff build/ui/X-diff.png --json build/ui/X-score.json`. Parts: palette 30, layout 25, contrast 15, outline 15, colour 15 (0-100 each).
5. **Fix the lowest part first**, following the notes in the report: palettes for colour, the main panel and grid for layout, the style's outline weight for outline, surfaces for contrast.
6. **Repeat** up to 3 rounds per issue. Stop when the total stops improving or reaches the target you agreed with the user (75+ is a strong match in style).
7. **Look yourself**: open the reference, the capture and the diff image side by side. A high score with an obvious mistake (a clipped title, an overlapping badge) is still a fail.

## Rules

- Never report a screenshot, score or Studio result you did not produce in this session. Name the capture file and which path made it.
- The rubric measures style resemblance, not quality or legal similarity. Recreate the feel with original art and words, never a pixel copy of someone else's game.
- The HTML preview approximates the Roblox builder from the same tokens. Final sign-off still needs Studio, at phone, tablet and console sizes.

## Limitations

- `extract` uses colour quantisation and edge maps; it cannot read text or recognise components.
- Layout scoring compares coarse edge maps, so moving a panel a few pixels barely changes it. Large structural differences show clearly.
- Screenshots of different aspect ratios are resized to the reference before scoring.
